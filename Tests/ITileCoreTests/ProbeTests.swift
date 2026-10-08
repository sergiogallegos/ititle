import XCTest

@testable import ITileCore

final class ProbeTests: XCTestCase {
  func testIdentitySurvivesReorderingAndMetadataChanges() {
    var registry = ProbeRegistry(app: AppToken(pid: 42, generation: 1))
    let first = registry.reconcile([10, 20])
    XCTAssertEqual(registry.reconcile([20, 10]), [first[1], first[0]])
    // Titles are intentionally absent from the registry's identity interface.
    XCTAssertEqual(registry.reconcile([10, 20]), first)
  }

  func testRemovedIdentityCannotRecoverOldToken() {
    var registry = ProbeRegistry(app: AppToken(pid: 42, generation: 1))
    let first = registry.reconcile([10, 20])
    XCTAssertEqual(registry.reconcile([20]), [first[1]])
    let reopened = registry.reconcile([10, 20])
    XCTAssertNotEqual(reopened[0], first[0])
    XCTAssertEqual(reopened[1], first[1])
  }

  func testDestructionUncertaintyInvalidatesAllTokens() {
    var registry = ProbeRegistry(app: AppToken(pid: 42, generation: 1))
    let first = registry.reconcile([10])
    registry.invalidate()
    XCTAssertNotEqual(first, registry.reconcile([10]))
  }

  func testUnsupportedElementDoesNotExpireObservableSiblings() {
    var registry = ProbeRegistry(app: AppToken(pid: 42, generation: 1))
    let first = registry.reconcile([10, 20, 30])
    for _ in 0..<3 {
      let previous = registry.reconcile([10, 20, 30])
      registry.invalidate([30])
      let next = registry.reconcile([30, 20, 10])
      XCTAssertNotEqual(next[0], previous[2])
      XCTAssertEqual(next[1], first[1])
      XCTAssertEqual(next[2], first[0])
    }
  }

  func testReusedPIDHasDifferentTokens() {
    var first = ProbeRegistry(app: AppToken(pid: 42, generation: 1))
    var restarted = ProbeRegistry(app: AppToken(pid: 42, generation: 2))
    XCTAssertNotEqual(first.reconcile([10]), restarted.reconcile([10]))
  }

  func testEmptySnapshotRetiresAllTokens() {
    var registry = ProbeRegistry(app: AppToken(pid: 42, generation: 1))
    let first = registry.reconcile([10])
    XCTAssertEqual(registry.reconcile([]), [])
    XCTAssertNotEqual(first, registry.reconcile([10]))
  }

  func testCoordinateRoundTripsAcrossDisplayOrigins() {
    for rect in [
      Rect(x: 0, y: 0, width: 1440, height: 900),
      Rect(x: -1920, y: 1200, width: 1920, height: 1080),
      Rect(x: 200, y: -1000, width: 800.5, height: 600.5),
    ] {
      let flipped = DesktopCoordinates.flip(rect, primaryTop: 900)
      XCTAssertEqual(flipped.x, rect.x)
      XCTAssertEqual(DesktopCoordinates.flip(flipped, primaryTop: 900), rect)
    }
    XCTAssertEqual(
      DesktopCoordinates.flip(Rect(x: -100, y: 1000, width: 100, height: 100), primaryTop: 900).y,
      -200)
  }
  func testRegistrySnapshotPreservesWatermarkAcrossCompleteAndSelectiveExpiry() {
    let app = AppToken(pid: 42, generation: 1)
    var registry = ProbeRegistry(app: app)
    let tokens = registry.reconcile([10, 20])
    registry.invalidate([10])
    let partial = registry.snapshot(environmentEpoch: 3, revision: 1)
    XCTAssertEqual(partial.windows, [tokens[1]])
    XCTAssertEqual(partial.highestSerial, 2)
    registry.invalidate()
    let empty = registry.snapshot(environmentEpoch: 4, revision: 2)
    XCTAssertTrue(empty.windows.isEmpty)
    XCTAssertEqual(empty.highestSerial, 2)
    let replacement = registry.reconcile([10])[0]
    XCTAssertEqual(replacement.serial, 3)
    XCTAssertEqual(registry.snapshot(environmentEpoch: 4, revision: 3).windows, [replacement])
  }

}
