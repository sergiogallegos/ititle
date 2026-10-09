import Foundation
import XCTest

@testable import ITileCore
@testable import ITilePlatform

@MainActor
final class SimulatedWorkerRuntimeTests: XCTestCase {
  private let a = AppToken(pid: 1, generation: 1)
  private let b = AppToken(pid: 2, generation: 2)
  private let original = Rect(x: 10, y: 10, width: 600, height: 400)
  private let destination = Rect(x: 0, y: 30, width: 800, height: 600)
  private func token(_ app: AppToken) -> WindowToken { WindowToken(app: app, serial: 1) }
  private func sample(_ app: AppToken) -> WindowObservation {
    WindowObservation(
      token: token(app), frame: original, eligibility: .eligible,
      positionSettable: .supported, sizeSettable: .supported,
      environmentEpoch: 0, workerSequence: 1, sampledAt: 1)
  }
  private func setup(_ runtime: SimulatedWorkerRuntime) {
    // Explicit bootstrap before worker execution, without relying on Task ordering.
    runtime.owner.trust(true, at: 0)
    _ = runtime.owner.gate.enqueue(.enable)
    _ = runtime.owner.drain(at: 0)
  }

  func testSuccessfulSequenceRequiresObservedReadbackAndRunsOffMainThread() async throws {
    let completed = expectation(description: "Readback terminal consumed")
    let exited = expectation(description: "Worker exited")
    var terminals: [SimulatedTerminalReceipt] = []
    let runtime = SimulatedWorkerRuntime(
      time: { 1 },
      schedule: { work in
        Task { @MainActor in work() }
      },
      terminal: {
        terminals.append($0)
        completed.fulfill()
      }, exited: { _ in exited.fulfill() })
    let backend = FakeSequenceBackend()
    XCTAssertTrue(runtime.attach(a, backend: backend, at: 0))
    setup(runtime)
    XCTAssertEqual(runtime.owner.observe(sample(a), at: 1), [])
    XCTAssertEqual(runtime.enqueue(.tile([token(a): destination])), .accepted(2))
    await fulfillment(of: [completed], timeout: 5)
    XCTAssertEqual(terminals.map(\.reason), [.completed])
    XCTAssertEqual(backend.calls, ["size", "position", "readback"])
    XCTAssertFalse(backend.usedMainThread)
    XCTAssertEqual(runtime.owner.model.observations[token(a)]?.frame, destination)
    XCTAssertEqual(runtime.owner.model.observations[token(a)]?.workerSequence, 2)
    XCTAssertFalse(runtime.owner.model.dirty.contains(token(a)))
    XCTAssertEqual(runtime.owner.model.inFlightCount, 0)
    XCTAssertEqual(runtime.owner.gate.operationCount, 0)
    XCTAssertEqual(runtime.retainedReplies, 0)
    runtime.revoke(.quit, at: 1)
    await fulfillment(of: [exited], timeout: 5)
  }

  func testStalledAppDoesNotBlockPeerReadbackOrQuitAndLateCallCannotContinue() async throws {
    let entered = expectation(description: "Stalled size admitted")
    let healthyDone = expectation(description: "Healthy peer completed readback")
    let stalledDone = expectation(description: "Late stalled operation cleaned up")
    let exited = expectation(description: "Both threads exited")
    exited.expectedFulfillmentCount = 2
    let release = DispatchSemaphore(value: 0)
    let stalled = FakeSequenceBackend(beforeSize: {
      entered.fulfill()
      XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
    })
    let healthy = FakeSequenceBackend()
    let runtime = SimulatedWorkerRuntime(
      time: { 1 },
      schedule: { work in
        Task { @MainActor in work() }
      },
      terminal: { receipt in
        if receipt.operation.app.pid == 1 {
          XCTAssertEqual(receipt.reason, .revoked)
          stalledDone.fulfill()
        } else {
          XCTAssertEqual(receipt.reason, .completed)
          healthyDone.fulfill()
        }
      }, exited: { _ in exited.fulfill() })
    XCTAssertTrue(runtime.attach(a, backend: stalled, at: 0))
    XCTAssertTrue(runtime.attach(b, backend: healthy, at: 0))
    setup(runtime)
    XCTAssertEqual(runtime.owner.observe(sample(a), at: 1), [])
    XCTAssertEqual(runtime.owner.observe(sample(b), at: 1), [])
    _ = runtime.enqueue(.tile([token(a): destination, token(b): destination]))
    await fulfillment(of: [entered, healthyDone], timeout: 5)
    XCTAssertEqual(runtime.owner.model.inFlightCount, 1)
    XCTAssertEqual(runtime.owner.model.observations[token(b)]?.frame, destination)
    runtime.revoke(.quit, at: .nan)
    XCTAssertEqual(runtime.enqueue(.enable), .rejected(.stopped))
    XCTAssertEqual(runtime.owner.gate.operationCount, 1)
    release.signal()
    await fulfillment(of: [stalledDone, exited], timeout: 5)
    XCTAssertEqual(stalled.calls, ["size"])
    XCTAssertEqual(runtime.owner.model.inFlightCount, 0)
    XCTAssertEqual(runtime.owner.gate.operationCount, 0)
    XCTAssertEqual(runtime.owner.model.state, .stopping)
    XCTAssertEqual(runtime.owner.model.observations[token(a)]?.frame, original)
  }

  func testPauseWhileReadbackIsBlockedDiscardsItsLateObservation() async throws {
    let entered = expectation(description: "Readback started")
    let done = expectation(description: "Revoked readback cleaned up")
    let exited = expectation(description: "Worker exited")
    let release = DispatchSemaphore(value: 0)
    let backend = FakeSequenceBackend(beforeReadback: {
      entered.fulfill()
      XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
    })
    let runtime = SimulatedWorkerRuntime(
      time: { 1 },
      schedule: { work in
        Task { @MainActor in work() }
      },
      terminal: { receipt in
        XCTAssertEqual(receipt.reason, .revoked)
        done.fulfill()
      },
      exited: { _ in exited.fulfill() })
    XCTAssertTrue(runtime.attach(a, backend: backend, at: 0))
    setup(runtime)
    _ = runtime.owner.observe(sample(a), at: 1)
    _ = runtime.enqueue(.tile([token(a): destination]))
    await fulfillment(of: [entered], timeout: 5)
    runtime.revoke(.pause, at: 1)
    release.signal()
    await fulfillment(of: [done], timeout: 5)
    XCTAssertEqual(runtime.owner.model.observations[token(a)]?.frame, original)
    XCTAssertTrue(runtime.owner.model.dirty.contains(token(a)))
    XCTAssertEqual(runtime.owner.model.inFlightCount, 0)
    XCTAssertEqual(runtime.owner.gate.operationCount, 0)
    XCTAssertEqual(backend.calls, ["size", "position", "readback"])
    runtime.revoke(.quit, at: 1)
    await fulfillment(of: [exited], timeout: 5)
  }

  func testMismatchedUnknownOrMissingReadbackNeverEstablishesDesiredGeometry() async throws {
    for value in [
      FakeSequenceBackend.Readback.mismatch, .missing, .unknown, .oldSequence, .oldTime,
    ] {
      let done = expectation(description: "Rejected readback terminal")
      let exited = expectation(description: "Worker exited")
      let runtime = SimulatedWorkerRuntime(
        time: { 1 },
        schedule: { work in
          Task { @MainActor in work() }
        },
        terminal: { receipt in
          XCTAssertEqual(receipt.reason, .revoked)
          done.fulfill()
        },
        exited: { _ in exited.fulfill() })
      let backend = FakeSequenceBackend(readback: value)
      XCTAssertTrue(runtime.attach(a, backend: backend, at: 0))
      setup(runtime)
      _ = runtime.owner.observe(sample(a), at: 1)
      _ = runtime.enqueue(.tile([token(a): destination]))
      await fulfillment(of: [done], timeout: 5)
      XCTAssertEqual(runtime.owner.model.observations[token(a)]?.frame, original)
      XCTAssertTrue(runtime.owner.model.dirty.contains(token(a)))
      XCTAssertEqual(runtime.owner.model.inFlightCount, 0)
      XCTAssertEqual(runtime.owner.gate.operationCount, 0)
      XCTAssertEqual(backend.calls, ["size", "position", "readback"])
      runtime.revoke(.quit, at: 1)
      await fulfillment(of: [exited], timeout: 5)
    }
  }

  func testPhysicalWorkerCapIncludesBlockedRetiredThread() async throws {
    let entered = expectation(description: "Retiring backend blocked")
    let done = expectation(description: "Retired completion consumed")
    let exited = expectation(description: "All original workers exited")
    exited.expectedFulfillmentCount = 16
    let replacementExit = expectation(description: "Replacement exited")
    let release = DispatchSemaphore(value: 0)
    let backend = FakeSequenceBackend(beforeSize: {
      entered.fulfill()
      XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
    })
    let runtime = SimulatedWorkerRuntime(
      time: { 1 },
      schedule: { work in
        Task { @MainActor in work() }
      }, terminal: { _ in done.fulfill() },
      exited: { app in
        if app.generation <= 16 { exited.fulfill() } else { replacementExit.fulfill() }
      })
    XCTAssertTrue(runtime.attach(a, backend: backend, at: 0))
    for index in 2...16 {
      XCTAssertTrue(
        runtime.attach(
          AppToken(pid: Int32(index), generation: UInt64(index)),
          backend: FakeSequenceBackend(), at: 0))
    }
    setup(runtime)
    _ = runtime.owner.observe(sample(a), at: 1)
    _ = runtime.enqueue(.tile([token(a): destination]))
    await fulfillment(of: [entered], timeout: 5)
    runtime.retire(a, at: 1)
    let replacement = AppToken(pid: a.pid, generation: 17)
    XCTAssertEqual(runtime.physicalWorkerCount, 16)
    XCTAssertFalse(runtime.attach(replacement, backend: FakeSequenceBackend(), at: 1))
    release.signal()
    await fulfillment(of: [done], timeout: 5)
    // Stop peers and await all actual exits, then confirmed replacement can attach.
    for index in 2...16 {
      runtime.retire(AppToken(pid: Int32(index), generation: UInt64(index)), at: 1)
    }
    await fulfillment(of: [exited], timeout: 5)
    XCTAssertTrue(runtime.attach(replacement, backend: FakeSequenceBackend(), at: 1))
    runtime.revoke(.quit, at: 1)
    await fulfillment(of: [replacementExit], timeout: 5)
  }
}

private final class FakeSequenceBackend: SimulatedWorkerBackend, @unchecked Sendable {
  enum Readback: Sendable { case matching, mismatch, missing, unknown, oldSequence, oldTime }
  private let lock = NSLock()
  private var recorded: [String] = []
  private var main = false
  private let value: Readback
  private let beforeSize: @Sendable () -> Void
  private let beforeReadback: @Sendable () -> Void
  init(
    readback: Readback = .matching, beforeSize: @escaping @Sendable () -> Void = {},
    beforeReadback: @escaping @Sendable () -> Void = {}
  ) {
    value = readback
    self.beforeSize = beforeSize
    self.beforeReadback = beforeReadback
  }
  var calls: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }
  var usedMainThread: Bool {
    lock.lock()
    defer { lock.unlock() }
    return main
  }
  private func record(_ name: String) {
    lock.lock()
    recorded.append(name)
    main = main || Thread.isMainThread
    lock.unlock()
  }
  func set(_ target: FrameTarget, setter: SimulatedSetter) -> ControlOutcome {
    record(setter == .size ? "size" : "position")
    if setter == .size { beforeSize() }
    return .succeeded
  }
  func readback(_ permit: SimulatedReadbackPermit) -> SimulatedReadbackValue {
    record("readback")
    beforeReadback()
    if value == .missing { return SimulatedReadbackValue(observation: nil, outcome: .unavailable) }
    let frame = value == .mismatch ? Rect(x: 2, y: 2, width: 50, height: 50) : permit.target.frame
    let observation = WindowObservation(
      token: permit.target.token, frame: frame,
      eligibility: .eligible, positionSettable: .supported, sizeSettable: .supported,
      environmentEpoch: permit.target.environmentEpoch,
      workerSequence: value == .oldSequence ? 1 : 2,
      sampledAt: value == .oldTime ? 0.9 : 1)
    return SimulatedReadbackValue(
      observation: observation,
      outcome: value == .unknown ? .unknownOutcome : .succeeded)
  }
}
