import Foundation
import ITileFixtureDiagnostics
import XCTest

final class SetupAckDelayTests: XCTestCase {
  private var context: FixtureUseContext {
    FixtureUseContext(
      expected: try! FixtureWindowIdentity(
        run: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, serial: 1))
  }

  private func manifest() -> FixtureTimingManifest {
    FixtureTimingManifest(
      os: "Test OS", utc: "2026-10-17T00:00:00Z",
      labHash: String(repeating: "a", count: 64), fixtureHash: String(repeating: "b", count: 64),
      initialContext: context, runStart: 1, collectionDeadline: 181,
      controlledSetupFailure: true, setupFault: .normalizationAckDelayOnce)
  }

  private func fault(scheduled: Bool = true) throws -> FixtureSetupFaultRecord {
    var value = FixtureSetupFaultRecord()
    try value.submit(at: 2)
    try value.observe("setup-ack-delay-armed 2.1", at: 2.2)
    try value.normalizationWrite(at: 3)
    try value.beginWait(at: 3.01)
    if scheduled { try value.observe("setup-ack-delay-deferred 3.02 9.02", at: 3.03) }
    return value
  }

  private func dataset(
    scheduled: Bool = true, category: FixtureStopCategory = .responseDeadline,
    running: Bool = true, orderly: Bool = true, end: Double = 8.02
  ) throws -> Data {
    var collector = FixtureTimingCollector(schema: 4)
    try collector.append(manifest(), maximumBytes: FixtureDiagnosticBudget.manifestBytes)
    var setup = FixtureSetupRecord(
      sequence: 1, nextIndex: 1, cohort: .ordinary, purpose: .cohort, at: 2.3,
      issued: 1, correlated: 1, revocation: 0, pairOccupied: false, readerOccupied: false)
    try setup.enter(.setupPrecondition, at: 2.3)
    try setup.complete(at: 2.3)
    try setup.enter(.normalizationWrite, at: 2.4)
    try setup.complete(at: 3.005)
    try setup.enter(.normalizationAck, at: 3.006)
    collector.latchStop(
      FixtureFirstStop(
        stage: .normalizationAck, category: category, at: end,
        setup: 1, pairs: 0, pairOccupied: false, readerOccupied: false))
    try setup.finish(at: end + 0.01, failure: category)
    try collector.setup(setup)
    var observation = try fault(scheduled: scheduled)
    try observation.finish(at: end, category: category, running: running)
    try collector.setupFault(observation)
    try collector.append(
      FixtureTimingSummary(records: []),
      maximumBytes: FixtureDiagnosticBudget.summaryBytes(schema: 4))
    collector.close(orderly: orderly, passed: false)
    return collector.bytes
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

  func testFixtureRequiresOptInArmsOnceAndConsumesOnlyCloseSheet() throws {
    var disabled = FixtureAckDelayOnce(enabled: false)
    XCTAssertNil(disabled.arm(at: 1))
    XCTAssertNil(disabled.deferAcknowledgment(for: "close-sheet", at: 2))
    var enabled = FixtureAckDelayOnce(enabled: true)
    XCTAssertNil(enabled.deferAcknowledgment(for: "close-sheet", at: 1))
    XCTAssertNil(enabled.arm(at: .nan))
    XCTAssertEqual(enabled.arm(at: 2), "setup-ack-delay-armed 2.0")
    XCTAssertNil(enabled.arm(at: 2))
    for command in ["quit", "activate", "safety-snapshot 1", "native-sheet"] {
      XCTAssertNil(enabled.deferAcknowledgment(for: command, at: 3))
    }
    XCTAssertNil(enabled.deferAcknowledgment(for: "close-sheet", at: 1))
    XCTAssertNil(enabled.deferAcknowledgment(for: "close-sheet", at: .infinity))
    XCTAssertEqual(
      enabled.deferAcknowledgment(for: "close-sheet", at: 3),
      "setup-ack-delay-deferred 3.0 9.0")
    XCTAssertNil(enabled.arm(at: 4))
    XCTAssertNil(enabled.deferAcknowledgment(for: "close-sheet", at: 4))
    XCTAssertEqual(FixtureAckDelayOnce.responseSeconds, 5)
  }

  func testSubmissionArmingSchedulingAndReceiptAreDistinctObservedFacts() throws {
    var value = FixtureSetupFaultRecord()
    XCTAssertEqual(value.result, .notSubmitted)
    try value.submit(at: 2)
    XCTAssertEqual(value.result, .submitted)
    XCTAssertNil(value.armed)
    XCTAssertThrowsError(try value.normalizationWrite(at: 2.1))
    try value.observe("setup-ack-delay-armed 2.1", at: 2.2)
    XCTAssertEqual(value.result, .armed)
    XCTAssertNil(value.scheduled)
    try value.normalizationWrite(at: 3)
    try value.beginWait(at: 3.01)
    try value.observe("setup-ack-delay-deferred 3.02 9.02", at: 3.03)
    XCTAssertEqual(value.result, .deferred)
    XCTAssertEqual(value.scheduled, 3.02)
    XCTAssertEqual(value.due, 9.02)
    XCTAssertEqual(value.receipt, 3.03)
    try value.finish(at: 8.02, category: .responseDeadline, running: true)
    XCTAssertTrue(value.valid)
    XCTAssertThrowsError(try value.observe("setup-ack-delay-deferred 8.1 14.1", at: 8.2))
    XCTAssertThrowsError(try value.submit(at: 8.2))
  }

  func testWrongMissingDuplicateLateAndNonfiniteMarkersCannotCreateEvidence() throws {
    for marker in [
      "setup-ack-delay-armed", "setup-ack-delay-armed 2.1 extra", "setup-ack-delay-armed 02.1",
      "setup-ack-delay-armed 1.0", "setup-ack-delay-armed nan", "setup-ack-delay-armed inf",
      "setup-ack-delay-deferred 2.0 8.0", "other 2.1",
    ] {
      var value = FixtureSetupFaultRecord()
      try value.submit(at: 2)
      XCTAssertThrowsError(try value.observe(marker, at: 2.2), marker)
      XCTAssertEqual(value.result, .submitted)
    }
    for (marker, time) in [
      ("setup-ack-delay-armed 3.02", 3.03),
      ("setup-ack-delay-deferred 2.9 8.9", 3.03),
      ("setup-ack-delay-deferred 3.02 8.02", 3.03),
      ("setup-ack-delay-deferred 3.02 9.02", 3.0),
      ("setup-ack-delay-deferred 3.02 9.02", 9.02),
      ("setup-ack-delay-deferred 3.02 9.02", Double.nan),
    ] {
      var value = try fault(scheduled: false)
      XCTAssertThrowsError(try value.observe(marker, at: time))
      XCTAssertNil(value.scheduled)
    }
    var value = try fault()
    XCTAssertThrowsError(try value.observe("setup-ack-delay-deferred 3.02 9.02", at: 3.04))
    XCTAssertThrowsError(try value.finish(at: 3, category: .responseDeadline, running: true))
    var missing = FixtureSetupFaultRecord()
    try missing.finish(at: 2, category: .pipeWrite, running: true)
    XCTAssertTrue(missing.valid)
    let object =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(missing)) as! [String: Any]
    for key in ["sent", "armed", "armReceipt", "scheduled", "due", "receipt", "write", "wait"] {
      XCTAssertTrue(object[key] is NSNull, key)
    }
  }

  func testObservedTimeoutAndMissingMarkerStayIncompleteWithZeroPairAdmission() throws {
    for scheduled in [true, false] {
      let data = try dataset(scheduled: scheduled)
      let report = try FixtureTimingReplay.review(data)
      XCTAssertEqual(report.attempts, 0)
      XCTAssertEqual(report.assessed, 0)
      XCTAssertEqual(report.setups, 1)
      XCTAssertEqual(report.firstStop, .responseDeadline)
      XCTAssertFalse(report.complete)
      XCTAssertFalse(report.calibrationSuitable)
      XCTAssertEqual(try rows(data).first { $0["kind"] as? String == "setup" }?["done"] as? Int, 3)
    }
    XCTAssertThrowsError(try FixtureTimingReplay.review(dataset(end: 8)))
    XCTAssertThrowsError(try FixtureTimingReplay.review(dataset(running: false)))
    XCTAssertThrowsError(try FixtureTimingReplay.review(dataset(end: 9.03)))
    for (category, running, end) in [
      (FixtureStopCategory.childExited, false, 4.0), (.childEOF, true, 4),
      (.protocolFailure, true, 4), (.unexpectedAcknowledgment, true, 4),
      (.collectionDeadline, true, 181),
    ] {
      let report = try FixtureTimingReplay.review(
        dataset(category: category, running: running, end: end))
      XCTAssertEqual(report.firstStop, category)
      XCTAssertFalse(report.complete)
    }
    XCTAssertEqual(
      try FixtureTimingReplay.review(dataset(orderly: false)).firstStop, .responseDeadline)
  }

  func testStrictReplayRejectsConfigurationClocksMasksLinkageAndAcceptanceForgery() throws {
    let original = try rows(dataset())
    for (kind, key, value): (String, String, Any) in [
      ("manifest", "schema", 3), ("manifest", "faultSeconds", 5),
      ("manifest", "responseSeconds", 4), ("manifest", "setupFault", "other"),
      ("manifest", "summaryLimit", 15104), ("manifest", "controlledExclusion", true),
      ("setupFault", "armed", 1.0), ("setupFault", "receipt", 3.0),
      ("setupFault", "due", 8.0), ("setupFault", "end", 8.03),
      ("setupFault", "result", "armed"), ("setupFault", "category", "childExited"),
      ("setupFault", "running", false), ("setupFault", "unknown", true),
      ("setup", "done", 7), ("setup", "next", 2), ("setup", "issued", 2),
      ("setup", "reader", true), ("setup", "stage", "activationWrite"),
      ("stop", "setup", 2), ("stop", "time", 8.03), ("stop", "pairs", 1),
      ("terminal", "complete", true), ("terminal", "calibrationSuitable", true),
      ("terminal", "attempts", 1), ("terminal", "occupied", true),
    ] {
      var copy = original
      let index = copy.firstIndex { $0["kind"] as? String == kind }!
      copy[index][key] = value
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)), "\(kind).\(key)")
    }
    for kind in ["setup", "setupFault", "stop"] {
      XCTAssertThrowsError(
        try FixtureTimingReplay.review(encode(original.filter { $0["kind"] as? String != kind })))
      var duplicate = original
      duplicate.insert(original.first { $0["kind"] as? String == kind }!, at: 2)
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(duplicate)))
    }
    var late = original
    late.append(late.first { $0["kind"] as? String == "setupFault" }!)
    XCTAssertThrowsError(try FixtureTimingReplay.review(encode(late)))
  }

  func testSchemaFourPreflightAndPartialArmingRetainActualFailure() throws {
    for submitted in [false, true] {
      var collector = FixtureTimingCollector(schema: 4)
      if submitted { try collector.append(manifest()) }
      collector.latchStop(
        FixtureFirstStop(
          stage: submitted ? .manifest : .trustPreflight,
          category: submitted ? .responseDeadline : .untrusted, at: 8,
          pairs: 0, pairOccupied: false, readerOccupied: false))
      if submitted {
        var value = FixtureSetupFaultRecord()
        try value.submit(at: 2)
        try value.finish(at: 8, category: .responseDeadline, running: true)
        try collector.setupFault(value)
      }
      collector.close(orderly: true, passed: false)
      let report = try FixtureTimingReplay.review(collector.bytes)
      XCTAssertEqual(report.firstStop, submitted ? .responseDeadline : .untrusted)
      XCTAssertEqual(report.setups, 0)
      XCTAssertEqual(report.attempts, 0)
    }
  }

  func testRetainedNativeTimeoutReplaysAndNewCategoryCannotEnterSchemaThreeHistory() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let retained = try Data(
      contentsOf: root.appendingPathComponent("docs/evidence/m2-41-ack-delay.jsonl"))
    let report = try FixtureTimingReplay.review(retained)
    XCTAssertEqual(report.attempts, 0)
    XCTAssertEqual(report.firstStop, .responseDeadline)
    XCTAssertEqual(report.setups, 1)
    XCTAssertFalse(report.complete)
    XCTAssertFalse(report.calibrationSuitable)
    let values = try rows(retained)
    let fault = values.first { $0["kind"] as? String == "setupFault" }!
    XCTAssertEqual(fault["result"] as? String, "deferred")
    XCTAssertEqual(values.last?["orderly"] as? Bool, true)
    let historical = try Data(
      contentsOf: root.appendingPathComponent("docs/evidence/m2-37-setup-exit.jsonl"))
    var forged = try rows(historical)
    for index in forged.indices {
      if forged[index]["kind"] as? String == "setup" {
        forged[index]["failure"] = "unexpectedAcknowledgment"
      } else if forged[index]["kind"] as? String == "stop" {
        forged[index]["category"] = "unexpectedAcknowledgment"
      }
    }
    XCTAssertThrowsError(try FixtureTimingReplay.review(encode(forged)))
  }

  func testFaultRecordIsOneShotAndFirstStopSurvivesExportAndCleanupFailure() throws {
    var collector = FixtureTimingCollector(schema: 4)
    XCTAssertThrowsError(try collector.begin(.ordinary))
    var observation = try fault()
    try observation.finish(at: 8.02, category: .responseDeadline, running: true)
    let stop = FixtureFirstStop(
      stage: .normalizationAck, category: .responseDeadline, at: 8.02,
      setup: 1, pairs: 0, pairOccupied: false, readerOccupied: false)
    collector.latchStop(stop)
    try collector.setupFault(observation)
    XCTAssertThrowsError(try collector.setupFault(observation))
    XCTAssertThrowsError(
      try collector.append(String(repeating: "x", count: 512), maximumBytes: 512))
    collector.latchStop(
      FixtureFirstStop(
        stage: .cleanup, category: .forcedCleanup, at: 9, pairs: 0,
        pairOccupied: false, readerOccupied: false))
    collector.close(orderly: false, passed: true)
    XCTAssertEqual(collector.firstStop?.category, .responseDeadline)
    XCTAssertEqual(collector.firstStop?.time, 8.02)
    XCTAssertThrowsError(try collector.begin(.ordinary))
    let bytes = collector.bytes
    collector.close(orderly: true, passed: true)
    XCTAssertEqual(collector.bytes, bytes)
    XCTAssertEqual(try rows(bytes).last?["complete"] as? Bool, false)
  }

  func testSchemaFourReserveAndMaximalValuesFitWithoutBorrowingClosureBytes() throws {
    XCTAssertEqual(FixtureDiagnosticBudget.summaryBytes(schema: 4), 14592)
    XCTAssertEqual(FixtureDiagnosticBudget.reservedBytes(schema: 4), 262144)
    XCTAssertEqual(28 + 128 + 14 + 1 + 1 + 1 + 1 + 1, 175)
    var widest = FixtureSetupFaultRecord()
    let early = 1.234567890123456e-100
    try widest.submit(at: early)
    try widest.observe("setup-ack-delay-armed \(early)", at: early)
    try widest.normalizationWrite(at: early)
    try widest.beginWait(at: early)
    try widest.observe("setup-ack-delay-deferred \(early) 6.0", at: early)
    try widest.finish(
      at: Double.greatestFiniteMagnitude, category: .unexpectedAcknowledgment, running: false)
    XCTAssertTrue(widest.valid)
    XCTAssertLessThanOrEqual(try JSONEncoder().encode(widest).count + 1, 512)
    var faultUpperBound =
      try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(widest)) as! [String: Any]
    for key in [
      "sent", "armed", "armReceipt", "write", "wait", "scheduled", "due", "receipt", "end",
    ] {
      faultUpperBound[key] = String(repeating: "9", count: 25)
    }
    XCTAssertLessThanOrEqual(
      try JSONSerialization.data(withJSONObject: faultUpperBound).count + 1, 512)
    var wideContext = context
    wideContext.environment = UInt64.max
    wideContext.activation = UInt64.max
    wideContext.revocation = UInt64.max
    let wideManifest = FixtureTimingManifest(
      os: String(repeating: "V", count: 128), utc: "2026-10-17T00:00:00Z",
      labHash: String(repeating: "a", count: 64), fixtureHash: String(repeating: "b", count: 64),
      initialContext: wideContext, runStart: early, collectionDeadline: early + 180,
      controlledSetupFailure: true, setupFault: .normalizationAckDelayOnce)
    XCTAssertTrue(wideManifest.valid)
    XCTAssertLessThanOrEqual(try JSONEncoder().encode(wideManifest).count + 1, 1280)
    // Quoted 32-byte placeholders exceed any nonnegative JSON Double spelling.
    // All other fields are at their schema-4 maxima, including unescaped OS
    // metadata and a canonical 20-byte UTC value.
    var upperBound =
      try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(wideManifest)) as! [String: Any]
    upperBound["runStart"] = String(repeating: "9", count: 32)
    upperBound["collectionDeadline"] = String(repeating: "9", count: 32)
    XCTAssertLessThanOrEqual(try JSONSerialization.data(withJSONObject: upperBound).count + 1, 1280)
    for os in [String(repeating: "\n", count: 128), "Version \\", "Version /", "Version \""] {
      var invalid = upperBound
      invalid["os"] = os
      invalid["runStart"] = 1
      invalid["collectionDeadline"] = 181
      let decoded = try JSONDecoder().decode(
        FixtureTimingManifest.self, from: JSONSerialization.data(withJSONObject: invalid))
      XCTAssertFalse(decoded.valid)
    }
    for row in try rows(dataset()) {
      let kind = row["kind"] as! String
      let cap = kind == "manifest" ? 1280 : kind == "summary" ? 14592 : 512
      XCTAssertLessThanOrEqual(try JSONSerialization.data(withJSONObject: row).count + 1, cap, kind)
    }
    XCTAssertThrowsError(try FixtureTimingReplay.review(Data(repeating: 10, count: 262145)))
    XCTAssertThrowsError(try FixtureTimingReplay.review(Data(repeating: 10, count: 176)))
  }
}
