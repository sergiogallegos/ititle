import CryptoKit
import Foundation
import XCTest

@testable import ITileFixtureDiagnostics

final class AgeComparisonTests: XCTestCase {
  private struct NumericComparison: Decodable {
    let dataset: FixtureAgeDataset
    let index: Int
    let revision: UInt64
    let evidenceAge: Double?
    let expiry: Double?
  }
  private let evaluatorHash = String(repeating: "a", count: 64)
  private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  private func inputs() throws -> [FixtureAgeInput] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    return try zip(
      FixtureAgeDataset.allCases,
      ["m2-37-timing.jsonl", "m2-37-exclusion.jsonl", "m2-37-setup-exit.jsonl"]
    ).map { dataset, name in
      FixtureAgeInput(
        dataset: dataset,
        data: try Data(contentsOf: root.appendingPathComponent("docs/evidence/" + name)))
    }
  }
  private func rows(_ data: Data) throws -> [[String: Any]] {
    try data.split(separator: 10).map {
      try JSONSerialization.jsonObject(with: Data($0)) as! [String: Any]
    }
  }
  private func encode(_ rows: [[String: Any]]) throws -> Data {
    var data = Data()
    for row in rows {
      data.append(try JSONSerialization.data(withJSONObject: row))
      data.append(10)
    }
    return data
  }
  private func records() throws -> [FixtureTimingRecord] {
    try FixtureAgeComparison.review(inputs()[0].data, dataset: .ordinary).records
  }

  func testScopedHashesBaselinesControlSeparationAndSummaryReconciliation() throws {
    let original = try inputs()
    let output = FixtureAgeComparison.evaluate(
      original, evaluatorHash: evaluatorHash, digest: digest)
    XCTAssertTrue(output.complete)
    XCTAssertLessThanOrEqual(output.bytes.count, FixtureAgeComparison.outputLimit)
    let values = try rows(output.bytes)
    XCTAssertEqual(values.count, 393)
    XCTAssertEqual(values.last?["complete"] as? Bool, true)
    XCTAssertEqual(values.last?["selectedPolicy"] as? Bool, false)
    let manifest = values[0]
    XCTAssertEqual(manifest["evaluatorHash"] as? String, evaluatorHash)
    let candidates = manifest["candidates"] as! [[String: Any]]
    XCTAssertEqual(candidates.map { $0["revision"] as! Int }, [1, 2, 3, 4, 5])
    XCTAssertEqual(candidates.map { $0["maximumAge"] as! Double }, [0.05, 0.1, 0.25, 0.5, 1])
    for input in original {
      XCTAssertEqual(digest(input.data), input.dataset.sha256)
      let inventory = values.first {
        $0["kind"] as? String == "ageInventory"
          && $0["dataset"] as? String == input.dataset.rawValue
      }!
      XCTAssertEqual(inventory["datasetHash"] as? String, input.dataset.sha256)
      let baseline = inventory["baseline"] as! [String: Any]
      let historical =
        try JSONSerialization.jsonObject(
          with: JSONEncoder().encode(FixtureTimingReplay.review(input.data))) as! NSDictionary
      XCTAssertEqual(baseline as NSDictionary, historical)
      XCTAssertEqual(inventory["unattempted"] as? Int, input.dataset == .setupExit ? 28 : 0)
      XCTAssertEqual(baseline["complete"] as? Bool, input.dataset != .setupExit)
      XCTAssertEqual(baseline["calibrationSuitable"] as? Bool, false)
      if input.dataset == .setupExit {
        let setup = inventory["failedSetup"] as! [String: Any]
        let stop = inventory["firstStop"] as! [String: Any]
        XCTAssertEqual(setup["stage"] as? String, "normalizationWrite")
        XCTAssertEqual(setup["done"] as? Int, 1)
        XCTAssertEqual(stop["stage"] as? String, "normalizationWrite")
        XCTAssertEqual(stop["category"] as? String, "childExited")
        XCTAssertEqual(stop["pairs"] as? Int, 0)
      } else {
        XCTAssertNil(inventory["firstStop"])
        XCTAssertNil(inventory["failedSetup"])
      }
    }
    let comparisons = values.filter { $0["kind"] as? String == "ageComparison" }
    XCTAssertEqual(comparisons.count, 280)
    // Decode floating-point fields directly; NSNumber bridging may round a last bit.
    let numeric = output.bytes.split(separator: 10).compactMap {
      try? JSONDecoder().decode(NumericComparison.self, from: Data($0))
    }
    XCTAssertEqual(numeric.count, 280)
    for input in original {
      let reviewed = try FixtureAgeComparison.review(input.data, dataset: input.dataset)
      for result in numeric where result.dataset == input.dataset {
        let record = reviewed.records.first { $0.index == result.index }!
        if let start = record.time(.beforeStart), let now = record.time(.assessmentEntry) {
          XCTAssertEqual(result.evidenceAge, now - start)
          if record.assessment == .historicalConsistent {
            let candidate = FixtureAgeComparison.candidates.first {
              $0.revision == result.revision
            }!
            XCTAssertEqual(result.expiry, start + candidate.maximumAge)
          } else {
            XCTAssertNil(result.expiry)
          }
        } else {
          XCTAssertNil(result.evidenceAge)
          XCTAssertNil(result.expiry)
        }
      }
    }
    XCTAssertFalse(comparisons.contains { $0["dataset"] as? String == "setupExit" })
    for row in comparisons {
      XCTAssertEqual(row["sourceComplete"] as? Bool, true)
      XCTAssertEqual(row["sourceSuitable"] as? Bool, false)
      if row["group"] as? String == "recovery" {
        XCTAssertEqual(row["cohort"] as? String, "invalidation")
        XCTAssertEqual(row["phase"] as? String, "recovery")
      }
      if row["originalAssessment"] as? String != "historicalConsistent" {
        XCTAssertEqual(row["ageResult"] as? String, "notApplicable")
        XCTAssertNil(row["expiry"])
      }
    }
    let summaries = values.filter { $0["kind"] as? String == "ageSummary" }
    XCTAssertEqual(summaries.count, 108)
    for summary in summaries {
      let dataset = summary["dataset"] as! String
      let group = summary["group"] as! String
      let revision = summary["revision"] as? Int
      let counts = summary["counts"] as! [String: Any]
      let keys = [
        "historicalConsistent", "diagnosticUnexpired", "expired", "originalRejection", "failed",
        "absent",
      ]
      XCTAssertEqual(keys.reduce(0) { $0 + (counts[$1] as! Int) }, counts["attempts"] as! Int)
      if let revision {
        let selected = comparisons.filter {
          $0["dataset"] as? String == dataset && $0["revision"] as? Int == revision
            && (group == "all" || $0["group"] as? String == group)
        }
        XCTAssertEqual(selected.count, counts["attempts"] as! Int)
        for result in ["diagnosticUnexpired", "expired"] {
          XCTAssertEqual(
            selected.filter { $0["ageResult"] as? String == result }.count, counts[result] as! Int)
        }
        let baseline =
          summaries.first {
            $0["dataset"] as? String == dataset && $0["group"] as? String == group
              && $0["revision"] == nil
          }!["counts"] as! [String: Any]
        XCTAssertEqual(counts["primary"] as! NSDictionary, baseline["primary"] as! NSDictionary)
        XCTAssertEqual(counts["failed"] as! Int, baseline["failed"] as! Int)
        XCTAssertEqual(counts["originalRejection"] as! Int, baseline["originalRejection"] as! Int)
      }
    }
  }

  func testExactExpiryUsesEarliestStartAndActualAssessmentNotRequestedDelay() throws {
    let base = try records()[0]
    let policy = try FixtureDiagnosticAgePolicy(revision: 1, maximumAge: 1)
    let deadline = base.before!.startedAt + 1
    for (now, expected) in [
      (deadline.nextDown, "diagnosticUnexpired"), (deadline, "expired"),
      (deadline.nextUp, "expired"),
    ] {
      var record = base
      record.mark(.assessmentEntry, at: now)
      record.mark(.assessmentExit, at: now)
      record.mark(.terminal, at: now)
      let result = try FixtureAgeComparison.measure(record, policy: policy)
      XCTAssertEqual(result.result.rawValue, expected)
      XCTAssertEqual(result.age, now - base.before!.startedAt)
      XCTAssertEqual(result.expiry, deadline)
      XCTAssertEqual(record.requestedDelay, 0)
    }
  }

  func testPrimaryRevocationUnsupportedAndSourceChangeRemainEvenWhenOld() throws {
    let policy = try FixtureDiagnosticAgePolicy(revision: 1, maximumAge: 0.001)
    for record in try records() where record.assessment != .historicalConsistent {
      let result = try FixtureAgeComparison.measure(record, policy: policy)
      XCTAssertEqual(result.result, .notApplicable)
      XCTAssertNil(result.expiry)
      if record.assessment != nil {
        XCTAssertGreaterThan(result.age!, policy.maximumAge)
      } else {
        XCTAssertNil(result.age)
      }
    }
  }

  func testInvalidCandidatesClocksMissingAcceptedInputsAndExpiryArithmetic() throws {
    for age in [Double.nan, .infinity, 0, -1] {
      XCTAssertThrowsError(try FixtureDiagnosticAgePolicy(revision: 1, maximumAge: age))
    }
    XCTAssertThrowsError(try FixtureDiagnosticAgePolicy(revision: 0, maximumAge: 1))
    let record = try records()[0]
    XCTAssertThrowsError(
      try FixtureAgeComparison.measure(
        record, policy: FixtureDiagnosticAgePolicy(revision: 1, maximumAge: .leastNonzeroMagnitude))
    )
    let policy = try FixtureDiagnosticAgePolicy(revision: 1, maximumAge: 1)
    var wrong = record
    wrong.mark(.assessmentEntry, at: .nan)
    XCTAssertThrowsError(try FixtureAgeComparison.measure(wrong, policy: policy))
    wrong = record
    wrong.after = nil
    XCTAssertThrowsError(try FixtureAgeComparison.measure(wrong, policy: policy))
    wrong = record
    wrong.final!.revocation += 1
    XCTAssertThrowsError(try FixtureAgeComparison.measure(wrong, policy: policy))
    var huge = record
    func snapshot(_ value: FixtureSafetySnapshot) throws -> FixtureSafetySnapshot {
      var fields = Dictionary(
        uniqueKeysWithValues: value.line.split(separator: " ").dropFirst().map {
          let parts = $0.split(separator: "=", maxSplits: 1)
          return (String(parts[0]), String(parts[1]))
        })
      fields["start"] = "1e308"
      fields["end"] = "1e308"
      return try FixtureSafetySnapshot(fields: fields)
    }
    huge.before = try snapshot(record.before!)
    huge.after = try snapshot(record.after!)
    huge.axStart = 1e308
    huge.axEnd = 1e308
    for point in FixtureTimingPoint.allCases { huge.mark(point, at: 1e308) }
    XCTAssertTrue(huge.valid)
    XCTAssertThrowsError(
      try FixtureAgeComparison.measure(
        huge, policy: FixtureDiagnosticAgePolicy(revision: 1, maximumAge: 1e308)))
  }

  func testNoRevivalAfterExpiryPolicyReplacementOrNewerContext() throws {
    let record = try records()[0]
    let policy = try FixtureDiagnosticAgePolicy(revision: 1, maximumAge: 1)
    let next = try FixtureDiagnosticAgePolicy(revision: 2, maximumAge: 2)
    let now = record.time(.assessmentEntry)!
    for action in 0..<3 {
      var reducer = FixturePairAssessment()
      try reducer.begin(request: record.request!, context: record.admitted!, policy: policy)
      XCTAssertEqual(
        reducer.consume(
          request: record.request!, before: record.before!, focused: record.focused!,
          axStart: record.axStart!, axEnd: record.axEnd!, after: record.after!,
          context: record.final!, now: now), .diagnosticUnexpired)
      let expected: FixturePairResult
      switch action {
      case 0:
        expected = .expired
        XCTAssertEqual(
          reducer.revalidate(
            context: record.final!, policy: policy, now: record.before!.startedAt + 1), expected)
      case 1:
        expected = .wrongPolicy
        XCTAssertEqual(reducer.revalidate(context: record.final!, policy: next, now: now), expected)
      default:
        expected = .contextRevoked
        var context = record.final!
        context.revocation += 1
        XCTAssertEqual(reducer.revalidate(context: context, policy: policy, now: now), expected)
      }
      XCTAssertEqual(reducer.revalidate(context: record.final!, policy: policy, now: now), expected)
    }
  }

  func testInputSetHashAndUnknownOrHistoricalInputsCannotProduceSuccessfulPrefix() throws {
    let original = try inputs()
    for values in [
      Array(original.dropLast()), original + [original[0]],
      [original[0], original[0], original[2]],
    ] {
      let output = FixtureAgeComparison.evaluate(
        values, evaluatorHash: evaluatorHash, digest: digest)
      XCTAssertFalse(output.complete)
      XCTAssertEqual(try rows(output.bytes).count, 1)
      XCTAssertEqual(try rows(output.bytes)[0]["reason"] as? String, "inputSet")
    }
    var changed = original
    changed[2] = FixtureAgeInput(dataset: .setupExit, data: original[2].data + Data([10]))
    let output = FixtureAgeComparison.evaluate(
      changed, evaluatorHash: evaluatorHash, digest: digest)
    XCTAssertFalse(output.complete)
    XCTAssertEqual(try rows(output.bytes)[0]["reason"] as? String, "hashMismatch")
    var values = try rows(original[0].data)
    values[0]["unknown"] = "unexported-content"
    XCTAssertThrowsError(try FixtureAgeComparison.review(encode(values), dataset: .ordinary))
    values = try rows(original[0].data)
    values[0]["schema"] = 2
    XCTAssertThrowsError(try FixtureAgeComparison.review(encode(values), dataset: .ordinary))
    XCTAssertThrowsError(try FixtureAgeComparison.review(original[0].data, dataset: .exclusion))
  }

  func testOutputBudgetRetainsOnlyReservedIncompleteTerminalOnBreach() throws {
    XCTAssertEqual(FixtureAgeComparison.reservedBytes, 523776)
    XCTAssertLessThanOrEqual(FixtureAgeComparison.reservedBytes, FixtureAgeComparison.outputLimit)
    for limit in [512, 4096] {
      let output = FixtureAgeComparison.evaluate(
        try inputs(), evaluatorHash: evaluatorHash, digest: digest, maximumBytes: limit)
      XCTAssertFalse(output.complete)
      XCTAssertLessThanOrEqual(output.bytes.count, 512)
      XCTAssertEqual(try rows(output.bytes).count, 1)
      XCTAssertEqual(try rows(output.bytes)[0]["reason"] as? String, "outputLimit")
      XCTAssertEqual(try rows(output.bytes)[0]["complete"] as? Bool, false)
    }
    for failure in [FixtureAgeComparison.Failure.inputRead, .arithmetic, .replayMismatch] {
      let output = FixtureAgeComparison.failure(failure)
      XCTAssertFalse(output.complete)
      XCTAssertLessThanOrEqual(output.bytes.count, 512)
      XCTAssertEqual(try rows(output.bytes)[0]["reason"] as? String, failure.rawValue)
    }
  }

  func testIncompleteOrUnwrittenAdmissionRetainsAbsenceAndUnattemptedCounts() throws {
    let context = try records()[0].admitted!
    for unwritten in [false, true] {
      var collector = FixtureTimingCollector(schema: 3, failureClock: { 15 })
      try collector.append(
        FixtureTimingManifest(
          os: "Test OS", utc: "2026-10-12T00:00:00Z", labHash: evaluatorHash,
          fixtureHash: evaluatorHash, initialContext: context,
          runStart: 1, collectionDeadline: 181, controlledSetupFailure: false))
      var setup = FixtureSetupRecord(
        sequence: 1, nextIndex: 1, cohort: .ordinary, purpose: .cohort, at: 2,
        issued: 1, correlated: 1, revocation: context.revocation,
        pairOccupied: false, readerOccupied: false)
      for stage in setup.purpose.stages {
        try setup.enter(stage, at: 2)
        try setup.complete(at: 2)
      }
      try setup.finish(at: 2)
      try collector.setup(setup)
      let index = try collector.begin(.ordinary)
      var record = FixtureTimingRecord(
        index: index, cohort: .ordinary, requestedDelay: 0, run: context.expected.run, schema: 3)
      record.mark(.admission, at: 10)
      record.mark(.terminal, at: 15)
      record.outcome = .timedOut
      if unwritten {
        record.mark(.entry, at: .nan)
        XCTAssertThrowsError(try collector.finish(record, readerDrained: true))
      } else {
        collector.latchStop(
          FixtureFirstStop(
            stage: .reader, category: .readerWatchdog, at: 15, pairs: 0,
            pairOccupied: true, readerOccupied: true))
        try collector.finish(record, readerDrained: false)
      }
      try collector.append(FixtureTimingSummary(records: collector.records))
      collector.close(orderly: true, passed: false)
      let reviewed = try FixtureAgeComparison.review(collector.bytes, dataset: .ordinary)
      XCTAssertEqual(reviewed.inventory.baseline.attempts, 1)
      XCTAssertEqual(reviewed.inventory.baseline.absent, 1)
      XCTAssertEqual(reviewed.inventory.unattempted, 27)
      XCTAssertEqual(reviewed.records.count, unwritten ? 0 : 1)
      let result = try FixtureAgeComparison.measure(
        reviewed.records.first, policy: FixtureDiagnosticAgePolicy(revision: 1, maximumAge: 1))
      XCTAssertEqual(result.result, .notApplicable)
      XCTAssertNil(result.age)
      XCTAssertNil(result.expiry)
    }
  }
}
