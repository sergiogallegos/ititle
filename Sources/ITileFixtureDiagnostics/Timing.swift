import Foundation

/// Laboratory timestamps only. Missing boundaries stay absent, including on timeout.
public enum FixtureTimingPoint: String, CaseIterable, Sendable {
  case beforeSubmission, beforeWrite, beforeStart, beforeEnd, beforeReceipt, beforeParse
  case admission, entry, exit, publication, receipt
  case afterSubmission, afterWrite, afterStart, afterEnd, afterReceipt, afterParse
  case inputsReady, assessmentEntry, assessmentExit
}

public enum FixtureTimingOutcome: String, Codable, Sendable {
  case completed, rejected, revoked, failed, timedOut, incomplete, malformedTiming
}

public struct FixtureTimingRecord: Encodable, Sendable {
  public let schema = 1
  public let kind = "pair"
  public let serial = 1
  public let index: Int
  public let cohort: FixtureTimingCohort
  public let requestedDelay: Double
  public let run: UUID
  public var request: UInt64?
  public var beforeSequence: UInt64?
  public var afterSequence: UInt64?
  public var beforeState: String?
  public var afterState: String?
  public var beforeRegistry: String?
  public var afterRegistry: String?
  public var admittedRevocation: UInt64?
  public var admittedEnvironment: UInt64?
  public var admittedActivation: UInt64?
  public var revocation: UInt64?
  public var environment: UInt64?
  public var activation: UInt64?
  public var outcome: FixtureTimingOutcome = .incomplete
  public var assessment: String?
  public private(set) var times: [String: Double] = [:]

  public init(index: Int, cohort: FixtureTimingCohort, requestedDelay: Double, run: UUID) {
    self.index = index
    self.cohort = cohort
    self.requestedDelay = requestedDelay
    self.run = run
  }

  public mutating func mark(_ point: FixtureTimingPoint, at time: Double) {
    times[point.rawValue] = time
  }

  public func time(_ point: FixtureTimingPoint) -> Double? { times[point.rawValue] }

  public var valid: Bool {
    guard index > 0, index <= 64, requestedDelay.isFinite, requestedDelay >= 0,
      requestedDelay <= 0.5,
      times.allSatisfy({ key, value in
        FixtureTimingPoint(rawValue: key) != nil && value.isFinite && value >= 0
      })
    else { return false }
    let chains: [[FixtureTimingPoint]] = [
      [
        .beforeSubmission, .beforeStart, .beforeEnd, .beforeReceipt, .beforeParse,
        .admission, .entry, .exit, .publication, .receipt, .afterSubmission, .afterStart,
        .afterEnd, .afterReceipt, .afterParse, .inputsReady, .assessmentEntry, .assessmentExit,
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
      ("beforeParsing", .beforeReceipt, .beforeParse),
      ("afterParsing", .afterReceipt, .afterParse),
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
}

public enum FixtureTimingCohort: String, Codable, CaseIterable, Sendable {
  case ordinary, dispatch, assessment, invalidation
}

public struct FixtureTimingEvent: Encodable, Sendable {
  public let kind = "event"
  public let code: String
  public let time: Double
  public let revocation: UInt64
  public let pending: UInt64?

  public init(code: String, time: Double, revocation: UInt64, pending: UInt64?) {
    self.code = code
    self.time = time
    self.revocation = revocation
    self.pending = pending
  }
}

/// One admission slot stays occupied by a timed-out physical reader until explicit drain.
public struct FixtureTimingCollector: Sendable {
  public private(set) var records: [FixtureTimingRecord] = []
  public private(set) var occupied: Int?
  public private(set) var stopped = false
  public private(set) var bytes = Data()
  private var counts: [FixtureTimingCohort: Int] = [:]
  private var eventCount = 0
  private var closed = false
  private var lastBoundary: Double = 0
  private var pendingCohort: FixtureTimingCohort?
  private let byteLimit: Int
  private let attemptLimit: Int
  private let cohortLimit: Int
  private let eventLimit: Int

  public init(
    byteLimit: Int = 262_144, attemptLimit: Int = 64, cohortLimit: Int = 16,
    eventLimit: Int = 128
  ) {
    self.byteLimit = min(262_144, max(1024, byteLimit))
    self.attemptLimit = min(64, max(1, attemptLimit))
    self.cohortLimit = min(16, max(1, cohortLimit))
    self.eventLimit = min(128, max(1, eventLimit))
  }

  public mutating func begin(_ cohort: FixtureTimingCohort) throws -> Int {
    guard !stopped, occupied == nil, records.count < attemptLimit,
      counts[cohort, default: 0] < cohortLimit
    else {
      stopped = true
      throw Failure.bound
    }
    let index = records.count + 1
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
    records.append(terminal)
    if readerDrained {
      occupied = nil
      pendingCohort = nil
    }
    try append(terminal)
    if terminal.outcome == .timedOut || terminal.outcome == .incomplete { stopped = true }
  }

  public mutating func drained(index: Int) throws {
    guard occupied == index else { throw Failure.mismatch }
    occupied = nil
    pendingCohort = nil
  }

  public mutating func event(_ event: FixtureTimingEvent) throws {
    guard !stopped, eventCount < eventLimit, event.time.isFinite, event.time >= 0,
      [
        "activation", "nativeSpace", "environment", "ownedTermination", "sampledTrustLost",
        "sampledTrustRestored", "sampledExit", "pause", "resume",
      ].contains(event.code)
    else {
      stopped = true
      throw Failure.bound
    }
    eventCount += 1
    try append(event)
  }

  public mutating func append<T: Encodable>(_ value: T) throws {
    guard !closed else { throw Failure.bound }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(value)
    data.append(10)
    guard bytes.count + data.count <= byteLimit - 512 else {
      stopped = true
      throw Failure.bound
    }
    bytes.append(data)
  }

  /// Reserved output survives a full record budget. No arbitrary strings or paths.
  public mutating func close(orderly: Bool, passed: Bool) {
    guard !closed else { return }
    closed = true
    struct Terminal: Encodable {
      let kind = "terminal"
      let orderly: Bool
      let complete: Bool
      let attempts: Int
      let occupied: Bool
    }
    let value = Terminal(
      orderly: orderly, complete: passed && orderly && !stopped && occupied == nil,
      attempts: records.count, occupied: occupied != nil)
    if let data = try? JSONEncoder().encode(value) {
      bytes.append(data)
      bytes.append(10)
    }
    stopped = true
  }

  public enum Failure: Error { case bound, mismatch }
}

public struct FixtureTimingSummary: Encodable, Sendable {
  public let kind = "summary"
  public let cohorts: [String: Cohort]

  public struct Statistics: Encodable, Sendable {
    public let count: Int
    public let minimum: Double
    public let median: Double
    public let p95: Double
    public let maximum: Double
  }

  public struct Cohort: Encodable, Sendable {
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
