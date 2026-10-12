import Foundation

/// Predeclared worst-case output, including newline bytes and terminal reserve.
public enum FixtureTimingBudget {
  public static let attempts = 28
  public static let pairBytes = 6144
  public static let eventBytes = 512
  public static let summaryBytes = 16384
  public static let manifestBytes = 1024
  public static let outputBytes = 262144
  public static let reservedBytes =
    attempts * pairBytes + 128 * eventBytes + summaryBytes + manifestBytes + 512
  public static let cohortAttempts = [
    "ordinary": 4, "dispatch": 4, "assessment": 4, "invalidation": 16,
  ]

  public static func phase(cohort: FixtureTimingCohort, offset: Int) -> FixtureTimingPhase {
    guard cohort == .invalidation else { return .observation }
    if offset % 2 == 1 { return .recovery }
    if offset < 8 { return .pause }
    return offset == 14 ? .failureProbe : .sheet
  }
}

public struct FixtureTimingManifest: Codable, Sendable {
  public private(set) var kind = "manifest"
  public private(set) var schema = 2
  public let os: String
  public let utc: String
  public let labHash: String
  public let fixtureHash: String
  public let initialContext: FixtureUseContext
  public let controlledExclusion: Bool
  public private(set) var cohortAttempts = FixtureTimingBudget.cohortAttempts
  public private(set) var attemptLimit = FixtureTimingBudget.attempts
  public private(set) var eventLimit = 128
  public private(set) var outputLimit = FixtureTimingBudget.outputBytes
  public private(set) var pairLimit = FixtureTimingBudget.pairBytes
  public private(set) var eventByteLimit = FixtureTimingBudget.eventBytes
  public private(set) var deadlineSeconds = 180
  public private(set) var readerSeconds = 5
  public private(set) var freshness = "unmeasured"
  public private(set) var failureProbe = "invalidationOffset14InvalidPID"

  public init(
    os: String, utc: String, labHash: String, fixtureHash: String,
    initialContext: FixtureUseContext, controlledExclusion: Bool = false
  ) {
    self.os = os
    self.utc = utc
    self.labHash = labHash
    self.fixtureHash = fixtureHash
    self.initialContext = initialContext
    self.controlledExclusion = controlledExclusion
  }

  public var valid: Bool {
    func hash(_ value: String) -> Bool {
      value.utf8.count == 64
        && value.utf8.allSatisfy {
          (48...57).contains($0) || (97...102).contains($0)
        }
    }
    return kind == "manifest" && schema == 2 && os.utf8.count <= 128
      && utc.utf8.count <= 32 && ISO8601DateFormatter().date(from: utc) != nil
      && hash(labHash) && hash(fixtureHash) && initialContext.expected.serial == 1
      && initialContext.trusted && !initialContext.paused && !initialContext.stopped
      && cohortAttempts == FixtureTimingBudget.cohortAttempts
      && attemptLimit == FixtureTimingBudget.attempts && eventLimit == 128
      && outputLimit == FixtureTimingBudget.outputBytes
      && pairLimit == FixtureTimingBudget.pairBytes
      && eventByteLimit == FixtureTimingBudget.eventBytes && deadlineSeconds == 180
      && readerSeconds == 5 && freshness == "unmeasured"
      && failureProbe == "invalidationOffset14InvalidPID"
  }
}

public struct FixtureTimingReplayReport: Encodable, Sendable {
  public let kind = "replay"
  public let attempts: Int
  public let assessed: Int
  public let failed: Int
  public let absent: Int
  public let complete: Bool
  public let calibrationSuitable: Bool
  public let outcomes: [String: Int]
  /// Each snapshot contributes its fixed unmet requirements; these are not primary outcomes.
  public let exclusions: [String: Int]
}

/// Bounded schema-2 replay through the existing host, with no AX/AppKit dependency or policy.
public enum FixtureTimingReplay {
  public enum Failure: String, Error { case malformed, historicalNonReplayable, mismatch, bound }

  private struct Terminal: Codable {
    var kind: String
    let orderly: Bool
    let complete: Bool
    let attempts: Int
    let occupied: Bool
    let calibrationSuitable: Bool
  }

  private enum Operation {
    case begin(FixtureTimingRecord)
    case finish(FixtureTimingRecord)
    case event(FixtureTimingEvent)
  }

  private static func decode<T: Codable>(_ type: T.Type, data: Data) throws -> T {
    let value = try JSONDecoder().decode(type, from: data)
    let original = try JSONSerialization.jsonObject(with: data) as? NSDictionary
    let canonical =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
      as? NSDictionary
    guard let original, let canonical, original == canonical else { throw Failure.malformed }
    return value
  }

  public static func review(_ data: Data) throws -> FixtureTimingReplayReport {
    guard !data.isEmpty, data.count <= FixtureTimingBudget.outputBytes, data.last == 10 else {
      throw Failure.bound
    }
    let lines = data.split(separator: 10, omittingEmptySubsequences: false).dropLast()
    guard lines.count <= 132 + FixtureTimingBudget.attempts else { throw Failure.bound }
    var manifest: FixtureTimingManifest?
    var records: [FixtureTimingRecord] = []
    var events: [FixtureTimingEvent] = []
    var summary: Data?
    var terminal: Terminal?
    var lastBoundary = 0.0
    var lastEvent = 0.0
    var cohortCounts: [String: Int] = [:]
    var snapshotRequest: UInt64 = 0
    var snapshotSequence: UInt64 = 0
    var sourceState: UInt64 = 0
    var sourceRegistry: UInt64 = 0
    for line in lines {
      let bytes = Data(line)
      guard bytes.count < FixtureTimingBudget.summaryBytes,
        let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
        let kind = object["kind"] as? String, terminal == nil
      else { throw Failure.malformed }
      if object["schema"] as? Int == 1 { throw Failure.historicalNonReplayable }
      switch kind {
      case "manifest":
        guard manifest == nil, records.isEmpty, events.isEmpty,
          bytes.count < FixtureTimingBudget.manifestBytes
        else { throw Failure.malformed }
        let value = try decode(FixtureTimingManifest.self, data: bytes)
        guard value.valid else { throw Failure.malformed }
        manifest = value
      case "pair":
        guard let manifest, summary == nil, bytes.count < FixtureTimingBudget.pairBytes else {
          throw Failure.malformed
        }
        let record = try decode(FixtureTimingRecord.self, data: bytes)
        let offset = cohortCounts[record.cohort.rawValue, default: 0]
        let expectedCohort: FixtureTimingCohort =
          records.count < 4
          ? .ordinary
          : records.count < 8
            ? .dispatch
            : records.count < 12 ? .assessment : .invalidation
        let delay =
          record.cohort == .dispatch || record.cohort == .assessment
          ? [0.0, 0.05, 0.2, 0.5][offset % 4] : 0
        guard record.valid, record.run == manifest.initialContext.expected.run,
          record.index == records.count + 1, record.index <= manifest.attemptLimit,
          record.cohort == expectedCohort,
          offset < manifest.cohortAttempts[record.cohort.rawValue]!,
          record.phase
            == (manifest.controlledExclusion && record.index == 1
              ? .exclusion : FixtureTimingBudget.phase(cohort: record.cohort, offset: offset)),
          record.requestedDelay == delay,
          (record.times.values.min() ?? lastBoundary) >= lastBoundary
        else { throw Failure.malformed }
        for snapshot in [record.before, record.after].compactMap({ $0 }) {
          let state = UInt64(snapshot.value("stateRevision")!)!
          let registry = UInt64(snapshot.value("registryRevision")!)!
          guard snapshot.run == record.run, snapshot.request > snapshotRequest,
            snapshot.sequence > snapshotSequence, state >= sourceState, registry >= sourceRegistry
          else { throw Failure.malformed }
          snapshotRequest = snapshot.request
          snapshotSequence = snapshot.sequence
          sourceState = state
          sourceRegistry = registry
        }
        if let before = record.before {
          guard before.request == record.request else { throw Failure.malformed }
          if let after = record.after {
            guard before.request < UInt64.max, after.request == before.request + 1 else {
              throw Failure.malformed
            }
          }
        }
        lastBoundary = record.times.values.max() ?? lastBoundary
        cohortCounts[record.cohort.rawValue] = offset + 1
        records.append(record)
      case "event":
        guard manifest != nil, summary == nil, events.count < 128,
          bytes.count < FixtureTimingBudget.eventBytes
        else { throw Failure.bound }
        let event = try decode(FixtureTimingEvent.self, data: bytes)
        guard event.kind == "event", event.hostEvent != nil, event.context != nil,
          event.time.isFinite, event.time >= 0, event.time >= lastEvent
        else { throw Failure.malformed }
        lastEvent = event.time
        events.append(event)
      case "summary":
        guard manifest != nil, summary == nil else { throw Failure.malformed }
        let expected =
          try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(FixtureTimingSummary(records: records))) as! NSDictionary
        guard expected == object as NSDictionary else { throw Failure.mismatch }
        summary = bytes
      case "terminal":
        guard summary != nil, bytes.count < 512 else { throw Failure.malformed }
        terminal = try decode(Terminal.self, data: bytes)
      default: throw Failure.malformed
      }
    }
    guard let manifest, let terminal, terminal.kind == "terminal",
      terminal.attempts == records.count,
      !terminal.complete
        || (terminal.orderly && !terminal.occupied
          && records.count == FixtureTimingBudget.attempts)
    else { throw Failure.malformed }

    var operations: [(Double, Operation)] = events.map { ($0.time, .event($0)) }
    var absent = 0
    for record in records {
      guard let admission = record.time(.hostAdmission), record.admitted != nil,
        record.request != nil, let end = record.time(.terminal), record.final != nil
      else {
        guard [.incomplete, .timedOut, .malformedTiming].contains(record.outcome) else {
          throw Failure.malformed
        }
        absent += 1
        continue
      }
      operations.append((admission, .begin(record)))
      operations.append((record.time(.assessmentEntry) ?? end, .finish(record)))
    }
    operations.sort { $0.0 < $1.0 }
    // Equal operation times cannot establish owner ordering; do not invent it.
    guard zip(operations, operations.dropFirst()).allSatisfy({ $0.0 < $1.0 }) else {
      throw Failure.malformed
    }
    var host = FixtureDiagnosticHost(context: manifest.initialContext)
    var assessed = 0
    var failed = 0
    var outcomes: [String: Int] = [:]
    var exclusions: [String: Int] = [:]
    for (_, operation) in operations {
      switch operation {
      case .begin(let record):
        guard record.admitted == host.context, host.pendingRequest == nil else {
          throw Failure.mismatch
        }
        try host.begin(request: record.request!)
      case .event(let event):
        guard event.pending == host.pendingRequest else { throw Failure.mismatch }
        host.observe(event.hostEvent!)
        guard event.context == host.context, event.revocation == host.context.revocation else {
          throw Failure.mismatch
        }
      case .finish(let record):
        guard record.final == host.context else { throw Failure.mismatch }
        if let result = record.assessment {
          guard let before = record.before, let after = record.after,
            let focused = record.focused, let start = record.axStart, let end = record.axEnd,
            let now = record.time(.assessmentEntry), record.time(.assessmentExit) != nil,
            record.time(.inputsReady) != nil,
            FixtureTimingPoint.allCases.allSatisfy({ record.time($0) != nil })
          else { throw Failure.malformed }
          let actual = host.finish(
            request: record.request!, before: before, focused: focused,
            axStart: start, axEnd: end, after: after, now: now)
          let outcome: FixtureTimingOutcome =
            actual == .historicalConsistent
            ? .completed
            : actual == .contextRevoked ? .revoked : .rejected
          guard actual == result, record.outcome == outcome else { throw Failure.mismatch }
          assessed += 1
          outcomes[actual.rawValue, default: 0] += 1
        } else {
          guard [.failed, .timedOut, .incomplete].contains(record.outcome) else {
            throw Failure.malformed
          }
          if record.outcome == .failed {
            guard record.before != nil, record.after == nil, record.focused == nil,
              record.axStart == nil, record.axEnd == nil,
              [.admission, .entry, .exit, .publication, .receipt].allSatisfy({
                record.time($0) != nil
              }),
              FixtureTimingPoint.allCases.allSatisfy({
                (!$0.rawValue.hasPrefix("after")
                  && ![.inputsReady, .assessmentEntry, .assessmentExit].contains($0))
                  || record.time($0) == nil
              })
            else { throw Failure.malformed }
          }
          _ = host.abandon(request: record.request!)
          if record.outcome == .failed { failed += 1 } else { absent += 1 }
        }
        for snapshot in [record.before, record.after].compactMap({ $0 }) {
          for key in exclusionKeys(snapshot) { exclusions[key, default: 0] += 1 }
        }
      }
    }
    let suitable =
      terminal.complete && absent == 0 && !manifest.controlledExclusion
      && records.allSatisfy(\.expectedOutcome)
    guard terminal.calibrationSuitable == suitable else { throw Failure.mismatch }
    return FixtureTimingReplayReport(
      attempts: records.count, assessed: assessed, failed: failed, absent: absent,
      complete: terminal.complete, calibrationSuitable: suitable,
      outcomes: outcomes, exclusions: exclusions)
  }

  public static func exclusionKeys(_ snapshot: FixtureSafetySnapshot) -> [String] {
    var keys: [String] = []
    let expected = [
      "active": "true", "visible": "true", "frontmost": "true", "hidden": "false",
      "minimized": "false", "fullscreen": "false", "modal": "false", "attached": "false",
      "synthetic": "false", "sheetCount": "0", "tabCount": "1", "focusedFault": "false",
      "windowFault": "false", "structuralFault": "false", "uncertainty": "none",
      "originalLive": "true",
    ]
    for (key, value) in expected where snapshot.value(key) != value { keys.append(key) }
    if !["ordinary", "close-sheet"].contains(snapshot.value("scenario") ?? "") {
      keys.append("scenario")
    }
    if !["controlledFixtureTransitions", "observedEventsOnly"].contains(
      snapshot.value("lifecycleCoverage") ?? "")
    {
      keys.append("lifecycleCoverage")
    }
    if snapshot.liveSerials?.contains(1) != true { keys.append("liveSerials") }
    if snapshot.value("number") == "unavailable" { keys.append("number") }
    for key in FixtureSafetySnapshot.flags {
      if !["true", "false"].contains(snapshot.value(key) ?? "")
        && !(["tabSelected", "tabBar"].contains(key) && snapshot.value(key) == "notApplicable")
      {
        keys.append(key)
      }
    }
    return Array(Set(keys)).sorted()
  }
}
