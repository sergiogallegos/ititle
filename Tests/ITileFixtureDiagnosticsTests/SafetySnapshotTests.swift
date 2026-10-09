import Foundation
import ITileFixtureDiagnostics
import XCTest

final class SafetySnapshotTests: XCTestCase {
  private let run = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

  private func fields(request: UInt64 = 1, sequence: UInt64 = 1) -> [String: String] {
    var result = Dictionary(uniqueKeysWithValues: FixtureSafetySnapshot.flags.map { ($0, "false") })
    result.merge([
      "schema": "1", "coverage": "ownedFixtureOnly", "run": run.uuidString,
      "request": String(request), "sequence": String(sequence), "start": "10", "end": "11",
      "original": "1", "number": "unavailable", "tabCount": "unavailable", "sheetCount": "0",
      "scenario": "ordinary", "tabSelected": "notApplicable", "structuralFault": "unavailable",
    ]) { _, new in new }
    return result
  }

  func testRoundTripPreservesUnavailableAndNotApplicable() throws {
    let original = try FixtureSafetySnapshot(fields: fields())
    let parsed = try FixtureSafetySnapshot(line: original.line)
    XCTAssertEqual(parsed.line, original.line)
    XCTAssertEqual(parsed.value("number"), "unavailable")
    XCTAssertEqual(parsed.value("tabSelected"), "notApplicable")
    XCTAssertEqual(parsed.value("structuralFault"), "unavailable")
    XCTAssertNil(parsed.value("eligible"))
  }

  func testStrictSchemaBoundsAndMalformedIntervals() throws {
    for (key, value) in [
      ("schema", "2"), ("coverage", "generic"), ("run", "bad"), ("start", "nan"),
      ("end", "9"), ("request", "0"), ("sequence", "01"), ("tabCount", "65"),
      ("sheetCount", "-1"), ("number", "0"), ("active", "yes"), ("scenario", "arbitrary"),
    ] {
      var invalid = fields()
      invalid[key] = value
      XCTAssertThrowsError(try FixtureSafetySnapshot(fields: invalid), key)
    }
    var missing = fields()
    missing.removeValue(forKey: "modal")
    XCTAssertThrowsError(try FixtureSafetySnapshot(fields: missing))
    var extra = fields()
    extra["eligible"] = "true"
    XCTAssertThrowsError(try FixtureSafetySnapshot(fields: extra))
    let line = try FixtureSafetySnapshot(fields: fields()).line
    XCTAssertThrowsError(
      try FixtureSafetySnapshot(line: line.replacingOccurrences(of: "schema=1", with: "request=1")))
    XCTAssertThrowsError(try FixtureSafetySnapshot(line: line + "\n"))
    XCTAssertThrowsError(try FixtureSafetySnapshot(line: String(repeating: "x", count: 4097)))
  }

  func testConsumerRequiresExactOutstandingRunRequestAndInterval() throws {
    var consumer = FixtureSnapshotConsumer(run: run)
    let valid = try FixtureSafetySnapshot(fields: fields()).line
    XCTAssertThrowsError(try consumer.consume(valid, at: 12))
    try consumer.begin(request: 1, at: 9)
    XCTAssertThrowsError(try consumer.begin(request: 2, at: 9))
    var wrong = fields()
    wrong["run"] = UUID().uuidString
    XCTAssertThrowsError(try consumer.consume(FixtureSafetySnapshot(fields: wrong).line, at: 12))
    wrong = fields(request: 2)
    XCTAssertThrowsError(try consumer.consume(FixtureSafetySnapshot(fields: wrong).line, at: 12))
    XCTAssertThrowsError(try consumer.consume(valid, at: 10))
    XCTAssertThrowsError(try consumer.consume(valid, at: .nan))
    XCTAssertEqual(try consumer.consume(valid, at: 12).request, 1)
    XCTAssertThrowsError(try consumer.consume(valid, at: 12))
    XCTAssertThrowsError(try consumer.begin(request: 1, at: 12))
  }

  func testSequenceWatermarkSurvivesRejectedReplies() throws {
    var consumer = FixtureSnapshotConsumer(run: run)
    try consumer.begin(request: 1, at: 9)
    _ = try consumer.consume(FixtureSafetySnapshot(fields: fields()).line, at: 12)
    try consumer.begin(request: 2, at: 9)
    XCTAssertThrowsError(
      try consumer.consume(FixtureSafetySnapshot(fields: fields(request: 2)).line, at: 12))
    XCTAssertEqual(
      try consumer.consume(
        FixtureSafetySnapshot(fields: fields(request: 2, sequence: 2)).line, at: 12
      ).sequence, 2)
    try consumer.begin(request: 3, at: 12)
    XCTAssertThrowsError(
      try consumer.consume(
        FixtureSafetySnapshot(fields: fields(request: 3, sequence: 3)).line, at: 13))
  }

  func testIssuerRejectsReplayAndClosesAtExhaustion() throws {
    var issuer = FixtureSnapshotIssuer(sequence: UInt64.max - 1)
    XCTAssertEqual(try issuer.issue(request: 1), UInt64.max)
    XCTAssertThrowsError(try issuer.issue(request: 1))
    XCTAssertThrowsError(try issuer.issue(request: 2))
    XCTAssertThrowsError(try issuer.issue(request: 3))
    var normal = FixtureSnapshotIssuer()
    XCTAssertThrowsError(try normal.issue(request: 0))
    XCTAssertEqual(try normal.issue(request: 1), 1)
  }
}
