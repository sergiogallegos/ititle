import Foundation
import XCTest
import ITileCore
@testable import ITilePlatform

/// Exercises the production thread/mailbox/run-loop using a worker-owned fake IPC adapter.
final class WindowProbeTests: XCTestCase {
    func testBlockedAppDoesNotBlockOtherAppAndMailboxStaysBounded() {
        let entered = expectation(description: "slow read entered")
        let retired = expectation(description: "slow worker retired")
        let healthyRetired = expectation(description: "healthy worker retired")
        let healthyResult = expectation(description: "healthy app responds while slow app blocked")
        let release = DispatchSemaphore(value: 0)
        let slow = WindowProbe(token: AppToken(pid: 1, generation: 1), makeBackend: {
            FakeBackend(read: { _, _ in
                entered.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
                return "late"
            }, finish: { retired.fulfill() })
        })
        let healthy = WindowProbe(token: AppToken(pid: 2, generation: 2), makeBackend: {
            FakeBackend(read: { _, _ in "healthy" }, finish: { healthyRetired.fulfill() })
        })
        defer { release.signal(); slow.stop(); healthy.stop() }
        XCTAssertTrue(slow.inspect(environmentEpoch: 0) { _ in XCTFail("Stopped worker delivered a late result") })
        wait(for: [entered], timeout: 2)
        for _ in 0..<1_000 {
            XCTAssertFalse(slow.inspect(environmentEpoch: 1) { _ in XCTFail("Overflow request admitted") })
        }
        XCTAssertTrue(healthy.inspect(environmentEpoch: 0) { report in
            XCTAssertEqual(report, "healthy")
            healthyResult.fulfill()
        })
        wait(for: [healthyResult], timeout: 2)
        // stop must return while the simulated IPC remains blocked.
        slow.stop()
        XCTAssertFalse(slow.inspect(environmentEpoch: 2) { _ in XCTFail("Stopped worker accepted work") })
        release.signal()
        healthy.stop()
        wait(for: [retired, healthyRetired], timeout: 2)
    }

    func testBackendLifetimeStaysOnOneDedicatedNonMainThread() {
        let completed = expectation(description: "read finished")
        let retired = expectation(description: "thread ownership checked at teardown")
        let probe = WindowProbe(token: AppToken(pid: 3, generation: 1), makeBackend: {
            FakeBackend(read: { epoch, _ in
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
        let probe = WindowProbe(token: AppToken(pid: 4, generation: 1), makeBackend: {
            let backend = FakeBackend(read: { epoch, _ in "epoch-\(epoch)" }, finish: { retired.fulfill() })
            initialized.fulfill()
            return backend
        })
        defer { probe.stop() }
        wait(for: [initialized], timeout: 2)
        XCTAssertTrue(probe.inspect(environmentEpoch: 1) { report in
            XCTAssertEqual(report, "epoch-1"); first.fulfill()
        })
        wait(for: [first], timeout: 2)
        XCTAssertTrue(probe.inspect(environmentEpoch: 2) { report in
            XCTAssertEqual(report, "epoch-2"); second.fulfill()
        })
        wait(for: [second], timeout: 2)
        probe.stop()
        wait(for: [retired], timeout: 2)
    }

    func testStopDuringReadIsVisibleToBackendAndDoesNotDeliver() {
        let entered = expectation(description: "read started")
        let retired = expectation(description: "cancelled worker retired")
        let release = DispatchSemaphore(value: 0)
        let probe = WindowProbe(token: AppToken(pid: 5, generation: 1), makeBackend: {
            FakeBackend(read: { _, cancelled in
                XCTAssertFalse(cancelled())
                entered.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
                XCTAssertTrue(cancelled())
                return "discard"
            }, finish: { retired.fulfill() })
        })
        defer { release.signal(); probe.stop() }
        XCTAssertTrue(probe.inspect(environmentEpoch: 0) { _ in XCTFail("Cancelled result escaped") })
        wait(for: [entered], timeout: 2)
        probe.stop()
        release.signal()
        wait(for: [retired], timeout: 2)
    }
}

private final class FakeBackend: ProbeBackend {
    private let owner = Thread.current
    private let read: (UInt64, () -> Bool) -> String
    private let finish: () -> Void

    init(read: @escaping (UInt64, () -> Bool) -> String, finish: @escaping () -> Void) {
        XCTAssertFalse(Thread.isMainThread)
        self.read = read
        self.finish = finish
    }

    func inspect(epoch: UInt64, cancelled: () -> Bool) -> String {
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertTrue(Thread.current === owner)
        return read(epoch, cancelled)
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
