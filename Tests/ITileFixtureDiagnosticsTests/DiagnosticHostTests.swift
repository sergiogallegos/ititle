import Foundation
import ITileFixtureDiagnostics
import XCTest

final class DiagnosticHostTests: XCTestCase {
  private let run = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
  private var context: FixtureUseContext {
    FixtureUseContext(expected: try! FixtureWindowIdentity(run: run, serial: 1))
  }
  private func snapshot(request: UInt64) throws -> FixtureSafetySnapshot {
    var fields = Dictionary(uniqueKeysWithValues: FixtureSafetySnapshot.flags.map { ($0, "false") })
    fields.merge([
      "schema": "2", "coverage": "ownedFixtureOnly", "run": run.uuidString,
      "request": String(request), "sequence": String(request), "start": String(request + 9),
      "end": String(request + 9), "original": "1", "number": "1", "tabCount": "1",
      "sheetCount": "0",
      "scenario": "ordinary", "active": "true", "visible": "true", "frontmost": "true",
      "tabSelected": "notApplicable", "tabBar": "notApplicable", "stateRevision": "2",
      "registryRevision": "2", "liveSerials": "1", "originalLive": "true",
      "lifecycleCoverage": "observedEventsOnly", "uncertainty": "none",
    ]) { _, new in new }
    return try FixtureSafetySnapshot(fields: fields)
  }
  private func finish(_ host: inout FixtureDiagnosticHost, request: UInt64) throws
    -> FixturePairResult
  {
    host.finish(
      request: request, before: try snapshot(request: request), focused: context.expected,
      axStart: Double(request + 9), axEnd: Double(request + 9),
      after: try snapshot(request: request + 1),
      now: Double(request + 10))
  }

  func testImmediateRevocationKeepsOutstandingWorkUntilExactCompletion() throws {
    var host = FixtureDiagnosticHost(context: context)
    try host.begin(request: 1)
    host.observe(.pause(true))
    XCTAssertEqual(host.current, .contextRevoked)
    XCTAssertEqual(host.pendingRequest, 1)
    host.observe(.pause(false))
    XCTAssertThrowsError(try host.begin(request: 3))
    XCTAssertEqual(try finish(&host, request: 2), .wrongRequest)
    XCTAssertEqual(host.pendingRequest, 1)
    XCTAssertEqual(try finish(&host, request: 1), .contextRevoked)
    XCTAssertNil(host.pendingRequest)
    try host.begin(request: 3)
    XCTAssertEqual(try finish(&host, request: 3), .historicalConsistent)
    XCTAssertEqual(try finish(&host, request: 1), .wrongRequest)
    XCTAssertEqual(host.current, .historicalConsistent)
  }

  func testDeliveredEventKindsInvalidateCurrentAndPending() throws {
    for event: FixtureHostEvent in [.environment, .activation, .trust(false), .pause(true)] {
      var host = FixtureDiagnosticHost(context: context)
      try host.begin(request: 1)
      XCTAssertEqual(try finish(&host, request: 1), .historicalConsistent)
      host.observe(event)
      XCTAssertEqual(host.current, .contextRevoked)
      XCTAssertGreaterThan(host.context.revocation, 0)
    }
    var host = FixtureDiagnosticHost(context: context)
    try host.begin(request: 1)
    host.observe(.trust(false))
    host.observe(.trust(true))
    XCTAssertEqual(host.abandon(request: 1), .contextRevoked)
    try host.begin(request: 3)
    XCTAssertEqual(try finish(&host, request: 3), .historicalConsistent)
  }

  func testExitStopAndReplacementAreTerminalAttachments() throws {
    for event: FixtureHostEvent in [.stop, .processExit, .runReplacement] {
      var host = FixtureDiagnosticHost(context: context)
      try host.begin(request: 1)
      host.observe(event)
      XCTAssertTrue(host.authority.closed)
      XCTAssertEqual(try finish(&host, request: 1), .contextRevoked)
      host.observe(.pause(false))
      host.observe(.trust(true))
      XCTAssertThrowsError(try host.begin(request: 3))
      var fresh = FixtureDiagnosticHost(
        context: FixtureUseContext(
          expected: try FixtureWindowIdentity(run: UUID(), serial: 1)))
      try fresh.begin(request: 1)
      XCTAssertNotEqual(fresh.context.expected.run, host.context.expected.run)
    }
  }

  func testFailedReadReplacesFavorableAndWrongAbandonDoesNotRelease() throws {
    var host = FixtureDiagnosticHost(context: context)
    try host.begin(request: 1)
    _ = try finish(&host, request: 1)
    try host.begin(request: 3)
    XCTAssertEqual(host.current, .incomplete)
    XCTAssertEqual(host.abandon(request: 1), .wrongRequest)
    XCTAssertEqual(host.pendingRequest, 3)
    XCTAssertEqual(host.abandon(request: 3), .incomplete)
    XCTAssertThrowsError(try host.begin(request: 3))
  }

  func testCheckedExhaustionStillReleasesMatchingWork() throws {
    for lane in 0..<3 {
      var c = context
      if lane == 0 { c.revocation = UInt64.max }
      if lane == 1 { c.environment = UInt64.max }
      if lane == 2 { c.activation = UInt64.max }
      var host = FixtureDiagnosticHost(context: c)
      try host.begin(request: 1)
      host.observe(lane == 2 ? .activation : .environment)
      XCTAssertTrue(host.authority.closed)
      XCTAssertEqual(host.current, .contextRevoked)
      XCTAssertEqual(host.abandon(request: 1), .contextRevoked)
      XCTAssertNil(host.pendingRequest)
      XCTAssertThrowsError(try host.begin(request: 3))
    }
  }

  func testRepeatedSampleDoesNotRevokeAndPauseBlocksAdmission() throws {
    var host = FixtureDiagnosticHost(context: context)
    try host.begin(request: 1)
    host.observe(.trust(true))
    host.observe(.pause(false))
    XCTAssertEqual(host.context.revocation, 0)
    XCTAssertEqual(try finish(&host, request: 1), .historicalConsistent)
    host.observe(.pause(true))
    XCTAssertThrowsError(try host.begin(request: 3))
    host.observe(.pause(false))
    try host.begin(request: 3)
    XCTAssertEqual(try finish(&host, request: 3), .historicalConsistent)
  }
}
