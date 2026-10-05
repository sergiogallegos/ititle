import XCTest

@testable import ITileCore

final class FocusedProbeTests: XCTestCase {
  private let app = AppToken(pid: 42, generation: 1)
  private var token: WindowToken { WindowToken(app: app, serial: 1) }

  private func evidence(
    role: ProbeRead<String> = .value("AXWindow"),
    subrole: ProbeRead<String> = .value("AXStandardWindow"),
    minimized: ProbeRead<Bool> = .value(false),
    fullscreen: ProbeRead<Bool> = .value(false), modal: ProbeRead<Bool> = .value(false),
    frame: ProbeRead<Rect> = .value(Rect(x: -100, y: -400, width: 800, height: 600)),
    capability: ProbeRead<Bool> = .value(true), sheets: ProbeRead<Int> = .value(0),
    complete: Bool = true, focus: ProbeRead<Bool> = .value(true),
    expected: WindowToken? = nil
  ) -> FocusedWindowEvidence {
    FocusedWindowEvidence(
      token: token, environmentEpoch: 3, workerSequence: 7,
      startedAt: 10, finishedAt: 10.1, role: role, subrole: subrole, minimized: minimized,
      fullscreen: fullscreen, modal: modal, frame: frame, positionSettable: capability,
      sizeSettable: capability, directSheetCount: sheets, directSheetScanComplete: complete,
      destructionNotification: .value(true), focusedWindowUnchanged: focus, expectedToken: expected)
  }

  func testNormalFocusedWindowStillCannotBeAdmittedForControl() throws {
    let observed = evidence()
    XCTAssertEqual(observed.eligibility, .unknown)
    let control = try XCTUnwrap(observed.controlObservation)
    XCTAssertEqual(control.token, token)
    XCTAssertEqual(control.frame.x, -100)
    XCTAssertEqual(control.sampledAt, 10)  // Conservatively age from beginning of scan.
    XCTAssertEqual(control.workerSequence, 7)
    var model = ControlModel()
    _ = model.reduce(.permission(true), at: 0)
    _ = model.reduce(.attach(app), at: 0)
    for _ in 0..<3 { _ = model.reduce(.environmentChanged(.environmentChanged), at: 0) }
    XCTAssertEqual(model.reduce(.observation(control), at: 10.1), [])
    XCTAssertTrue(
      model.reduce(.tile([token: control.frame]), at: 10.1).contains(.rejected(.invalidPlan)))
    XCTAssertEqual(model.state, .paused)
  }

  func testSheetsAndUnsafeWindowStatesArePositiveExclusions() {
    let excluded = [
      evidence(role: .value("other-role")), evidence(subrole: .value("AXDialog")),
      evidence(minimized: .value(true)), evidence(fullscreen: .value(true)),
      evidence(modal: .value(true)), evidence(capability: .value(false)),
      evidence(sheets: .value(1), complete: false), evidence(focus: .value(false)),
    ]
    for sample in excluded { XCTAssertEqual(sample.eligibility, .ineligible) }
  }

  func testMissingAttributesAndIncompleteZeroSheetsNeverBecomeEligible() {
    let unknown = [
      evidence(role: .unavailable(-25212)), evidence(subrole: .invalidType),
      evidence(modal: .unavailable(-25212)), evidence(capability: .invalidType),
      evidence(sheets: .value(0), complete: false), evidence(sheets: .unavailable(-25204)),
      evidence(focus: .unavailable(-25207)),
    ]
    for sample in unknown { XCTAssertEqual(sample.eligibility, .unknown) }
    XCTAssertNil(evidence(frame: .unavailable(-25204)).controlObservation)
    XCTAssertTrue(evidence(modal: .unavailable(-25212)).report.contains("unknown(AX -25212)"))
  }

  func testSameBoundsCannotMakeDifferentTokenPassRevalidation() {
    XCTAssertEqual(evidence(expected: token).expectedWindowMatches, true)
    let otherWindow = WindowToken(app: app, serial: 2)
    let otherProcess = WindowToken(app: AppToken(pid: app.pid, generation: 2), serial: 1)
    for expected in [otherWindow, otherProcess] {
      XCTAssertEqual(evidence(expected: expected).expectedWindowMatches, false)
      XCTAssertEqual(evidence(expected: expected).eligibility, .ineligible)
    }
    XCTAssertNil(evidence().expectedWindowMatches)
  }

  func testInspectorActivationAndSwitchAwayBackInvalidatePendingDelivery() {
    let context = FocusRequestContext(app: app, environmentEpoch: 3, activationRevision: 10)
    XCTAssertTrue(
      context.accepts(
        currentApp: app, environmentEpoch: 3, activationRevision: 10,
        trusted: true, paused: false))
    // The inspector is not the source app.
    XCTAssertFalse(
      context.accepts(
        currentApp: nil, environmentEpoch: 3, activationRevision: 11,
        trusted: true, paused: false))
    // Returning to the source does not make the old request current again.
    XCTAssertFalse(
      context.accepts(
        currentApp: app, environmentEpoch: 3, activationRevision: 12,
        trusted: true, paused: false))
  }

  func testDeliveryRequiresCurrentProcessEpochTrustAndUnpausedState() {
    let context = FocusRequestContext(app: app, environmentEpoch: 3, activationRevision: 10)
    XCTAssertFalse(
      context.accepts(
        currentApp: AppToken(pid: 42, generation: 2), environmentEpoch: 3,
        activationRevision: 10, trusted: true, paused: false))
    XCTAssertFalse(
      context.accepts(
        currentApp: app, environmentEpoch: 4, activationRevision: 10,
        trusted: true, paused: false))
    XCTAssertFalse(
      context.accepts(
        currentApp: app, environmentEpoch: 3, activationRevision: 10,
        trusted: false, paused: false))
    XCTAssertFalse(
      context.accepts(
        currentApp: app, environmentEpoch: 3, activationRevision: 10,
        trusted: true, paused: true))
  }
}
