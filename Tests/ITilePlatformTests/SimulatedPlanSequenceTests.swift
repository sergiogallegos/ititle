import Foundation
import XCTest

@testable import ITileCore
@testable import ITilePlatform

@MainActor
final class SimulatedPlanSequenceTests: XCTestCase {
  private let app = AppToken(pid: 1, generation: 1)
  private let peer = AppToken(pid: 2, generation: 2)
  private let frame = Rect(x: 0, y: 30, width: 700, height: 500)
  private func token(_ serial: UInt64, app: AppToken? = nil) -> WindowToken {
    WindowToken(app: app ?? self.app, serial: serial)
  }
  private func bootstrap(_ runtime: SimulatedWorkerRuntime, windows: [WindowToken]) {
    runtime.owner.trust(true, at: 0)
    _ = runtime.owner.gate.enqueue(.enable)
    _ = runtime.owner.drain(at: 0)
    var sequences: [AppToken: UInt64] = [:]
    for window in windows.sorted(by: { $0.serial < $1.serial }) {
      sequences[window.app, default: 0] += 1
      XCTAssertEqual(
        runtime.owner.observe(
          WindowObservation(
            token: window, frame: frame,
            eligibility: .eligible, positionSettable: .supported, sizeSettable: .supported,
            environmentEpoch: 0, workerSequence: sequences[window.app]!, sampledAt: 1), at: 1), [])
    }
  }
  private func runtime(
    done: @escaping @MainActor @Sendable (SimulatedTerminalReceipt) -> Void,
    exited: @escaping @Sendable (AppToken) -> Void
  ) -> SimulatedWorkerRuntime {
    SimulatedWorkerRuntime(
      time: { 1 }, schedule: { work in Task { @MainActor in work() } },
      terminal: done, exited: exited)
  }

  func testTwoSameAppWindowsRunInSerialOrderWithOneRevisionAndNoTicketReplay() async throws {
    let done = expectation(description: "Two windows observed")
    done.expectedFulfillmentCount = 2
    let exited = expectation(description: "Worker exited")
    var operations: [ControlOperationID] = []
    let runtime = runtime(
      done: { receipt in
        XCTAssertEqual(receipt.reason, .completed)
        operations.append(receipt.operation)
        done.fulfill()
      }, exited: { _ in exited.fulfill() })
    let backend = PlanBackend(initialSequence: 2)
    XCTAssertTrue(runtime.attach(app, backend: backend, at: 0))
    bootstrap(runtime, windows: [token(1), token(2)])
    let second = Rect(x: 700, y: 30, width: 600, height: 500)
    _ = runtime.enqueue(.tile([token(2): second, token(1): frame]))
    await fulfillment(of: [done], timeout: 5)
    XCTAssertEqual(
      backend.calls, ["1:size", "1:position", "1:readback", "2:size", "2:position", "2:readback"])
    XCTAssertEqual(Set(operations).count, 2)
    XCTAssertEqual(runtime.owner.model.layoutRevision, 1)
    XCTAssertEqual(runtime.owner.model.observations[token(1)]?.workerSequence, 3)
    XCTAssertEqual(runtime.owner.model.observations[token(2)]?.workerSequence, 4)
    XCTAssertEqual(runtime.owner.model.observations[token(2)]?.frame, second)
    XCTAssertEqual(runtime.owner.gate.remainingPlanTargets, 0)
    XCTAssertNil(runtime.owner.prepare(app, at: 1))
    runtime.revoke(.quit, at: 1)
    await fulfillment(of: [exited], timeout: 5)
  }

  func testFailureCancelsRemainingSameAppWindowsButHealthyPlanCompletes() async throws {
    let done = expectation(description: "Failed app and healthy peer terminal")
    done.expectedFulfillmentCount = 2
    let exited = expectation(description: "Workers exited")
    exited.expectedFulfillmentCount = 2
    let runtime = runtime(done: { _ in done.fulfill() }, exited: { _ in exited.fulfill() })
    let broken = PlanBackend(initialSequence: 2, failSize: true)
    let healthy = PlanBackend(initialSequence: 1)
    XCTAssertTrue(runtime.attach(app, backend: broken, at: 0))
    XCTAssertTrue(runtime.attach(peer, backend: healthy, at: 0))
    let peerToken = token(1, app: peer)
    bootstrap(runtime, windows: [token(1), token(2), peerToken])
    _ = runtime.enqueue(.tile([token(1): frame, token(2): frame, peerToken: frame]))
    await fulfillment(of: [done], timeout: 5)
    XCTAssertEqual(broken.calls, ["1:size"])
    XCTAssertEqual(healthy.calls, ["1:size", "1:position", "1:readback"])
    XCTAssertTrue(runtime.owner.model.dirty.contains(token(2)))
    XCTAssertEqual(runtime.owner.gate.remainingPlanTargets, 0)
    XCTAssertEqual(runtime.owner.model.inFlightCount, 0)
    runtime.revoke(.quit, at: 1)
    await fulfillment(of: [exited], timeout: 5)
  }

  func testAppUncertaintyCancelsStalledCursorWithoutBlockingPeerFromSharedTicket() async throws {
    let entered = expectation(description: "First app blocked")
    let peerDone = expectation(description: "Two peer windows completed")
    peerDone.expectedFulfillmentCount = 2
    let stopped = expectation(description: "Late revoked app terminal")
    let exited = expectation(description: "Workers exited")
    exited.expectedFulfillmentCount = 2
    let release = DispatchSemaphore(value: 0)
    let blocked = PlanBackend(
      initialSequence: 2,
      beforeSize: { _ in
        entered.fulfill()
        XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
      })
    let peerEntered = expectation(description: "Peer size admitted before uncertainty")
    let releasePeer = DispatchSemaphore(value: 0)
    let healthy = PlanBackend(
      initialSequence: 2,
      beforeSize: { token in
        if token.serial == 1 {
          peerEntered.fulfill()
          XCTAssertEqual(releasePeer.wait(timeout: .now() + 5), .success)
        }
      })
    let runtime = runtime(
      done: { receipt in
        if receipt.operation.app.pid == 1 {
          XCTAssertEqual(receipt.reason, .revoked)
          stopped.fulfill()
        } else {
          XCTAssertEqual(receipt.reason, .completed)
          peerDone.fulfill()
        }
      }, exited: { _ in exited.fulfill() })
    XCTAssertTrue(runtime.attach(app, backend: blocked, at: 0))
    XCTAssertTrue(runtime.attach(peer, backend: healthy, at: 0))
    let peers = [token(1, app: peer), token(2, app: peer)]
    bootstrap(runtime, windows: [token(1), token(2)] + peers)
    _ = runtime.enqueue(
      .tile(Dictionary(uniqueKeysWithValues: ([token(1), token(2)] + peers).map { ($0, frame) })))
    await fulfillment(of: [entered, peerEntered], timeout: 5)
    runtime.revoke(.appUncertain(app), at: 1)
    releasePeer.signal()
    await fulfillment(of: [peerDone], timeout: 5)
    XCTAssertEqual(runtime.owner.model.inFlightCount, 1)
    release.signal()
    await fulfillment(of: [stopped], timeout: 5)
    XCTAssertEqual(blocked.calls, ["1:size"])
    XCTAssertEqual(healthy.calls.count, 6)
    XCTAssertEqual(runtime.owner.gate.remainingPlanTargets, 0)
    runtime.revoke(.quit, at: 1)
    await fulfillment(of: [exited], timeout: 5)
  }

  func testNewRevisionDuringAdmittedCallCancelsOldRemainingTargetsAndPreservesNewDesired()
    async throws
  {
    let entered = expectation(description: "Old size admitted")
    let done = expectation(description: "Old operation revoked")
    let exited = expectation(description: "Worker exited")
    let release = DispatchSemaphore(value: 0)
    let backend = PlanBackend(
      initialSequence: 2,
      beforeSize: { _ in
        entered.fulfill()
        XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
      })
    let runtime = runtime(
      done: { receipt in
        XCTAssertEqual(receipt.reason, .revoked)
        done.fulfill()
      },
      exited: { _ in exited.fulfill() })
    XCTAssertTrue(runtime.attach(app, backend: backend, at: 0))
    bootstrap(runtime, windows: [token(1), token(2)])
    _ = runtime.enqueue(.tile([token(1): frame, token(2): frame]))
    await fulfillment(of: [entered], timeout: 5)
    let newer = Rect(x: 500, y: 30, width: 500, height: 500)
    _ = runtime.owner.gate.enqueue(.tile([token(1): newer, token(2): newer]))
    _ = runtime.owner.drain(at: 1)
    XCTAssertEqual(runtime.owner.model.layoutRevision, 2)
    release.signal()
    await fulfillment(of: [done], timeout: 5)
    XCTAssertEqual(runtime.owner.model.desired[token(2)], newer)
    XCTAssertEqual(backend.calls, ["1:size"])
    XCTAssertEqual(runtime.owner.gate.remainingPlanTargets, 0)
    XCTAssertTrue(runtime.owner.model.pending.isEmpty)
    XCTAssertTrue(runtime.owner.model.dirty.contains(token(2)))
    runtime.revoke(.quit, at: 1)
    await fulfillment(of: [exited], timeout: 5)
  }

  func testMaximumSameAppPlanHasBoundedCursorAndSixtyFifthWindowRejects() async throws {
    let entered = expectation(description: "Maximum cursor held on its first window")
    let done = expectation(description: "Maximum cursor completed")
    done.expectedFulfillmentCount = 64
    let exited = expectation(description: "Worker exited")
    let release = DispatchSemaphore(value: 0)
    let backend = PlanBackend(
      initialSequence: 64,
      beforeSize: { token in
        if token.serial == 1 {
          entered.fulfill()
          XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
        }
      })
    let runtime = runtime(
      done: { receipt in
        XCTAssertEqual(receipt.reason, .completed)
        done.fulfill()
      },
      exited: { _ in exited.fulfill() })
    XCTAssertTrue(runtime.attach(app, backend: backend, at: 0))
    let windows = (1...64).map { token(UInt64($0)) }
    bootstrap(runtime, windows: windows)
    _ = runtime.enqueue(.tile(Dictionary(uniqueKeysWithValues: windows.map { ($0, frame) })))
    await fulfillment(of: [entered], timeout: 5)
    XCTAssertEqual(runtime.owner.gate.remainingPlanTargets, 64)
    XCTAssertEqual(runtime.owner.gate.operationCount, 1)
    release.signal()
    await fulfillment(of: [done], timeout: 5)
    XCTAssertEqual(backend.calls.count, 192)
    XCTAssertEqual(runtime.owner.gate.remainingPlanTargets, 0)
    XCTAssertEqual(runtime.owner.model.layoutRevision, 1)
    XCTAssertEqual(runtime.owner.model.observations[token(64)]?.workerSequence, 128)
    runtime.revoke(.quit, at: 1)
    await fulfillment(of: [exited], timeout: 5)

    let owner = SimulatedControlOwner(requiresReadback: true, allowsMultiWindowPlans: true)
    XCTAssertTrue(owner.attach(app, at: 0))
    owner.trust(true, at: 0)
    _ = owner.gate.enqueue(.enable)
    _ = owner.drain(at: 0)
    var large: [WindowToken: Rect] = [:]
    for serial in 1...65 {
      let window = token(UInt64(serial))
      large[window] = frame
      XCTAssertEqual(
        owner.observe(
          WindowObservation(
            token: window, frame: frame,
            eligibility: .eligible, positionSettable: .supported, sizeSettable: .supported,
            environmentEpoch: 0, workerSequence: UInt64(serial), sampledAt: 1), at: 1), [])
    }
    _ = owner.gate.enqueue(.tile(large))
    XCTAssertEqual(owner.drain(at: 1), [.reduced(2, [.rejected(.capacity)])])
    XCTAssertEqual(owner.model.layoutRevision, 0)
    XCTAssertEqual(owner.gate.remainingPlanTargets, 0)
    XCTAssertNil(owner.prepare(app, at: 1))
  }

  func testRegistryRemovalOfRemainingWindowCancelsEntireCursorBeforeNextDispatch() async throws {
    let done = expectation(description: "First window completed before registry replacement")
    let exited = expectation(description: "Worker exited")
    var runtime: SimulatedWorkerRuntime!
    runtime = self.runtime(
      done: { receipt in
        XCTAssertEqual(receipt.reason, .completed)
        let first = WindowToken(app: receipt.operation.app, serial: 1)
        let third = WindowToken(app: receipt.operation.app, serial: 3)
        XCTAssertEqual(
          runtime.owner.registry(
            ProbeRegistrySnapshot(
              app: receipt.operation.app,
              environmentEpoch: 0, revision: 2, highestSerial: 3, windows: [first, third]), at: 1),
          [])
        done.fulfill()
      }, exited: { _ in exited.fulfill() })
    let backend = PlanBackend(initialSequence: 3)
    XCTAssertTrue(runtime.attach(app, backend: backend, at: 0))
    let windows = [token(1), token(2), token(3)]
    bootstrap(runtime, windows: windows)
    XCTAssertEqual(
      runtime.owner.registry(
        ProbeRegistrySnapshot(
          app: app, environmentEpoch: 0,
          revision: 1, highestSerial: 3, windows: Set(windows)), at: 1), [])
    _ = runtime.enqueue(.tile(Dictionary(uniqueKeysWithValues: windows.map { ($0, frame) })))
    await fulfillment(of: [done], timeout: 5)
    XCTAssertEqual(backend.calls, ["1:size", "1:position", "1:readback"])
    XCTAssertEqual(runtime.owner.model.observations[token(1)]?.workerSequence, 4)
    XCTAssertNil(runtime.owner.model.observations[token(2)])
    XCTAssertTrue(runtime.owner.model.pending.isEmpty)
    XCTAssertEqual(runtime.owner.gate.remainingPlanTargets, 0)
    runtime.revoke(.quit, at: 1)
    await fulfillment(of: [exited], timeout: 5)
  }

  func testRetirementBetweenWindowsStopsCursorWithoutTouchingCompletedGeometry() async throws {
    let done = expectation(description: "First observed window terminal")
    let exited = expectation(description: "Worker exited")
    var runtime: SimulatedWorkerRuntime!
    runtime = self.runtime(
      done: { receipt in
        XCTAssertEqual(receipt.reason, .completed)
        runtime.owner.destroy(WindowToken(app: receipt.operation.app, serial: 2), at: 1)
        done.fulfill()
      }, exited: { _ in exited.fulfill() })
    let backend = PlanBackend(initialSequence: 2)
    XCTAssertTrue(runtime.attach(app, backend: backend, at: 0))
    bootstrap(runtime, windows: [token(1), token(2)])
    _ = runtime.enqueue(.tile([token(1): frame, token(2): frame]))
    await fulfillment(of: [done], timeout: 5)
    XCTAssertEqual(backend.calls, ["1:size", "1:position", "1:readback"])
    XCTAssertEqual(runtime.owner.model.observations[token(1)]?.workerSequence, 3)
    XCTAssertNil(runtime.owner.model.observations[token(2)])
    XCTAssertEqual(runtime.owner.gate.remainingPlanTargets, 0)
    XCTAssertNil(runtime.owner.prepare(app, at: 1))
    runtime.revoke(.quit, at: 1)
    await fulfillment(of: [exited], timeout: 5)
  }
}

private final class PlanBackend: SimulatedWorkerBackend, @unchecked Sendable {
  private let lock = NSLock()
  private var sequence: UInt64
  private var recorded: [String] = []
  private let failSize: Bool
  private let beforeSize: @Sendable (WindowToken) -> Void
  init(
    initialSequence: UInt64, failSize: Bool = false,
    beforeSize: @escaping @Sendable (WindowToken) -> Void = { _ in }
  ) {
    sequence = initialSequence
    self.failSize = failSize
    self.beforeSize = beforeSize
  }
  var calls: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }
  func set(_ target: FrameTarget, setter: SimulatedSetter) -> ControlOutcome {
    XCTAssertFalse(Thread.isMainThread)
    lock.lock()
    recorded.append("\(target.token.serial):\(setter == .size ? "size" : "position")")
    lock.unlock()
    if setter == .size { beforeSize(target.token) }
    return failSize && setter == .size ? .unavailable : .succeeded
  }
  func readback(_ permit: SimulatedReadbackPermit) -> SimulatedReadbackValue {
    XCTAssertFalse(Thread.isMainThread)
    lock.lock()
    recorded.append("\(permit.target.token.serial):readback")
    sequence += 1
    let next = sequence
    lock.unlock()
    return SimulatedReadbackValue(
      observation: WindowObservation(
        token: permit.target.token,
        frame: permit.target.frame, eligibility: .eligible, positionSettable: .supported,
        sizeSettable: .supported, environmentEpoch: permit.target.environmentEpoch,
        workerSequence: next, sampledAt: 1), outcome: .succeeded)
  }
}
