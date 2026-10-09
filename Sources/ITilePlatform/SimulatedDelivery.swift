import Foundation
import ITileCore

/// Internal simulation routing. Lock order: transport -> gate; gate never calls transport.
/// No backend, owner callback, or scheduling closure runs under either lock.
final class SimulatedDelivery: @unchecked Sendable {
  private enum Envelope: Equatable, Sendable {
    case step(SimulatedStepReceipt)
    case terminal(SimulatedTerminalReceipt)
    case readback(SimulatedReadbackReceipt)
    var operation: ControlOperationID {
      switch self {
      case .step(let receipt): receipt.permit.operation
      case .readback(let receipt): receipt.permit.operation
      case .terminal(let receipt): receipt.operation
      }
    }
  }
  private struct Safety: OptionSet, Sendable {
    let rawValue: UInt8
    static let pause = Safety(rawValue: 1)
    static let disable = Safety(rawValue: 2)
    static let quit = Safety(rawValue: 4)
    static let permission = Safety(rawValue: 8)
    static let environment = Safety(rawValue: 16)
  }
  private let lock = NSLock()
  private let owner: SimulatedControlOwner
  private let gate: SimulatedCommandGate
  private let schedule: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
  private let time: @Sendable () -> Double
  private let commands: @MainActor @Sendable ([SimulatedControlOwner.Disposition]) -> Void
  private let continued: @MainActor @Sendable (ControlOperationID, SimulatedStepDisposition) -> Void
  private let beforeAcknowledgment: @MainActor @Sendable (ControlOperationID) -> Void
  private var apps: [AppToken] = []
  private var retired: Set<AppToken> = []
  private var failed: Set<AppToken> = []
  private var entries: [AppToken: Envelope] = [:]
  private var safety: Safety = []
  private var uncertain: Set<AppToken> = []
  private var highestGeneration: UInt64 = 0
  private var cursor = 0
  private var scheduled = false

  @MainActor
  init(
    owner: SimulatedControlOwner,
    time: @escaping @Sendable () -> Double,
    schedule: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
    commands: @escaping @MainActor @Sendable ([SimulatedControlOwner.Disposition]) -> Void = { _ in
    },
    continued:
      @escaping @MainActor @Sendable (ControlOperationID, SimulatedStepDisposition) -> Void = {
        _, _ in
      },
    beforeAcknowledgment: @escaping @MainActor @Sendable (ControlOperationID) -> Void = { _ in }
  ) {
    self.owner = owner
    self.gate = owner.gate
    self.time = time
    self.schedule = schedule
    self.commands = commands
    self.beforeAcknowledgment = beforeAcknowledgment
    self.continued = continued
  }

  /// Bootstrap through the serialized owner; no live application enrollment.
  @MainActor
  func attach(_ app: AppToken, at now: Double) -> Bool {
    lock.lock()
    let admissible =
      !apps.contains(app) && apps.count < 16 && app.generation > highestGeneration
      && !apps.contains(where: { $0.pid == app.pid && !retired.contains($0) })
    lock.unlock()
    guard admissible, owner.attach(app, at: now) else { return false }
    lock.lock()
    highestGeneration = app.generation
    apps.append(app)
    lock.unlock()
    return true
  }

  @MainActor
  func retire(_ app: AppToken, at now: Double) {
    owner.retire(app, at: now)
    lock.lock()
    if apps.contains(app) {
      retired.insert(app)
      cleanup(app)
    }
    lock.unlock()
  }

  var retainedReplies: Int {
    lock.lock()
    defer { lock.unlock() }
    return entries.count
  }
  var attachmentCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return apps.count
  }
  func hasFailed(_ app: AppToken) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return failed.contains(app)
  }

  func enqueue(_ command: SemanticCommand) -> CommandEnqueueResult {
    lock.lock()
    let result = gate.enqueue(command)
    let wake: Bool
    if case .accepted = result { wake = arm() } else { wake = false }
    lock.unlock()
    if wake { post() }
    return result
  }

  /// Repeated pending epoch signals coalesce, but every ingress still closes admission.
  func revoke(_ reason: CommandRevocation, at now: Double) {
    lock.lock()
    latch(reason, at: now)
    let wake = arm()
    lock.unlock()
    if wake { post() }
  }

  @discardableResult
  func submit(_ receipt: SimulatedStepReceipt) -> Bool { submit(.step(receipt)) }
  @discardableResult
  func submit(_ receipt: SimulatedTerminalReceipt) -> Bool { submit(.terminal(receipt)) }

  @discardableResult
  func submit(_ receipt: SimulatedReadbackReceipt) -> Bool { submit(.readback(receipt)) }

  private func submit(_ envelope: Envelope) -> Bool {
    lock.lock()
    let app = envelope.operation.app
    let exact: Bool
    switch envelope {
    case .step(let receipt): exact = gate.canDeliver(receipt)
    case .readback(let receipt): exact = gate.canDeliver(receipt)
    case .terminal(let receipt): exact = gate.canDeliver(receipt)
    }
    guard apps.contains(app), entries[app] == nil, exact else {
      // Quarantine a known malformed/duplicate route without overwriting its receipt.
      if apps.contains(app), !failed.contains(app) {
        failed.insert(app)
        gate.quarantine(app)
        // Retired routing exists only for cleanup; an old malformed callback
        // must not become unknown global uncertainty for a replacement process.
        if !retired.contains(app) { latch(.appUncertain(app), at: gate.currentTime) }
      }
      let wake = !safety.isEmpty || !uncertain.isEmpty ? arm() : false
      lock.unlock()
      if wake { post() }
      return false
    }
    entries[app] = envelope
    let wake = arm()
    lock.unlock()
    if wake { post() }
    return true
  }

  private func latch(_ reason: CommandRevocation, at now: Double) {
    let flag: Safety
    switch reason {
    case .pause: flag = .pause
    case .disable: flag = .disable
    case .quit: flag = .quit
    case .permissionLost: flag = .permission
    case .environmentChanged: flag = .environment
    case .appUncertain(let app):
      if apps.contains(app) {
        uncertain.insert(app)
        gate.revoke(reason, at: now)
      } else {
        safety.insert(.pause)
        gate.revoke(.pause, at: now)
      }
      return
    }
    let alreadyPending = safety.contains(flag)
    safety.insert(flag)
    let coalescedEpoch = alreadyPending && (flag == .permission || flag == .environment)
    gate.revoke(coalescedEpoch ? .pause : reason, at: now)
  }

  private func arm() -> Bool {
    let wake = !scheduled
    scheduled = true
    return wake
  }
  private func post() { schedule { [self] in drain() } }

  @MainActor
  private func now() -> Double {
    let value = time()
    return max(value.isFinite ? value : 0, gate.currentTime, owner.currentTime)
  }

  @MainActor
  private func applySafety() {
    lock.lock()
    let flags = safety
    let dirty = uncertain.sorted { $0.generation < $1.generation }
    safety = []
    uncertain.removeAll()
    lock.unlock()
    let timestamp = now()
    // Apply epoch-bearing signals before terminal Quit so model and gate stay aligned.
    if flags.contains(.permission) { owner.applyRevocation(.permissionLost, at: timestamp) }
    if flags.contains(.environment) { owner.applyRevocation(.environmentChanged, at: timestamp) }
    if flags.contains(.pause) { owner.applyRevocation(.pause, at: timestamp) }
    if flags.contains(.disable) { owner.applyRevocation(.disable, at: timestamp) }
    for app in dirty { owner.applyRevocation(.appUncertain(app), at: timestamp) }
    if flags.contains(.quit) { owner.applyRevocation(.quit, at: timestamp) }
  }

  @MainActor
  private func drain() {
    applySafety()
    for _ in 0..<8 {
      lock.lock()
      var envelope: Envelope?
      for _ in 0..<apps.count {
        cursor %= apps.count
        let app = apps[cursor]
        cursor = (cursor + 1) % apps.count
        if let entry = entries[app] {
          envelope = entry
          break
        }
      }
      lock.unlock()
      guard let entry = envelope else { break }
      applySafety()
      let release = { [self] in
        beforeAcknowledgment(entry.operation)
        lock.lock()
        if entries[entry.operation.app] == entry {
          entries.removeValue(forKey: entry.operation.app)
        }
        lock.unlock()
      }
      switch entry {
      case .step(let receipt):
        let result = owner.consume(receipt, at: now(), willAcknowledge: release)
        continued(entry.operation, result)
      case .terminal(let receipt):
        if owner.consume(receipt, at: now(), willAcknowledge: release) {
          continued(entry.operation, .terminal(receipt))
        }
      case .readback(let receipt):
        if let terminal = owner.consume(receipt, at: now(), willAcknowledge: release) {
          continued(entry.operation, .terminal(terminal))
        }
      }
      lock.lock()
      cleanup(entry.operation.app)
      lock.unlock()
    }
    applySafety()
    let dispositions = owner.drain(at: now())
    if !dispositions.isEmpty { commands(dispositions) }
    lock.lock()
    let again = !safety.isEmpty || !uncertain.isEmpty || !entries.isEmpty || gate.queuedCount > 0
    scheduled = again
    lock.unlock()
    if again { post() }
  }

  /// Caller holds transport lock; gate has no callbacks and never takes this lock.
  private func cleanup(_ app: AppToken) {
    if retired.contains(app), entries[app] == nil, !gate.hasOperation(app) {
      apps.removeAll { $0 == app }
      retired.remove(app)
      failed.remove(app)
      uncertain.remove(app)
    }
  }
}
