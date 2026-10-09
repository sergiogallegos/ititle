import XCTest

@testable import ITileCore

final class LifecycleCounterTests: XCTestCase {
  private let app = AppToken(pid: 10, generation: 1)

  func testLastValueIsIssuedOnceAndOverflowDoesNotChangeIt() {
    var serial = UInt64.max - 1
    XCTAssertTrue(LifecycleCounter.advance(&serial))
    XCTAssertEqual(serial, UInt64.max)
    XCTAssertFalse(LifecycleCounter.advance(&serial))
    XCTAssertFalse(LifecycleCounter.advance(&serial))
    XCTAssertEqual(serial, UInt64.max)
    var identity = Int.max
    XCTAssertFalse(LifecycleCounter.advance(&identity))
    XCTAssertEqual(identity, Int.max)
  }

  func testRegistryExhaustionIsAtomicAndInvalidationCannotRestartIssuer() {
    var registry = ProbeRegistry(app: app, initialSerial: UInt64.max - 1)
    let last = registry.reconcile([1, 1])
    XCTAssertEqual(last.count, 2)
    XCTAssertEqual(last[0], last[1])
    XCTAssertEqual(last[0].serial, UInt64.max)
    XCTAssertEqual(registry.reconcile([1]), [last[0]])
    XCTAssertEqual(registry.reconcile([1, 2]), [])
    XCTAssertTrue(registry.exhausted)
    XCTAssertTrue(registry.snapshot(environmentEpoch: 0, revision: 1).windows.isEmpty)
    registry.invalidate()
    XCTAssertEqual(registry.reconcile([1]), [])
  }

  func testRegistryRejectsWholeBatchWithoutIssuingPartialTokens() {
    var registry = ProbeRegistry(app: app, initialSerial: UInt64.max - 1)
    XCTAssertEqual(registry.reconcile([1, 2]), [])
    XCTAssertEqual(
      registry.snapshot(environmentEpoch: 0, revision: 1).highestSerial, UInt64.max - 1)
    XCTAssertTrue(registry.exhausted)
  }

  func testEpochExhaustionStopsEvenWithInvalidSafetyTimestamp() {
    for (event, time) in [
      (ControlEvent.permission(false), Double.nan), (.environmentChanged(.environmentChanged), 1.0),
    ] {
      var model = ControlModel(
        environmentEpoch: UInt64.max, layoutRevision: 0, admissionGeneration: 0)
      let effects = model.reduce(event, at: time)
      XCTAssertTrue(effects.contains(.rejected(.counterExhausted)))
      XCTAssertEqual(model.environmentEpoch, UInt64.max)
      XCTAssertEqual(model.state, .stopping)
      XCTAssertEqual(model.reduce(.permission(true), at: 1), [.rejected(.stopped)])
    }
  }

  func testAdmissionExhaustionRetainsExactBoundCleanup() throws {
    var model = ControlModel(
      environmentEpoch: 0, layoutRevision: 0, admissionGeneration: UInt64.max)
    let target = try prepare(&model)
    let id = ControlOperationID(app: app, serial: 1)
    XCTAssertEqual(model.reduce(.operationBound(target, id), at: 1), [])
    XCTAssertTrue(model.reduce(.pause, at: .nan).contains(.rejected(.counterExhausted)))
    XCTAssertEqual(model.state, .stopping)
    XCTAssertTrue(model.pending.isEmpty)
    XCTAssertTrue(model.observations.isEmpty)
    XCTAssertTrue(model.desired.isEmpty)
    XCTAssertEqual(model.inFlightCount, 1)
    XCTAssertEqual(
      model.reduce(.operationTerminated(ControlOperationID(app: app, serial: 2)), at: 1),
      [.rejected(.staleWork)])
    _ = model.reduce(.operationTerminated(id), at: .nan)
    XCTAssertEqual(model.inFlightCount, 0)
    XCTAssertEqual(model.state, .stopping)
  }

  func testRevisionExhaustionCannotPublishPlan() {
    var model = ControlModel(
      environmentEpoch: 0, layoutRevision: UInt64.max, admissionGeneration: 0)
    let window = observe(&model)
    XCTAssertTrue(
      model.reduce(.tile([window: frame]), at: 1).contains(.rejected(.counterExhausted)))
    XCTAssertEqual(model.layoutRevision, UInt64.max)
    XCTAssertTrue(model.pending.isEmpty)
    XCTAssertEqual(model.reduce(.dispatch(app), at: 1), [.rejected(.stopped)])
  }

  private var frame: Rect { Rect(x: 0, y: 0, width: 600, height: 400) }

  private func observe(_ model: inout ControlModel) -> WindowToken {
    let window = WindowToken(app: app, serial: 1)
    _ = model.reduce(.permission(true), at: 1)
    _ = model.reduce(.attach(app), at: 1)
    _ = model.reduce(
      .observation(
        WindowObservation(
          token: window, frame: frame, eligibility: .eligible, positionSettable: .supported,
          sizeSettable: .supported, environmentEpoch: 0, workerSequence: 1, sampledAt: 1)), at: 1)
    return window
  }

  private func prepare(_ model: inout ControlModel) throws -> FrameTarget {
    let window = observe(&model)
    XCTAssertEqual(model.reduce(.tile([window: frame]), at: 1), [])
    guard case .prepare(let target) = model.reduce(.dispatch(app), at: 1).first else {
      throw NSError(domain: "Expected preparation", code: 1)
    }
    return target
  }
}
