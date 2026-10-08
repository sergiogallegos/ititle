/// Simulation-only control records. No platform adapter currently supplies eligibility
/// or executes these effects. A future adapter must establish the full eligibility contract.
public enum ControlEligibility: Equatable, Sendable {
  case eligible, ineligible, unknown
}

public enum ControlCapability: Equatable, Sendable { case supported, unsupported, unknown }

public struct WindowObservation: Equatable, Sendable {
  public let token: WindowToken
  public let frame: Rect
  public let eligibility: ControlEligibility
  public let positionSettable: ControlCapability
  public let sizeSettable: ControlCapability
  public let environmentEpoch: UInt64
  public let workerSequence: UInt64
  public let sampledAt: Double

  public init(
    token: WindowToken, frame: Rect, eligibility: ControlEligibility,
    positionSettable: ControlCapability, sizeSettable: ControlCapability,
    environmentEpoch: UInt64, workerSequence: UInt64, sampledAt: Double
  ) {
    self.token = token
    self.frame = frame
    self.eligibility = eligibility
    self.positionSettable = positionSettable
    self.sizeSettable = sizeSettable
    self.environmentEpoch = environmentEpoch
    self.workerSequence = workerSequence
    self.sampledAt = sampledAt
  }
}

public struct FrameTarget: Equatable, Sendable {
  public let token: WindowToken
  public let frame: Rect
  public let environmentEpoch: UInt64
  public let layoutRevision: UInt64
  public let admissionGeneration: UInt64
  public let observationSequence: UInt64
  public let plannedAt: Double
}

public enum SimulatedSetter: Equatable, Sendable { case size, position }

/// Emitting this permit is the simulation's admission point, not cancellable IPC.
public struct SetterPermit: Equatable, Sendable {
  public let target: FrameTarget
  public let setter: SimulatedSetter
  public let admittedAt: Double
}

public enum ControlOutcome: Equatable, Sendable { case succeeded, unavailable, unknownOutcome }

public struct ApplyResult: Equatable, Sendable {
  public let target: FrameTarget
  public let observation: WindowObservation?
  public let startedAt: Double
  public let finishedAt: Double
  public let outcome: ControlOutcome

  public init(
    target: FrameTarget, observation: WindowObservation?, startedAt: Double,
    finishedAt: Double, outcome: ControlOutcome
  ) {
    self.target = target
    self.observation = observation
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.outcome = outcome
  }
}

public enum SuspensionReason: Equatable, Sendable { case environmentChanged, uncertain }
public enum ControlState: Equatable, Sendable {
  case permissionRequired, paused, active
  case suspended(SuspensionReason)
  case stopping
}
public enum ControlRejection: Equatable, Sendable {
  case invalidTime, permission, stopped, capacity, invalidPlan, staleObservation, staleWork
}

public enum ControlEvent: Sendable {
  case permission(Bool)
  /// Tokens must come from one monotonically increasing process-generation issuer.
  case attach(AppToken)
  case appTerminated(AppToken)
  case windowDestroyed(WindowToken)
  case registrySnapshot(ProbeRegistrySnapshot)
  case observation(WindowObservation)
  /// An explicit complete absolute plan, not a relative command or automatic retry.
  case tile([WindowToken: Rect])
  case pause, resume, quit
  case environmentChanged(SuspensionReason)
  case overflow(AppToken)
  case dispatch(AppToken)
  case admit(FrameTarget, SimulatedSetter)
  case setterFinished(SetterPermit, ControlOutcome)
  case completed(ApplyResult)
}

public enum ControlEffect: Equatable, Sendable {
  case rejected(ControlRejection)
  case admissionRevoked(UInt64)
  case reconcile(AppToken)
  case prepare(FrameTarget)
  case perform(SetterPermit)
  case readback(FrameTarget)
}

/// Deterministic, synchronous reduction with no I/O, locks, tasks, or platform objects.
/// Callers serialize events. This does NOT implement the future worker-side atomic
/// admission mailbox; tests deliver events directly to simulate its linearization.
public struct ControlModel: Sendable {
  public private(set) var state: ControlState = .permissionRequired
  public private(set) var environmentEpoch: UInt64 = 0
  public private(set) var layoutRevision: UInt64 = 0
  public private(set) var admissionGeneration: UInt64 = 0
  public private(set) var observations: [WindowToken: WindowObservation] = [:]
  public private(set) var desired: [WindowToken: Rect] = [:]
  public private(set) var pending: [WindowToken: FrameTarget] = [:]
  public private(set) var dirty: Set<WindowToken> = []

  private enum Phase: Equatable, Sendable {
    case ready(SimulatedSetter)
    case executing(SetterPermit)
    case readback
  }
  private struct Flight: Sendable {
    let target: FrameTarget
    var phase: Phase
    var firstAdmission: Double?
    var readbackRequestedAt: Double?
  }
  private struct Attachment: Sendable {
    let token: AppToken
    var registryRevision: UInt64?
    var highestSerial: UInt64 = 0
    var sequence: UInt64 = 0
    var invalidatedAt: Double = 0
    var lastSampleTime: Double = 0
  }
  private var apps: [Int32: Attachment] = [:]
  private var live: Set<WindowToken> = []
  private var flights: [AppToken: Flight] = [:]
  private var highestGeneration: UInt64 = 0
  private var trusted = false
  private var clock: Double = 0
  public let maximumWindows: Int
  public let maximumApps: Int
  public let maximumObservationAge: Double

  /// Age is a simulation policy, not a measured AX control default.
  public init(
    maximumWindows: Int = 256, maximumApps: Int = 16,
    maximumObservationAge: Double = 0.5
  ) {
    precondition(maximumWindows > 0 && maximumApps > 0)
    precondition(maximumObservationAge.isFinite && maximumObservationAge > 0)
    self.maximumWindows = maximumWindows
    self.maximumApps = maximumApps
    self.maximumObservationAge = maximumObservationAge
  }

  public var inFlightCount: Int { flights.count }

  public mutating func reduce(_ event: ControlEvent, at now: Double) -> [ControlEffect] {
    // Safety controls bypass timestamp validation, just as they bypass backlogs.
    let validTime = now.isFinite && now >= clock
    if validTime { clock = now }
    switch event {
    case .quit:
      guard state != .stopping else { return [] }
      state = .stopping
      return revoke()
    case .pause:
      guard state != .stopping else { return [.rejected(.stopped)] }
      state = trusted ? .paused : .permissionRequired
      return revoke()
    case .permission(false):
      guard state != .stopping else { return [.rejected(.stopped)] }
      trusted = false
      state = .permissionRequired
      environmentEpoch += 1
      observations.removeAll()
      desired.removeAll()
      return revoke()
    default: break
    }
    guard validTime else { return [.rejected(.invalidTime)] }
    guard state != .stopping else { return [.rejected(.stopped)] }
    switch event {
    case .permission(true):
      if !trusted {
        trusted = true
        state = .paused
      }
      return []
    case .attach(let token):
      if apps[token.pid]?.token == token { return [] }
      guard token.generation > highestGeneration else { return [.rejected(.staleWork)] }
      guard apps[token.pid] != nil || apps.count < maximumApps else {
        return [.rejected(.capacity)]
      }
      if let old = apps[token.pid]?.token { removeApp(old) }
      highestGeneration = token.generation
      apps[token.pid] = Attachment(token: token, invalidatedAt: clock)
      return []
    case .appTerminated(let app):
      if isCurrent(app) { removeApp(app) }
      return []
    case .registrySnapshot(let snapshot):
      guard var attachment = apps[snapshot.app.pid], attachment.token == snapshot.app,
        snapshot.environmentEpoch == environmentEpoch,
        snapshot.revision > (attachment.registryRevision ?? 0),
        snapshot.highestSerial >= attachment.highestSerial,
        snapshot.windows.count <= 64,
        snapshot.windows.allSatisfy({
          $0.app == snapshot.app && $0.serial > 0 && $0.serial <= snapshot.highestSerial
            && (live.contains($0) || $0.serial > attachment.highestSerial)
        })
      else { return [.rejected(.staleWork)] }
      let previous = live.filter { $0.app == snapshot.app }
      guard live.count - previous.count + snapshot.windows.count <= maximumWindows else {
        return [.rejected(.capacity)]
      }
      for token in previous.subtracting(snapshot.windows) {
        live.remove(token)
        observations.removeValue(forKey: token)
        desired.removeValue(forKey: token)
        pending.removeValue(forKey: token)
        dirty.remove(token)
      }
      live.formUnion(snapshot.windows)
      attachment.highestSerial = snapshot.highestSerial
      attachment.registryRevision = snapshot.revision
      apps[snapshot.app.pid] = attachment
      return []
    case .windowDestroyed(let token):
      guard var attachment = apps[token.app.pid], attachment.token == token.app else { return [] }
      // A destruction can arrive before the first observation of a new token.
      // Retire its serial too; a delayed read must not introduce it afterward.
      attachment.highestSerial = max(attachment.highestSerial, token.serial)
      apps[token.app.pid] = attachment
      live.remove(token)
      observations.removeValue(forKey: token)
      desired.removeValue(forKey: token)
      pending.removeValue(forKey: token)
      dirty.remove(token)
      // Keep a blocked app's slot until its worker acknowledges completion.
      return []
    case .observation(let observation):
      guard trusted else { return [.rejected(.permission)] }
      guard accept(observation, at: now) else { return [.rejected(.staleObservation)] }
      return []
    case .tile(let plan):
      guard trusted else { return [.rejected(.permission)] }
      guard !plan.isEmpty, plan.count <= maximumWindows,
        plan.allSatisfy({ validFrame($0.value) && fresh($0.key, at: now) })
      else {
        state = .paused
        return revoke() + [.rejected(plan.count > maximumWindows ? .capacity : .invalidPlan)]
      }
      layoutRevision += 1
      desired = plan
      pending.removeAll()
      state = .active
      for (token, frame) in plan {
        pending[token] = FrameTarget(
          token: token, frame: frame,
          environmentEpoch: environmentEpoch, layoutRevision: layoutRevision,
          admissionGeneration: admissionGeneration,
          observationSequence: observations[token]!.workerSequence, plannedAt: now)
      }
      return []
    case .resume:
      guard trusted else { return [.rejected(.permission)] }
      state = .paused
      return revoke() + orderedApps().map(ControlEffect.reconcile)
    case .environmentChanged(let reason):
      environmentEpoch += 1
      observations.removeAll()
      desired.removeAll()
      state = trusted ? .suspended(reason) : .permissionRequired
      return revoke() + orderedApps().map(ControlEffect.reconcile)
    case .overflow(let app):
      guard isCurrent(app) else { return [] }
      return invalidate(app)
    case .dispatch(let app):
      guard state == .active, isCurrent(app), flights[app] == nil else { return [] }
      guard
        let target = pending.values.filter({ $0.token.app == app })
          .min(by: { $0.token.serial < $1.token.serial })
      else { return [] }
      guard current(target, at: now) else { return invalidate(app) }
      pending.removeValue(forKey: target.token)
      flights[app] = Flight(target: target, phase: .ready(.size))
      return [.prepare(target)]
    case .admit(let target, let setter):
      guard var flight = flights[target.token.app], flight.target == target,
        flight.phase == .ready(setter)
      else { return [.rejected(.staleWork)] }
      guard current(target, at: now) else {
        flights.removeValue(forKey: target.token.app)
        return invalidate(target.token.app) + [.rejected(.staleWork)]
      }
      let permit = SetterPermit(target: target, setter: setter, admittedAt: now)
      flight.phase = .executing(permit)
      if flight.firstAdmission == nil { flight.firstAdmission = now }
      flights[target.token.app] = flight
      return [.perform(permit)]
    case .setterFinished(let permit, let outcome):
      let target = permit.target
      guard var flight = flights[target.token.app], flight.target == target,
        flight.phase == .executing(permit)
      else { return [.rejected(.staleWork)] }
      guard outcome == .succeeded, current(target, at: now) else {
        flights.removeValue(forKey: target.token.app)
        return invalidate(target.token.app)
      }
      flight.phase = permit.setter == .size ? .ready(.position) : .readback
      if permit.setter == .position { flight.readbackRequestedAt = now }
      flights[target.token.app] = flight
      return permit.setter == .position ? [.readback(target)] : []
    case .completed(let result):
      let target = result.target
      guard let flight = flights[target.token.app], flight.target == target,
        flight.phase == .readback
      else { return [.rejected(.staleWork)] }
      flights.removeValue(forKey: target.token.app)
      guard current(target, at: now), result.outcome == .succeeded,
        result.startedAt == flight.firstAdmission,
        result.finishedAt.isFinite, result.finishedAt >= result.startedAt,
        result.finishedAt <= now,
        let observation = result.observation, observation.token == target.token,
        let readbackTime = flight.readbackRequestedAt,
        observation.sampledAt >= readbackTime,
        observation.sampledAt <= result.finishedAt,
        observation.frame == target.frame,
        eligible(observation), accept(observation, at: now)
      else {
        return invalidate(target.token.app)
      }
      return []
    case .quit, .pause, .permission(false):
      return []  // Handled before timestamp validation.
    }
  }

  private func isCurrent(_ app: AppToken) -> Bool { apps[app.pid]?.token == app }

  private func eligible(_ observation: WindowObservation) -> Bool {
    observation.eligibility == .eligible && observation.positionSettable == .supported
      && observation.sizeSettable == .supported
  }

  private func fresh(_ token: WindowToken, at now: Double) -> Bool {
    guard live.contains(token), isCurrent(token.app), !dirty.contains(token),
      let observation = observations[token]
    else { return false }
    return observation.environmentEpoch == environmentEpoch && eligible(observation)
      && now >= observation.sampledAt && now - observation.sampledAt <= maximumObservationAge
  }

  private func current(_ target: FrameTarget, at now: Double) -> Bool {
    state == .active && trusted && target.environmentEpoch == environmentEpoch
      && target.layoutRevision == layoutRevision
      && target.admissionGeneration == admissionGeneration
      && desired[target.token] == target.frame && fresh(target.token, at: now)
      && observations[target.token]?.workerSequence == target.observationSequence
  }

  private mutating func accept(_ observation: WindowObservation, at now: Double) -> Bool {
    let token = observation.token
    guard var app = apps[token.app.pid], app.token == token.app,
      flights[token.app] == nil, observation.environmentEpoch == environmentEpoch,
      observation.workerSequence > app.sequence,
      observation.sampledAt.isFinite, observation.sampledAt >= app.invalidatedAt,
      observation.sampledAt >= app.lastSampleTime,
      observation.sampledAt <= now, now - observation.sampledAt <= maximumObservationAge,
      validFrame(observation.frame)
    else { return false }
    if !live.contains(token) {
      guard app.registryRevision == nil, token.serial > app.highestSerial,
        live.count < maximumWindows
      else { return false }
      app.highestSerial = token.serial
      live.insert(token)
    }
    app.sequence = observation.workerSequence
    app.lastSampleTime = observation.sampledAt
    apps[token.app.pid] = app
    observations[token] = observation
    dirty.remove(token)
    return true
  }

  private mutating func revoke() -> [ControlEffect] {
    admissionGeneration += 1
    pending.removeAll()
    dirty.formUnion(live)
    for pid in Array(apps.keys) { apps[pid]?.invalidatedAt = clock }
    // Prepared (not admitted) work can be discarded; executing/readback work owns
    // its slot until acknowledgement, preventing replacement of stuck workers.
    flights = flights.filter {
      if case .ready = $0.value.phase { return false }
      return true
    }
    return [.admissionRevoked(admissionGeneration)]
  }

  private mutating func invalidate(_ app: AppToken) -> [ControlEffect] {
    guard isCurrent(app) else { return [] }
    apps[app.pid]?.invalidatedAt = clock
    dirty.formUnion(live.filter { $0.app == app })
    pending = pending.filter { $0.key.app != app }
    return [.reconcile(app)]
  }

  private mutating func removeApp(_ app: AppToken) {
    live = live.filter { $0.app != app }
    dirty = dirty.filter { $0.app != app }
    observations = observations.filter { $0.key.app != app }
    desired = desired.filter { $0.key.app != app }
    pending = pending.filter { $0.key.app != app }
    flights.removeValue(forKey: app)
    apps.removeValue(forKey: app.pid)
  }

  private func orderedApps() -> [AppToken] {
    apps.values.map(\.token).sorted { $0.generation < $1.generation }
  }
}

private func validFrame(_ frame: Rect) -> Bool {
  [frame.x, frame.y, frame.width, frame.height, frame.x + frame.width, frame.y + frame.height]
    .allSatisfy(\.isFinite) && frame.width > 0 && frame.height > 0
}
