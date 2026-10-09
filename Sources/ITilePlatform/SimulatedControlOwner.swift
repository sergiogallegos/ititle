import ITileCore

/// Internal test harness. No UI, platform calls, scheduler, or live worker wiring.
/// Methods reduce synchronously on one owner; fake workers access only `gate`.
@MainActor
final class SimulatedControlOwner {
  enum Disposition: Equatable {
    case reduced(UInt64, [ControlEffect])
    case rejected(UInt64, CommandRejection)
    case unsupported(UInt64)
  }
  let gate = SimulatedCommandGate(requiresOwnerAuthorization: true)
  private(set) var model = ControlModel()
  private var apps: Set<AppToken> = []
  private var tickets: [AppToken: CommandTicket] = [:]
  private var operations: [ControlOperationID: FrameTarget] = [:]
  private var clock: Double = 0

  @discardableResult
  func attach(_ app: AppToken, at now: Double) -> Bool {
    guard advance(now), gate.attach(app) else { return false }
    let effects = model.reduce(.attach(app), at: now)
    guard effects.isEmpty else {
      gate.retire(app)
      return false
    }
    apps.insert(app)
    synchronize()
    return true
  }

  func trust(_ value: Bool, at now: Double) {
    if !value {
      revoke(.permissionLost, at: now)
      return
    }
    guard advance(now) else { return }
    gate.setTrust(true, at: now)
    _ = model.reduce(.permission(true), at: now)
    synchronize()
  }

  func revoke(_ reason: CommandRevocation, at now: Double) {
    // Close worker ingress first. Invalid timestamps must not defer safety.
    gate.revoke(reason, at: now)
    _ = advance(now)
    let event: ControlEvent
    switch reason {
    case .pause, .disable: event = .pause
    case .quit: event = .quit
    case .permissionLost: event = .permission(false)
    case .environmentChanged: event = .environmentChanged(.environmentChanged)
    case .appUncertain(let app): event = apps.contains(app) ? .overflow(app) : .pause
    }
    _ = model.reduce(event, at: clock)
    if case .appUncertain(let app) = reason {
      tickets.removeValue(forKey: app)
    } else {
      tickets.removeAll()
    }
    synchronize()
  }

  func retire(_ app: AppToken, at now: Double) {
    gate.retire(app)
    _ = advance(now)
    _ = model.reduce(.appTerminated(app), at: clock)
    apps.remove(app)
    tickets.removeValue(forKey: app)
    // Retained gate operations still require exact terminal consumption.
    synchronize()
  }

  func destroy(_ token: WindowToken, at now: Double) {
    gate.revoke(.appUncertain(token.app), at: now)
    _ = advance(now)
    _ = model.reduce(.windowDestroyed(token), at: clock)
    tickets.removeValue(forKey: token.app)
    synchronize()
  }

  @discardableResult
  func observe(_ observation: WindowObservation, at now: Double) -> [ControlEffect] {
    guard advance(now) else { return [.rejected(.invalidTime)] }
    let effects = model.reduce(.observation(observation), at: now)
    synchronize()
    return effects
  }

  @discardableResult
  func registry(_ snapshot: ProbeRegistrySnapshot, at now: Double) -> [ControlEffect] {
    guard advance(now) else { return [.rejected(.invalidTime)] }
    let effects = model.reduce(.registrySnapshot(snapshot), at: now)
    if !effects.isEmpty { revoke(.appUncertain(snapshot.app), at: now) }
    synchronize()
    return effects
  }

  func drain(at now: Double) -> [Disposition] {
    guard advance(now) else { return [] }
    var result: [Disposition] = []
    for disposition in gate.drain(at: now) {
      switch disposition {
      case .rejected(let id, let reason): result.append(.rejected(id, reason))
      case .revalidationRequired(let id):
        tickets.removeAll()
        result.append(.reduced(id, model.reduce(.resume, at: now)))
      case .ready(let ticket):
        guard gate.accepts(ticket) else {
          result.append(.rejected(ticket.serial, .stale))
          continue
        }
        guard case .tile(let frames) = ticket.command,
          Set(frames.keys.map(\.app)).count == frames.count
        else {
          result.append(.unsupported(ticket.serial))
          continue
        }
        let effects = model.reduce(.tile(frames), at: now)
        tickets.removeAll()
        if effects.isEmpty {
          for token in frames.keys { tickets[token.app] = ticket }
        }
        result.append(.reduced(ticket.serial, effects))
      }
      synchronize()
    }
    return result
  }

  /// Returns an ID only after both gate publication and model binding succeed.
  func prepare(_ app: AppToken, at now: Double) -> ControlOperationID? {
    guard advance(now), let ticket = tickets[app], gate.accepts(ticket) else { return nil }
    let effects = model.reduce(.dispatch(app), at: now)
    synchronize()
    guard case .prepare(let target) = effects.first,
      let evidence = model.observations[target.token]
    else { return nil }
    guard let id = gate.publish(target, evidence: evidence, ticket: ticket, at: now) else {
      _ = model.reduce(.preparationDiscarded(target), at: now)
      synchronize()
      return nil
    }
    let binding = model.reduce(.operationBound(target, id), at: now)
    guard binding.isEmpty else {
      if let terminal = gate.withdraw(id), gate.reserve(terminal) { _ = gate.acknowledge(terminal) }
      _ = model.reduce(.preparationDiscarded(target), at: now)
      synchronize()
      return nil
    }
    operations[id] = target
    tickets.removeValue(forKey: app)
    synchronize()
    return id
  }

  /// Reserve -> reduce -> mirror -> acknowledge, without suspension or work under a lock.
  func consume(_ receipt: SimulatedStepReceipt, at now: Double) -> SimulatedStepDisposition {
    guard advance(now), operations[receipt.permit.operation] != nil, gate.reserve(receipt) else {
      return .stale
    }
    let permit = receipt.permit
    _ = model.reduce(
      .operationStepFinished(
        OperationStepResult(
          operation: permit.operation, setter: permit.setter, admittedAt: permit.admittedAt,
          finishedAt: now, outcome: receipt.outcome)), at: now)
    synchronize()
    let disposition = gate.acknowledge(receipt, at: now)
    if case .terminal(let terminal) = disposition { _ = consume(terminal, at: now) }
    return disposition
  }

  @discardableResult
  func consume(_ receipt: SimulatedTerminalReceipt, at now: Double) -> Bool {
    guard advance(now), operations[receipt.operation] != nil, gate.reserve(receipt) else {
      return false
    }
    _ = model.reduce(.operationTerminated(receipt.operation), at: now)
    synchronize()
    operations.removeValue(forKey: receipt.operation)
    return gate.acknowledge(receipt)
  }

  private func synchronize() {
    _ = gate.synchronize(revision: model.layoutRevision, targets: model.admissionTargets(at: clock))
  }

  private func advance(_ now: Double) -> Bool {
    guard now.isFinite, now >= clock else { return false }
    clock = now
    return true
  }
}
