import XCTest

@testable import ITileCore

final class PlanCursorTests: XCTestCase {
  private let app = AppToken(pid: 1, generation: 1)
  private func token(_ serial: UInt64) -> WindowToken { WindowToken(app: app, serial: serial) }

  func testCursorSortsAndAdvancesOnlyItsExactNextWindow() throws {
    var cursor = try XCTUnwrap(
      PlanCursor(
        app: app, commandSerial: 2, layoutRevision: 1,
        windows: [token(3), token(1), token(2)]))
    XCTAssertEqual(cursor.next, token(1))
    XCTAssertEqual(cursor.remainingCount, 3)
    XCTAssertFalse(cursor.advance(completed: token(2)))
    XCTAssertEqual(cursor.remainingCount, 3)
    XCTAssertTrue(cursor.advance(completed: token(1)))
    XCTAssertFalse(cursor.advance(completed: token(1)))
    XCTAssertTrue(cursor.advance(completed: token(2)))
    XCTAssertTrue(cursor.advance(completed: token(3)))
    XCTAssertNil(cursor.next)
    XCTAssertEqual(cursor.remainingCount, 0)
    XCTAssertFalse(cursor.advance(completed: token(3)))
  }

  func testCursorBoundsAndMalformedIdentityFailWithoutPartialConstruction() {
    for windows in [
      [], [token(0)], [token(1), token(1)],
      (1...65).map { token(UInt64($0)) },
      [WindowToken(app: AppToken(pid: 2, generation: 2), serial: 1)],
    ] {
      XCTAssertNil(PlanCursor(app: app, commandSerial: 2, layoutRevision: 1, windows: windows))
    }
    XCTAssertNil(PlanCursor(app: app, commandSerial: 0, layoutRevision: 1, windows: [token(1)]))
    XCTAssertNil(PlanCursor(app: app, commandSerial: 2, layoutRevision: 0, windows: [token(1)]))
    XCTAssertEqual(
      PlanCursor(
        app: app, commandSerial: 2, layoutRevision: 1,
        windows: (1...64).map { token(UInt64($0)) })?.remainingCount, 64)
  }

  func testPerAppExecutionStampIsolationDoesNotPermitPartialCommandReduction() throws {
    let other = AppToken(pid: 2, generation: 2)
    let peer = WindowToken(app: other, serial: 1)
    var boundary = CommandBoundary()
    XCTAssertTrue(boundary.attach(app))
    XCTAssertTrue(boundary.attach(other))
    boundary.setTrust(true)
    _ = boundary.enqueue(.enable)
    _ = boundary.drain()
    let frame = Rect(x: 0, y: 0, width: 100, height: 100)
    _ = boundary.enqueue(.tile([token(1): frame, peer: frame]))
    guard case .ready(let ticket) = boundary.drain().first else { return XCTFail("No ticket") }
    boundary.revoke(.appUncertain(app))
    XCTAssertFalse(boundary.accepts(ticket.stamp))
    XCTAssertFalse(boundary.accepts(ticket.stamp, for: app))
    XCTAssertTrue(boundary.accepts(ticket.stamp, for: other))
    XCTAssertTrue(boundary.activate(ticket, for: other))
    XCTAssertFalse(boundary.activate(ticket))
    boundary.revoke(.pause)
    XCTAssertFalse(boundary.accepts(ticket.stamp, for: other))
  }
}
