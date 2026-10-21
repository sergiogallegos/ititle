import Foundation

public enum FixtureLabStage: String, Codable, CaseIterable, Sendable {
  case trustPreflight, startup, baseline, manifest, setupPrecondition
  case normalizationWrite, normalizationAck, exclusionWrite, exclusionAck
  case activationWrite, activationAck, activationConfirmation, settle
  case admissionChecks, beforeSnapshot, hostAdmission, reader, sheetTransition, afterSnapshot
  case assessment, controlledExit, cleanup, drain, summary, output
}

public enum FixtureStopCategory: String, Codable, CaseIterable, Sendable {
  case untrusted, activationRefused, responseDeadline, collectionDeadline
  case childExited, childEOF, pipeRead, pipeWrite, protocolFailure, clockFailure, counterFailure
  case occupiedSetup, observerLimit, recordLimit, outputLimit, readerFailure, readerWatchdog
  case forcedCleanup, childExitNonzero, unclassified
  case unexpectedAcknowledgment
}

public enum FixtureSetupPurpose: String, Codable, CaseIterable, Sendable {
  case cohort, recovery, exclusion, reset

  public var stages: [FixtureLabStage] {
    if self == .exclusion { return [.setupPrecondition, .exclusionWrite, .exclusionAck] }
    return [
      .setupPrecondition, .normalizationWrite, .normalizationAck,
      .activationWrite, .activationAck, .activationConfirmation, .settle,
    ]
  }
}

/// Compact terminal setup observations; mask bits refer to the purpose's ordered stages.
public struct FixtureSetupRecord: Codable, Sendable {
  public private(set) var kind = "setup"
  public let sequence: Int
  public let nextIndex: Int
  public let cohort: FixtureTimingCohort
  public let purpose: FixtureSetupPurpose
  public let start: Double
  public private(set) var end: Double?
  public private(set) var stage: FixtureLabStage = .setupPrecondition
  public private(set) var completed: UInt16 = 0
  public var issued: UInt64
  public var correlated: UInt64
  public let revocationBefore: UInt64
  public var revocationAfter: UInt64
  public var pairOccupied: Bool
  public var readerOccupied: Bool
  public private(set) var failure: FixtureStopCategory?
  private var lastStageTime: Double

  private enum CodingKeys: String, CodingKey {
    case kind
    case sequence = "seq"
    case nextIndex = "next"
    case cohort, purpose, start, end, stage
    case completed = "done"
    case issued, correlated
    case revocationBefore = "revBefore"
    case revocationAfter = "revAfter"
    case pairOccupied = "pair"
    case readerOccupied = "reader"
    case failure
    case lastStageTime = "last"
  }

  public init(
    sequence: Int, nextIndex: Int, cohort: FixtureTimingCohort, purpose: FixtureSetupPurpose,
    at time: Double, issued: UInt64, correlated: UInt64, revocation: UInt64,
    pairOccupied: Bool, readerOccupied: Bool
  ) {
    self.sequence = sequence
    self.nextIndex = nextIndex
    self.cohort = cohort
    self.purpose = purpose
    start = time
    lastStageTime = time
    self.issued = issued
    self.correlated = correlated
    revocationBefore = revocation
    revocationAfter = revocation
    self.pairOccupied = pairOccupied
    self.readerOccupied = readerOccupied
  }

  public mutating func enter(_ next: FixtureLabStage, at time: Double) throws {
    guard end == nil, time.isFinite, time >= lastStageTime,
      let index = purpose.stages.firstIndex(of: next),
      completed == UInt16((1 << index) - 1)
    else { throw FixtureSnapshotError.malformed }
    stage = next
    lastStageTime = time
  }

  public mutating func complete(at time: Double) throws {
    guard end == nil, time.isFinite, time >= lastStageTime,
      let index = purpose.stages.firstIndex(of: stage),
      completed == UInt16((1 << index) - 1)
    else { throw FixtureSnapshotError.malformed }
    completed |= UInt16(1 << index)
    lastStageTime = time
  }

  public mutating func finish(at time: Double, failure: FixtureStopCategory? = nil) throws {
    guard end == nil, time.isFinite, time >= lastStageTime else {
      throw FixtureSnapshotError.malformed
    }
    end = time
    self.failure = failure
    guard valid else { throw FixtureSnapshotError.malformed }
  }

  var lastObservation: Double { lastStageTime }

  public var valid: Bool {
    guard kind == "setup", sequence > 0, sequence <= 14, nextIndex > 0, nextIndex <= 28,
      start.isFinite, start >= 0, lastStageTime.isFinite, lastStageTime >= start,
      let end, end.isFinite, end >= lastStageTime, correlated <= issued,
      revocationAfter >= revocationBefore, let index = purpose.stages.firstIndex(of: stage)
    else { return false }
    let preceding = UInt16((1 << index) - 1)
    guard completed == preceding || completed == preceding | UInt16(1 << index) else {
      return false
    }
    if failure == nil {
      return index == purpose.stages.count - 1
        && completed == UInt16((1 << purpose.stages.count) - 1)
        && !pairOccupied && !readerOccupied
    }
    return true
  }
}

/// First observed failure only; later drain/cleanup failures cannot replace it.
public struct FixtureFirstStop: Codable, Sendable {
  public private(set) var kind = "stop"
  public private(set) var schema = 3
  public let stage: FixtureLabStage
  public let category: FixtureStopCategory
  public let time: Double?
  public let setup: Int?
  public let request: UInt64?
  public let pairs: Int
  public let pairOccupied: Bool
  public let readerOccupied: Bool

  public init(
    stage: FixtureLabStage, category: FixtureStopCategory, at time: Double?,
    setup: Int? = nil, request: UInt64? = nil, pairs: Int,
    pairOccupied: Bool, readerOccupied: Bool
  ) {
    self.stage = stage
    self.category = category
    self.time = time?.isFinite == true && time! >= 0 ? time : nil
    self.setup = setup
    self.request = request
    self.pairs = pairs
    self.pairOccupied = pairOccupied
    self.readerOccupied = readerOccupied
  }

  public var valid: Bool {
    kind == "stop" && schema == 3 && (0...28).contains(pairs)
      && (setup == nil || (1...14).contains(setup!))
      && (request == nil || request! > 0)
      && (time == nil || (time!.isFinite && time! >= 0))
  }
}

public enum FixtureActivationDirection: String, Codable, Sendable { case activate, deactivate }
public enum FixtureActivationRelation: String, Codable, Sendable {
  case owned, unrelated, unavailable
}

public enum FixtureDiagnosticBudget {
  public static let setupLimit = 14
  public static let setupBytes = 512
  public static let summaryBytes = 15104
  public static let manifestBytes = 1280
  public static let closureBytes = 1024
  public static let reservedBytes = 28 * 6144 + 128 * 512 + 14 * 512 + 1280 + 15104 + 512 + 512
  public static let faultBytes = 512
  public static func summaryBytes(schema: Int) -> Int { schema >= 4 ? 14592 : summaryBytes }
  public static func reservedBytes(schema: Int) -> Int {
    28 * 6144 + 128 * 512 + 14 * 512 + 1280 + summaryBytes(schema: schema)
      + (schema >= 4 ? faultBytes : 0) + closureBytes
  }
}

/// Versioned diagnostics are checked before the unchanged schema-2 pair replay is used.
public enum FixtureDiagnosticReplay {
  private struct Terminal: Codable {
    let kind: String
    let schema: Int
    let orderly: Bool
    let complete: Bool
    let attempts: Int
    let records: Int
    let setups: Int
    let occupied: Bool
    let calibrationSuitable: Bool
    let firstStop: Bool
  }

  public static func review(_ data: Data) throws -> FixtureTimingReplayReport {
    typealias Failure = FixtureTimingReplay.Failure
    guard data.count <= FixtureTimingBudget.outputBytes, data.last == 10 else {
      throw Failure.bound
    }
    let rows = data.split(separator: 10, omittingEmptySubsequences: false).dropLast()
    guard let last = rows.last,
      let terminalObject = try JSONSerialization.jsonObject(with: Data(last)) as? [String: Any],
      let schema = terminalObject["schema"] as? Int, [3, 4, 5, 6].contains(schema),
      rows.count <= (schema >= 4 ? 175 : 174)
    else { throw Failure.bound }
    var manifest: FixtureTimingManifest?
    var records: [FixtureTimingRecord] = []
    var events: [FixtureTimingEvent] = []
    var setups: [FixtureSetupRecord] = []
    var stop: FixtureFirstStop?
    var terminal: Terminal?
    var summary: Data?
    var fault: FixtureSetupFaultRecord?
    var eofFault: FixtureOutputEOFRecord?
    var lastSetupEnd = 0.0
    var failedSetup = false
    for row in rows {
      let bytes = Data(row)
      guard bytes.count < FixtureDiagnosticBudget.summaryBytes(schema: schema),
        let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
        let kind = object["kind"] as? String, terminal == nil
      else { throw Failure.malformed }
      if stop != nil && kind != "terminal" { throw Failure.malformed }
      switch kind {
      case "manifest":
        guard manifest == nil, records.isEmpty, events.isEmpty, setups.isEmpty,
          bytes.count < FixtureDiagnosticBudget.manifestBytes
        else { throw Failure.malformed }
        let value = try FixtureTimingReplay.decode(FixtureTimingManifest.self, data: bytes)
        guard value.schema == schema, value.valid else { throw Failure.malformed }
        manifest = value
      case "setup":
        guard let manifest, summary == nil, !failedSetup, setups.count < 14,
          bytes.count < FixtureDiagnosticBudget.setupBytes
        else { throw Failure.bound }
        let setup = try FixtureTimingReplay.decode(FixtureSetupRecord.self, data: bytes)
        guard setup.valid, schema >= 4 || setup.failure != .unexpectedAcknowledgment,
          setup.sequence == setups.count + 1,
          setup.nextIndex == records.count + 1, setup.start >= lastSetupEnd,
          setup.start >= manifest.runStart!,
          records.last?.time(.terminal).map({ $0 <= setup.start }) ?? true,
          scheduleAllows(
            setup, records: records, setups: setups, exclusion: manifest.controlledExclusion)
        else { throw Failure.malformed }
        setups.append(setup)
        lastSetupEnd = setup.end!
        failedSetup = setup.failure != nil
      case "setupFault":
        guard schema >= 4, manifest != nil, fault == nil, eofFault == nil, summary == nil,
          bytes.count < FixtureDiagnosticBudget.faultBytes
        else { throw Failure.malformed }
        if schema == 6 {
          let value = try FixtureTimingReplay.decode(FixtureOutputEOFRecord.self, data: bytes)
          guard value.valid else { throw Failure.malformed }
          eofFault = value
        } else {
          let value = try FixtureTimingReplay.decode(FixtureSetupFaultRecord.self, data: bytes)
          guard value.valid else { throw Failure.malformed }
          fault = value
        }
      case "pair":
        guard schema == 3, manifest != nil, summary == nil, !failedSetup,
          bytes.count < FixtureTimingBudget.pairBytes
        else { throw Failure.malformed }
        let value = try FixtureTimingReplay.decode(FixtureTimingRecord.self, data: bytes)
        guard value.schema == 3, value.valid, value.index == records.count + 1,
          value.index <= 28,
          setups.last?.end.map({ $0 <= (value.times.values.min() ?? $0) }) ?? false,
          requiredSetup(value, setups: setups, exclusion: manifest!.controlledExclusion),
          !value.times.isEmpty, value.times.values.allSatisfy({ $0 >= manifest!.runStart! })
        else { throw Failure.malformed }
        records.append(value)
      case "event":
        guard manifest != nil, summary == nil, events.count < 128,
          bytes.count < FixtureTimingBudget.eventBytes
        else { throw Failure.bound }
        let event = try FixtureTimingReplay.decode(FixtureTimingEvent.self, data: bytes)
        guard event.hasValidMetadata(for: schema),
          event.context?.expected == manifest!.initialContext.expected,
          event.revocation == event.context?.revocation, event.time.isFinite,
          event.time >= manifest!.runStart!,
          events.last.map({ $0.time <= event.time }) ?? true
        else { throw Failure.malformed }
        events.append(event)
      case "summary":
        guard summary == nil, bytes.count < FixtureDiagnosticBudget.summaryBytes(schema: schema)
        else {
          throw Failure.malformed
        }
        let expected =
          try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(FixtureTimingSummary(records: records))) as! NSDictionary
        guard expected == object as NSDictionary else { throw Failure.mismatch }
        summary = bytes
      case "stop":
        guard stop == nil, bytes.count < 512 else { throw Failure.bound }
        let value = try FixtureTimingReplay.decode(FixtureFirstStop.self, data: bytes)
        guard value.valid, schema >= 4 || value.category != .unexpectedAcknowledgment,
          value.pairs <= records.count, records.count - value.pairs <= 1,
          value.setup == nil || value.setup == setups.last?.sequence
        else { throw Failure.malformed }
        stop = value
      case "terminal":
        guard bytes.count < 512 else { throw Failure.bound }
        terminal = try FixtureTimingReplay.decode(Terminal.self, data: bytes)
      default: throw Failure.malformed
      }
    }
    guard let terminal, terminal.kind == "terminal", terminal.schema == schema,
      terminal.records == records.count, terminal.setups == setups.count,
      terminal.attempts >= records.count, terminal.attempts <= 28,
      terminal.attempts - records.count <= 1, terminal.firstStop == (stop != nil),
      !terminal.complete || (stop == nil && summary != nil && terminal.attempts == 28),
      terminal.complete || stop != nil
    else { throw Failure.malformed }
    if schema == 6 {
      try FixtureOutputEOFReplay.validate(
        manifest: manifest, fault: eofFault, setups: setups, stop: stop,
        attempts: terminal.attempts, records: records.count, occupied: terminal.occupied,
        complete: terminal.complete, suitable: terminal.calibrationSuitable)
    } else if schema >= 4 {
      try FixtureSetupFaultReplay.validate(
        manifest: manifest, fault: fault, setups: setups, stop: stop,
        attempts: terminal.attempts, records: records.count, occupied: terminal.occupied,
        complete: terminal.complete, suitable: terminal.calibrationSuitable)
    }
    if schema >= 5, let time = stop?.time {
      guard events.allSatisfy({ $0.time <= time }) else { throw Failure.mismatch }
    }
    if let failed = setups.last, let category = failed.failure {
      guard stop?.setup == failed.sequence, stop?.category == category,
        stop?.stage == failed.stage
      else { throw Failure.mismatch }
      if let time = stop?.time {
        guard time >= failed.lastObservation, time <= failed.end! else { throw Failure.malformed }
      }
    }
    if let manifest {
      for setup in setups {
        let before =
          events.last(where: { $0.time < setup.start })?.revocation
          ?? manifest.initialContext.revocation
        let after =
          events.last(where: { $0.time <= setup.end! })?.revocation
          ?? manifest.initialContext.revocation
        guard setup.revocationBefore == before, setup.revocationAfter == after else {
          throw Failure.mismatch
        }
      }
    }
    if let stop, let start = manifest?.runStart, let time = stop.time {
      guard time >= start else { throw Failure.malformed }
      if stop.category == .collectionDeadline {
        guard time >= manifest!.collectionDeadline! else { throw Failure.malformed }
      }
    }
    guard let manifest else {
      guard records.isEmpty, events.isEmpty, setups.isEmpty, terminal.attempts == 0,
        !terminal.complete, !terminal.calibrationSuitable, !terminal.occupied,
        [.trustPreflight, .startup, .baseline, .manifest].contains(stop!.stage)
          || (stop!.stage == .output
            && [.recordLimit, .outputLimit, .protocolFailure].contains(stop!.category))
      else { throw Failure.malformed }
      return FixtureTimingReplayReport(
        attempts: 0, assessed: 0, failed: 0, absent: 0, complete: false,
        calibrationSuitable: false, outcomes: [:], exclusions: [:], setups: 0,
        firstStop: stop!.category, summaryPresent: summary != nil)
    }
    // Incomplete last-pair inputs cannot establish host/reducer outcomes. Retain
    // their diagnostics, replay only the fully observed prefix, and count absence.
    let partial = records.last.map { [.incomplete, .timedOut].contains($0.outcome) } ?? false
    if partial {
      guard !terminal.complete, stop != nil, records.last!.assessment == nil else {
        throw Failure.malformed
      }
    }
    guard !records.dropLast().contains(where: { [.incomplete, .timedOut].contains($0.outcome) })
    else {
      throw Failure.malformed
    }
    let prefix = partial ? Array(records.dropLast()) : records
    let cut =
      partial ? records.last!.time(.hostAdmission) ?? records.last!.times.values.min()! : nil
    let retainedEvents = events.filter { cut == nil || $0.time < cut! }
    var normalized = Data()
    func append<T: Encodable>(_ value: T) throws {
      normalized.append(try JSONEncoder().encode(value))
      normalized.append(10)
    }
    try append(
      FixtureTimingManifest(
        os: manifest.os, utc: manifest.utc, labHash: manifest.labHash,
        fixtureHash: manifest.fixtureHash,
        initialContext: manifest.initialContext, controlledExclusion: manifest.controlledExclusion))
    for event in retainedEvents {
      try append(
        FixtureTimingEvent(
          code: event.code, time: event.time,
          revocation: event.revocation, pending: event.pending, context: event.context))
    }
    for record in prefix {
      try append(record.historicalCopy())
    }
    try append(FixtureTimingSummary(records: prefix))
    let suitability =
      terminal.complete && !manifest.controlledSetupFailure!
      && !manifest.controlledExclusion && records.allSatisfy(\.expectedOutcome)
    guard terminal.calibrationSuitable == suitability else { throw Failure.mismatch }
    let historicalTerminal: [String: Any] = [
      "kind": "terminal", "orderly": terminal.orderly, "complete": terminal.complete,
      "attempts": prefix.count, "occupied": terminal.occupied, "calibrationSuitable": suitability,
    ]
    normalized.append(try JSONSerialization.data(withJSONObject: historicalTerminal))
    normalized.append(10)
    let report = try FixtureTimingReplay.reviewHistorical(normalized)
    return FixtureTimingReplayReport(
      attempts: terminal.attempts, assessed: report.assessed, failed: report.failed,
      absent: report.absent + (partial ? 1 : 0) + terminal.attempts - records.count,
      complete: report.complete, calibrationSuitable: report.calibrationSuitable,
      outcomes: report.outcomes, exclusions: report.exclusions, setups: setups.count,
      firstStop: stop?.category, summaryPresent: summary != nil)
  }

  private static func scheduleAllows(
    _ setup: FixtureSetupRecord, records: [FixtureTimingRecord], setups: [FixtureSetupRecord],
    exclusion: Bool
  ) -> Bool {
    let next = records.count + 1
    let cohort: FixtureTimingCohort =
      next <= 4
      ? .ordinary
      : next <= 8
        ? .dispatch
        : next <= 12 ? .assessment : .invalidation
    guard setup.cohort == cohort,
      !setups.contains(where: { $0.nextIndex == next && $0.purpose == setup.purpose })
    else { return false }
    switch setup.purpose {
    case .cohort:
      return [1, 5, 9, 13].contains(next)
        && !setups.contains(where: { $0.nextIndex == next && $0.purpose == .cohort })
    case .recovery: return next >= 14 && next % 2 == 0
    case .exclusion: return exclusion && next == 1 && setups.last?.purpose == .cohort
    case .reset: return exclusion && next == 2
    }
  }

  private static func requiredSetup(
    _ record: FixtureTimingRecord, setups: [FixtureSetupRecord], exclusion: Bool
  )
    -> Bool
  {
    let last = setups.last!
    if [1, 5, 9, 13].contains(record.index) {
      return last.nextIndex == record.index
        && last.purpose == (record.index == 1 && exclusion ? .exclusion : .cohort)
    }
    if record.index == 2 && exclusion { return last.nextIndex == 2 && last.purpose == .reset }
    if record.phase == .recovery {
      return last.nextIndex == record.index && last.purpose == .recovery
    }
    return true
  }
}
