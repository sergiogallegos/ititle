import Foundation

/// Bounded authority for an owned laboratory process, never production enrollment.
public struct FixtureLifecycleSource {
  public private(set) var stateRevision: UInt64
  public private(set) var registryRevision: UInt64
  public private(set) var uncertainty = "none"
  private var issued: UInt64
  private var live: Set<UInt64> = []
  private var sampled: [String: String]?

  public init(stateRevision: UInt64 = 1, registryRevision: UInt64 = 1, issued: UInt64 = 0) {
    self.stateRevision = stateRevision
    self.registryRevision = registryRevision
    self.issued = issued
    if stateRevision == 0 || registryRevision == 0 { uncertainty = "counterExhausted" }
  }

  public mutating func transition() {
    guard uncertainty == "none" else { return }
    guard stateRevision < UInt64.max else {
      uncertainty = "counterExhausted"
      return
    }
    stateRevision += 1
  }

  public mutating func create() throws -> UInt64 {
    guard uncertainty == "none" else { throw FixtureSnapshotError.exhausted }
    guard live.count < 8 else {
      transition()
      if registryRevision < UInt64.max {
        registryRevision += 1
      } else {
        uncertainty = "counterExhausted"
        throw FixtureSnapshotError.exhausted
      }
      uncertainty = "registryLimit"
      throw FixtureSnapshotError.unsupported
    }
    guard issued < UInt64.max, registryRevision < UInt64.max else {
      uncertainty = "counterExhausted"
      throw FixtureSnapshotError.exhausted
    }
    transition()
    guard uncertainty == "none" else { throw FixtureSnapshotError.exhausted }
    issued += 1
    registryRevision += 1
    live.insert(issued)
    return issued
  }

  /// Cleanup still removes membership after terminal exhaustion; no identity is revived.
  public mutating func retire(_ serial: UInt64) {
    guard live.remove(serial) != nil else { return }
    transition()
    if registryRevision < UInt64.max {
      registryRevision += 1
    } else {
      uncertainty = "counterExhausted"
    }
  }

  public mutating func observe(_ fields: [String: String]) {
    if let sampled, sampled != fields { transition() }
    sampled = fields
  }

  public var fields: [String: String] {
    [
      "stateRevision": String(stateRevision), "registryRevision": String(registryRevision),
      "liveSerials": uncertainty == "none"
        ? (live.isEmpty ? "none" : live.sorted().map(String.init).joined(separator: ","))
        : "unavailable",
      "originalLive": uncertainty == "none" ? (live.contains(1) ? "true" : "false") : "unavailable",
      "lifecycleCoverage": uncertainty == "none" ? "observedEventsOnly" : "unavailable",
      "uncertainty": uncertainty,
    ]
  }
}

public struct FixtureUseContext: Equatable, Sendable {
  public var expected: FixtureWindowIdentity
  public var environment: UInt64
  public var activation: UInt64
  public var revocation: UInt64
  public var trusted: Bool
  public var paused: Bool
  public var stopped: Bool

  public init(
    expected: FixtureWindowIdentity, environment: UInt64 = 0, activation: UInt64 = 0,
    revocation: UInt64 = 0, trusted: Bool = true, paused: Bool = false, stopped: Bool = false
  ) {
    self.expected = expected
    self.environment = environment
    self.activation = activation
    self.revocation = revocation
    self.trusted = trusted
    self.paused = paused
    self.stopped = stopped
  }
}

public struct FixtureDiagnosticAgePolicy: Equatable, Sendable {
  public let revision: UInt64
  public let maximumAge: Double
  public init(revision: UInt64, maximumAge: Double) throws {
    guard revision > 0, maximumAge.isFinite, maximumAge > 0 else {
      throw FixtureSnapshotError.malformed
    }
    self.revision = revision
    self.maximumAge = maximumAge
  }
}

public enum FixturePairResult: String, Sendable {
  case historicalConsistent, diagnosticUnexpired, incomplete, wrongRun, wrongWindow, wrongRequest
  case stale, contextRevoked, sourceChanged, retired, malformed, unsupported, expired, wrongPolicy
}

/// One pending read-only pair. Starting newer work clears the prior result immediately.
public struct FixturePairAssessment {
  public private(set) var current: FixturePairResult = .incomplete
  private var pending:
    (request: UInt64, context: FixtureUseContext, policy: FixtureDiagnosticAgePolicy?)?
  private var requestWatermark: UInt64 = 0
  private var sequenceWatermark: UInt64 = 0
  private var lastTime: Double = 0
  private var accepted:
    (context: FixtureUseContext, policy: FixtureDiagnosticAgePolicy?, expiry: Double?)?

  public init() {}

  public mutating func begin(
    request: UInt64, context: FixtureUseContext,
    policy: FixtureDiagnosticAgePolicy? = nil
  ) throws {
    guard request > requestWatermark, request < UInt64.max else { throw FixtureSnapshotError.stale }
    requestWatermark = request
    pending = (request, context, policy)
    accepted = nil
    current = .incomplete
  }

  public mutating func discard() {
    pending = nil
    accepted = nil
    current = .incomplete
  }

  public mutating func invalidate() {
    pending = nil
    accepted = nil
    current = .contextRevoked
  }

  @discardableResult
  public mutating func consume(
    request: UInt64, before: FixtureSafetySnapshot,
    focused: FixtureWindowIdentity, axStart: Double, axEnd: Double, after: FixtureSafetySnapshot,
    context: FixtureUseContext, now: Double
  ) -> FixturePairResult {
    guard let pending else {
      current = .incomplete
      return current
    }
    self.pending = nil
    func assess() -> FixturePairResult {
      guard request == pending.request, before.request == request else { return .wrongRequest }
      guard context == pending.context, context.trusted, !context.paused, !context.stopped else {
        return .contextRevoked
      }
      guard before.run == context.expected.run, after.run == before.run, focused.run == before.run
      else {
        return .wrongRun
      }
      guard focused == context.expected else { return .wrongWindow }
      // Snapshot state describes original serial 1 only; peer membership is not peer state.
      guard context.expected.serial == 1 else { return .unsupported }
      guard before.sequence > sequenceWatermark, after.sequence > before.sequence,
        after.request == request + 1
      else { return .stale }
      guard now.isFinite, axStart.isFinite, axEnd.isFinite, now >= lastTime,
        before.finishedAt <= axStart, axStart <= axEnd, axEnd <= after.startedAt,
        now >= after.finishedAt
      else { return .malformed }
      guard before.value("schema") == "2", after.value("schema") == "2" else { return .unsupported }
      guard before.value("stateRevision") == after.value("stateRevision"),
        before.value("registryRevision") == after.value("registryRevision")
      else { return .sourceChanged }
      for sample in [before, after] {
        guard sample.value("uncertainty") == "none",
          ["controlledFixtureTransitions", "observedEventsOnly"].contains(
            sample.value("lifecycleCoverage") ?? "")
        else { return .unsupported }
        guard let live = sample.liveSerials else { return .incomplete }
        guard live.contains(context.expected.serial) else { return .retired }
        guard sample.value("originalLive") == "true" else { return .retired }
        guard
          FixtureSafetySnapshot.flags.allSatisfy({
            ["true", "false"].contains(sample.value($0) ?? "")
              || (["tabSelected", "tabBar"].contains($0) && sample.value($0) == "notApplicable")
          }), sample.value("number") != "unavailable"
        else { return .incomplete }
        guard sample.value("active") == "true", sample.value("visible") == "true",
          sample.value("frontmost") == "true", sample.value("hidden") == "false",
          sample.value("minimized") == "false", sample.value("fullscreen") == "false",
          sample.value("modal") == "false", sample.value("attached") == "false",
          sample.value("synthetic") == "false", sample.value("sheetCount") == "0",
          sample.value("tabCount") == "1",
          ["focusedFault", "windowFault", "structuralFault"].allSatisfy({
            sample.value($0) == "false"
          }),
          ["ordinary", "close-sheet"].contains(sample.value("scenario") ?? "")
        else { return .unsupported }
      }
      let metadata: Set<String> = ["request", "sequence", "start", "end"]
      guard
        FixtureSafetySnapshot.keys.allSatisfy({
          metadata.contains($0) || before.value($0) == after.value($0)
        })
      else { return .sourceChanged }
      if let policy = pending.policy {
        let expiry = before.startedAt + policy.maximumAge
        guard expiry.isFinite, expiry > before.startedAt else { return .malformed }
        guard now < expiry else { return .expired }
        accepted = (context, policy, expiry)
        return .diagnosticUnexpired
      }
      accepted = (context, nil, nil)
      return .historicalConsistent
    }
    current = assess()
    sequenceWatermark = max(sequenceWatermark, before.sequence, after.sequence)
    if now.isFinite { lastTime = max(lastTime, now) }
    return current
  }

  @discardableResult
  public mutating func revalidate(
    context: FixtureUseContext,
    policy: FixtureDiagnosticAgePolicy? = nil, now: Double
  ) -> FixturePairResult {
    guard let accepted else { return current }
    if context != accepted.context || !context.trusted || context.paused || context.stopped {
      current = .contextRevoked
    } else if accepted.policy != policy {
      current = .wrongPolicy
    } else if !now.isFinite || now < lastTime {
      current = .malformed
    } else if let expiry = accepted.expiry, now >= expiry {
      current = .expired
    }
    if now.isFinite { lastTime = max(lastTime, now) }
    if current != .historicalConsistent && current != .diagnosticUnexpired { self.accepted = nil }
    return current
  }
}

/// Host-owned laboratory revocation. Every observed change advances a checked generation.
public struct FixtureHostAuthority {
  public private(set) var context: FixtureUseContext
  public private(set) var closed = false
  public init(context: FixtureUseContext) {
    self.context = context
    closed = context.stopped
  }

  public mutating func update(
    trusted: Bool? = nil, paused: Bool? = nil, stopped: Bool? = nil,
    environmentChanged: Bool = false, activationChanged: Bool = false
  ) {
    guard !closed else { return }
    guard context.revocation < UInt64.max,
      !environmentChanged || context.environment < UInt64.max,
      !activationChanged || context.activation < UInt64.max
    else {
      closed = true
      context.stopped = true
      return
    }
    context.revocation += 1
    if environmentChanged { context.environment += 1 }
    if activationChanged { context.activation += 1 }
    if let trusted { context.trusted = trusted }
    if let paused { context.paused = paused }
    if let stopped {
      context.stopped = stopped
      if stopped { closed = true }
    }
  }
}
