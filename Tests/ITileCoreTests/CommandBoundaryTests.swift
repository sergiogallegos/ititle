import XCTest

@testable import ITileCore

final class CommandBoundaryTests: XCTestCase {
  private let app = AppToken(pid: 1, generation: 1)
  private let other = AppToken(pid: 2, generation: 2)
  private let frame = Rect(x: 0, y: 0, width: 100, height: 100)
  private var token: WindowToken { WindowToken(app: app, serial: 1) }

  private func ready(capacity: Int = 128) -> CommandBoundary {
    var boundary = CommandBoundary(capacity: capacity)
    XCTAssertTrue(boundary.attach(app))
    XCTAssertTrue(boundary.attach(other))
    boundary.setTrust(true)
    XCTAssertEqual(boundary.enqueue(.enable), .accepted(1))
    XCTAssertEqual(boundary.drain(), [.revalidationRequired(1)])
    XCTAssertTrue(boundary.paused)
    return boundary
  }

  func testOverloadPreservesEveryAcceptedSemanticIntentInOrder() {
    var boundary = ready()
    var commands: [SemanticCommand] = []
    for index in 0..<128 {
      let command: SemanticCommand
      switch index % 4 {
      case 0: command = .resize(token, 0.05)
      case 1: command = .focus(token)
      case 2: command = .toggleFloating(token)
      default: command = .swap(token, WindowToken(app: other, serial: 1))
      }
      commands.append(command)
      XCTAssertEqual(boundary.enqueue(command), .accepted(UInt64(index + 2)))
    }
    XCTAssertEqual(boundary.enqueue(.resize(token, -0.05)), .rejected(.capacity))
    XCTAssertEqual(boundary.queuedCount, 128)
    var observed: [SemanticCommand] = []
    while boundary.queuedCount > 0 {
      let batch = boundary.drain()
      XCTAssertLessThanOrEqual(batch.count, 8)
      for result in batch {
        guard case .ready(let ticket) = result else { return XCTFail("Unexpected disposition") }
        observed.append(ticket.command)
      }
    }
    XCTAssertEqual(observed, commands)
    XCTAssertEqual(boundary.enqueue(.focus(token)), .accepted(130))
  }

  func testDisableBypassesFullQueueAndRetainsOrderedRejections() {
    var boundary = ready()
    for _ in 0..<128 { _ = boundary.enqueue(.toggleFloating(token)) }
    boundary.revoke(.disable)
    XCTAssertFalse(boundary.enabled)
    XCTAssertEqual(boundary.enqueue(.focus(token)), .rejected(.disabled))
    var ids: [UInt64] = []
    while boundary.queuedCount > 0 {
      for result in boundary.drain() {
        guard case .rejected(let id, .stale) = result else {
          return XCTFail("Stale intent replayed")
        }
        ids.append(id)
      }
    }
    XCTAssertEqual(ids, Array(2...129))
  }

  func testOlderEnableAndResumeCannotReopenNewerRevocation() {
    var boundary = CommandBoundary()
    boundary.setTrust(true)
    XCTAssertEqual(boundary.enqueue(.enable), .accepted(1))
    boundary.revoke(.disable)
    XCTAssertEqual(boundary.drain(), [.rejected(1, .stale)])
    XCTAssertFalse(boundary.enabled)
    XCTAssertEqual(boundary.enqueue(.enable), .accepted(2))
    XCTAssertEqual(boundary.drain(), [.revalidationRequired(2)])
    XCTAssertTrue(boundary.enabled)
    XCTAssertTrue(boundary.paused)
    XCTAssertEqual(boundary.enqueue(.resume), .accepted(3))
    boundary.revoke(.pause)
    XCTAssertEqual(boundary.drain(), [.rejected(3, .stale)])
    XCTAssertTrue(boundary.paused)
  }

  func testApplicationRevocationRejectsOnlyItsTicketsAndUnknownRoutingClosesGlobally() {
    var boundary = ready()
    let second = WindowToken(app: other, serial: 1)
    _ = boundary.enqueue(.tile([token: frame]))
    _ = boundary.enqueue(.tile([second: frame]))
    boundary.revoke(.appUncertain(app))
    let batch = boundary.drain()
    XCTAssertEqual(batch.first, .rejected(2, .stale))
    guard case .ready(let healthy) = batch.last else { return XCTFail("Healthy app was blocked") }
    XCTAssertTrue(boundary.activate(healthy))
    boundary.revoke(.appUncertain(AppToken(pid: 99, generation: 99)))
    XCTAssertFalse(boundary.activate(healthy))
    XCTAssertTrue(boundary.paused)
  }

  func testPermissionRecoveryAndQuitNeverReplayOldCommands() {
    var boundary = ready()
    _ = boundary.enqueue(.tile([token: frame]))
    boundary.setTrust(false)
    XCTAssertEqual(boundary.enqueue(.focus(token)), .rejected(.permission))
    boundary.setTrust(true)
    XCTAssertEqual(boundary.drain(), [.rejected(2, .stale)])
    XCTAssertTrue(boundary.paused)
    _ = boundary.enqueue(.enable)
    boundary.revoke(.quit)
    boundary.setTrust(true)
    XCTAssertEqual(boundary.drain(), [.rejected(3, .stopped)])
    XCTAssertEqual(boundary.enqueue(.enable), .rejected(.stopped))
  }

  func testMalformedPayloadsAndAttachmentBoundsDoNotGrowQueue() {
    var boundary = ready()
    XCTAssertEqual(boundary.enqueue(.tile([:])), .rejected(.malformed))
    XCTAssertEqual(boundary.enqueue(.resize(token, .nan)), .rejected(.malformed))
    XCTAssertEqual(boundary.enqueue(.swap(token, token)), .rejected(.malformed))
    var large: [WindowToken: Rect] = [:]
    for serial in 1...257 { large[WindowToken(app: app, serial: UInt64(serial))] = frame }
    XCTAssertEqual(boundary.enqueue(.tile(large)), .rejected(.malformed))
    XCTAssertEqual(boundary.queuedCount, 0)
    for index in 3...16 {
      XCTAssertTrue(boundary.attach(AppToken(pid: Int32(index), generation: UInt64(index))))
    }
    XCTAssertFalse(boundary.attach(AppToken(pid: 17, generation: 17)))
    boundary.retire(app)
    XCTAssertFalse(boundary.attach(app))
    XCTAssertTrue(boundary.attach(AppToken(pid: app.pid, generation: 17)))
    XCTAssertEqual(boundary.enqueue(.focus(token)), .rejected(.stale))
  }

  func testGenerationExhaustionStopsInsteadOfWrapping() {
    var boundary = CommandBoundary(initialGeneration: UInt64.max)
    boundary.revoke(.pause)
    XCTAssertTrue(boundary.stopped)
    XCTAssertEqual(boundary.generation, UInt64.max)
    XCTAssertEqual(boundary.enqueue(.enable), .rejected(.stopped))
  }
}
