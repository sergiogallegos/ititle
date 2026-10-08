import Foundation
import ITileCore
import XCTest

@testable import ITilePlatform

final class ProbeReplyTransportTests: XCTestCase {
  private func receipt(
    _ app: AppToken, initialSerial: UInt64 = 0, ack: @escaping @Sendable () -> Void
  ) throws -> ProbeReceipt {
    var state = ReadOnlyReceiptState(app: app, initialSerial: initialSerial)
    let id = try XCTUnwrap(state.admit())
    XCTAssertTrue(state.begin(id))
    return ProbeReceipt(
      id: try XCTUnwrap(state.publish(id)),
      consume: { _ in
        ack()
        return true
      })
  }

  @MainActor
  func testFullTransportUsesOneDrainChainAndRotatesEightReplyBatches() async throws {
    let scheduler = HeldDrains()
    let transport = ProbeReplyTransport(maximumApps: 16, schedule: scheduler.schedule)
    let ack = AckCounter()
    var delivered: [UInt64] = []
    for index in 1...16 {
      let app = AppToken(pid: Int32(index), generation: UInt64(index))
      XCTAssertTrue(transport.attach(app))
      XCTAssertTrue(
        transport.submit(try receipt(app, ack: ack.increment)) {
          delivered.append(app.generation)
        })
    }
    XCTAssertFalse(transport.attach(AppToken(pid: 17, generation: 17)))
    XCTAssertEqual(scheduler.count, 1)
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(delivered, Array(1...8))
    XCTAssertEqual(ack.count, 8)
    XCTAssertEqual(scheduler.count, 1)
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(delivered, Array(1...16))
    XCTAssertEqual(ack.count, 16)
    XCTAssertEqual(scheduler.count, 0)
    transport.stop()
  }

  @MainActor
  func testPublishDuringConsumptionAndAfterDrainFinalizationCannotLoseWakeup() async throws {
    let scheduler = HeldDrains()
    let transport = ProbeReplyTransport(maximumApps: 2, schedule: scheduler.schedule)
    let a = AppToken(pid: 1, generation: 1)
    let b = AppToken(pid: 2, generation: 2)
    XCTAssertTrue(transport.attach(a))
    XCTAssertTrue(transport.attach(b))
    let ack = AckCounter()
    let second = try receipt(b, ack: ack.increment)
    var deliveries = 0
    XCTAssertTrue(
      transport.submit(try receipt(a, ack: ack.increment)) {
        deliveries += 1
        XCTAssertTrue(transport.submit(second) { deliveries += 1 })
        XCTAssertEqual(scheduler.count, 0)
      })
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(deliveries, 2)
    XCTAssertEqual(ack.count, 2)
    XCTAssertEqual(scheduler.count, 0)
    XCTAssertTrue(
      transport.submit(try receipt(a, initialSerial: 1, ack: ack.increment)) { deliveries += 1 })
    XCTAssertEqual(scheduler.count, 1)
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(deliveries, 3)
  }

  @MainActor
  func testDuplicatePublishQuarantinesWithoutOverwritingOrAcknowledgingFirstOwner() async throws {
    let scheduler = HeldDrains()
    let transport = ProbeReplyTransport(maximumApps: 1, schedule: scheduler.schedule)
    let app = AppToken(pid: 1, generation: 1)
    XCTAssertTrue(transport.attach(app))
    let ack = AckCounter()
    let first = try receipt(app, ack: ack.increment)
    var delivered = 0
    XCTAssertTrue(transport.submit(first) { delivered += 1 })
    XCTAssertFalse(transport.submit(first) { XCTFail("Duplicate replaced first") })
    XCTAssertTrue(transport.hasFailed(app))
    XCTAssertEqual(ack.count, 0)
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(delivered, 1)
    XCTAssertEqual(ack.count, 1)
    XCTAssertFalse(transport.submit(first) { XCTFail("Quarantined route reopened") })
  }

  @MainActor
  func testStopAndProcessReplacementRejectOldRouting() async throws {
    let scheduler = HeldDrains()
    let transport = ProbeReplyTransport(maximumApps: 1, schedule: scheduler.schedule)
    let old = AppToken(pid: 1, generation: 1)
    let replacement = AppToken(pid: 1, generation: 2)
    let ack = AckCounter()
    XCTAssertTrue(transport.attach(old))
    let oldReceipt = try receipt(old, ack: ack.increment)
    XCTAssertTrue(transport.submit(oldReceipt) { XCTFail("Retired reply presented") })
    transport.retire(old)
    XCTAssertFalse(transport.attach(old))
    XCTAssertTrue(transport.attach(replacement))
    XCTAssertFalse(transport.submit(oldReceipt) { XCTFail("Old route admitted") })
    let fresh = try receipt(replacement, ack: ack.increment)
    XCTAssertTrue(transport.submit(fresh) { XCTFail("Stopped reply presented") })
    transport.stop()
    try XCTUnwrap(scheduler.take())()
    XCTAssertFalse(transport.attach(AppToken(pid: 2, generation: 3)))
    XCTAssertFalse(transport.submit(fresh) { XCTFail("Stop reopened") })
  }
  @MainActor
  func testOldReceiptAfterConsumptionCannotBePublishedAgain() async throws {
    let scheduler = HeldDrains()
    let transport = ProbeReplyTransport(maximumApps: 1, schedule: scheduler.schedule)
    let app = AppToken(pid: 1, generation: 1)
    XCTAssertTrue(transport.attach(app))
    let ack = AckCounter()
    let old = try receipt(app, ack: ack.increment)
    XCTAssertTrue(transport.submit(old) {})
    try XCTUnwrap(scheduler.take())()
    XCTAssertFalse(transport.submit(old) { XCTFail("Old receipt replayed") })
    XCTAssertTrue(transport.hasFailed(app))
    XCTAssertEqual(scheduler.count, 0)
  }

  @MainActor
  func testConcurrentProducersCoalesceWhileFirstWakeupIsHeldAtBarrier() async throws {
    let scheduler = HeldDrains()
    let scheduling = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let posted = expectation(description: "first producer posted drain")
    let transport = ProbeReplyTransport(
      maximumApps: 2,
      schedule: { work in
        scheduling.signal()
        XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
        scheduler.schedule(work)
      })
    let a = AppToken(pid: 1, generation: 1)
    let b = AppToken(pid: 2, generation: 2)
    XCTAssertTrue(transport.attach(a))
    XCTAssertTrue(transport.attach(b))
    let ack = AckCounter()
    let first = try receipt(a, ack: ack.increment)
    let second = try receipt(b, ack: ack.increment)
    DispatchQueue.global().async {
      XCTAssertTrue(transport.submit(first) {})
      posted.fulfill()
    }
    XCTAssertEqual(scheduling.wait(timeout: .now() + 2), .success)
    XCTAssertTrue(transport.submit(second) {})
    XCTAssertEqual(scheduler.count, 0)
    release.signal()
    await fulfillment(of: [posted], timeout: 2)
    XCTAssertEqual(scheduler.count, 1)
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(ack.count, 2)
    XCTAssertEqual(scheduler.count, 0)
    transport.stop()
  }

}

final class HeldDrains: @unchecked Sendable {
  private let lock = NSLock()
  private var work: [@MainActor @Sendable () -> Void] = []
  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return work.count
  }
  func schedule(_ next: @escaping @MainActor @Sendable () -> Void) {
    lock.lock()
    work.append(next)
    lock.unlock()
  }
  func take() -> (@MainActor @Sendable () -> Void)? {
    lock.lock()
    defer { lock.unlock() }
    return work.isEmpty ? nil : work.removeFirst()
  }
}

private final class AckCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0
  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
  func increment() {
    lock.lock()
    value += 1
    lock.unlock()
  }
}
