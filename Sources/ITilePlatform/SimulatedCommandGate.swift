import Foundation
import ITileCore

// Internal simulation boundary only: no WindowProbe/AppKit/AX references or
// callback dispatcher. Its permits cannot execute platform work.
typealias SimulatedOperationID = ControlOperationID
struct SimulatedGatePermit: Equatable, Sendable {
  let operation: SimulatedOperationID
  let setter: SimulatedSetter
  let admittedAt: Double
}
struct SimulatedStepReceipt: Equatable, Sendable {
  let permit: SimulatedGatePermit
  let outcome: ControlOutcome
}
struct SimulatedTerminalReceipt: Equatable, Sendable {
  enum Reason: Equatable, Sendable { case completed, revoked, unavailable, unknownOutcome }
  let operation: SimulatedOperationID
  let reason: Reason
}
enum SimulatedGateAdmission: Equatable, Sendable {
  case permit(SimulatedGatePermit)
  case denied(SimulatedTerminalReceipt)
  case stale
}
enum SimulatedStepDisposition: Equatable, Sendable {
  case positionReady
  case terminal(SimulatedTerminalReceipt)
  case stale
}

final class SimulatedCommandGate: @unchecked Sendable {
  private enum Phase: Equatable, Sendable {
    case ready(SimulatedSetter)
    case executing(SimulatedGatePermit)
    case step(SimulatedStepReceipt)
    case terminal(SimulatedTerminalReceipt)
    case consumingStep(SimulatedStepReceipt)
    case consumingTerminal(SimulatedTerminalReceipt)
  }
  private struct Slot: Sendable {
    let id: SimulatedOperationID
    let target: FrameTarget
    let evidence: WindowObservation
    let ticket: CommandTicket
    var phase: Phase
  }
  private let lock = NSLock()
  private var boundary: CommandBoundary
  private var slots: [AppToken: Slot] = [:]
  private var lastPublished: [AppToken: UInt64] = [:]
  private var serial: UInt64 = 0
  private var clock: Double = 0
  private var invalidatedAt: Double = 0
  private var appInvalidatedAt: [AppToken: Double] = [:]
  private var epoch: UInt64 = 0
  private let requiresOwnerAuthorization: Bool
  private var authorized: [AppToken: FrameTarget] = [:]
  private var ownerRevision: UInt64 = 0

  init(capacity: Int = 128, requiresOwnerAuthorization: Bool = false) {
    boundary = CommandBoundary(capacity: capacity)
    self.requiresOwnerAuthorization = requiresOwnerAuthorization
  }

  /// Immutable owner snapshot. Revisions never regress; malformed snapshots close this mirror.
  func synchronize(revision: UInt64, targets: [AppToken: FrameTarget]) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard revision >= ownerRevision, targets.count <= 16,
      targets.allSatisfy({ $0.key == $0.value.token.app && $0.value.layoutRevision == revision })
    else {
      authorized.removeAll()
      return false
    }
    ownerRevision = revision
    authorized = targets
    return true
  }

  func reserve(_ receipt: SimulatedStepReceipt) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let app = receipt.permit.operation.app
    guard var slot = slots[app], slot.id == receipt.permit.operation,
      slot.phase == .step(receipt)
    else { return false }
    slot.phase = .consumingStep(receipt)
    slots[app] = slot
    return true
  }

  func reserve(_ receipt: SimulatedTerminalReceipt) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard var slot = slots[receipt.operation.app], slot.id == receipt.operation,
      slot.phase == .terminal(receipt)
    else { return false }
    slot.phase = .consumingTerminal(receipt)
    slots[receipt.operation.app] = slot
    return true
  }

  /// Only unadmitted work can be withdrawn by its owner.
  func withdraw(_ id: SimulatedOperationID) -> SimulatedTerminalReceipt? {
    lock.lock()
    defer { lock.unlock() }
    guard var slot = slots[id.app], slot.id == id, case .ready = slot.phase else { return nil }
    let receipt = SimulatedTerminalReceipt(operation: id, reason: .revoked)
    slot.phase = .terminal(receipt)
    slots[id.app] = slot
    return receipt
  }

  var queuedCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return boundary.queuedCount
  }
  var operationCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return slots.count
  }

  @discardableResult
  func attach(_ app: AppToken) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let retired = slots.keys.filter { !boundary.contains($0) }.count
    guard boundary.contains(app) || boundary.attachedCount + retired < 16 else { return false }
    return boundary.attach(app)
  }

  func retire(_ app: AppToken) {
    lock.lock()
    defer { lock.unlock() }
    boundary.retire(app)
    lastPublished.removeValue(forKey: app)
    appInvalidatedAt.removeValue(forKey: app)
    // Executing/undelivered work retains its slot until an exact terminal acknowledgment.
  }

  func setTrust(_ value: Bool, at now: Double) {
    if !value {
      revoke(.permissionLost, at: now)
      return
    }
    lock.lock()
    defer { lock.unlock() }
    guard advanceClock(now) else { return }
    if !boundary.trusted {
      boundary.setTrust(true)
      invalidatedAt = clock
    }
  }

  /// Safety ingress bypasses the command queue and timestamp validation.
  func revoke(_ reason: CommandRevocation, at now: Double) {
    lock.lock()
    defer { lock.unlock() }
    _ = advanceClock(now)
    switch reason {
    case .appUncertain(let app) where boundary.contains(app): appInvalidatedAt[app] = clock
    default: invalidatedAt = clock
    }
    switch reason {
    case .environmentChanged, .permissionLost:
      if epoch < UInt64.max { epoch += 1 } else { boundary.revoke(.quit) }
    default: break
    }
    boundary.revoke(reason)
  }

  func accepts(_ ticket: CommandTicket) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return boundary.accepts(ticket.stamp)
  }

  func enqueue(_ command: SemanticCommand) -> CommandEnqueueResult {
    lock.lock()
    defer { lock.unlock() }
    return boundary.enqueue(command)
  }

  func drain(at now: Double) -> [CommandDisposition] {
    lock.lock()
    defer { lock.unlock() }
    guard advanceClock(now) else { return [] }
    let old = boundary.generation
    let dispositions = boundary.drain()
    if old != boundary.generation { invalidatedAt = clock }
    return dispositions
  }

  /// Owner-supplied synthetic eligibility is checked here, not inferred from AX.
  /// Only an accepted explicit Tile ticket can publish this simulation operation.
  func publish(
    _ target: FrameTarget, evidence: WindowObservation, ticket: CommandTicket, at now: Double
  ) -> SimulatedOperationID? {
    lock.lock()
    defer { lock.unlock() }
    let app = target.token.app
    guard advanceClock(now), slots[app] == nil, slots.count < 16 else { return nil }
    guard ticket.serial > (lastPublished[app] ?? 0), case .tile(let frames) = ticket.command,
      frames[target.token] == target.frame, ticket.stamp.apps[app] != nil,
      target.token == evidence.token, target.environmentEpoch == epoch,
      evidence.environmentEpoch == epoch,
      target.observationSequence == evidence.workerSequence, evidence.workerSequence > 0,
      target.layoutRevision > 0,
      target.plannedAt.isFinite, target.plannedAt >= evidence.sampledAt, target.plannedAt <= now,
      validEvidence(evidence, at: now), boundary.accepts(ticket.stamp),
      !requiresOwnerAuthorization || authorized[app] == target
    else { return nil }
    guard serial < UInt64.max else {
      boundary.revoke(.quit)
      return nil
    }
    guard boundary.activate(ticket) else { return nil }
    serial += 1
    let id = SimulatedOperationID(app: app, serial: serial)
    slots[app] = Slot(
      id: id, target: target, evidence: evidence, ticket: ticket, phase: .ready(.size))
    lastPublished[app] = ticket.serial
    return id
  }

  /// The lock orders revocation against this permit. No fake backend runs under it.
  func admit(_ id: SimulatedOperationID, setter: SimulatedSetter, at now: Double)
    -> SimulatedGateAdmission
  {
    lock.lock()
    defer { lock.unlock() }
    guard var slot = slots[id.app], slot.id == id, slot.phase == .ready(setter) else {
      return .stale
    }
    guard advanceClock(now), current(slot, at: now) else {
      let receipt = SimulatedTerminalReceipt(operation: id, reason: .revoked)
      slot.phase = .terminal(receipt)
      slots[id.app] = slot
      return .denied(receipt)
    }
    let permit = SimulatedGatePermit(operation: id, setter: setter, admittedAt: now)
    slot.phase = .executing(permit)
    slots[id.app] = slot
    return .permit(permit)
  }

  func finish(_ permit: SimulatedGatePermit, outcome: ControlOutcome) -> SimulatedStepReceipt? {
    lock.lock()
    defer { lock.unlock() }
    guard var slot = slots[permit.operation.app], slot.id == permit.operation,
      slot.phase == .executing(permit)
    else { return nil }
    let receipt = SimulatedStepReceipt(permit: permit, outcome: outcome)
    slot.phase = .step(receipt)
    slots[permit.operation.app] = slot
    return receipt
  }

  func acknowledge(_ receipt: SimulatedStepReceipt, at now: Double) -> SimulatedStepDisposition {
    lock.lock()
    defer { lock.unlock() }
    let id = receipt.permit.operation
    guard var slot = slots[id.app], slot.id == id,
      slot.phase == .consumingStep(receipt)
        || (!requiresOwnerAuthorization && slot.phase == .step(receipt))
    else {
      return .stale
    }
    let valid = advanceClock(now) && current(slot, at: now)
    if valid, receipt.outcome == .succeeded, receipt.permit.setter == .size {
      slot.phase = .ready(.position)
      slots[id.app] = slot
      return .positionReady
    }
    let reason: SimulatedTerminalReceipt.Reason
    if !valid {
      reason = .revoked
    } else {
      switch receipt.outcome {
      case .succeeded: reason = .completed
      case .unavailable: reason = .unavailable
      case .unknownOutcome: reason = .unknownOutcome
      }
    }
    let terminal = SimulatedTerminalReceipt(operation: id, reason: reason)
    slot.phase = .terminal(terminal)
    slots[id.app] = slot
    return .terminal(terminal)
  }

  @discardableResult
  func acknowledge(_ receipt: SimulatedTerminalReceipt) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard let slot = slots[receipt.operation.app], slot.id == receipt.operation,
      slot.phase == .consumingTerminal(receipt)
        || (!requiresOwnerAuthorization && slot.phase == .terminal(receipt))
    else { return false }
    slots.removeValue(forKey: receipt.operation.app)
    return true
  }

  private func current(_ slot: Slot, at now: Double) -> Bool {
    boundary.enabled && boundary.trusted && !boundary.paused
      && boundary.accepts(slot.ticket.stamp) && slot.target.environmentEpoch == epoch
      && validEvidence(slot.evidence, at: now)
      && (!requiresOwnerAuthorization || authorized[slot.id.app] == slot.target)
  }

  private func validEvidence(_ evidence: WindowObservation, at now: Double) -> Bool {
    evidence.eligibility == .eligible && evidence.positionSettable == .supported
      && evidence.sizeSettable == .supported && evidence.sampledAt.isFinite
      && evidence.sampledAt >= max(invalidatedAt, appInvalidatedAt[evidence.token.app] ?? 0)
      && evidence.sampledAt <= now && now - evidence.sampledAt <= 0.5
      && (try? LayoutEngine.frames(for: .window(0), in: evidence.frame)) != nil
  }

  private func advanceClock(_ now: Double) -> Bool {
    guard now.isFinite, now >= clock else { return false }
    clock = now
    return true
  }
}
