import Foundation
import ITileCore

struct SimulatedReadbackValue: Sendable {
  let observation: WindowObservation?
  let outcome: ControlOutcome
}

/// Fake values only; never pass AX/AppKit handles or a real platform adapter here.
protocol SimulatedWorkerBackend: Sendable {
  func set(_ target: FrameTarget, setter: SimulatedSetter) -> ControlOutcome
  func readback(_ permit: SimulatedReadbackPermit) -> SimulatedReadbackValue
}

private final class SimulatedSequenceWorker: @unchecked Sendable {
  enum Job: Sendable {
    case setter(ControlOperationID, FrameTarget, SimulatedSetter)
    case readback(ControlOperationID)
  }
  private let condition = NSCondition()
  private let gate: SimulatedCommandGate
  private let delivery: SimulatedDelivery
  private let backend: any SimulatedWorkerBackend
  private let time: @Sendable () -> Double
  private let exited: @Sendable () -> Void
  private var pending: Job?
  private var busy = false
  private var stopping = false
  private var finished = false

  init(
    gate: SimulatedCommandGate, delivery: SimulatedDelivery,
    backend: any SimulatedWorkerBackend, time: @escaping @Sendable () -> Double,
    exited: @escaping @Sendable () -> Void
  ) {
    self.gate = gate
    self.delivery = delivery
    self.backend = backend
    self.time = time
    self.exited = exited
    Thread { [self] in run() }.start()
  }

  var isFinished: Bool {
    condition.lock()
    defer { condition.unlock() }
    return finished
  }
  func submit(_ job: Job) -> Bool {
    condition.lock()
    defer { condition.unlock() }
    guard !busy, !stopping else { return false }
    busy = true
    pending = job
    condition.signal()
    return true
  }
  func stop() {
    condition.lock()
    stopping = true
    condition.signal()
    condition.unlock()
  }
  private func run() {
    while true {
      condition.lock()
      while pending == nil && !stopping { condition.wait() }
      guard let job = pending else {
        finished = true
        condition.unlock()
        exited()
        return
      }
      pending = nil
      condition.unlock()
      // Complete backend work and build its exact gate receipt before freeing
      // the worker mailbox; gate occupancy still prevents another sequence.
      switch job {
      case .setter(let id, let target, let setter):
        switch gate.admit(id, setter: setter, at: time()) {
        case .permit(let permit):
          let outcome = backend.set(target, setter: setter)
          let receipt = gate.finish(permit, outcome: outcome)
          idle()
          if let receipt { delivery.submit(receipt) }
        case .denied(let receipt):
          idle()
          delivery.submit(receipt)
        case .stale: idle()
        }
      case .readback(let id):
        switch gate.admitReadback(id, at: time()) {
        case .permit(let permit):
          let value = backend.readback(permit)
          let receipt = gate.finishReadback(
            permit, observation: value.observation,
            outcome: value.outcome, at: time())
          idle()
          if let receipt { delivery.submit(receipt) }
        case .denied(let receipt):
          idle()
          delivery.submit(receipt)
        case .stale: idle()
        }
      }
    }
  }
  private func idle() {
    condition.lock()
    busy = false
    condition.unlock()
  }
}

/// Internal end-to-end harness. At most 16 physical workers, including retiring
/// blocked threads. No worker replacement, polling, or real window control.
@MainActor
final class SimulatedWorkerRuntime {
  let owner = SimulatedControlOwner(requiresReadback: true, allowsMultiWindowPlans: true)
  private let time: @Sendable () -> Double
  private let schedule: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
  private let terminal: @MainActor @Sendable (SimulatedTerminalReceipt) -> Void
  private let exited: @Sendable (AppToken) -> Void
  private var workers: [AppToken: SimulatedSequenceWorker] = [:]
  private var retired: Set<AppToken> = []
  private lazy var delivery = SimulatedDelivery(
    owner: owner, time: time, schedule: schedule,
    commands: { [weak self] _ in self?.preparePending() },
    continued: { [weak self] id, result in self?.continueSequence(id, result: result) })

  init(
    time: @escaping @Sendable () -> Double,
    schedule: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
    terminal: @escaping @MainActor @Sendable (SimulatedTerminalReceipt) -> Void = { _ in },
    exited: @escaping @Sendable (AppToken) -> Void = { _ in }
  ) {
    self.time = time
    self.schedule = schedule
    self.terminal = terminal
    self.exited = exited
  }

  var physicalWorkerCount: Int { workers.count }
  var retainedReplies: Int { delivery.retainedReplies }

  func attach(_ app: AppToken, backend: any SimulatedWorkerBackend, at now: Double) -> Bool {
    for app in Array(retired) where workers[app]?.isFinished == true {
      workers.removeValue(forKey: app)
      retired.remove(app)
    }
    guard workers.count < 16, workers[app] == nil, delivery.attach(app, at: now) else {
      return false
    }
    let onExit = exited
    workers[app] = SimulatedSequenceWorker(
      gate: owner.gate, delivery: delivery,
      backend: backend, time: time, exited: { onExit(app) })
    return true
  }
  func retire(_ app: AppToken, at now: Double) {
    delivery.retire(app, at: now)
    retired.insert(app)
    workers[app]?.stop()
  }
  func enqueue(_ command: SemanticCommand) -> CommandEnqueueResult { delivery.enqueue(command) }
  func revoke(_ reason: CommandRevocation, at now: Double) {
    delivery.revoke(reason, at: now)
    if case .quit = reason { for worker in workers.values { worker.stop() } }
  }

  private func preparePending() {
    let now = max(time(), owner.currentTime, owner.gate.currentTime)
    for app in workers.keys.sorted(by: { $0.generation < $1.generation })
    where !retired.contains(app) {
      guard let id = owner.prepare(app, at: now), let target = owner.target(id) else { continue }
      if workers[app]?.submit(.setter(id, target, .size)) != true {
        if let receipt = owner.gate.withdraw(id) { delivery.submit(receipt) }
      }
    }
  }
  private func continueSequence(_ id: ControlOperationID, result: SimulatedStepDisposition) {
    let job: SimulatedSequenceWorker.Job
    switch result {
    case .positionReady:
      guard let target = owner.target(id) else { return }
      job = .setter(id, target, .position)
    case .readbackReady: job = .readback(id)
    case .terminal(let receipt):
      terminal(receipt)
      // Continue only a still-current cursor from the same explicit plan, after
      // exact observed readback and terminal acknowledgment. Never retry failure.
      if receipt.reason == .completed { preparePending() }
      return
    case .stale: return
    }
    if workers[id.app]?.submit(job) != true {
      // No backend is available: terminalize only unadmitted matching work.
      if let receipt = owner.gate.withdraw(id) { delivery.submit(receipt) }
    }
  }
}
