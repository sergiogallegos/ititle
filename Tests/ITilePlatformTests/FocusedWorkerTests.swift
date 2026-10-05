import Foundation
import ITileCore
import XCTest

@testable import ITilePlatform

final class FocusedWorkerTests: XCTestCase {
  func testFocusedReadSharesBoundedMailboxAndStopSuppressesLateResult() {
    let entered = expectation(description: "focused read entered")
    let retired = expectation(description: "focused worker retired")
    let release = DispatchSemaphore(value: 0)
    let probe = WindowProbe(
      token: AppToken(pid: 1, generation: 1),
      makeBackend: {
        FocusBackend(
          read: { epoch, expected, cancelled in
            XCTAssertEqual(epoch, 12)
            XCTAssertNil(expected)
            XCTAssertFalse(cancelled())
            entered.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            XCTAssertTrue(cancelled())
            return .failure(.cancelled)
          }, finish: { retired.fulfill() })
      })
    defer {
      release.signal()
      probe.stop()
    }
    XCTAssertTrue(
      probe.inspectFocused(environmentEpoch: 12) { _ in XCTFail("Stopped result delivered") })
    wait(for: [entered], timeout: 2)
    for _ in 0..<100 {
      XCTAssertFalse(probe.inspect(environmentEpoch: 13) { _ in XCTFail("Extra report queued") })
      XCTAssertFalse(
        probe.inspectFocused(environmentEpoch: 13) { _ in XCTFail("Extra focus read queued") })
    }
    probe.stop()
    release.signal()
    wait(for: [retired], timeout: 2)
  }

  func testStructuredFocusedResultAndExpectedTokenStayOnSameWorker() {
    let completed = expectation(description: "structured result delivered")
    let retired = expectation(description: "worker retired")
    var registry = ProbeRegistry(app: AppToken(pid: 42, generation: 1))
    let expected = registry.reconcile([1])[0]
    let probe = WindowProbe(
      token: expected.app,
      makeBackend: {
        FocusBackend(
          read: { epoch, token, _ in
            XCTAssertEqual(epoch, 7)
            XCTAssertEqual(token, expected)
            return .failure(.identityChanged)
          }, finish: { retired.fulfill() })
      })
    defer { probe.stop() }
    XCTAssertTrue(
      probe.inspectFocused(environmentEpoch: 7, expected: expected) { result in
        guard case .failure(.identityChanged) = result else { return XCTFail("Typed failure lost") }
        completed.fulfill()
      })
    wait(for: [completed], timeout: 2)
    probe.stop()
    wait(for: [retired], timeout: 2)
  }
}

private final class FocusBackend: ProbeBackend {
  private let owner = Thread.current
  private let read: (UInt64, WindowToken?, () -> Bool) -> FocusedProbeResult
  private let finish: () -> Void

  init(
    read: @escaping (UInt64, WindowToken?, () -> Bool) -> FocusedProbeResult,
    finish: @escaping () -> Void
  ) {
    XCTAssertFalse(Thread.isMainThread)
    self.read = read
    self.finish = finish
  }
  func inspect(epoch: UInt64, cancelled: () -> Bool) -> String {
    XCTFail("Wrong request kind dispatched")
    return "unexpected"
  }
  func inspectFocused(epoch: UInt64, expected: WindowToken?, cancelled: () -> Bool)
    -> FocusedProbeResult
  {
    XCTAssertFalse(Thread.isMainThread)
    XCTAssertTrue(Thread.current === owner)
    return read(epoch, expected, cancelled)
  }
  func invalidateIdentity() { XCTAssertTrue(Thread.current === owner) }
  func tearDown() {
    XCTAssertTrue(Thread.current === owner)
    finish()
  }
}
