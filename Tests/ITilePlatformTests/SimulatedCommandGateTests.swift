import Foundation
import XCTest

@testable import ITileCore
@testable import ITilePlatform

final class SimulatedCommandGateTests: XCTestCase {
  private let app = AppToken(pid: 10, generation: 1)
  private let destination = Rect(x: 0, y: 40, width: 800, height: 600)

  private func ready() -> SimulatedCommandGate {
    let gate = SimulatedCommandGate()
    XCTAssertTrue(gate.attach(app))
    gate.setTrust(true, at: 0)
    XCTAssertEqual(gate.enqueue(.enable), .accepted(1))
    XCTAssertEqual(gate.drain(at: 0), [.revalidationRequired(1)])
    return gate
  }

  private func plan(_ app: AppToken, at time: Double = 1) throws
    -> (FrameTarget, WindowObservation)
  {
    let token = WindowToken(app: app, serial: 1)
    let sample = WindowObservation(
      token: token, frame: Rect(x: 10, y: 10, width: 600, height: 400),
      eligibility: .eligible, positionSettable: .supported, sizeSettable: .supported,
      environmentEpoch: 0, workerSequence: 1, sampledAt: time)
    var model = ControlModel()
    _ = model.reduce(.permission(true), at: 0)
    _ = model.reduce(.attach(app), at: 0)
    _ = model.reduce(.observation(sample), at: time)
    XCTAssertEqual(model.reduce(.tile([token: destination]), at: time), [])
    guard case .prepare(let target) = model.reduce(.dispatch(app), at: time).first else {
      throw Failure.missingTarget
    }
    return (target, sample)
  }

  private func ticket(_ gate: SimulatedCommandGate, target: FrameTarget, at time: Double = 1)
    throws -> CommandTicket
  {
    guard case .accepted = gate.enqueue(.tile([target.token: target.frame])),
      case .ready(let ticket) = gate.drain(at: time).first
    else { throw Failure.missingTicket }
    return ticket
  }

  private func published(_ gate: SimulatedCommandGate, app: AppToken? = nil) throws
    -> SimulatedOperationID
  {
    let (target, sample) = try plan(app ?? self.app)
    let command = try ticket(gate, target: target)
    return try XCTUnwrap(gate.publish(target, evidence: sample, ticket: command, at: 1))
  }

  private func permit(
    _ gate: SimulatedCommandGate, id: SimulatedOperationID,
    setter: SimulatedSetter, at time: Double = 1
  ) throws -> SimulatedGatePermit {
    guard case .permit(let permit) = gate.admit(id, setter: setter, at: time) else {
      throw Failure.missingPermit
    }
    return permit
  }

  private enum Failure: Error { case missingTarget, missingTicket, missingPermit }

  func testRevocationBeforeAdmissionDeniesEverySafetyReasonAndHoldsExactReceipt() throws {
    for reason in [
      CommandRevocation.pause, .disable, .quit, .permissionLost,
      .environmentChanged, .appUncertain(app),
    ] {
      let gate = ready()
      let id = try published(gate)
      gate.revoke(reason, at: .nan)
      guard case .denied(let terminal) = gate.admit(id, setter: .size, at: 1.1) else {
        return XCTFail("Revocation issued a permit")
      }
      XCTAssertEqual(terminal.reason, .revoked)
      XCTAssertEqual(gate.operationCount, 1)
      XCTAssertEqual(gate.admit(id, setter: .position, at: 1.1), .stale)
      XCTAssertFalse(gate.acknowledge(SimulatedTerminalReceipt(operation: id, reason: .completed)))
      XCTAssertTrue(gate.acknowledge(terminal))
      XCTAssertFalse(gate.acknowledge(terminal))
      XCTAssertEqual(gate.operationCount, 0)
    }
  }

  func testPermitBeforePauseCanFinishButCannotContinueToPosition() throws {
    let gate = ready()
    let id = try published(gate)
    let entered = expectation(description: "Fake call admitted")
    let finished = expectation(description: "Late fake completion rejected for continuation")
    let release = DispatchSemaphore(value: 0)
    DispatchQueue(label: "itile.test.simulated-call").async {
      guard case .permit(let permit) = gate.admit(id, setter: .size, at: 1) else {
        XCTFail("Missing permit")
        entered.fulfill()
        finished.fulfill()
        return
      }
      entered.fulfill()
      // Deliberately outside the gate lock: safety ingress must remain available.
      guard release.wait(timeout: .now() + 5) == .success else {
        XCTFail("Fake backend was not released")
        finished.fulfill()
        return
      }
      guard let step = gate.finish(permit, outcome: .succeeded),
        case .terminal(let terminal) = gate.acknowledge(step, at: 1.2)
      else {
        XCTFail("Late completion continued")
        finished.fulfill()
        return
      }
      XCTAssertEqual(terminal.reason, .revoked)
      XCTAssertEqual(gate.admit(id, setter: .position, at: 1.2), .stale)
      XCTAssertTrue(gate.acknowledge(terminal))
      finished.fulfill()
    }
    wait(for: [entered], timeout: 5)
    gate.revoke(.pause, at: 1.1)
    XCTAssertEqual(gate.operationCount, 1)
    release.signal()
    wait(for: [finished], timeout: 5)
    XCTAssertEqual(gate.operationCount, 0)
  }

  func testEachStepAndTerminalRequireExactAcknowledgment() throws {
    let gate = ready()
    let id = try published(gate)
    let size = try permit(gate, id: id, setter: .size)
    XCTAssertEqual(gate.admit(id, setter: .size, at: 1), .stale)
    let receipt = try XCTUnwrap(gate.finish(size, outcome: .succeeded))
    XCTAssertNil(gate.finish(size, outcome: .succeeded))
    XCTAssertEqual(gate.admit(id, setter: .position, at: 1), .stale)
    XCTAssertEqual(
      gate.acknowledge(SimulatedStepReceipt(permit: size, outcome: .unavailable), at: 1), .stale)
    XCTAssertEqual(gate.acknowledge(receipt, at: 1), .positionReady)
    XCTAssertEqual(gate.acknowledge(receipt, at: 1), .stale)
    let position = try permit(gate, id: id, setter: .position)
    let result = try XCTUnwrap(gate.finish(position, outcome: .succeeded))
    guard case .terminal(let terminal) = gate.acknowledge(result, at: 1) else {
      return XCTFail("Missing terminal receipt")
    }
    XCTAssertEqual(terminal.reason, .completed)
    XCTAssertEqual(gate.operationCount, 1)
    XCTAssertTrue(gate.acknowledge(terminal))
    let newer = try published(gate)
    XCTAssertNotEqual(id, newer)
    XCTAssertFalse(gate.acknowledge(terminal))
    XCTAssertEqual(gate.operationCount, 1)
    XCTAssertEqual(gate.admit(id, setter: .size, at: 1), .stale)
  }

  func testFailureAndExpiryNeverAdmitSecondStep() throws {
    for outcome in [ControlOutcome.unavailable, .unknownOutcome, .succeeded] {
      let gate = ready()
      let id = try published(gate)
      let size = try permit(gate, id: id, setter: .size)
      let receipt = try XCTUnwrap(gate.finish(size, outcome: outcome))
      let time = outcome == .succeeded ? 1.6 : 1.1
      guard case .terminal(let terminal) = gate.acknowledge(receipt, at: time) else {
        return XCTFail("Failure or expiry continued")
      }
      XCTAssertEqual(
        terminal.reason,
        outcome == .succeeded ? .revoked : outcome == .unavailable ? .unavailable : .unknownOutcome)
      XCTAssertEqual(gate.admit(id, setter: .position, at: time), .stale)
      XCTAssertTrue(gate.acknowledge(terminal))
    }
  }

  func testFreshEnableDoesNotReplayOldPublicationOrEvidence() throws {
    let gate = ready()
    let (old, oldSample) = try plan(app)
    let oldTicket = try ticket(gate, target: old)
    gate.revoke(.pause, at: 1.1)
    XCTAssertNil(gate.publish(old, evidence: oldSample, ticket: oldTicket, at: 1.1))
    _ = gate.enqueue(.resume)
    guard case .revalidationRequired = gate.drain(at: 1.2).first else {
      return XCTFail("Resume failed")
    }
    let newTicket = try ticket(gate, target: old, at: 1.2)
    XCTAssertNil(gate.publish(old, evidence: oldSample, ticket: newTicket, at: 1.2))
    let (fresh, sample) = try plan(app, at: 1.3)
    let freshTicket = try ticket(gate, target: fresh, at: 1.3)
    XCTAssertNotNil(gate.publish(fresh, evidence: sample, ticket: freshTicket, at: 1.3))
  }

  func testAppUncertaintyAndRetirementDoNotBlockHealthyAppOrFreeReplacement() throws {
    let gate = ready()
    let other = AppToken(pid: 20, generation: 2)
    XCTAssertTrue(gate.attach(other))
    let old = try published(gate)
    let healthy = try published(gate, app: other)
    gate.revoke(.appUncertain(app), at: 1)
    _ = try permit(gate, id: healthy, setter: .size)
    gate.retire(app)
    let replacement = AppToken(pid: app.pid, generation: 3)
    XCTAssertTrue(gate.attach(replacement))
    let newer = try published(gate, app: replacement)
    guard case .denied(let terminal) = gate.admit(old, setter: .size, at: 1) else {
      return XCTFail("Retired work admitted")
    }
    XCTAssertTrue(gate.acknowledge(terminal))
    XCTAssertFalse(gate.acknowledge(terminal))
    XCTAssertEqual(gate.operationCount, 2)
    _ = try permit(gate, id: newer, setter: .size)
  }

  func testFullCommandQueueCannotDelayDisableOrReopenWithOldEnable() throws {
    let gate = ready()
    let id = try published(gate)
    let window = WindowToken(app: app, serial: 1)
    _ = gate.enqueue(.enable)
    for _ in 0..<127 { _ = gate.enqueue(.toggleFloating(window)) }
    XCTAssertEqual(gate.queuedCount, 128)
    XCTAssertEqual(gate.enqueue(.focus(window)), .rejected(.capacity))
    gate.revoke(.disable, at: 1)
    guard case .denied(let terminal) = gate.admit(id, setter: .size, at: 1) else {
      return XCTFail("Full buffer delayed disable")
    }
    var rejected = 0
    while gate.queuedCount > 0 {
      let batch = gate.drain(at: 1)
      XCTAssertLessThanOrEqual(batch.count, 8)
      for disposition in batch {
        guard case .rejected(_, .stale) = disposition else {
          return XCTFail("Old intent replayed")
        }
        rejected += 1
      }
    }
    XCTAssertEqual(rejected, 128)
    XCTAssertEqual(gate.enqueue(.focus(window)), .rejected(.disabled))
    XCTAssertTrue(gate.acknowledge(terminal))
  }

  func testRetiredExecutingOperationStillCountsAgainstAttachmentCapacity() throws {
    let gate = ready()
    let id = try published(gate)
    let size = try permit(gate, id: id, setter: .size)
    for index in 2...16 {
      XCTAssertTrue(gate.attach(AppToken(pid: Int32(index + 100), generation: UInt64(index))))
    }
    gate.retire(app)
    let replacement = AppToken(pid: app.pid, generation: 17)
    XCTAssertFalse(gate.attach(replacement))
    let receipt = try XCTUnwrap(gate.finish(size, outcome: .unknownOutcome))
    guard case .terminal(let terminal) = gate.acknowledge(receipt, at: 1) else {
      return XCTFail("Retired executing operation continued")
    }
    XCTAssertFalse(gate.attach(replacement))
    XCTAssertTrue(gate.acknowledge(terminal))
    XCTAssertTrue(gate.attach(replacement))
    XCTAssertFalse(gate.acknowledge(terminal))
    XCTAssertFalse(gate.attach(app))
  }

  func testPublicationRejectsUnknownEvidenceFutureExpiredAndInvalidClock() throws {
    for time in [0.9, 1.6, Double.nan] {
      let gate = ready()
      let (target, sample) = try plan(app)
      let command = try ticket(gate, target: target)
      XCTAssertNil(gate.publish(target, evidence: sample, ticket: command, at: time))
      XCTAssertEqual(gate.operationCount, 0)
    }
    let gate = ready()
    let (target, sample) = try plan(app)
    let command = try ticket(gate, target: target)
    let unknown = WindowObservation(
      token: sample.token, frame: sample.frame, eligibility: .unknown,
      positionSettable: .supported, sizeSettable: .supported,
      environmentEpoch: 0, workerSequence: 1, sampledAt: 1)
    XCTAssertNil(gate.publish(target, evidence: unknown, ticket: command, at: 1))
    XCTAssertNotNil(gate.publish(target, evidence: sample, ticket: command, at: 1))
  }
}
