import Foundation
import ITileFixtureDiagnostics
import XCTest

final class WindowIdentityTests: XCTestCase {
  func testCanonicalIdentityRejectsMalformedAndNoncanonicalValues() throws {
    let identity = try FixtureWindowIdentity(run: UUID(), serial: 1)
    XCTAssertEqual(try FixtureWindowIdentity(identifier: identity.identifier), identity)
    for invalid in [
      identity.identifier + ":1", "itile-fixture-v2:\(identity.run.uuidString):1",
      "itile-fixture-v1:\(identity.run.uuidString):0",
      "itile-fixture-v1:\(identity.run.uuidString):01", String(repeating: "x", count: 97),
    ] {
      XCTAssertThrowsError(try FixtureWindowIdentity(identifier: invalid))
    }
  }

  func testBindingRejectsWrongRunAndWindowWithoutUsingGeometry() throws {
    let run = UUID()
    var fields = Dictionary(
      uniqueKeysWithValues: FixtureSafetySnapshot.flags.map { ($0, "unavailable") })
    fields.merge([
      "schema": "1", "coverage": "ownedFixtureOnly", "run": run.uuidString,
      "request": "1", "sequence": "1", "start": "1", "end": "2", "original": "1",
      "number": "unavailable", "tabCount": "unavailable", "sheetCount": "unavailable",
      "scenario": "ordinary",
    ]) { _, new in new }
    let snapshot = try FixtureSafetySnapshot(fields: fields)
    XCTAssertTrue(try FixtureWindowIdentity(run: run, serial: 1).matchesOriginal(in: snapshot))
    XCTAssertFalse(try FixtureWindowIdentity(run: UUID(), serial: 1).matchesOriginal(in: snapshot))
    XCTAssertFalse(try FixtureWindowIdentity(run: run, serial: 2).matchesOriginal(in: snapshot))
    XCTAssertEqual(snapshot.value("active"), "unavailable")
    XCTAssertNil(snapshot.value("eligible"))
  }
}
