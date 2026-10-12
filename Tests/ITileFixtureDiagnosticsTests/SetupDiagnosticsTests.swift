import Foundation
import ITileFixtureDiagnostics
import XCTest

final class SetupDiagnosticsTests: XCTestCase {
  private let run = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
  private var context: FixtureUseContext {
    FixtureUseContext(expected: try! FixtureWindowIdentity(run: run, serial: 1))
  }
  private func manifest() -> FixtureTimingManifest {
    FixtureTimingManifest(
      os: "Test OS", utc: "2026-10-12T00:00:00Z",
      labHash: String(repeating: "a", count: 64), fixtureHash: String(repeating: "b", count: 64),
      initialContext: context, runStart: 1, collectionDeadline: 181, controlledSetupFailure: false)
  }
  private func setup(
    purpose: FixtureSetupPurpose = .cohort, at time: Double = 2,
    issued: UInt64 = 1, correlated: UInt64 = 1, revocation: UInt64 = 0
  ) -> FixtureSetupRecord {
    FixtureSetupRecord(
      sequence: 1, nextIndex: 1, cohort: .ordinary, purpose: purpose,
      at: time, issued: issued, correlated: correlated, revocation: revocation,
      pairOccupied: false, readerOccupied: false)
  }
  private func completedSetup() throws -> FixtureSetupRecord {
    var value = setup()
    for (index, stage) in value.purpose.stages.enumerated() {
      try value.enter(stage, at: Double(index + 2))
      try value.complete(at: Double(index + 2))
    }
    try value.finish(at: 9)
    return value
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
  private func archive(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("docs/evidence/" + name))
  }

  func testEverySetupStageRetainsSuccessOrPartialFailureWithoutInventingLaterStages() throws {
    for purpose in FixtureSetupPurpose.allCases {
      for failureIndex in purpose.stages.indices {
        var value = setup(purpose: purpose)
        for index in 0...failureIndex {
          try value.enter(purpose.stages[index], at: Double(index + 2))
          if index < failureIndex { try value.complete(at: Double(index + 2)) }
        }
        try value.finish(at: 20, failure: .responseDeadline)
        XCTAssertTrue(value.valid)
        XCTAssertEqual(value.stage, purpose.stages[failureIndex])
        XCTAssertEqual(value.completed, UInt16((1 << failureIndex) - 1))
        XCTAssertThrowsError(try value.enter(purpose.stages[0], at: 21))
      }
    }
    let completed = try completedSetup()
    XCTAssertTrue(completed.valid)
    XCTAssertEqual(completed.completed, 127)
    XCTAssertNil(completed.failure)
  }

  func testStageOrderClockAndRequestCorrelationRejectMalformedProgress() throws {
    var value = setup()
    XCTAssertThrowsError(try value.enter(.normalizationAck, at: 3))
    XCTAssertThrowsError(try value.enter(.setupPrecondition, at: 1))
    XCTAssertThrowsError(try value.enter(.setupPrecondition, at: .nan))
    try value.enter(.setupPrecondition, at: 2)
    try value.complete(at: 2)
    XCTAssertThrowsError(try value.complete(at: 2))
    var wrong = setup(issued: 1, correlated: 2)
    XCTAssertThrowsError(try wrong.finish(at: 3, failure: .protocolFailure))
    var occupied = setup()
    occupied.readerOccupied = true
    try occupied.finish(at: 3, failure: .occupiedSetup)
    XCTAssertTrue(occupied.valid)
  }

  func testFirstStopSurvivesSetupExportCleanupAndSummaryFailure() throws {
    var value = setup()
    for stage in value.purpose.stages.prefix(6) {
      try value.enter(stage, at: 3)
      try value.complete(at: 3)
    }
    var collector = FixtureTimingCollector(schema: 3)
    try collector.append(manifest())
    collector.latchStop(
      FixtureFirstStop(
        stage: .activationConfirmation,
        category: .activationRefused, at: 4, setup: 1, pairs: 0, pairOccupied: false,
        readerOccupied: false))
    try value.finish(at: 5, failure: .activationRefused)
    try collector.setup(value)
    collector.latchStop(
      FixtureFirstStop(
        stage: .cleanup, category: .forcedCleanup,
        at: 6, pairs: 0, pairOccupied: false, readerOccupied: false))
    XCTAssertThrowsError(
      try collector.append(String(repeating: "x", count: 16384), maximumBytes: 15360))
    collector.close(orderly: false, passed: false)
    let report = try FixtureTimingReplay.review(collector.bytes)
    XCTAssertEqual(report.firstStop, .activationRefused)
    XCTAssertFalse(report.complete)
    XCTAssertEqual(report.setups, 1)
    XCTAssertEqual(report.summaryPresent, false)
    let data = collector.bytes
    collector.close(orderly: true, passed: true)
    XCTAssertEqual(collector.bytes, data)
    XCTAssertThrowsError(try collector.begin(.ordinary))
  }

  func testDiagnosticOnlyPreflightDoesNotFabricateTrustedManifest() throws {
    var collector = FixtureTimingCollector(schema: 3)
    collector.latchStop(
      FixtureFirstStop(
        stage: .trustPreflight, category: .untrusted, at: 1,
        pairs: 0, pairOccupied: false, readerOccupied: false))
    try collector.append(FixtureTimingSummary(records: []), maximumBytes: 15360)
    collector.close(orderly: true, passed: false)
    let report = try FixtureTimingReplay.review(collector.bytes)
    XCTAssertEqual(report.attempts, 0)
    XCTAssertEqual(report.firstStop, .untrusted)
    XCTAssertFalse(report.calibrationSuitable)
    XCTAssertFalse(try rows(collector.bytes).contains { $0["kind"] as? String == "manifest" })
  }

  func testExactReserveAndMaximalCompactValuesFitEachRecordCap() throws {
    XCTAssertEqual(FixtureDiagnosticBudget.reservedBytes, 262144)
    var value = setup(
      at: Double.greatestFiniteMagnitude,
      issued: UInt64.max, correlated: UInt64.max, revocation: UInt64.max)
    for stage in value.purpose.stages.prefix(6) {
      try value.enter(stage, at: Double.greatestFiniteMagnitude)
      try value.complete(at: Double.greatestFiniteMagnitude)
    }
    try value.finish(at: Double.greatestFiniteMagnitude, failure: .activationRefused)
    XCTAssertLessThanOrEqual(try JSONEncoder().encode(value).count + 1, 512)
    var maxContext = context
    maxContext.environment = UInt64.max
    maxContext.activation = UInt64.max
    maxContext.revocation = UInt64.max
    let event = FixtureTimingEvent(
      code: "activation", time: Double.greatestFiniteMagnitude,
      revocation: UInt64.max, pending: UInt64.max, context: maxContext,
      direction: .deactivate, relation: .unavailable)
    XCTAssertLessThanOrEqual(try JSONEncoder().encode(event).count + 1, 512)
    let stop = FixtureFirstStop(
      stage: .activationConfirmation, category: .activationRefused,
      at: Double.greatestFiniteMagnitude, setup: 14, request: UInt64.max, pairs: 28,
      pairOccupied: true, readerOccupied: true)
    XCTAssertLessThanOrEqual(try JSONEncoder().encode(stop).count + 1, 512)
    XCTAssertLessThanOrEqual(try JSONEncoder().encode(manifest()).count + 1, 1280)
    let wideManifest = FixtureTimingManifest(
      os: String(repeating: "V", count: 128),
      utc: "2026-10-12T00:00:00Z", labHash: String(repeating: "a", count: 64),
      fixtureHash: String(repeating: "b", count: 64), initialContext: maxContext,
      runStart: 285123.123456789, collectionDeadline: 285123.123456789 + 180,
      controlledSetupFailure: false)
    XCTAssertLessThanOrEqual(try JSONEncoder().encode(wideManifest).count + 1, 1280)
  }

  func testOutputExhaustionKeepsStopAndTerminalWithinReservedBytes() throws {
    var collector = FixtureTimingCollector(byteLimit: 2048, schema: 3)
    try collector.append(String(repeating: "x", count: 1000))
    XCTAssertThrowsError(try collector.append(String(repeating: "x", count: 100)))
    collector.latchStop(
      FixtureFirstStop(
        stage: .cleanup, category: .forcedCleanup,
        at: 2, pairs: 0, pairOccupied: false, readerOccupied: false))
    collector.close(orderly: false, passed: false)
    XCTAssertEqual(collector.firstStop?.category, .outputLimit)
    XCTAssertLessThanOrEqual(collector.bytes.count, 2048)
    let values = collector.bytes.split(separator: 10).suffix(2)
    XCTAssertEqual(values.count, 2)
    XCTAssertEqual(try rows(Data(values.first!) + Data([10]))[0]["kind"] as? String, "stop")
    XCTAssertEqual(try rows(Data(values.last!) + Data([10]))[0]["firstStop"] as? Bool, true)
  }

  func testPhysicalTimeoutRetainsSlotAndLaterDrainCannotReviveCollection() throws {
    var collector = FixtureTimingCollector(schema: 3)
    try collector.append(manifest())
    try collector.setup(completedSetup())
    let index = try collector.begin(.ordinary)
    var record = FixtureTimingRecord(
      index: index, cohort: .ordinary, requestedDelay: 0, run: run, schema: 3)
    record.mark(.admission, at: 10)
    record.mark(.terminal, at: 15)
    record.outcome = .timedOut
    collector.latchStop(
      FixtureFirstStop(
        stage: .reader, category: .readerWatchdog, at: 15,
        pairs: 0, pairOccupied: true, readerOccupied: true))
    try collector.finish(record, readerDrained: false)
    XCTAssertEqual(collector.occupied, 1)
    XCTAssertThrowsError(try collector.drained(index: 2))
    try collector.drained(index: 1)
    XCTAssertThrowsError(try collector.begin(.ordinary))
    try collector.append(FixtureTimingSummary(records: collector.records))
    collector.close(orderly: true, passed: false)
    let report = try FixtureTimingReplay.review(collector.bytes)
    XCTAssertEqual(report.absent, 1)
    XCTAssertEqual(report.assessed, 0)
    XCTAssertEqual(report.firstStop, .readerWatchdog)
    var contradictory = try rows(collector.bytes)
    let pair = contradictory.firstIndex { $0["kind"] as? String == "pair" }!
    contradictory[pair]["assessment"] = "historicalConsistent"
    XCTAssertThrowsError(try FixtureTimingReplay.review(encode(contradictory)))
  }

  func testMissingEncodedPairIsAbsentAndNeverAnAssessment() throws {
    var collector = FixtureTimingCollector(schema: 3)
    try collector.append(manifest())
    try collector.setup(completedSetup())
    let index = try collector.begin(.ordinary)
    var malformed = FixtureTimingRecord(
      index: index, cohort: .ordinary, requestedDelay: 0, run: run, schema: 3)
    malformed.mark(.entry, at: .nan)
    XCTAssertThrowsError(try collector.finish(malformed, readerDrained: true))
    try collector.append(FixtureTimingSummary(records: collector.records))
    collector.close(orderly: true, passed: false)
    let report = try FixtureTimingReplay.review(collector.bytes)
    XCTAssertEqual(report.attempts, 1)
    XCTAssertEqual(report.absent, 1)
    XCTAssertEqual(report.assessed, 0)
    XCTAssertEqual(report.firstStop, .clockFailure)
  }

  func testUnknownStageAndWrongSequenceOrDeadlineDoNotReplay() throws {
    var collector = FixtureTimingCollector(schema: 3)
    try collector.append(manifest())
    var value = setup()
    try value.finish(at: 3, failure: .occupiedSetup)
    collector.latchStop(
      FixtureFirstStop(
        stage: .setupPrecondition, category: .occupiedSetup,
        at: 3, setup: 1, pairs: 0, pairOccupied: false, readerOccupied: false))
    try collector.setup(value)
    collector.close(orderly: true, passed: false)
    let original = try rows(collector.bytes)
    for key in ["stage", "seq", "next"] {
      var copy = original
      let index = copy.firstIndex { $0["kind"] as? String == "setup" }!
      copy[index][key] = key == "stage" ? "unknown" : 2
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)))
    }
    var copy = original
    let index = copy.firstIndex { $0["kind"] as? String == "stop" }!
    copy[index]["category"] = "collectionDeadline"
    copy[index]["setup"] = nil
    XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)))
  }

  func testAllFourSchemaTwoArchivesKeepTheirHistoricalResults() throws {
    let expectations: [(String, Int, Bool, Bool)] = [
      ("m2-35-timing-first.jsonl", 27, true, true),
      ("m2-35-exclusion-first.jsonl", 27, true, false),
      ("m2-35-timing-final.jsonl", 27, true, false),
      ("m2-35-exclusion-final.jsonl", 15, false, false),
    ]
    for (file, count, complete, suitable) in expectations {
      let report = try FixtureTimingReplay.review(archive(file))
      XCTAssertEqual(report.assessed, count)
      XCTAssertEqual(report.complete, complete)
      XCTAssertEqual(report.calibrationSuitable, suitable)
      XCTAssertNil(report.setups)
      XCTAssertNil(report.firstStop)
    }
  }

  func testCompleteSchemaThreeScheduleReplaysBothModesAndRejectsMissingSetups() throws {
    for file in ["m2-35-timing-first.jsonl", "m2-35-exclusion-first.jsonl"] {
      let originalLines = try archive(file).split(separator: 10).map { Data($0) }
      let oldManifest = try JSONDecoder().decode(
        FixtureTimingManifest.self,
        from: originalLines.first!)
      let pairLine = originalLines.first {
        String(decoding: $0, as: UTF8.self).contains("\"kind\":\"pair\"")
      }!
      let firstTime = try JSONDecoder().decode(FixtureTimingRecord.self, from: pairLine).times
        .values.min()!
      let updated = FixtureTimingManifest(
        os: oldManifest.os, utc: oldManifest.utc,
        labHash: oldManifest.labHash, fixtureHash: oldManifest.fixtureHash,
        initialContext: oldManifest.initialContext,
        controlledExclusion: oldManifest.controlledExclusion,
        runStart: firstTime - 1, collectionDeadline: firstTime - 1 + 180,
        controlledSetupFailure: false)
      var result = try JSONEncoder().encode(updated)
      result.append(10)
      var sequence = 0
      var previousTerminal = firstTime - 1
      var issued: UInt64 = 1
      for line in originalLines.dropFirst() {
        var row = try JSONSerialization.jsonObject(with: line) as! [String: Any]
        var output = line
        if row["kind"] as? String == "pair" {
          let index = row["index"] as! Int
          let cohort = FixtureTimingCohort(rawValue: row["cohort"] as! String)!
          let pair = try JSONDecoder().decode(FixtureTimingRecord.self, from: line)
          let times = pair.times
          let currentFirst = times.values.min()!
          let admitted = pair.admitted!
          var purposes: [FixtureSetupPurpose] = []
          if [1, 5, 9, 13].contains(index) { purposes.append(.cohort) }
          if row["phase"] as? String == "recovery" { purposes.append(.recovery) }
          if oldManifest.controlledExclusion && index == 1 { purposes.append(.exclusion) }
          if oldManifest.controlledExclusion && index == 2 { purposes.append(.reset) }
          for (offset, purpose) in purposes.enumerated() {
            sequence += 1
            let start =
              previousTerminal + (currentFirst - previousTerminal) * Double(offset * 2 + 1) / 6
            let end =
              previousTerminal + (currentFirst - previousTerminal) * Double(offset * 2 + 2) / 6
            var setup = FixtureSetupRecord(
              sequence: sequence, nextIndex: index, cohort: cohort,
              purpose: purpose, at: start, issued: issued, correlated: issued,
              revocation: admitted.revocation, pairOccupied: false, readerOccupied: false)
            for stage in purpose.stages {
              try setup.enter(stage, at: start)
              try setup.complete(at: start)
            }
            try setup.finish(at: end)
            result.append(try JSONEncoder().encode(setup))
            result.append(10)
          }
          output = Data(
            String(decoding: line, as: UTF8.self).replacingOccurrences(
              of: "\"schema\":2", with: "\"schema\":3"
            ).utf8)
          previousTerminal = times["terminal"]!
          issued = (row["request"] as! NSNumber).uint64Value + (row["after"] != nil ? 1 : 0)
        } else if row["kind"] as? String == "terminal" {
          row["schema"] = 3
          row["records"] = 28
          row["setups"] = sequence
          row["firstStop"] = false
          output = try JSONSerialization.data(withJSONObject: row)
        }
        result.append(output)
        result.append(10)
      }
      let report = try FixtureTimingReplay.review(result)
      XCTAssertEqual(report.assessed, 27)
      XCTAssertEqual(report.failed, 1)
      XCTAssertTrue(report.complete)
      XCTAssertEqual(report.setups, oldManifest.controlledExclusion ? 14 : 12)
      XCTAssertEqual(report.calibrationSuitable, !oldManifest.controlledExclusion)
      var withoutSetups = Data()
      for line in result.split(separator: 10) {
        let object = try JSONSerialization.jsonObject(with: Data(line)) as! [String: Any]
        if object["kind"] as? String != "setup" {
          withoutSetups.append(contentsOf: line)
          withoutSetups.append(10)
        }
      }
      XCTAssertThrowsError(try FixtureTimingReplay.review(withoutSetups))
    }
  }

  func testInjectedFailureClockStampsResourceStopBeforeLaterCleanup() throws {
    var collector = FixtureTimingCollector(schema: 3, failureClock: { 42 })
    XCTAssertThrowsError(
      try collector.append(String(repeating: "x", count: 1280), maximumBytes: 1280))
    XCTAssertEqual(collector.firstStop?.time, 42)
    collector.latchStop(
      FixtureFirstStop(
        stage: .cleanup, category: .forcedCleanup, at: 43,
        pairs: 0, pairOccupied: false, readerOccupied: false))
    try collector.append(FixtureTimingSummary(records: []))
    collector.close(orderly: true, passed: false)
    let report = try FixtureTimingReplay.review(collector.bytes)
    XCTAssertEqual(report.firstStop, .recordLimit)
    XCTAssertFalse(report.complete)
    XCTAssertEqual(collector.firstStop?.time, 42)
  }

  func testInvalidEventsAndUnknownCleanupDoNotInventObservedCauses() throws {
    for (event, expected) in [
      (
        FixtureTimingEvent(code: "activation", time: .nan, revocation: 0, pending: nil),
        FixtureStopCategory.clockFailure
      ),
      (FixtureTimingEvent(code: "unknown", time: 1, revocation: 0, pending: nil), .protocolFailure),
    ] {
      var collector = FixtureTimingCollector(schema: 3)
      XCTAssertThrowsError(try collector.event(event))
      XCTAssertEqual(collector.firstStop?.category, expected)
    }
    var collector = FixtureTimingCollector(schema: 3, failureClock: { 2 })
    collector.close(orderly: false, passed: false)
    XCTAssertEqual(collector.firstStop?.category, .unclassified)
    XCTAssertEqual(collector.firstStop?.stage, .cleanup)
  }
}
