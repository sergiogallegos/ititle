import XCTest

@testable import ITileCore

final class ReadOnlyReceiptTests: XCTestCase {
  private let app = AppToken(pid: 1, generation: 1)

  func testReadRemainsOccupiedUntilExactAcknowledgment() throws {
    var state = ReadOnlyReceiptState(app: app)
    let id = try XCTUnwrap(state.admit())
    XCTAssertTrue(state.begin(id))
    let receipt = try XCTUnwrap(state.publish(id))
    for _ in 0..<1_000 { XCTAssertNil(state.admit()) }
    XCTAssertFalse(state.acknowledge(ReadReceiptID(operation: id, reply: 2)))
    XCTAssertEqual(state.phase, .awaitingAcknowledgment(receipt))
    XCTAssertTrue(state.acknowledge(receipt))
    XCTAssertFalse(state.acknowledge(receipt))
    let next = try XCTUnwrap(state.admit())
    XCTAssertGreaterThan(next.serial, id.serial)
    XCTAssertFalse(state.acknowledge(receipt))
    XCTAssertFalse(state.begin(id))
    XCTAssertTrue(state.isCancelled(id))
  }

  func testInvalidationDoesNotReleaseReadAndFreshAdmissionClearsCancellation() throws {
    var state = ReadOnlyReceiptState(app: app)
    let id = try XCTUnwrap(state.admit())
    state.invalidate()
    XCTAssertTrue(state.begin(id))
    XCTAssertTrue(state.isCancelled(id))
    let receipt = try XCTUnwrap(state.publish(id))
    XCTAssertNil(state.admit())
    XCTAssertTrue(state.acknowledge(receipt))
    let fresh = try XCTUnwrap(state.admit())
    XCTAssertFalse(state.isCancelled(fresh))
  }

  func testStopIsTerminalFromEveryOccupiedPhase() throws {
    for stage in 0...3 {
      var state = ReadOnlyReceiptState(app: app)
      let id = try XCTUnwrap(state.admit())
      if stage >= 1 { XCTAssertTrue(state.begin(id)) }
      let receipt = stage >= 2 ? try XCTUnwrap(state.publish(id)) : nil
      if stage == 3 { XCTAssertTrue(state.acknowledge(try XCTUnwrap(receipt))) }
      state.stop()
      XCTAssertNil(state.admit())
      XCTAssertFalse(state.begin(id))
      XCTAssertNil(state.publish(id))
      if let receipt { XCTAssertFalse(state.acknowledge(receipt)) }
      XCTAssertTrue(state.isCancelled(id))
    }
  }

  func testReplacedProcessAndExhaustedSerialCannotReuseIdentity() throws {
    var old = ReadOnlyReceiptState(app: app)
    let id = try XCTUnwrap(old.admit())
    XCTAssertTrue(old.begin(id))
    let receipt = try XCTUnwrap(old.publish(id))
    var replacement = ReadOnlyReceiptState(app: AppToken(pid: app.pid, generation: 2))
    let newer = try XCTUnwrap(replacement.admit())
    XCTAssertFalse(replacement.begin(id))
    XCTAssertFalse(replacement.acknowledge(receipt))
    XCTAssertTrue(replacement.begin(newer))
    var exhausted = ReadOnlyReceiptState(app: app, initialSerial: UInt64.max)
    XCTAssertNil(exhausted.admit())
    XCTAssertEqual(exhausted.phase, .stopped)
  }
}
