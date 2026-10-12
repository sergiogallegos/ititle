import Foundation

public enum FixtureAgeDataset: String, CaseIterable, Codable, Sendable {
  case ordinary, exclusion, setupExit

  public var sha256: String {
    switch self {
    case .ordinary: "8cf5fef8d2e480eff1859b981c8c967ad370d2bb7c11091cf055e056ebdd70b1"
    case .exclusion: "ad10ad96d7e27dbbc729332b84ded469fb68b705dc610f7c11735c3cf69546ea"
    case .setupExit: "605232f61e7f78ba665b81f7eddddf7d2cc85618ecd08a9b660bc37da7dbc1cc"
    }
  }
}

public struct FixtureAgeInput: Sendable {
  public let dataset: FixtureAgeDataset
  public let data: Data
  public init(dataset: FixtureAgeDataset, data: Data) {
    self.dataset = dataset
    self.data = data
  }
}

public struct FixtureAgeComparisonOutput: Sendable {
  public let bytes: Data
  public let complete: Bool
}

public enum FixtureAgeComparison {
  public enum Failure: String, Error, Codable, Sendable {
    case inputRead, inputSet, hashMismatch, malformed, replayMismatch, arithmetic, outputLimit
  }

  public struct Candidate: Encodable, Sendable {
    public let revision: UInt64
    public let maximumAge: Double
  }

  public static let candidates: [Candidate] = [
    Candidate(revision: 1, maximumAge: 0.05), Candidate(revision: 2, maximumAge: 0.1),
    Candidate(revision: 3, maximumAge: 0.25), Candidate(revision: 4, maximumAge: 0.5),
    Candidate(revision: 5, maximumAge: 1),
  ]
  public static let outputLimit = 524288
  // Including newlines: 420 comparisons, 18 baseline + 90 candidate summaries.
  public static let reservedBytes = 1024 + 3 * 3072 + 420 * 1024 + 108 * 768 + 512

  enum Group: String, CaseIterable, Encodable {
    case all, ordinary, dispatch, assessment, invalidation, recovery
    static func of(_ record: FixtureTimingRecord) -> Self {
      if record.phase == .recovery { return .recovery }
      return Group(rawValue: record.cohort.rawValue)!
    }
    static func of(index: Int) -> Self {
      if index <= 4 { return .ordinary }
      if index <= 8 { return .dispatch }
      if index <= 12 { return .assessment }
      return index % 2 == 0 ? .recovery : .invalidation
    }
  }

  enum AgeResult: String, Encodable {
    case notApplicable, diagnosticUnexpired, expired
  }

  struct Measurement {
    let result: AgeResult
    let age: Double?
    let expiry: Double?
  }

  private struct Counts: Encodable {
    var attempts = 0
    var historicalConsistent = 0
    var diagnosticUnexpired = 0
    var expired = 0
    var originalRejection = 0
    var failed = 0
    var absent = 0
    var primary: [String: Int] = [:]

    mutating func add(_ record: FixtureTimingRecord?, result: AgeResult = .notApplicable) {
      attempts += 1
      guard let record else {
        absent += 1
        return
      }
      primary[record.assessment?.rawValue ?? record.outcome.rawValue, default: 0] += 1
      if record.assessment == .historicalConsistent {
        switch result {
        case .notApplicable: historicalConsistent += 1
        case .diagnosticUnexpired: diagnosticUnexpired += 1
        case .expired: expired += 1
        }
      } else if record.assessment != nil {
        originalRejection += 1
      } else if record.outcome == .failed {
        failed += 1
      } else {
        absent += 1
      }
    }
  }

  private struct Manifest: Encodable {
    let kind = "ageComparisonManifest"
    let schema = 1
    let evaluatorHash: String
    let candidates = FixtureAgeComparison.candidates
    let datasets = FixtureAgeDataset.allCases
    let inputByteLimit = FixtureTimingBudget.outputBytes
    let outputByteLimit = FixtureAgeComparison.outputLimit
    let selectedPolicy = false
    let productionFreshness = "unmeasured"
  }

  struct Inventory: Encodable {
    let kind = "ageInventory"
    let dataset: FixtureAgeDataset
    let datasetHash: String
    let collectionLabHash: String
    let fixtureHash: String
    let controlledExclusion: Bool
    let controlledSetupFailure: Bool
    let orderly: Bool
    let occupied: Bool
    let unattempted: Int
    let failedSetup: FixtureSetupRecord?
    let firstStop: FixtureFirstStop?
    let baseline: FixtureTimingReplayReport
  }

  private struct Comparison: Encodable {
    let kind = "ageComparison"
    let dataset: FixtureAgeDataset
    let sourceComplete: Bool
    let sourceSuitable: Bool
    let revision: UInt64
    let index: Int
    let cohort: FixtureTimingCohort?
    let group: Group
    let phase: FixtureTimingPhase?
    let requestedDelay: Double?
    let originalOutcome: FixtureTimingOutcome?
    let originalAssessment: FixturePairResult?
    let ageResult: AgeResult
    let evidenceAge: Double?
    let expiry: Double?
  }

  private struct Summary: Encodable {
    let kind = "ageSummary"
    let dataset: FixtureAgeDataset
    let group: Group
    let revision: UInt64?
    let counts: Counts
  }

  private struct Terminal: Encodable {
    let kind = "ageComparisonTerminal"
    let schema = 1
    let complete: Bool
    let reason: Failure?
    let selectedPolicy = false
  }

  struct Reviewed {
    let inventory: Inventory
    let records: [FixtureTimingRecord]
  }

  /// The adapter supplies a cryptographic digest of the exact bounded input bytes.
  public static func evaluate(
    _ inputs: [FixtureAgeInput], evaluatorHash: String, digest: (Data) -> String
  ) -> FixtureAgeComparisonOutput {
    evaluate(inputs, evaluatorHash: evaluatorHash, digest: digest, maximumBytes: outputLimit)
  }

  static func evaluate(
    _ inputs: [FixtureAgeInput], evaluatorHash: String, digest: (Data) -> String,
    maximumBytes: Int
  ) -> FixtureAgeComparisonOutput {
    do {
      guard inputs.count == 3, Set(inputs.map(\.dataset)) == Set(FixtureAgeDataset.allCases) else {
        throw Failure.inputSet
      }
      guard validHash(evaluatorHash) else { throw Failure.malformed }
      guard reservedBytes <= outputLimit,
        (512...outputLimit).contains(maximumBytes)
      else { throw Failure.outputLimit }
      // Validate every input before constructing any candidate result or output prefix.
      var reviewed: [Reviewed] = []
      for dataset in FixtureAgeDataset.allCases {
        let input = inputs.first { $0.dataset == dataset }!
        guard input.data.count <= FixtureTimingBudget.outputBytes else { throw Failure.malformed }
        guard digest(input.data) == dataset.sha256 else { throw Failure.hashMismatch }
        reviewed.append(try review(input.data, dataset: dataset))
      }
      var bytes = Data()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      func append<T: Encodable>(_ row: T, cap: Int, terminal: Bool = false) throws {
        var data = try encoder.encode(row)
        data.append(10)
        guard data.count <= cap, bytes.count + data.count <= maximumBytes - (terminal ? 0 : 512)
        else { throw Failure.outputLimit }
        bytes.append(data)
      }
      try append(Manifest(evaluatorHash: evaluatorHash), cap: 1024)
      for value in reviewed {
        let inventory = value.inventory
        try append(inventory, cap: 3072)
        let comparisons: [Candidate?] = [nil] + candidates.map { Optional($0) }
        for candidate in comparisons {
          var counts = Dictionary(uniqueKeysWithValues: Group.allCases.map { ($0, Counts()) })
          for offset in 0..<inventory.baseline.attempts {
            let index = offset + 1
            let record = value.records.first { $0.index == index }
            let group = record.map(Group.of) ?? Group.of(index: index)
            let measurement =
              try candidate.map {
                try measure(
                  record,
                  policy: FixtureDiagnosticAgePolicy(
                    revision: $0.revision, maximumAge: $0.maximumAge))
              } ?? Measurement(result: .notApplicable, age: nil, expiry: nil)
            counts[group]!.add(record, result: measurement.result)
            counts[.all]!.add(record, result: measurement.result)
            if let candidate {
              try append(
                Comparison(
                  dataset: inventory.dataset, sourceComplete: inventory.baseline.complete,
                  sourceSuitable: inventory.baseline.calibrationSuitable,
                  revision: candidate.revision, index: index, cohort: record?.cohort, group: group,
                  phase: record?.phase, requestedDelay: record?.requestedDelay,
                  originalOutcome: record?.outcome, originalAssessment: record?.assessment,
                  ageResult: measurement.result, evidenceAge: measurement.age,
                  expiry: measurement.expiry), cap: 1024)
            }
          }
          for group in Group.allCases {
            try append(
              Summary(
                dataset: inventory.dataset, group: group, revision: candidate?.revision,
                counts: counts[group]!), cap: 768)
          }
        }
      }
      try append(Terminal(complete: true, reason: nil), cap: 512, terminal: true)
      return FixtureAgeComparisonOutput(bytes: bytes, complete: true)
    } catch {
      // Buffered export is all-or-nothing. No successful prefix escapes on failure.
      return failure((error as? Failure) ?? .malformed)
    }
  }

  public static func failure(_ reason: Failure) -> FixtureAgeComparisonOutput {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var bytes = try! encoder.encode(Terminal(complete: false, reason: reason))
    bytes.append(10)
    return FixtureAgeComparisonOutput(bytes: bytes, complete: false)
  }

  static func review(_ data: Data, dataset: FixtureAgeDataset) throws -> Reviewed {
    let baseline: FixtureTimingReplayReport
    do { baseline = try FixtureDiagnosticReplay.review(data) } catch {
      throw Failure.replayMismatch
    }
    let rows = data.split(separator: 10).map(Data.init)
    guard let first = rows.first,
      let manifest = try? FixtureTimingReplay.decode(FixtureTimingManifest.self, data: first),
      manifest.schema == 3, manifest.controlledExclusion == (dataset == .exclusion),
      manifest.controlledSetupFailure == (dataset == .setupExit),
      let last = rows.last,
      let terminal = try JSONSerialization.jsonObject(with: last) as? [String: Any],
      let orderly = terminal["orderly"] as? Bool, let occupied = terminal["occupied"] as? Bool
    else { throw Failure.malformed }
    var records: [FixtureTimingRecord] = []
    var failedSetup: FixtureSetupRecord?
    var firstStop: FixtureFirstStop?
    for row in rows {
      let kind = (try JSONSerialization.jsonObject(with: row) as? [String: Any])?["kind"] as? String
      if kind == "pair" {
        records.append(try FixtureTimingReplay.decode(FixtureTimingRecord.self, data: row))
      } else if kind == "setup" {
        let setup = try FixtureTimingReplay.decode(FixtureSetupRecord.self, data: row)
        if setup.failure != nil { failedSetup = setup }
      } else if kind == "stop" {
        firstStop = try FixtureTimingReplay.decode(FixtureFirstStop.self, data: row)
      }
    }
    return Reviewed(
      inventory: Inventory(
        dataset: dataset, datasetHash: dataset.sha256, collectionLabHash: manifest.labHash,
        fixtureHash: manifest.fixtureHash, controlledExclusion: manifest.controlledExclusion,
        controlledSetupFailure: manifest.controlledSetupFailure!, orderly: orderly,
        occupied: occupied, unattempted: 28 - baseline.attempts,
        failedSetup: failedSetup, firstStop: firstStop, baseline: baseline),
      records: records)
  }

  /// Called only after complete no-policy host replay validates the original record.
  static func measure(
    _ record: FixtureTimingRecord?, policy: FixtureDiagnosticAgePolicy
  ) throws -> Measurement {
    guard let record else { return Measurement(result: .notApplicable, age: nil, expiry: nil) }
    guard record.valid else { throw Failure.malformed }
    let age: Double?
    if let start = record.time(.beforeStart), let now = record.time(.assessmentEntry) {
      let value = now - start
      guard value.isFinite, value >= 0 else { throw Failure.arithmetic }
      age = value
    } else {
      age = nil
    }
    // Preserve primary host/source rejection and failed/partial reads even if old.
    guard record.assessment == .historicalConsistent else {
      return Measurement(result: .notApplicable, age: age, expiry: nil)
    }
    guard let before = record.before, let after = record.after, let request = record.request,
      let focused = record.focused, let start = record.axStart, let end = record.axEnd,
      let admitted = record.admitted, let final = record.final,
      let now = record.time(.assessmentEntry), age != nil
    else { throw Failure.malformed }
    var reducer = FixturePairAssessment()
    try reducer.begin(request: request, context: admitted, policy: policy)
    let result = reducer.consume(
      request: request, before: before, focused: focused, axStart: start, axEnd: end,
      after: after, context: final, now: now)
    let expiry = before.startedAt + policy.maximumAge
    guard expiry.isFinite, expiry > before.startedAt,
      result == (now >= expiry ? .expired : .diagnosticUnexpired)
    else { throw Failure.arithmetic }
    return Measurement(
      result: result == .expired ? .expired : .diagnosticUnexpired, age: age, expiry: expiry)
  }

  private static func validHash(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy {
        (48...57).contains($0) || (97...102).contains($0)
      }
  }
}
