import Foundation
import ITileCore
import XCTest

@testable import ITilePlatform

/// Exercises the production thread/mailbox/run-loop using a worker-owned fake IPC adapter.
final class WindowProbeTests: XCTestCase {
  func testSnapshotExhaustionDiscardsReadAndCannotReadmitAfterAcknowledgment() {
    for focused in [false, true] {
      let completed = expectation(description: "exhausted reply acknowledged")
      let retired = expectation(description: "exhausted worker exits")
      let probe = WindowProbe(
        token: AppToken(pid: 1, generation: 1),
        makeBackend: {
          FakeBackend(
            read: { _, _ in "must be discarded" }, finish: { retired.fulfill() },
            exhaustOnSnapshot: true)
        })
      if focused {
        XCTAssertTrue(
          probe.inspectFocusedAcknowledged(environmentEpoch: 0) { result, registry, receipt in
            guard case .failure(.counterExhausted) = result else {
              return XCTFail("Exhaustion lost")
            }
            XCTAssertNil(registry)
            XCTAssertTrue(receipt.acknowledge())
            completed.fulfill()
          })
      } else {
        XCTAssertTrue(
          probe.inspectAcknowledged(environmentEpoch: 0) { report, registry, receipt in
            XCTAssertEqual(report, "Lifecycle counter exhausted; inspection stopped.")
            XCTAssertNil(registry)
            XCTAssertTrue(receipt.acknowledge())
            completed.fulfill()
          })
      }
      wait(for: [completed], timeout: 2)
      XCTAssertFalse(
        probe.inspect(environmentEpoch: 1) { _ in XCTFail("Exhausted worker restarted") })
      probe.stop()
      wait(for: [retired], timeout: 2)
    }
  }

  func testBlockedAppDoesNotBlockOtherAppAndMailboxStaysBounded() {
    let entered = expectation(description: "slow read entered")
    let retired = expectation(description: "slow worker retired")
    let healthyRetired = expectation(description: "healthy worker retired")
    let healthyResult = expectation(description: "healthy app responds while slow app blocked")
    let release = DispatchSemaphore(value: 0)
    let slow = WindowProbe(
      token: AppToken(pid: 1, generation: 1),
      makeBackend: {
        FakeBackend(
          read: { _, _ in
            entered.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            return "late"
          }, finish: { retired.fulfill() })
      })
    let healthy = WindowProbe(
      token: AppToken(pid: 2, generation: 2),
      makeBackend: {
        FakeBackend(read: { _, _ in "healthy" }, finish: { healthyRetired.fulfill() })
      })
    defer {
      release.signal()
      slow.stop()
      healthy.stop()
    }
    XCTAssertTrue(
      slow.inspect(environmentEpoch: 0) { _ in XCTFail("Stopped worker delivered a late result") })
    wait(for: [entered], timeout: 2)
    for _ in 0..<1_000 {
      XCTAssertFalse(
        slow.inspect(environmentEpoch: 1) { _ in XCTFail("Overflow request admitted") })
    }
    XCTAssertTrue(
      healthy.inspect(environmentEpoch: 0) { report in
        XCTAssertEqual(report, "healthy")
        healthyResult.fulfill()
      })
    wait(for: [healthyResult], timeout: 2)
    // stop must return while the simulated IPC remains blocked.
    slow.stop()
    XCTAssertFalse(
      slow.inspect(environmentEpoch: 2) { _ in XCTFail("Stopped worker accepted work") })
    release.signal()
    healthy.stop()
    wait(for: [retired, healthyRetired], timeout: 2)
  }

  func testBackendLifetimeStaysOnOneDedicatedNonMainThread() {
    let completed = expectation(description: "read finished")
    let retired = expectation(description: "thread ownership checked at teardown")
    let probe = WindowProbe(
      token: AppToken(pid: 3, generation: 1),
      makeBackend: {
        FakeBackend(
          read: { epoch, _ in
            XCTAssertEqual(epoch, 17)
            return "ok"
          }, finish: { retired.fulfill() })
      })
    defer { probe.stop() }
    XCTAssertTrue(probe.inspect(environmentEpoch: 17) { _ in completed.fulfill() })
    wait(for: [completed], timeout: 2)
    probe.stop()
    wait(for: [retired], timeout: 2)
  }

  func testIdleWorkerWakesAndCanBeReusedWithNewEpoch() {
    let initialized = expectation(description: "backend initialized")
    let first = expectation(description: "first request")
    let second = expectation(description: "second request")
    let retired = expectation(description: "idle worker stopped")
    let probe = WindowProbe(
      token: AppToken(pid: 4, generation: 1),
      makeBackend: {
        let backend = FakeBackend(
          read: { epoch, _ in "epoch-\(epoch)" }, finish: { retired.fulfill() })
        initialized.fulfill()
        return backend
      })
    defer { probe.stop() }
    wait(for: [initialized], timeout: 2)
    XCTAssertTrue(
      probe.inspectAcknowledged(environmentEpoch: 1) { report, _, receipt in
        XCTAssertEqual(report, "epoch-1")
        XCTAssertTrue(receipt.acknowledge())
        first.fulfill()
      })
    wait(for: [first], timeout: 2)
    XCTAssertTrue(
      probe.inspect(environmentEpoch: 2) { report in
        XCTAssertEqual(report, "epoch-2")
        second.fulfill()
      })
    wait(for: [second], timeout: 2)
    probe.stop()
    wait(for: [retired], timeout: 2)
  }

  func testStopDuringReadIsVisibleToBackendAndDoesNotDeliver() {
    let entered = expectation(description: "read started")
    let retired = expectation(description: "cancelled worker retired")
    let release = DispatchSemaphore(value: 0)
    let probe = WindowProbe(
      token: AppToken(pid: 5, generation: 1),
      makeBackend: {
        FakeBackend(
          read: { _, cancelled in
            XCTAssertFalse(cancelled())
            entered.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            XCTAssertTrue(cancelled())
            return "discard"
          }, finish: { retired.fulfill() })
      })
    defer {
      release.signal()
      probe.stop()
    }
    XCTAssertTrue(probe.inspect(environmentEpoch: 0) { _ in XCTFail("Cancelled result escaped") })
    wait(for: [entered], timeout: 2)
    probe.stop()
    release.signal()
    wait(for: [retired], timeout: 2)
  }
  func testFocusedFailureCarriesRegistryInTheSameWorkerOwnedDelivery() {
    let completed = expectation(description: "failure and retirement snapshot delivered")
    let retired = expectation(description: "worker stopped")
    let app = AppToken(pid: 6, generation: 1)
    let expected = ProbeRegistrySnapshot(
      app: app, environmentEpoch: 3, revision: 2, highestSerial: 1, windows: [])
    let probe = WindowProbe(
      token: app,
      makeBackend: {
        FakeBackend(
          read: { _, _ in "unused" }, finish: { retired.fulfill() },
          snapshot: { epoch in
            XCTAssertEqual(epoch, 3)
            return expected
          })
      })
    defer { probe.stop() }
    XCTAssertTrue(
      probe.inspectFocusedWithRegistry(environmentEpoch: 3) { result, registry in
        if case .failure(.cancelled) = result {} else { XCTFail("Unexpected focused result") }
        XCTAssertEqual(registry, expected)
        completed.fulfill()
      })
    wait(for: [completed], timeout: 2)
    probe.stop()
    wait(for: [retired], timeout: 2)
  }

  func testBackendCompletionStaysBusyUntilOwnerAcknowledgesExactReceipt() throws {
    let delivered = expectation(description: "backend finished, owner held")
    let second = expectation(description: "next request after acknowledgment")
    let retired = expectation(description: "acknowledged worker retired")
    let held = HeldReceipt()
    let probe = WindowProbe(
      token: AppToken(pid: 7, generation: 1),
      makeBackend: {
        FakeBackend(read: { _, _ in "bounded" }, finish: { retired.fulfill() })
      })
    defer { probe.stop() }
    XCTAssertTrue(
      probe.inspectAcknowledged(environmentEpoch: 0) { report, _, receipt in
        XCTAssertEqual(report, "bounded")
        held.set(receipt)
        delivered.fulfill()
      })
    wait(for: [delivered], timeout: 2)
    for _ in 0..<1_000 {
      XCTAssertFalse(
        probe.inspect(environmentEpoch: 0) { _ in XCTFail("Read admitted before owner") })
    }
    let receipt = try XCTUnwrap(held.get())
    XCTAssertTrue(receipt.acknowledge())
    XCTAssertFalse(receipt.acknowledge())
    XCTAssertTrue(
      probe.inspectAcknowledged(environmentEpoch: 1) { _, _, newer in
        XCTAssertFalse(receipt.acknowledge())
        XCTAssertGreaterThan(newer.id.operation.serial, receipt.id.operation.serial)
        XCTAssertTrue(newer.acknowledge())
        second.fulfill()
      })
    wait(for: [second], timeout: 2)
    probe.stop()
    wait(for: [retired], timeout: 2)
  }

  func testStopWhileOwnerHoldsReplyCannotBeUndoneByLateAcknowledgment() throws {
    let delivered = expectation(description: "reply held")
    let retired = expectation(description: "held worker stopped")
    let held = HeldReceipt()
    let probe = WindowProbe(
      token: AppToken(pid: 8, generation: 1),
      makeBackend: {
        FakeBackend(read: { _, _ in "late" }, finish: { retired.fulfill() })
      })
    XCTAssertTrue(
      probe.inspectAcknowledged(environmentEpoch: 0) { _, _, receipt in
        held.set(receipt)
        delivered.fulfill()
      })
    wait(for: [delivered], timeout: 2)
    probe.stop()
    XCTAssertFalse(try XCTUnwrap(held.get()).acknowledge())
    XCTAssertFalse(probe.inspect(environmentEpoch: 1) { _ in XCTFail("Stop reopened") })
    wait(for: [retired], timeout: 2)
  }

  func testInvalidationDuringBlockedBackendRequiresAckThenAllowsFreshRead() {
    let entered = expectation(description: "backend blocked")
    let cancelled = expectation(description: "invalidated result returned")
    let retired = expectation(description: "invalidated worker stopped")
    let release = DispatchSemaphore(value: 0)
    let probe = WindowProbe(
      token: AppToken(pid: 9, generation: 1),
      makeBackend: {
        FakeBackend(
          read: { _, isCancelled in
            entered.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            XCTAssertTrue(isCancelled())
            return "discardable"
          }, finish: { retired.fulfill() })
      })
    defer {
      release.signal()
      probe.stop()
    }
    XCTAssertTrue(
      probe.inspectAcknowledged(environmentEpoch: 0) { _, registry, receipt in
        XCTAssertNil(registry)
        XCTAssertTrue(receipt.acknowledge())
        cancelled.fulfill()
      })
    wait(for: [entered], timeout: 2)
    probe.invalidateRead()
    XCTAssertFalse(probe.inspect(environmentEpoch: 1) { _ in XCTFail("Invalidation freed slot") })
    release.signal()
    wait(for: [cancelled], timeout: 2)
    probe.stop()
    wait(for: [retired], timeout: 2)
  }

  func testRetainedReportTextIsCappedAtUtf8BoundaryWithVisibleMarker() {
    let delivered = expectation(description: "oversize report bounded")
    let retired = expectation(description: "bounded report worker stopped")
    let probe = WindowProbe(
      token: AppToken(pid: 10, generation: 1),
      makeBackend: {
        FakeBackend(
          read: { _, _ in String(repeating: "é", count: 70_000) }, finish: { retired.fulfill() })
      })
    defer { probe.stop() }
    XCTAssertTrue(
      probe.inspectAcknowledged(environmentEpoch: 0) { report, _, receipt in
        XCTAssertLessThanOrEqual(report.utf8.count, 65_536)
        XCTAssertTrue(report.hasSuffix("Diagnostic text truncated."))
        XCTAssertTrue(receipt.acknowledge())
        delivered.fulfill()
      })
    wait(for: [delivered], timeout: 2)
    probe.stop()
    wait(for: [retired], timeout: 2)
  }

  @MainActor
  func testActualWorkerRemainsBusyThroughoutSharedOwnerConsumption() async throws {
    let delivered = expectation(description: "worker reply routed to held drain")
    let retired = expectation(description: "shared transport worker retired")
    let scheduler = HeldDrains()
    let transport = ProbeReplyTransport(maximumApps: 1, schedule: scheduler.schedule)
    let app = AppToken(pid: 11, generation: 1)
    XCTAssertTrue(transport.attach(app))
    let probe = WindowProbe(
      token: app,
      makeBackend: {
        FakeBackend(read: { _, _ in "owner" }, finish: { retired.fulfill() })
      })
    defer {
      probe.stop()
      transport.stop()
    }
    let consumed = ConsumptionFlag()
    XCTAssertTrue(
      probe.inspectAcknowledged(environmentEpoch: 0) { report, _, receipt in
        XCTAssertTrue(
          transport.submit(receipt) {
            XCTAssertEqual(report, "owner")
            XCTAssertFalse(
              probe.inspect(environmentEpoch: 1) { _ in XCTFail("Owner slot freed early") })
            consumed.value = true
          })
        delivered.fulfill()
      })
    await fulfillment(of: [delivered], timeout: 2)
    XCTAssertFalse(consumed.value)
    for _ in 0..<1_000 {
      XCTAssertFalse(
        probe.inspect(environmentEpoch: 1) { _ in XCTFail("Held reply admitted read") })
    }
    try XCTUnwrap(scheduler.take())()
    XCTAssertTrue(consumed.value)
    probe.stop()
    transport.stop()
    await fulfillment(of: [retired], timeout: 2)
  }

  func testMalformedRegistryIsExcludedWithoutTruncatedIdentityClaims() {
    let delivered = expectation(description: "bad registry rejected")
    let retired = expectation(description: "bad registry worker stopped")
    let app = AppToken(pid: 12, generation: 1)
    var registry = ProbeRegistry(app: app)
    _ = registry.reconcile(Array(1...65))
    let oversized = registry.snapshot(environmentEpoch: 0, revision: 1)
    let probe = WindowProbe(
      token: app,
      makeBackend: {
        FakeBackend(
          read: { _, _ in "untrusted" }, finish: { retired.fulfill() }, snapshot: { _ in oversized }
        )
      })
    defer { probe.stop() }
    XCTAssertTrue(
      probe.inspectAcknowledged(environmentEpoch: 0) { report, registry, receipt in
        XCTAssertEqual(report, "Invalid registry replacement; inspection excluded.")
        XCTAssertNil(registry)
        XCTAssertTrue(receipt.acknowledge())
        delivered.fulfill()
      })
    wait(for: [delivered], timeout: 2)
    probe.stop()
    wait(for: [retired], timeout: 2)
  }

  func testInvalidatedQueuedReadPublishesCanceledReceiptWithoutBackendEntry() {
    let initializing = expectation(description: "worker creation held")
    let delivered = expectation(description: "queued cancellation acknowledged")
    let retired = expectation(description: "queued cancellation worker retired")
    let release = DispatchSemaphore(value: 0)
    let probe = WindowProbe(
      token: AppToken(pid: 13, generation: 1),
      makeBackend: {
        initializing.fulfill()
        XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
        return FakeBackend(
          read: { _, _ in
            XCTFail("Canceled queued request entered backend")
            return "bad"
          },
          finish: { retired.fulfill() })
      })
    defer {
      release.signal()
      probe.stop()
    }
    wait(for: [initializing], timeout: 2)
    XCTAssertTrue(
      probe.inspectAcknowledged(environmentEpoch: 0) { report, registry, receipt in
        XCTAssertEqual(report, "Inspection cancelled. No windows inspected.")
        XCTAssertNil(registry)
        XCTAssertTrue(receipt.acknowledge())
        delivered.fulfill()
      })
    probe.invalidateRead()
    release.signal()
    wait(for: [delivered], timeout: 2)
    probe.stop()
    wait(for: [retired], timeout: 2)
  }

}

private final class FakeBackend: ProbeBackend {
  private(set) var countersExhausted = false
  private let exhaustOnSnapshot: Bool
  private let owner = Thread.current
  private let read: (UInt64, () -> Bool) -> String
  private let finish: () -> Void
  private let snapshot: (UInt64) -> ProbeRegistrySnapshot?

  init(
    read: @escaping (UInt64, () -> Bool) -> String, finish: @escaping () -> Void,
    snapshot: @escaping (UInt64) -> ProbeRegistrySnapshot? = { _ in nil },
    exhaustOnSnapshot: Bool = false
  ) {
    XCTAssertFalse(Thread.isMainThread)
    self.read = read
    self.finish = finish
    self.snapshot = snapshot
    self.exhaustOnSnapshot = exhaustOnSnapshot
  }

  func inspect(epoch: UInt64, cancelled: () -> Bool) -> String {
    XCTAssertFalse(Thread.isMainThread)
    XCTAssertTrue(Thread.current === owner)
    return read(epoch, cancelled)
  }

  func inspectFocused(epoch: UInt64, expected: WindowToken?, cancelled: () -> Bool)
    -> FocusedProbeResult
  {
    XCTAssertTrue(Thread.current === owner)
    return .failure(.cancelled)
  }

  func registrySnapshot(epoch: UInt64) -> ProbeRegistrySnapshot? {
    XCTAssertFalse(Thread.isMainThread)
    XCTAssertTrue(Thread.current === owner)
    countersExhausted = exhaustOnSnapshot
    return snapshot(epoch)
  }

  func invalidateIdentity() {
    XCTAssertTrue(Thread.current === owner)
  }

  func tearDown() {
    XCTAssertFalse(Thread.isMainThread)
    XCTAssertTrue(Thread.current === owner)
    finish()
  }
}

private final class HeldReceipt: @unchecked Sendable {
  private let lock = NSLock()
  private var value: ProbeReceipt?
  func set(_ receipt: ProbeReceipt) {
    lock.lock()
    value = receipt
    lock.unlock()
  }
  func get() -> ProbeReceipt? {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

@MainActor
private final class ConsumptionFlag { var value = false }
