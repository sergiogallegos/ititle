import Foundation
import ITileFixtureDiagnostics
import XCTest

final class EnvironmentSourceTests: XCTestCase {
  private var context: FixtureUseContext {
    FixtureUseContext(
      expected: try! FixtureWindowIdentity(
        run: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, serial: 1))
  }

  private func manifest(context: FixtureUseContext? = nil, os: String = "Synthetic Test OS")
    -> FixtureTimingManifest
  {
    FixtureTimingManifest(
      os: os, utc: "2026-10-21T00:00:00Z",
      labHash: String(repeating: "a", count: 64), fixtureHash: String(repeating: "b", count: 64),
      initialContext: context ?? self.context, runStart: 1, collectionDeadline: 181,
      controlledSetupFailure: true, setupFault: .normalizationAckDelayOnce,
      eventSources: .environmentCallbacks)
  }

  /// Synthetic control only; no retained native artifact is promoted to schema 5.
  private func dataset(activation: Bool = false, orderly: Bool = true) throws -> Data {
    var collector = FixtureTimingCollector(schema: 5)
    try collector.append(manifest(), maximumBytes: 1280)
    var host = FixtureDiagnosticHost(context: context)
    if activation {
      host.observe(.activation)
      try collector.event(
        FixtureTimingEvent(
          code: "activation", time: 3.9, revocation: host.context.revocation, pending: nil,
          context: host.context, direction: .deactivate, relation: .unrelated))
    }
    for (offset, source) in FixtureEnvironmentSource.allCases.enumerated() {
      host.observe(.environment)
      try collector.event(
        FixtureTimingEvent(
          code: source.eventCode, time: 4 + Double(offset), revocation: host.context.revocation,
          pending: nil, context: host.context, source: source))
    }
    var setup = FixtureSetupRecord(
      sequence: 1, nextIndex: 1, cohort: .ordinary, purpose: .cohort, at: 3,
      issued: 1, correlated: 1, revocation: 0, pairOccupied: false, readerOccupied: false)
    try setup.enter(.setupPrecondition, at: 3)
    try setup.complete(at: 3)
    try setup.enter(.normalizationWrite, at: 3.1)
    try setup.complete(at: 3.2)
    try setup.enter(.normalizationAck, at: 3.3)
    setup.revocationAfter = host.context.revocation
    try setup.finish(at: 8.41, failure: .responseDeadline)
    try collector.setup(setup)
    var fault = FixtureSetupFaultRecord()
    try fault.submit(at: 2)
    try fault.observe("setup-ack-delay-armed 2.1", at: 2.2)
    try fault.normalizationWrite(at: 3.1)
    try fault.beginWait(at: 3.3)
    try fault.observe("setup-ack-delay-deferred 3.4 9.4", at: 3.5)
    try fault.finish(at: 8.4, category: .responseDeadline, running: true)
    try collector.setupFault(fault)
    try collector.append(FixtureTimingSummary(records: []), maximumBytes: 14592)
    collector.latchStop(
      FixtureFirstStop(
        stage: .normalizationAck, category: .responseDeadline, at: 8.4,
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

  func testEverySourcePreservesHostInvalidationAndPendingWorkRejection() throws {
    for source in FixtureEnvironmentSource.allCases {
      var host = FixtureDiagnosticHost(context: context)
      try host.begin(request: 1)
      let event = FixtureTimingEvent(
        code: source.eventCode, time: 4, revocation: 1, pending: 1, source: source)
      XCTAssertTrue(event.hasValidMetadata(for: 5))
      XCTAssertEqual(event.hostEvent, .environment)
      host.observe(event.hostEvent!)
      XCTAssertEqual(host.context.environment, 1)
      XCTAssertEqual(host.context.revocation, 1)
      XCTAssertEqual(host.context.activation, 0)
      XCTAssertEqual(host.pendingRequest, 1)
      XCTAssertThrowsError(try host.begin(request: 2))
      XCTAssertEqual(host.abandon(request: 1), .contextRevoked)
      XCTAssertNil(host.pendingRequest)
    }
  }

  func testSyntheticSchemaFiveReplaysAllSourcesAndKeepsTimeoutAndControlFlags() throws {
    for activation in [false, true] {
      for orderly in [false, true] {
        let data = try dataset(activation: activation, orderly: orderly)
        let report = try FixtureTimingReplay.review(data)
        XCTAssertEqual(report.attempts, 0)
        XCTAssertEqual(report.assessed, 0)
        XCTAssertEqual(report.setups, 1)
        XCTAssertEqual(report.firstStop, .responseDeadline)
        XCTAssertEqual(report.summaryPresent, true)
        XCTAssertFalse(report.complete)
        XCTAssertFalse(report.calibrationSuitable)
        let values = try rows(data)
        XCTAssertEqual(values[0]["schema"] as? Int, 5)
        XCTAssertEqual(values[0]["eventSources"] as? String, "environmentCallbacks")
        XCTAssertEqual(values.last?["schema"] as? Int, 5)
        XCTAssertEqual(
          values.filter { $0["kind"] as? String == "event" }.compactMap { $0["source"] as? String },
          FixtureEnvironmentSource.allCases.map(\.rawValue))
      }
    }
  }

  func testAbsentUnknownMismatchedAndForbiddenSourcesCannotReplay() throws {
    let original = try rows(dataset(activation: true))
    let environment = original.firstIndex { $0["source"] as? String == "screenParameters" }!
    let space = original.firstIndex { $0["source"] as? String == "nativeSpace" }!
    let activation = original.firstIndex { $0["code"] as? String == "activation" }!
    for (index, source) in [
      (environment, nil), (environment, "unknown"), (environment, "nativeSpace"),
      (space, "willSleep"), (activation, "screenParameters"),
    ] as [(Int, String?)] {
      var copy = original
      copy[index]["source"] = source
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)))
    }
    for code in [
      "pause", "resume", "sampledTrustLost", "sampledTrustRestored", "sampledExit",
      "ownedTermination",
    ] {
      let event = FixtureTimingEvent(
        code: code, time: 4, revocation: 1, pending: nil, source: .willSleep)
      XCTAssertFalse(event.hasValidMetadata(for: 5))
    }
    var null = original
    null[environment]["source"] = NSNull()
    XCTAssertThrowsError(try FixtureTimingReplay.review(encode(null)))
    for key in ["direction", "relation"] {
      var copy = original
      copy[environment][key] = key == "direction" ? "activate" : "owned"
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)))
      copy = original
      copy[activation].removeValue(forKey: key)
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)))
    }
  }

  func testContractAndEnvelopeVersionsMustMatchWithoutChangingHistoricalVocabulary() throws {
    let original = try rows(dataset())
    for source in [nil, "unknown"] as [String?] {
      var copy = original
      copy[0]["eventSources"] = source
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)))
    }
    for schema in [2, 3, 4, 6] {
      var copy = original
      copy[0]["schema"] = schema
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)))
      copy = original
      copy[copy.count - 1]["schema"] = schema
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)))
    }
    var copy = original
    copy[0]["setupFault"] = nil
    XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)))
    for (kind, key, value) in [
      ("terminal", "complete", true), ("terminal", "calibrationSuitable", true),
      ("terminal", "attempts", 1), ("terminal", "occupied", true),
      ("stop", "pairs", 1),
    ] as [(String, String, Any)] {
      copy = original
      let index = copy.firstIndex { $0["kind"] as? String == kind }!
      copy[index][key] = value
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)))
    }
  }

  func testHistoricalArchivesReplayAndCannotAcquireEnvironmentSourceMetadata() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    for name in [
      "m2-35-timing-first", "m2-35-exclusion-first", "m2-35-timing-final", "m2-35-exclusion-final",
      "m2-37-timing", "m2-37-exclusion", "m2-37-setup-exit", "m2-41-ack-delay",
    ] {
      let data = try Data(contentsOf: root.appendingPathComponent("docs/evidence/\(name).jsonl"))
      let baseline = try FixtureTimingReplay.review(data)
      XCTAssertEqual(
        baseline.attempts,
        name == "m2-37-setup-exit" || name == "m2-41-ack-delay"
          ? 0 : name == "m2-35-exclusion-final" ? 15 : 28)
      var values = try rows(data)
      for index in values.indices where values[index]["kind"] as? String == "event" {
        XCTAssertNil(values[index]["source"])
      }
      if let index = values.firstIndex(where: { $0["kind"] as? String == "event" }) {
        values[index]["source"] = "screenParameters"
        XCTAssertThrowsError(try FixtureTimingReplay.review(encode(values)), name)
      }
      values = try rows(data)
      values[0]["eventSources"] = "environmentCallbacks"
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(values)), name)
    }
  }

  func testClockAndContextTamperingRejectsBeforeHistoricalNormalization() throws {
    let original = try rows(dataset())
    let events = original.indices.filter { original[$0]["kind"] as? String == "event" }
    for time in [-1.0, 0.9, 3.0, 9.0] {
      var copy = original
      copy[events[1]]["time"] = time
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)))
    }
    // A post-stop callback cannot enter the export even if a forged setup
    // revision were adjusted to hide its late occurrence.
    var late = original
    late[events.last!]["time"] = 9.0
    let setup = late.firstIndex { $0["kind"] as? String == "setup" }!
    late[setup]["revAfter"] = 3
    XCTAssertThrowsError(try FixtureTimingReplay.review(encode(late)))
    for key in ["revocation", "pending"] {
      var copy = original
      copy[events[0]][key] = 99
      XCTAssertThrowsError(try FixtureTimingReplay.review(encode(copy)))
    }
    for time in [Double.nan, .infinity, -.infinity, -1] {
      var collector = FixtureTimingCollector(schema: 5)
      XCTAssertThrowsError(
        try collector.event(
          FixtureTimingEvent(
            code: "environment", time: time, revocation: 1, pending: nil, source: .willSleep)))
      XCTAssertEqual(collector.firstStop?.category, .clockFailure)
    }
    var collector = FixtureTimingCollector(schema: 5)
    try collector.event(
      FixtureTimingEvent(
        code: "environment", time: 4, revocation: 1, pending: nil, source: .willSleep))
    XCTAssertThrowsError(
      try collector.event(
        FixtureTimingEvent(
          code: "environment", time: 3, revocation: 2, pending: nil, source: .didWake)))
    XCTAssertEqual(collector.firstStop?.category, .clockFailure)
  }

  func testCollectorRejectsInvalidSourcesAndCannotReviveOrReplaceFirstStop() throws {
    for schema in 2...5 {
      var collector = FixtureTimingCollector(schema: schema)
      let event = FixtureTimingEvent(
        code: "environment", time: 4, revocation: 1, pending: nil,
        source: schema == 5 ? nil : .willSleep)
      XCTAssertThrowsError(try collector.event(event))
      if schema >= 3 { XCTAssertEqual(collector.firstStop?.category, .protocolFailure) }
    }
    var collector = FixtureTimingCollector(schema: 5)
    collector.latchStop(
      FixtureFirstStop(
        stage: .normalizationAck, category: .responseDeadline, at: 8.4, pairs: 0,
        pairOccupied: false, readerOccupied: false))
    XCTAssertThrowsError(
      try collector.event(
        FixtureTimingEvent(
          code: "environment", time: 9, revocation: 1, pending: nil, source: .didWake)))
    XCTAssertThrowsError(try collector.begin(.ordinary))
    collector.close(orderly: false, passed: true)
    XCTAssertEqual(collector.firstStop?.category, .responseDeadline)
    XCTAssertEqual(collector.admissions, 0)
    XCTAssertNil(collector.occupied)
    let bytes = collector.bytes
    XCTAssertThrowsError(
      try collector.event(
        FixtureTimingEvent(
          code: "nativeSpace", time: 10, revocation: 2, pending: nil, source: .nativeSpace)))
    XCTAssertEqual(collector.bytes, bytes)
    var noStop = FixtureTimingCollector(schema: 5)
    noStop.close(orderly: true, passed: true)
    XCTAssertFalse(try rows(noStop.bytes).last?["complete"] as! Bool)
  }

  func testMaximalSourceEventsManifestAndTotalFitExistingReserves() throws {
    var wide = context
    wide.environment = UInt64.max
    wide.activation = UInt64.max
    wide.revocation = UInt64.max
    for source in FixtureEnvironmentSource.allCases {
      let event = FixtureTimingEvent(
        code: source.eventCode, time: Double.greatestFiniteMagnitude, revocation: .max,
        pending: .max, context: wide, source: source)
      XCTAssertTrue(event.hasValidMetadata(for: 5))
      XCTAssertLessThanOrEqual(try JSONEncoder().encode(event).count + 1, 512)
      var upper =
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as! [String: Any]
      upper["time"] = String(repeating: "9", count: 32)
      XCTAssertLessThanOrEqual(try JSONSerialization.data(withJSONObject: upper).count + 1, 512)
    }
    let maximal = manifest(context: wide, os: String(repeating: "V", count: 128))
    XCTAssertTrue(maximal.valid)
    var upper =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(maximal)) as! [String: Any]
    upper["runStart"] = String(repeating: "9", count: 32)
    upper["collectionDeadline"] = String(repeating: "9", count: 32)
    XCTAssertLessThanOrEqual(try JSONSerialization.data(withJSONObject: upper).count + 1, 1280)
    XCTAssertEqual(FixtureDiagnosticBudget.reservedBytes(schema: 5), 262144)
    XCTAssertEqual(FixtureDiagnosticBudget.summaryBytes(schema: 5), 14592)
    for row in try rows(dataset(activation: true)) {
      let kind = row["kind"] as! String
      let cap = kind == "manifest" ? 1280 : kind == "summary" ? 14592 : 512
      XCTAssertLessThanOrEqual(try JSONSerialization.data(withJSONObject: row).count + 1, cap)
    }
    XCTAssertThrowsError(try FixtureTimingReplay.review(Data(repeating: 10, count: 262145)))
    var values = try rows(dataset())
    let event = values.first { $0["kind"] as? String == "event" }!
    values.insert(contentsOf: Array(repeating: event, count: 176), at: 1)
    XCTAssertThrowsError(try FixtureTimingReplay.review(encode(values)))
  }
}
