import Foundation
import XCTest

@testable import ITileCore
@testable import ITilePlatform

@MainActor
final class SimulatedControlOwnerTests: XCTestCase {
  private let app = AppToken(pid: 10, generation: 1)
  private let destination = Rect(x: 0, y: 40, width: 800, height: 600)
  private var token: WindowToken { WindowToken(app: app, serial: 1) }

  private func sample(
    _ token: WindowToken, sequence: UInt64 = 1, time: Double = 1,
    epoch: UInt64 = 0
  ) -> WindowObservation {
    WindowObservation(
      token: token, frame: Rect(x: 10, y: 10, width: 600, height: 400),
      eligibility: .eligible, positionSettable: .supported, sizeSettable: .supported,
      environmentEpoch: epoch, workerSequence: sequence, sampledAt: time)
  }

  private func ready() -> SimulatedControlOwner {
    let owner = SimulatedControlOwner()
    XCTAssertTrue(owner.attach(app, at: 0))
    owner.trust(true, at: 0)
    _ = owner.gate.enqueue(.enable)
    _ = owner.drain(at: 0)
    XCTAssertEqual(owner.observe(sample(token), at: 1), [])
    return owner
  }

  private func prepare(
    _ owner: SimulatedControlOwner, token: WindowToken? = nil,
    frame: Rect? = nil, at now: Double = 1
  ) throws -> ControlOperationID {
    _ = owner.gate.enqueue(.tile([token ?? self.token: frame ?? destination]))
    _ = owner.drain(at: now)
    return try XCTUnwrap(owner.prepare((token ?? self.token).app, at: now))
  }

  private func step(
    _ owner: SimulatedControlOwner, id: ControlOperationID,
    setter: SimulatedSetter, outcome: ControlOutcome = .succeeded,
    at now: Double = 1
  ) throws -> SimulatedStepReceipt {
    guard case .permit(let permit) = owner.gate.admit(id, setter: setter, at: now) else {
      throw Failure.noPermit
    }
    return try XCTUnwrap(owner.gate.finish(permit, outcome: outcome))
  }
  private enum Failure: Error { case noPermit }

  func testDeniedBeforeFirstPermitCleansBothMatchingSlotsWithoutFakeSuccess() throws {
    let owner = ready()
    let id = try prepare(owner)
    XCTAssertEqual(owner.model.inFlightCount, 1)
    owner.revoke(.pause, at: .nan)
    XCTAssertEqual(owner.model.inFlightCount, 1)
    guard case .denied(let receipt) = owner.gate.admit(id, setter: .size, at: 1) else {
      return XCTFail("Paused operation admitted")
    }
    XCTAssertTrue(owner.consume(receipt, at: 1))
    XCTAssertEqual(owner.model.inFlightCount, 0)
    XCTAssertEqual(owner.gate.operationCount, 0)
    XCTAssertEqual(owner.model.observations[token]?.frame, sample(token).frame)
    XCTAssertTrue(owner.model.dirty.contains(token))
    XCTAssertFalse(owner.consume(receipt, at: 1))
    XCTAssertNil(owner.prepare(app, at: 1))
  }

  func testSuccessfulStepsWaitForOwnerAndStillRequireFreshObservedGeometry() throws {
    let owner = ready()
    let id = try prepare(owner)
    let size = try step(owner, id: id, setter: .size)
    XCTAssertEqual(owner.gate.acknowledge(size, at: 1), .stale)
    XCTAssertEqual(owner.gate.admit(id, setter: .position, at: 1), .stale)
    XCTAssertEqual(owner.consume(size, at: 1), .positionReady)
    XCTAssertEqual(owner.consume(size, at: 1), .stale)
    let position = try step(owner, id: id, setter: .position)
    guard case .terminal(let terminal) = owner.consume(position, at: 1) else {
      return XCTFail("Missing terminal completion")
    }
    XCTAssertEqual(terminal.reason, .completed)
    XCTAssertEqual(owner.model.inFlightCount, 0)
    XCTAssertEqual(owner.gate.operationCount, 0)
    XCTAssertEqual(owner.model.observations[token]?.frame, sample(token).frame)
    XCTAssertEqual(owner.model.desired[token], destination)
    XCTAssertTrue(owner.model.dirty.contains(token))
    XCTAssertNil(owner.prepare(app, at: 1))
    XCTAssertEqual(owner.observe(sample(token, sequence: 2), at: 1), [])
    let newer = try prepare(owner)
    XCTAssertFalse(owner.consume(terminal, at: 1))
    XCTAssertEqual(owner.model.inFlightCount, 1)
    XCTAssertEqual(owner.gate.operationCount, 1)
    XCTAssertNotEqual(id, newer)
  }

  func testNewRevisionBeforeReceiptPreventsPositionAndPreservesNewDesiredFrame() throws {
    let owner = ready()
    let id = try prepare(owner)
    let size = try step(owner, id: id, setter: .size)
    let newer = Rect(x: 800, y: 40, width: 700, height: 600)
    _ = owner.gate.enqueue(.tile([token: newer]))
    _ = owner.drain(at: 1)
    XCTAssertEqual(owner.model.layoutRevision, 2)
    guard case .terminal = owner.consume(size, at: 1) else {
      return XCTFail("Old revision continued")
    }
    XCTAssertEqual(owner.model.desired[token], newer)
    XCTAssertEqual(owner.model.inFlightCount, 0)
    XCTAssertEqual(owner.gate.operationCount, 0)
    XCTAssertTrue(owner.model.dirty.contains(token))
    XCTAssertNil(owner.prepare(app, at: 1))
  }

  func testRegistryRetirementDeniesAndCannotBeRevivedByStaleReceipt() throws {
    let owner = ready()
    XCTAssertEqual(
      owner.registry(
        ProbeRegistrySnapshot(
          app: app, environmentEpoch: 0,
          revision: 1, highestSerial: 1, windows: [token]), at: 1), [])
    let id = try prepare(owner)
    XCTAssertEqual(
      owner.registry(
        ProbeRegistrySnapshot(
          app: app, environmentEpoch: 0,
          revision: 2, highestSerial: 1, windows: []), at: 1), [])
    guard case .denied(let terminal) = owner.gate.admit(id, setter: .size, at: 1) else {
      return XCTFail("Retired window admitted")
    }
    XCTAssertTrue(owner.consume(terminal, at: 1))
    XCTAssertTrue(owner.model.observations.isEmpty)
    XCTAssertTrue(owner.model.desired.isEmpty)
    XCTAssertEqual(owner.model.inFlightCount, 0)
    XCTAssertEqual(owner.observe(sample(token, sequence: 2), at: 1), [.rejected(.staleObservation)])
  }

  func testBlockedFakeCallAcrossQuitDoesNotBlockOwnerOrLeakModelFlight() async throws {
    let owner = ready()
    let id = try prepare(owner)
    let gate = owner.gate
    let entered = expectation(description: "Admitted fake call")
    let returned = expectation(description: "Backend returned")
    let release = DispatchSemaphore(value: 0)
    let box = ReceiptBox()
    DispatchQueue(label: "itile.test.owner-backend").async {
      guard case .permit(let permit) = gate.admit(id, setter: .size, at: 1) else {
        XCTFail("No permit")
        entered.fulfill()
        returned.fulfill()
        return
      }
      entered.fulfill()
      guard release.wait(timeout: .now() + 5) == .success else {
        XCTFail("Backend not released")
        returned.fulfill()
        return
      }
      box.set(gate.finish(permit, outcome: .succeeded))
      returned.fulfill()
    }
    await fulfillment(of: [entered], timeout: 5)
    owner.revoke(.quit, at: .nan)
    XCTAssertEqual(owner.model.state, .stopping)
    XCTAssertEqual(owner.model.inFlightCount, 1)
    XCTAssertEqual(gate.enqueue(.enable), .rejected(.stopped))
    release.signal()
    await fulfillment(of: [returned], timeout: 5)
    let receipt = try XCTUnwrap(box.get())
    guard case .terminal(let terminal) = owner.consume(receipt, at: 1.1) else {
      return XCTFail("Quit completion continued")
    }
    XCTAssertEqual(terminal.reason, .revoked)
    XCTAssertEqual(owner.model.inFlightCount, 0)
    XCTAssertEqual(gate.operationCount, 0)
    XCTAssertEqual(owner.model.state, .stopping)
  }

  func testPIDReplacementLateCompletionCannotRemoveNewFlight() throws {
    let owner = ready()
    let old = try prepare(owner)
    let late = try step(owner, id: old, setter: .size)
    owner.retire(app, at: 1)
    let replacement = AppToken(pid: app.pid, generation: 2)
    let replacementToken = WindowToken(app: replacement, serial: 1)
    XCTAssertTrue(owner.attach(replacement, at: 1))
    XCTAssertEqual(owner.observe(sample(replacementToken), at: 1), [])
    let newer = try prepare(owner, token: replacementToken)
    guard case .terminal = owner.consume(late, at: 1) else {
      return XCTFail("Retired completion continued")
    }
    XCTAssertEqual(owner.model.inFlightCount, 1)
    XCTAssertEqual(owner.gate.operationCount, 1)
    _ = try step(owner, id: newer, setter: .size)
  }

  func testPermissionAndEnvironmentRecoveryRequireMatchingEpochAndFreshExplicitTile() throws {
    for reason in [CommandRevocation.permissionLost, .environmentChanged] {
      let owner = ready()
      let old = try prepare(owner)
      owner.revoke(reason, at: .nan)
      XCTAssertEqual(owner.model.environmentEpoch, 1)
      guard case .denied(let terminal) = owner.gate.admit(old, setter: .size, at: 1) else {
        return XCTFail("Old epoch admitted")
      }
      XCTAssertTrue(owner.consume(terminal, at: 1))
      owner.trust(true, at: 1.1)
      _ = owner.gate.enqueue(.resume)
      _ = owner.drain(at: 1.1)
      XCTAssertNil(owner.prepare(app, at: 1.1))
      XCTAssertEqual(
        owner.observe(sample(token, sequence: 2, time: 1.2), at: 1.2),
        [.rejected(.staleObservation)])
      XCTAssertEqual(owner.observe(sample(token, sequence: 2, time: 1.2, epoch: 1), at: 1.2), [])
      let fresh = try prepare(owner, at: 1.2)
      XCTAssertNotEqual(old, fresh)
      XCTAssertFalse(owner.consume(terminal, at: 1.2))
      _ = try step(owner, id: fresh, setter: .size, at: 1.2)
    }
  }

  func testUnsupportedSemanticPoliciesAndSameAppMultiWindowPlanAreExplicit() {
    let owner = ready()
    _ = owner.gate.enqueue(.focus(token))
    _ = owner.gate.enqueue(.resize(token, 0.1))
    _ = owner.gate.enqueue(
      .tile([
        token: destination,
        WindowToken(app: app, serial: 2): destination,
      ]))
    XCTAssertEqual(owner.drain(at: 1), [.unsupported(2), .unsupported(3), .unsupported(4)])
    XCTAssertEqual(owner.model.layoutRevision, 0)
    XCTAssertEqual(owner.model.inFlightCount, 0)
    XCTAssertEqual(owner.gate.operationCount, 0)
  }
}

private final class ReceiptBox: @unchecked Sendable {
  private let lock = NSLock()
  private var receipt: SimulatedStepReceipt?
  func set(_ receipt: SimulatedStepReceipt?) {
    lock.lock()
    defer { lock.unlock() }
    self.receipt = receipt
  }
  func get() -> SimulatedStepReceipt? {
    lock.lock()
    defer { lock.unlock() }
    return receipt
  }
}
