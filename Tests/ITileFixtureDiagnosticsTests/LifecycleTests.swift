import Foundation
import ITileFixtureDiagnostics
import XCTest

final class LifecycleTests: XCTestCase {
  private let run = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
  private var context: FixtureUseContext {
    FixtureUseContext(expected: try! FixtureWindowIdentity(run: run, serial: 1))
  }
  private func snapshot(_ after: Bool = false, changes: [String: String] = [:]) throws
    -> FixtureSafetySnapshot
  {
    var fields = Dictionary(uniqueKeysWithValues: FixtureSafetySnapshot.flags.map { ($0, "false") })
    fields.merge([
      "schema": "2", "coverage": "ownedFixtureOnly", "run": run.uuidString,
      "request": after ? "2" : "1", "sequence": after ? "2" : "1",
      "start": after ? "13" : "10", "end": after ? "14" : "11",
      "original": "1", "number": "1", "tabCount": "1", "sheetCount": "0",
      "scenario": "ordinary", "tabSelected": "notApplicable", "tabBar": "notApplicable",
      "active": "true", "visible": "true", "frontmost": "true", "key": "true", "main": "true",
      "stateRevision": "3", "registryRevision": "2", "liveSerials": "1", "originalLive": "true",
      "lifecycleCoverage": "observedEventsOnly", "uncertainty": "none",
    ]) { _, new in new }
    fields.merge(changes) { _, new in new }
    return try FixtureSafetySnapshot(fields: fields)
  }
  private func consume(
    _ reducer: inout FixturePairAssessment, changes: [String: String] = [:],
    context: FixtureUseContext? = nil, now: Double = 14
  ) throws -> FixturePairResult {
    reducer.consume(
      request: 1, before: try snapshot(), focused: self.context.expected,
      axStart: 11, axEnd: 12, after: try snapshot(true, changes: changes),
      context: context ?? self.context, now: now)
  }

  func testRegistryRetirementRecreationAndStableSampling() throws {
    var source = FixtureLifecycleSource()
    XCTAssertEqual(try source.create(), 1)
    source.observe(["visible": "true"])
    let stable = source.stateRevision
    source.observe(["visible": "true"])
    XCTAssertEqual(source.stateRevision, stable)
    let registry = source.registryRevision
    let tab = try source.create()
    // AX omission never participates in the source registry.
    XCTAssertEqual(source.fields["liveSerials"], "1,2")
    source.retire(tab)
    XCTAssertEqual(source.fields["liveSerials"], "1")
    XCTAssertGreaterThan(source.stateRevision, stable)
    XCTAssertGreaterThan(source.registryRevision, registry)
    XCTAssertEqual(try source.create(), 3)
    source.retire(1)
    XCTAssertEqual(source.fields["originalLive"], "false")
    XCTAssertEqual(try source.create(), 4)
    XCTAssertEqual(source.fields["originalLive"], "false")
  }

  func testRegistryLimitAndTerminalExhaustionRetainCleanup() throws {
    var source = FixtureLifecycleSource()
    for _ in 0..<8 { _ = try source.create() }
    XCTAssertThrowsError(try source.create())
    XCTAssertEqual(source.fields["liveSerials"], "unavailable")
    XCTAssertEqual(source.uncertainty, "registryLimit")
    var exhausted = FixtureLifecycleSource(stateRevision: UInt64.max - 1)
    let original = try exhausted.create()
    exhausted.transition()
    XCTAssertEqual(exhausted.uncertainty, "counterExhausted")
    exhausted.retire(original)
    XCTAssertThrowsError(try exhausted.create())
    XCTAssertEqual(exhausted.stateRevision, UInt64.max)
    var serial = FixtureLifecycleSource(issued: UInt64.max)
    XCTAssertThrowsError(try serial.create())
    var registry = FixtureLifecycleSource(registryRevision: UInt64.max)
    XCTAssertThrowsError(try registry.create())
  }

  func testSchemaTwoCanonicalRegistryAndHistoricalCompatibility() throws {
    let sample = try snapshot()
    XCTAssertEqual(try FixtureSafetySnapshot(line: sample.line).liveSerials, [1])
    for raw in ["1,1", "2,1", "01", "0", "1,", "1,2,3,4,5,6,7,8,9"] {
      XCTAssertThrowsError(try snapshot(changes: ["liveSerials": raw]))
    }
    XCTAssertThrowsError(try snapshot(changes: ["lifecycleCoverage": "continuous"]))
    XCTAssertThrowsError(try snapshot(changes: ["stateRevision": "0"]))
  }

  func testHistoricalAcceptanceAndNewIncompleteReplacement() throws {
    var reducer = FixturePairAssessment()
    try reducer.begin(request: 1, context: context)
    XCTAssertEqual(try consume(&reducer), .historicalConsistent)
    try reducer.begin(request: 3, context: context)
    XCTAssertEqual(reducer.current, .incomplete)
    XCTAssertThrowsError(try reducer.begin(request: 2, context: context))
    reducer.invalidate()
    XCTAssertEqual(reducer.current, .contextRevoked)
  }

  func testReversalRevisionAndEqualRevisionChangedFieldsReject() throws {
    for changes in [
      ["stateRevision": "5"], ["registryRevision": "4"], ["number": "2"], ["key": "false"],
    ] {
      var reducer = FixturePairAssessment()
      try reducer.begin(request: 1, context: context)
      XCTAssertEqual(try consume(&reducer, changes: changes), .sourceChanged)
    }
  }

  func testAttributionForRunRequestRetiredAndUnsupported() throws {
    for (changes, expected) in [
      (["run": UUID().uuidString], FixturePairResult.wrongRun),
      (["liveSerials": "none", "originalLive": "false"], .retired),
      (["liveSerials": "unavailable"], .incomplete),
      (["lifecycleCoverage": "unavailable"], .unsupported),
      (["uncertainty": "notificationFailure"], .unsupported),
      (["focusedFault": "true"], .unsupported),
      (["sequence": "1"], .stale),
    ] {
      var reducer = FixturePairAssessment()
      try reducer.begin(request: 1, context: context)
      XCTAssertEqual(try consume(&reducer, changes: changes), expected)
    }
    var reducer = FixturePairAssessment()
    try reducer.begin(request: 2, context: context)
    XCTAssertEqual(try consume(&reducer), .wrongRequest)
    var windowReducer = FixturePairAssessment()
    try windowReducer.begin(request: 1, context: context)
    XCTAssertEqual(
      windowReducer.consume(
        request: 1, before: try snapshot(),
        focused: try FixtureWindowIdentity(run: run, serial: 2), axStart: 11, axEnd: 12,
        after: try snapshot(true), context: context, now: 14), .wrongWindow)
  }

  func testHostPauseResumeTrustAndEnvironmentCannotRevive() throws {
    for action in 0..<4 {
      var host = FixtureHostAuthority(context: context)
      var reducer = FixturePairAssessment()
      try reducer.begin(request: 1, context: host.context)
      switch action {
      case 0:
        host.update(paused: true)
        host.update(paused: false)
      case 1:
        host.update(trusted: false)
        host.update(trusted: true)
      case 2: host.update(environmentChanged: true)
      default: host.update(activationChanged: true)
      }
      XCTAssertEqual(try consume(&reducer, context: host.context), .contextRevoked)
    }
    var c = context
    c.revocation = UInt64.max
    var host = FixtureHostAuthority(context: c)
    host.update(paused: true)
    XCTAssertTrue(host.closed)
    XCTAssertTrue(host.context.stopped)
  }

  func testExpiryEarliestStartExactBoundaryAndNoRevival() throws {
    let policy = try FixtureDiagnosticAgePolicy(revision: 1, maximumAge: 5)
    var reducer = FixturePairAssessment()
    try reducer.begin(request: 1, context: context, policy: policy)
    XCTAssertEqual(try consume(&reducer), .diagnosticUnexpired)
    XCTAssertEqual(reducer.revalidate(context: context, policy: policy, now: 15), .expired)
    XCTAssertEqual(reducer.revalidate(context: context, policy: policy, now: 14), .expired)
    var wrong = FixturePairAssessment()
    try wrong.begin(request: 1, context: context, policy: policy)
    _ = try consume(&wrong)
    XCTAssertEqual(wrong.revalidate(context: context, now: 14), .wrongPolicy)
    XCTAssertEqual(wrong.revalidate(context: context, policy: policy, now: 14), .wrongPolicy)
  }

  func testInvalidTimePolicyAndNonadvancingExpiry() throws {
    for age in [Double.nan, Double.infinity, 0, -1] {
      XCTAssertThrowsError(try FixtureDiagnosticAgePolicy(revision: 1, maximumAge: age))
    }
    XCTAssertThrowsError(try FixtureDiagnosticAgePolicy(revision: 0, maximumAge: 5))
    for now in [Double.nan, 13] {
      var reducer = FixturePairAssessment()
      try reducer.begin(request: 1, context: context)
      XCTAssertEqual(try consume(&reducer, now: now), .malformed)
    }
    var reducer = FixturePairAssessment()
    try reducer.begin(
      request: 1, context: context,
      policy: FixtureDiagnosticAgePolicy(revision: 1, maximumAge: Double.leastNonzeroMagnitude))
    XCTAssertEqual(try consume(&reducer), .malformed)
  }
  func testOverflowClockRegressionIntervalAndStopAreTerminal() throws {
    var reducer = FixturePairAssessment()
    try reducer.begin(
      request: 1, context: context,
      policy: FixtureDiagnosticAgePolicy(revision: 1, maximumAge: 1e308))
    let huge = try snapshot(changes: ["start": "1e308", "end": "1e308"])
    let after = try snapshot(true, changes: ["start": "1e308", "end": "1e308"])
    XCTAssertEqual(
      reducer.consume(
        request: 1, before: huge, focused: context.expected,
        axStart: 1e308, axEnd: 1e308, after: after, context: context, now: 1e308), .malformed)
    var regression = FixturePairAssessment()
    try regression.begin(request: 1, context: context)
    _ = try consume(&regression)
    XCTAssertEqual(regression.revalidate(context: context, now: 13), .malformed)
    var interval = FixturePairAssessment()
    try interval.begin(request: 1, context: context)
    XCTAssertEqual(
      interval.consume(
        request: 1, before: try snapshot(), focused: context.expected,
        axStart: 10, axEnd: 12, after: try snapshot(true), context: context, now: 14), .malformed)
    var host = FixtureHostAuthority(context: context)
    host.update(stopped: true)
    host.update(stopped: false)
    XCTAssertTrue(host.context.stopped)
    XCTAssertTrue(host.closed)
  }

  func testPeerStateAndHistoricalSchemaCannotBePromoted() throws {
    let peer = FixtureUseContext(expected: try FixtureWindowIdentity(run: run, serial: 2))
    var reducer = FixturePairAssessment()
    try reducer.begin(request: 1, context: peer)
    XCTAssertEqual(
      reducer.consume(
        request: 1, before: try snapshot(), focused: peer.expected,
        axStart: 11, axEnd: 12, after: try snapshot(true), context: peer, now: 14), .unsupported)
    func historical(_ after: Bool) throws -> FixtureSafetySnapshot {
      let sample = try snapshot(after)
      var fields = Dictionary(
        uniqueKeysWithValues: FixtureSafetySnapshot.historicalKeys.map {
          ($0, sample.value($0)!)
        })
      fields["schema"] = "1"
      return try FixtureSafetySnapshot(fields: fields)
    }
    var old = FixturePairAssessment()
    try old.begin(request: 1, context: context)
    XCTAssertEqual(
      old.consume(
        request: 1, before: try historical(false), focused: context.expected,
        axStart: 11, axEnd: 12, after: try historical(true), context: context, now: 14),
      .unsupported)
  }

}
