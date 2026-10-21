import Darwin
import Foundation
import ITileFixtureDiagnostics
import ITileFixtureTransport
import XCTest

final class SetupOutputEOFTests: XCTestCase {
  private var context: FixtureUseContext {
    FixtureUseContext(
      expected: try! FixtureWindowIdentity(
        run: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, serial: 1))
  }

  private func manifest(context: FixtureUseContext? = nil, os: String = "Synthetic EOF Test OS")
    -> FixtureTimingManifest
  {
    FixtureTimingManifest(
      os: os, utc: "2026-10-21T00:00:00Z",
      labHash: String(repeating: "a", count: 64), fixtureHash: String(repeating: "b", count: 64),
      initialContext: context ?? self.context, runStart: 1, collectionDeadline: 181,
      controlledSetupFailure: true, setupFault: .normalizationOutputEOFOnce,
      eventSources: .environmentCallbacks)
  }

  private func observation(selected: Bool = true) throws -> FixtureOutputEOFRecord {
    var fault = FixtureOutputEOFRecord()
    try fault.submit(at: 2)
    try fault.observe("setup-output-eof-armed 2.1", at: 2.2)
    try fault.normalizationWrite(at: 3.1)
    try fault.beginWait(at: 3.31, deadline: 3.31 + 5)
    if selected { try fault.observe("setup-output-eof-selected 3.4", at: 3.5) }
    return fault
  }

  private func dataset(
    category: FixtureStopCategory = .childEOF, running: Bool = true,
    selected: Bool = true, orderly: Bool = true
  ) throws -> Data {
    var collector = FixtureTimingCollector(schema: 6)
    try collector.append(manifest(), maximumBytes: 1280)
    var host = FixtureDiagnosticHost(context: context)
    host.observe(.environment)
    try collector.event(
      FixtureTimingEvent(
        code: "environment", time: 3.55,
        revocation: host.context.revocation, pending: nil, context: host.context,
        source: .screenParameters))
    let end: Double =
      category == .collectionDeadline ? 181 : category == .responseDeadline ? 8.32 : 3.6
    var setup = FixtureSetupRecord(
      sequence: 1, nextIndex: 1, cohort: .ordinary, purpose: .cohort,
      at: 3, issued: 1, correlated: 1, revocation: 0, pairOccupied: false, readerOccupied: false)
    try setup.enter(.setupPrecondition, at: 3)
    try setup.complete(at: 3)
    try setup.enter(.normalizationWrite, at: 3.05)
    try setup.complete(at: 3.2)
    try setup.enter(.normalizationAck, at: 3.3)
    setup.revocationAfter = host.context.revocation
    try setup.finish(at: end + 0.01, failure: category)
    try collector.setup(setup)
    var fault = try observation(selected: selected)
    if category == .childEOF { try fault.observeEOF(at: end, running: running) }
    try fault.finish(at: end, category: category)
    try collector.setupFault(fault)
    try collector.append(FixtureTimingSummary(records: []), maximumBytes: 14592)
    collector.latchStop(
      FixtureFirstStop(
        stage: .normalizationAck, category: category, at: end,
        setup: 1, pairs: 0, pairOccupied: false, readerOccupied: false))
    collector.close(orderly: orderly, passed: true)
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

  func testOptInPrerequisitesMutualExclusionAndOneShotCommandSelection() throws {
    for enabled in [false, true] {
      for safety in [false, true] {
        for nested in [false, true] {
          for delay in [false, true] {
            var fault = FixtureOutputEOFOnce(
              enabled: enabled, safety: safety, nested: nested, acknowledgmentDelay: delay)
            XCTAssertNil(fault.select(for: "close-sheet", at: 1))
            XCTAssertNil(fault.arm(at: .nan))
            let marker = fault.arm(at: 2)
            if enabled && safety && nested && !delay {
              XCTAssertEqual(marker, "setup-output-eof-armed 2.0")
              XCTAssertNil(fault.arm(at: 3))
              for command in [
                "quit", "activate", "safety-snapshot 1", "native-sheet", "tree-ordinary",
              ] {
                XCTAssertNil(fault.select(for: command, at: 3))
              }
              XCTAssertNil(fault.select(for: "close-sheet", at: 1))
              XCTAssertNil(fault.select(for: "close-sheet", at: .infinity))
              XCTAssertEqual(
                fault.select(for: "close-sheet", at: 3), "setup-output-eof-selected 3.0")
              XCTAssertNil(fault.arm(at: 4))
              XCTAssertNil(fault.select(for: "close-sheet", at: 4))
            } else {
              XCTAssertNil(marker)
            }
          }
        }
      }
    }
  }

  func testSelectionIsIntentAndOnlyObservedEOFCanSupplyLiveness() throws {
    var fault = try observation()
    XCTAssertEqual(fault.result, .selected)
    XCTAssertNil(fault.eof)
    XCTAssertNil(fault.running)
    XCTAssertFalse(fault.observedLiveSelectedEOF)
    XCTAssertThrowsError(try fault.finish(at: 3.6, category: .childEOF))
    try fault.observeEOF(at: 3.6, running: true)
    try fault.finish(at: 3.6, category: .childEOF)
    XCTAssertTrue(fault.valid)
    XCTAssertTrue(fault.observedLiveSelectedEOF)
    XCTAssertThrowsError(try fault.observeEOF(at: 3.7, running: true))
    XCTAssertThrowsError(try fault.observe("setup-output-eof-selected 3.7", at: 3.8))
    for selected in [false, true] {
      var dead = try observation(selected: selected)
      try dead.observeEOF(at: 3.6, running: false)
      try dead.finish(at: 3.6, category: .childEOF)
      XCTAssertTrue(dead.valid)
      XCTAssertFalse(dead.observedLiveSelectedEOF)
    }
    var missing = try observation(selected: false)
    try missing.observeEOF(at: 3.6, running: true)
    try missing.finish(at: 3.6, category: .childEOF)
    XCTAssertFalse(missing.observedLiveSelectedEOF)
  }

  func testMarkerGrammarCausalClocksAndRedirectionFailureNeverInventEOF() throws {
    for line in [
      "setup-output-eof-armed", "setup-output-eof-armed 02.1", "setup-output-eof-armed 2.1 extra",
      "setup-output-eof-armed nan", "setup-output-eof-armed inf", "setup-output-eof-armed 1.0",
      "setup-output-eof-selected 2.1", "setup-output-eof-unknown 2.1",
    ] {
      var value = FixtureOutputEOFRecord()
      try value.submit(at: 2)
      XCTAssertThrowsError(try value.observe(line, at: 2.2), line)
      XCTAssertEqual(value.result, .submitted)
    }
    for line in [
      "setup-output-eof-selected 3.0", "setup-output-eof-selected 4.0",
      "setup-output-eof-armed 3.4",
    ] {
      var value = try observation(selected: false)
      XCTAssertThrowsError(try value.observe(line, at: 3.5))
    }
    var failed = try observation()
    XCTAssertThrowsError(try failed.observe("setup-output-eof-failed 3.51", at: 3.52))
    try failed.finish(at: 3.6, category: .protocolFailure)
    XCTAssertTrue(failed.valid)
    XCTAssertNil(failed.eof)
    XCTAssertNil(failed.running)
    var earlySelection = try observation(selected: false)
    try earlySelection.observe("setup-output-eof-selected 3.2", at: 3.5)
    try earlySelection.finish(at: 3.6, category: .unexpectedAcknowledgment)
    XCTAssertTrue(earlySelection.valid)  // Fixture selection may precede host wait entry.
    for time in [Double.nan, .infinity, -1, 3.0, 3.31 + 5] {
      var value = try observation()
      XCTAssertThrowsError(try value.observeEOF(at: time, running: true))
    }
  }

  func testRealDescriptorReplacementKeepsCommandPipeAndVerifierOutputUsable() throws {
    try FixtureOutputTransport.selfCheck()
    XCTAssertThrowsError(try FixtureOutputTransport.redirectToNull(-1))
    XCTAssertThrowsError(try FixtureOutputTransport.redirectToNull(STDIN_FILENO))
    XCTAssertThrowsError(try FixtureOutputTransport.redirectToNull(STDERR_FILENO))
    XCTAssertEqual(FixtureOutputTransport.classifyRead(count: 1, error: EIO), .bytes)
    XCTAssertEqual(FixtureOutputTransport.classifyRead(count: 0, error: EAGAIN), .eof)
    for error in [EAGAIN, EINTR] {
      XCTAssertEqual(FixtureOutputTransport.classifyRead(count: -1, error: error), .retry)
    }
    for error in [EIO, EBADF, EPIPE] {
      XCTAssertEqual(FixtureOutputTransport.classifyRead(count: -1, error: error), .failure)
    }
  }

  func testDeadlineBoundariesAndRegressingMarkersCannotBecomeEOF() throws {
    for deadline in [Double.nan, .infinity, 3.31, 8.32] {
      var value = FixtureOutputEOFRecord()
      try value.submit(at: 2)
      try value.observe("setup-output-eof-armed 2.1", at: 2.2)
      try value.normalizationWrite(at: 3.1)
      XCTAssertThrowsError(try value.beginWait(at: 3.31, deadline: deadline))
    }
    var late = try observation(selected: false)
    XCTAssertThrowsError(try late.observe("setup-output-eof-selected 3.4", at: 3.31 + 5))
    try late.finish(at: 8.32, category: .responseDeadline)
    XCTAssertTrue(late.valid)
    XCTAssertNil(late.eof)
    XCTAssertNil(late.running)
    var regression = try observation()
    XCTAssertThrowsError(try regression.observe("setup-output-eof-failed 3.3", at: 3.55))
    try regression.finish(at: 3.6, category: .clockFailure)
    XCTAssertTrue(regression.valid)
    var truncated = FixtureOutputEOFRecord()
    try truncated.submit(at: 2)
    try truncated.observe("setup-output-eof-armed 2.1", at: 2.2)
    try truncated.normalizationWrite(at: 3.1)
    try truncated.beginWait(at: 3.31, deadline: 4)
    XCTAssertThrowsError(try truncated.observeEOF(at: 4, running: true))
    try truncated.finish(at: 4, category: .collectionDeadline)
    XCTAssertTrue(truncated.valid)
  }

  func testObservedEOFReplayAndAlternativeFailuresRetainIncompleteControl() throws {
    for category: FixtureStopCategory in [
      .childEOF, .childExited, .pipeRead, .pipeWrite, .protocolFailure,
      .responseDeadline, .collectionDeadline, .unexpectedAcknowledgment,
    ] {
      for orderly in [false, true] {
        let data = try dataset(category: category, orderly: orderly)
        let report = try FixtureTimingReplay.review(data)
        XCTAssertEqual(report.firstStop, category)
        XCTAssertEqual(report.attempts, 0)
        XCTAssertEqual(report.assessed, 0)
        XCTAssertEqual(report.setups, 1)
        XCTAssertEqual(report.summaryPresent, true)
        XCTAssertFalse(report.complete)
        XCTAssertFalse(report.calibrationSuitable)
      }
    }
    for running in [false, true] {
      for selected in [false, true] {
        XCTAssertEqual(
          try FixtureTimingReplay.review(dataset(running: running, selected: selected)).firstStop,
          .childEOF)
      }
    }
  }

  func testStrictFaultClockLinkageSourceMetadataAndZeroAdmission() throws {
    let original = try rows(dataset())
    for (kind, key, value) in [
      ("setupFault", "running", NSNull()), ("setupFault", "result", "selected"),
      ("setupFault", "eof", NSNull()), ("setupFault", "end", 3.61), ("setupFault", "limit", 9.0),
      ("setupFault", "receipt", 3.0), ("setupFault", "selected", 3.0),
      ("setup", "done", 7), ("setup", "revAfter", 0), ("setup", "next", 2),
      ("stop", "time", 3.61), ("stop", "pairs", 1), ("terminal", "attempts", 1),
      ("terminal", "occupied", true), ("terminal", "complete", true),
      ("terminal", "calibrationSuitable", true),
      ("event", "source", "nativeSpace"), ("event", "source", NSNull()),
      ("event", "time", 3.7), ("manifest", "faultSeconds", 6),
      ("manifest", "eventSources", "unknown"),
      ("manifest", "setupFault", "normalizationAckDelayOnce"),
    ] as [(String, String, Any)] {
      var copy = original
      copy[copy.firstIndex { $0["kind"] as? String == kind }!][key] = value
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)), "\(kind).\(key)")
    }
    for kind in ["setupFault", "setup", "stop"] {
      XCTAssertThrowsError(
        try FixtureTimingReplay.review(encode(original.filter { $0["kind"] as? String != kind })))
      var copy = original
      copy.insert(copy.first { $0["kind"] as? String == kind }!, at: 2)
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)))
    }
    for schema in [2, 3, 4, 5] {
      var copy = original
      copy[0]["schema"] = schema
      copy[copy.count - 1]["schema"] = schema
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)))
    }
  }

  func testPartialArmingAndPreflightNullsRetainActualEarlierFailure() throws {
    for submitted in [false, true] {
      var collector = FixtureTimingCollector(schema: 6)
      if submitted { try collector.append(manifest()) }
      collector.latchStop(
        FixtureFirstStop(
          stage: submitted ? .manifest : .trustPreflight,
          category: submitted ? .responseDeadline : .untrusted, at: 8, pairs: 0,
          pairOccupied: false, readerOccupied: false))
      if submitted {
        var fault = FixtureOutputEOFRecord()
        try fault.submit(at: 2)
        try fault.finish(at: 8, category: .responseDeadline)
        let object =
          try JSONSerialization.jsonObject(with: JSONEncoder().encode(fault)) as! [String: Any]
        for key in [
          "armed", "armReceipt", "write", "wait", "limit", "selected", "receipt", "eof", "running",
        ] {
          XCTAssertTrue(object[key] is NSNull, key)
        }
        try collector.setupFault(fault)
      }
      collector.close(orderly: true, passed: false)
      let report = try FixtureTimingReplay.review(collector.bytes)
      XCTAssertEqual(report.setups, 0)
      XCTAssertFalse(report.complete)
      XCTAssertEqual(report.firstStop, submitted ? .responseDeadline : .untrusted)
    }
    var armingEOF = FixtureOutputEOFRecord()
    try armingEOF.submit(at: 2)
    try armingEOF.observeEOF(at: 2.5, running: true)
    try armingEOF.finish(at: 2.5, category: .childEOF)
    XCTAssertTrue(armingEOF.valid)
    XCTAssertFalse(armingEOF.observedLiveSelectedEOF)
  }

  func testFirstStopSurvivesExportCleanupAndLateDataWithoutRevival() throws {
    var collector = FixtureTimingCollector(schema: 6)
    var fault = try observation()
    try fault.observeEOF(at: 3.6, running: true)
    try fault.finish(at: 3.6, category: .childEOF)
    collector.latchStop(
      FixtureFirstStop(
        stage: .normalizationAck, category: .childEOF, at: 3.6,
        pairs: 0, pairOccupied: false, readerOccupied: false))
    try collector.setupFault(fault)
    XCTAssertThrowsError(try collector.setupFault(fault))
    XCTAssertThrowsError(
      try collector.append(String(repeating: "x", count: 512), maximumBytes: 512))
    XCTAssertThrowsError(try collector.begin(.ordinary))
    collector.latchStop(
      FixtureFirstStop(
        stage: .cleanup, category: .forcedCleanup, at: 4,
        pairs: 0, pairOccupied: false, readerOccupied: false))
    collector.close(orderly: false, passed: true)
    XCTAssertEqual(collector.firstStop?.category, .childEOF)
    XCTAssertEqual(collector.firstStop?.time, 3.6)
    XCTAssertEqual(collector.admissions, 0)
    let bytes = collector.bytes
    XCTAssertThrowsError(
      try collector.event(
        FixtureTimingEvent(
          code: "environment", time: 4,
          revocation: 1, pending: nil, source: .didWake)))
    collector.close(orderly: true, passed: true)
    XCTAssertEqual(collector.bytes, bytes)
  }

  func testMaximalEOFFaultManifestEventAndEnvelopeBudgets() throws {
    var wideContext = context
    wideContext.environment = .max
    wideContext.activation = .max
    wideContext.revocation = .max
    let maximal = manifest(context: wideContext, os: String(repeating: "V", count: 128))
    XCTAssertTrue(maximal.valid)
    var upper =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(maximal)) as! [String: Any]
    upper["runStart"] = String(repeating: "9", count: 32)
    upper["collectionDeadline"] = String(repeating: "9", count: 32)
    XCTAssertLessThanOrEqual(try JSONSerialization.data(withJSONObject: upper).count + 1, 1280)
    var value = try observation()
    try value.observeEOF(at: 3.6, running: true)
    try value.finish(at: 3.6, category: .childEOF)
    var faultUpper =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
    for key in [
      "sent", "armed", "armReceipt", "write", "wait", "limit", "selected", "receipt", "eof", "end",
    ] {
      faultUpper[key] = String(repeating: "9", count: 25)
    }
    faultUpper["result"] = "notSubmitted"
    faultUpper["running"] = false
    faultUpper["category"] = "unexpectedAcknowledgment"
    XCTAssertLessThanOrEqual(try JSONSerialization.data(withJSONObject: faultUpper).count + 1, 512)
    for source in FixtureEnvironmentSource.allCases {
      let event = FixtureTimingEvent(
        code: source.eventCode, time: Double.greatestFiniteMagnitude,
        revocation: .max, pending: .max, context: wideContext, source: source)
      XCTAssertTrue(event.hasValidMetadata(for: 6))
      XCTAssertLessThanOrEqual(try JSONEncoder().encode(event).count + 1, 512)
    }
    XCTAssertEqual(FixtureDiagnosticBudget.reservedBytes(schema: 6), 262144)
    XCTAssertEqual(FixtureDiagnosticBudget.summaryBytes(schema: 6), 14592)
    let data = try dataset()
    for row in try rows(data) {
      let kind = row["kind"] as! String
      let cap = kind == "manifest" ? 1280 : kind == "summary" ? 14592 : 512
      XCTAssertLessThanOrEqual(try JSONSerialization.data(withJSONObject: row).count + 1, cap)
    }
    XCTAssertThrowsError(try FixtureTimingReplay.review(Data(repeating: 10, count: 262145)))
    var values = try rows(data)
    values.insert(contentsOf: Array(repeating: values[1], count: 176), at: 1)
    XCTAssertThrowsError(try FixtureTimingReplay.review(encode(values)))
    // Fill the entire declared non-closure reservation with newline-inclusive rows.
    var budget = FixtureTimingCollector(schema: 6)
    func pad(_ cap: Int) -> String { String(repeating: "x", count: cap - 3) }
    try budget.append(pad(1280), maximumBytes: 1280)
    for _ in 0..<28 { try budget.append(pad(6144), maximumBytes: 6144) }
    for _ in 0..<128 { try budget.append(pad(512), maximumBytes: 512) }
    for _ in 0..<14 { try budget.append(pad(512), maximumBytes: 512) }
    try budget.append(pad(512), maximumBytes: 512)
    try budget.append(pad(14592), maximumBytes: 14592)
    XCTAssertEqual(budget.bytes.count, 262144 - 1024)
    budget.close(orderly: true, passed: false)
    XCTAssertLessThanOrEqual(budget.bytes.count, 262144)
  }
}
