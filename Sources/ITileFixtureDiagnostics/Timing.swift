import Foundation

/// Laboratory timestamps only. Missing boundaries stay absent, including on timeout.
public enum FixtureTimingPoint: String, CaseIterable, Sendable {
  case beforeSubmission, beforeWrite, beforeStart, beforeEnd, beforeReceipt, beforeSelection
  case beforeParseEntry, beforeParse, hostAdmission
  case admission, entry, exit, publication, receipt
  case afterSubmission, afterWrite, afterStart, afterEnd, afterReceipt, afterSelection
  case afterParseEntry, afterParse
  case inputsReady, assessmentEntry, assessmentExit, terminal
}

public enum FixtureTimingOutcome: String, Codable, Sendable {
  case completed, rejected, revoked, failed, timedOut, incomplete, malformedTiming
}

public enum FixtureTimingPhase: String, Codable, Sendable {
  case observation, pause, sheet, failureProbe, recovery, exclusion
}

public struct FixtureTimingRecord: Codable, Sendable {
  public private(set) var schema = 2
  public private(set) var kind = "pair"
  public let index: Int
  public let cohort: FixtureTimingCohort
  public let requestedDelay: Double
  public let run: UUID
  public var phase: FixtureTimingPhase = .observation
  public var request: UInt64?
  public var before: FixtureSafetySnapshot?
  public var after: FixtureSafetySnapshot?
  public var admitted: FixtureUseContext?
  public var final: FixtureUseContext?
  public var focused: FixtureWindowIdentity?
  public var axStart: Double?
  public var axEnd: Double?
  public var outcome: FixtureTimingOutcome = .incomplete
  public var assessment: FixturePairResult?
  public private(set) var times: [String: Double] = [:]

  public init(
    index: Int, cohort: FixtureTimingCohort, requestedDelay: Double, run: UUID, schema: Int = 2
  ) {
    self.index = index
    self.cohort = cohort
    self.requestedDelay = requestedDelay
    self.run = run
    self.schema = schema
  }

  public mutating func mark(_ point: FixtureTimingPoint, at time: Double) {
    times[point.rawValue] = time
  }

  public func time(_ point: FixtureTimingPoint) -> Double? { times[point.rawValue] }

  func historicalCopy() -> Self {
    var value = self
    value.schema = 2
    return value
  }

  public var valid: Bool {
    guard [2, 3].contains(schema), kind == "pair", index > 0, index <= 64,
      requestedDelay.isFinite, requestedDelay >= 0,
      requestedDelay <= 0.5,
      times.allSatisfy({ key, value in
        FixtureTimingPoint(rawValue: key) != nil && value.isFinite && value >= 0
      })
    else { return false }
    for sample in [before, after].compactMap({ $0 }) {
      guard sample.value("schema") == "2", sample.line.utf8.count <= 1280 else { return false }
    }
    for value in [axStart, axEnd].compactMap({ $0 }) {
      guard value.isFinite, value >= 0 else { return false }
    }
    if let axStart, let axEnd {
      guard axStart <= axEnd, axStart >= (time(.entry) ?? axStart),
        axEnd <= (time(.exit) ?? axEnd)
      else { return false }
    }
    if let before {
      guard time(.beforeStart) == before.startedAt, time(.beforeEnd) == before.finishedAt else {
        return false
      }
    }
    if let after {
      guard time(.afterStart) == after.startedAt, time(.afterEnd) == after.finishedAt else {
        return false
      }
    }
    if let terminal = time(.terminal), times.values.contains(where: { $0 > terminal }) {
      return false
    }
    let chains: [[FixtureTimingPoint]] = [
      [
        .beforeSubmission, .beforeStart, .beforeEnd, .beforeReceipt, .beforeSelection,
        .beforeParseEntry, .beforeParse, .hostAdmission, .admission, .entry, .exit,
        .publication, .receipt, .afterSubmission, .afterStart, .afterEnd, .afterReceipt,
        .afterSelection, .afterParseEntry, .afterParse, .inputsReady, .assessmentEntry,
        .assessmentExit, .terminal,
      ],
      [.beforeSubmission, .beforeStart, .beforeEnd, .beforeReceipt, .beforeParse],
      [.beforeSubmission, .beforeWrite, .beforeReceipt],
      [.afterSubmission, .afterStart, .afterEnd, .afterReceipt, .afterParse],
      [.afterSubmission, .afterWrite, .afterReceipt],
      [.admission, .entry, .exit, .publication, .receipt],
      [.beforeParse, .admission, .entry],
      [.receipt, .afterSubmission, .afterStart],
      [.beforeEnd, .entry, .exit, .afterStart],
      [.beforeParse, .inputsReady, .assessmentEntry, .assessmentExit],
      [.afterParse, .inputsReady, .assessmentEntry, .assessmentExit],
      [.receipt, .inputsReady, .assessmentEntry, .assessmentExit],
    ]
    return chains.allSatisfy { chain in
      let values = chain.compactMap(time)
      return zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }
    }
  }

  /// Only validated available intervals contribute; failures never become zero samples.
  public var metrics: [String: Double] {
    guard valid, outcome != .malformedTiming else { return [:] }
    let intervals: [(String, FixtureTimingPoint, FixtureTimingPoint)] = [
      ("beforeAcquisition", .beforeStart, .beforeEnd),
      ("afterAcquisition", .afterStart, .afterEnd),
      ("beforeEndToEnd", .beforeSubmission, .beforeParse),
      ("afterEndToEnd", .afterSubmission, .afterParse),
      ("beforeDelivery", .beforeEnd, .beforeReceipt),
      ("afterDelivery", .afterEnd, .afterReceipt),
      ("beforeReceiptToCompletion", .beforeReceipt, .beforeParse),
      ("afterReceiptToCompletion", .afterReceipt, .afterParse),
      ("beforeSelectionWait", .beforeReceipt, .beforeSelection),
      ("afterSelectionWait", .afterReceipt, .afterSelection),
      ("beforeParsing", .beforeParseEntry, .beforeParse),
      ("afterParsing", .afterParseEntry, .afterParse),
      ("dispatchWait", .admission, .entry), ("inspection", .entry, .exit),
      ("publication", .exit, .publication), ("replyWait", .publication, .receipt),
      ("assessmentWait", .inputsReady, .assessmentEntry),
      ("assessmentCost", .assessmentEntry, .assessmentExit),
      ("evidenceAge", .beforeStart, .assessmentEntry),
      ("pairLatency", .beforeSubmission, .assessmentExit),
    ]
    return Dictionary(
      uniqueKeysWithValues: intervals.compactMap { name, start, end in
        guard let a = time(start), let b = time(end), b >= a else { return nil }
        return (name, b - a)
      })
  }

  public var expectedOutcome: Bool {
    switch phase {
    case .observation, .recovery: outcome == .completed && assessment == .historicalConsistent
    case .pause: outcome == .revoked && assessment == .contextRevoked
    case .sheet:
      outcome == .rejected && assessment == .sourceChanged
        || outcome == .revoked && assessment == .contextRevoked
    case .failureProbe: outcome == .failed && assessment == nil
    case .exclusion: outcome == .rejected && assessment == .unsupported
    }
  }
}

public enum FixtureTimingCohort: String, Codable, CaseIterable, Sendable {
  case ordinary, dispatch, assessment, invalidation
}

public struct FixtureTimingEvent: Codable, Sendable {
  public private(set) var kind = "event"
  public let code: String
  public let time: Double
  public let revocation: UInt64
  public let pending: UInt64?
  public let context: FixtureUseContext?
  public let direction: FixtureActivationDirection?
  public let relation: FixtureActivationRelation?
  public let source: FixtureEnvironmentSource?

  public init(
    code: String, time: Double, revocation: UInt64, pending: UInt64?,
    context: FixtureUseContext? = nil, direction: FixtureActivationDirection? = nil,
    relation: FixtureActivationRelation? = nil, source: FixtureEnvironmentSource? = nil
  ) {
    self.code = code
    self.time = time
    self.revocation = revocation
    self.pending = pending
    self.context = context
    self.direction = direction
    self.relation = relation
    self.source = source
  }

  /// Historical envelopes must retain their original absence of source metadata.
  public func hasValidMetadata(for schema: Int) -> Bool {
    guard (2...6).contains(schema), hostEvent != nil else { return false }
    if schema >= 3 {
      guard
        code == "activation"
          ? direction != nil && relation != nil
          : direction == nil && relation == nil
      else { return false }
    }
    if schema >= 5 && (code == "nativeSpace" || code == "environment") {
      return source?.eventCode == code
    }
    return source == nil
  }

  public var hostEvent: FixtureHostEvent? {
    switch code {
    case "activation": .activation
    case "nativeSpace", "environment": .environment
    case "ownedTermination", "sampledExit": .processExit
    case "sampledTrustLost": .trust(false)
    case "sampledTrustRestored": .trust(true)
    case "pause": .pause(true)
    case "resume": .pause(false)
    default: nil
    }
  }
}

/// One admission slot stays occupied by a timed-out physical reader until explicit drain.
public struct FixtureTimingCollector: Sendable {
  public private(set) var records: [FixtureTimingRecord] = []
  public private(set) var occupied: Int?
  public private(set) var stopped = false
  public private(set) var bytes = Data()
  public private(set) var firstStop: FixtureFirstStop?
  public private(set) var setups: [FixtureSetupRecord] = []
  public private(set) var admissions = 0
  private var faultRecorded = false
  private let schema: Int
  private let failureClock: (@Sendable () -> Double)?
  private var counts: [FixtureTimingCohort: Int] = [:]
  private var eventCount = 0
  private var lastEventTime = 0.0
  private var closed = false
  private var lastBoundary: Double = 0
  private var pendingCohort: FixtureTimingCohort?
  private let byteLimit: Int
  private let attemptLimit: Int
  private let cohortLimit: Int
  private let eventLimit: Int

  public init(
    byteLimit: Int = 262_144, attemptLimit: Int = 64, cohortLimit: Int = 16,
    eventLimit: Int = 128, schema: Int = 2, failureClock: (@Sendable () -> Double)? = nil
  ) {
    self.schema = schema
    self.failureClock = failureClock
    self.byteLimit = min(262_144, max(1024, byteLimit))
    self.attemptLimit = min(schema >= 3 ? 28 : 64, max(1, attemptLimit))
    self.cohortLimit = min(16, max(1, cohortLimit))
    self.eventLimit = min(128, max(1, eventLimit))
  }

  public mutating func begin(_ cohort: FixtureTimingCohort) throws -> Int {
    guard schema < 4, !stopped, occupied == nil, admissions < attemptLimit,
      counts[cohort, default: 0] < cohortLimit
    else {
      stopped = true
      throw Failure.bound
    }
    let index = admissions + 1
    admissions = index
    occupied = index
    pendingCohort = cohort
    counts[cohort, default: 0] += 1
    return index
  }

  public mutating func finish(_ record: FixtureTimingRecord, readerDrained: Bool) throws {
    guard occupied == record.index, pendingCohort == record.cohort,
      records.count + 1 == record.index
    else {
      throw Failure.mismatch
    }
    var terminal = record
    if !terminal.valid || (terminal.times.values.min() ?? lastBoundary) < lastBoundary {
      terminal.outcome = .malformedTiming
      stopped = true
    }
    if terminal.valid {
      lastBoundary = max(lastBoundary, terminal.times.values.max() ?? lastBoundary)
    }
    if schema == 2 { records.append(terminal) }
    if readerDrained {
      occupied = nil
      pendingCohort = nil
    }
    if schema >= 3 && (!terminal.valid || terminal.outcome == .malformedTiming) {
      latchStop(
        FixtureFirstStop(
          stage: .assessment, category: .clockFailure, at: failureClock?(),
          pairs: records.count, pairOccupied: occupied != nil, readerOccupied: !readerDrained))
      throw Failure.bound
    }
    try append(terminal, maximumBytes: FixtureTimingBudget.pairBytes)
    if schema >= 3 { records.append(terminal) }
    if terminal.outcome == .timedOut || terminal.outcome == .incomplete { stopped = true }
  }

  public mutating func latchStop(_ value: FixtureFirstStop) {
    guard schema >= 3, !closed, firstStop == nil, value.valid else { return }
    firstStop = value
    stopped = true
  }

  public mutating func setup(_ value: FixtureSetupRecord) throws {
    guard schema >= 3, value.valid, setups.count < 14,
      value.sequence == setups.count + 1, value.nextIndex == admissions + 1
    else { throw Failure.mismatch }
    try append(value, maximumBytes: FixtureDiagnosticBudget.setupBytes)
    setups.append(value)
  }

  public mutating func setupFault(_ value: FixtureSetupFaultRecord) throws {
    guard [4, 5].contains(schema), !faultRecorded, value.valid else { throw Failure.mismatch }
    try append(value, maximumBytes: FixtureDiagnosticBudget.faultBytes)
    faultRecorded = true
  }

  public mutating func setupFault(_ value: FixtureOutputEOFRecord) throws {
    guard schema == 6, !faultRecorded, value.valid else { throw Failure.mismatch }
    try append(value, maximumBytes: FixtureDiagnosticBudget.faultBytes)
    faultRecorded = true
  }

  public mutating func drained(index: Int) throws {
    guard occupied == index else { throw Failure.mismatch }
    occupied = nil
    pendingCohort = nil
  }

  public mutating func event(_ event: FixtureTimingEvent) throws {
    let clockValid =
      event.time.isFinite && event.time >= 0
      && (schema < 5 || event.time >= lastEventTime)
    guard !stopped, eventCount < eventLimit, clockValid,
      event.hasValidMetadata(for: schema)
    else {
      stopped = true
      latchStop(
        FixtureFirstStop(
          stage: .output,
          category: !clockValid
            ? .clockFailure
            : !event.hasValidMetadata(for: schema) ? .protocolFailure : .observerLimit,
          at: event.time,
          request: event.pending, pairs: records.count,
          pairOccupied: occupied != nil, readerOccupied: occupied != nil))
      throw Failure.bound
    }
    eventCount += 1
    lastEventTime = event.time
    try append(event, maximumBytes: FixtureTimingBudget.eventBytes)
  }

  public mutating func append<T: Encodable>(_ value: T, maximumBytes: Int = 262_144) throws {
    guard !closed else { throw Failure.bound }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let encoded: Data
    do { encoded = try encoder.encode(value) } catch {
      latchStop(
        FixtureFirstStop(
          stage: .output, category: .protocolFailure, at: failureClock?(),
          pairs: records.count, pairOccupied: occupied != nil, readerOccupied: occupied != nil))
      throw error
    }
    var data = encoded
    data.append(10)
    guard data.count <= maximumBytes,
      bytes.count + data.count <= byteLimit - (schema >= 3 ? 1024 : 512)
    else {
      stopped = true
      latchStop(
        FixtureFirstStop(
          stage: .output,
          category: data.count > maximumBytes ? .recordLimit : .outputLimit, at: failureClock?(),
          pairs: records.count, pairOccupied: occupied != nil, readerOccupied: occupied != nil))
      throw Failure.bound
    }
    bytes.append(data)
  }

  /// Reserved output survives a full record budget. No arbitrary strings or paths.
  public mutating func close(orderly: Bool, passed: Bool) {
    guard !closed else { return }
    if schema >= 3 && firstStop == nil && (!passed || !orderly || stopped || schema >= 4) {
      latchStop(
        FixtureFirstStop(
          stage: !orderly ? .cleanup : .output,
          category: .unclassified, at: failureClock?(),
          pairs: records.count, pairOccupied: occupied != nil, readerOccupied: occupied != nil))
    }
    closed = true
    struct Terminal: Encodable {
      let kind = "terminal"
      let orderly: Bool
      let complete: Bool
      let attempts: Int
      let occupied: Bool
      let calibrationSuitable: Bool
      let schema: Int?
      let records: Int?
      let setups: Int?
      let firstStop: Bool?
    }
    let value = Terminal(
      orderly: orderly, complete: passed && orderly && !stopped && occupied == nil,
      attempts: schema >= 3 ? admissions : records.count, occupied: occupied != nil,
      calibrationSuitable: passed && orderly && !stopped && occupied == nil
        && records.count == FixtureTimingBudget.attempts && records.allSatisfy(\.expectedOutcome)
        && !records.contains(where: { $0.phase == .exclusion }),
      schema: schema >= 3 ? schema : nil, records: schema >= 3 ? records.count : nil,
      setups: schema >= 3 ? setups.count : nil, firstStop: schema >= 3 ? firstStop != nil : nil)
    if let firstStop, let data = try? JSONEncoder().encode(firstStop), data.count < 512 {
      bytes.append(data)
      bytes.append(10)
    }
    if let data = try? JSONEncoder().encode(value) {
      bytes.append(data)
      bytes.append(10)
    }
    stopped = true
  }

  public enum Failure: Error { case bound, mismatch }
}

public struct FixtureTimingSummary: Codable, Sendable {
  public private(set) var kind = "summary"
  public let cohorts: [String: Cohort]

  public struct Statistics: Codable, Sendable {
    public let count: Int
    public let minimum: Double
    public let median: Double
    public let p95: Double
    public let maximum: Double
  }

  public struct Cohort: Codable, Sendable {
    public let attempts: Int
    public let outcomes: [String: Int]
    public let metrics: [String: Statistics]
  }

  public init(records: [FixtureTimingRecord]) {
    cohorts = Dictionary(
      uniqueKeysWithValues: FixtureTimingCohort.allCases.map { cohort in
        let records = records.filter { $0.cohort == cohort }
        let names = Set(records.flatMap { $0.metrics.keys })
        let metrics = Dictionary(
          uniqueKeysWithValues: names.compactMap { name in
            let values = records.compactMap { $0.metrics[name] }.sorted()
            guard !values.isEmpty else { return nil as (String, Statistics)? }
            let middle = values.count / 2
            let median =
              values.count % 2 == 0
              ? values[middle - 1] + (values[middle] - values[middle - 1]) / 2 : values[middle]
            return (
              name,
              Statistics(
                count: values.count, minimum: values[0], median: median,
                p95: values[Int(ceil(Double(values.count) * 0.95)) - 1], maximum: values.last!)
            )
          })
        var outcomes: [String: Int] = [:]
        for record in records { outcomes[record.outcome.rawValue, default: 0] += 1 }
        return (
          cohort.rawValue, Cohort(attempts: records.count, outcomes: outcomes, metrics: metrics)
        )
      })
  }
}
