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
    expected: WindowToken? = nil,
    destruction: ProbeRead<Bool> = .value(true),
    startedAt: Double = 10, finishedAt: Double = 10.1, sequence: UInt64 = 7,
    nestedDialogs: NestedDialogScanSummary = .notScanned,
    onScreenBounds: OnScreenBoundsEvidence = .notSampled
  ) -> FocusedWindowEvidence {
    FocusedWindowEvidence(
      token: token, environmentEpoch: 3, workerSequence: sequence,
      startedAt: startedAt, finishedAt: finishedAt, role: role, subrole: subrole,
      minimized: minimized,
      fullscreen: fullscreen, modal: modal, frame: frame, positionSettable: capability,
      sizeSettable: capability, directSheetCount: sheets, directSheetScanComplete: complete,
      destructionNotification: destruction, focusedWindowUnchanged: focus, expectedToken: expected,
      nestedDialogs: nestedDialogs, onScreenBounds: onScreenBounds)
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

  func testSuccessfulGenericReadsRetainAllUnsupportedScopeRequirements() {
    let assessment = evidence(expected: token).eligibilityAssessment
    XCTAssertTrue(assessment.exclusions.isEmpty)
    XCTAssertEqual(
      assessment.unproven, [.currentDesktopVisibility, .nativeTabSafety, .nestedDialogSafety])
    XCTAssertEqual(assessment.eligibility, .unknown)
    XCTAssertTrue(assessment.report.contains("eligibility-exclusions=none"))
    // Matching token, negative coordinates and successful attributes supply no
    // evidence for the three unsupported scope requirements.
    XCTAssertTrue(assessment.report.contains("currentDesktopVisibility"))
  }

  func testPositiveExclusionWinsWithoutDiscardingMissingEvidence() {
    let assessment = evidence(
      minimized: .value(true), modal: .unavailable(-25204), sheets: .value(2), complete: false,
      destruction: .unavailable(-25207)
    ).eligibilityAssessment
    XCTAssertEqual(assessment.eligibility, .ineligible)
    XCTAssertEqual(assessment.exclusions, [.minimized, .sheetPresent])
    for requirement in [
      UnprovenWindowRequirement.modalState, .destructionContinuity, .completeDirectSheetScan,
      .currentDesktopVisibility, .nativeTabSafety, .nestedDialogSafety,
    ] { XCTAssertTrue(assessment.unproven.contains(requirement)) }
  }

  func testUnsupportedReadsRemainUnknownRatherThanInventingWindowState() {
    let assessment = evidence(
      role: .invalidType, subrole: .unavailable(-25212), capability: .unavailable(-25204),
      sheets: .value(-1), focus: .invalidType, destruction: .value(false)
    ).eligibilityAssessment
    XCTAssertTrue(assessment.exclusions.isEmpty)
    XCTAssertEqual(assessment.eligibility, .unknown)
    for requirement in [
      UnprovenWindowRequirement.role, .subrole, .positionCapability, .sizeCapability,
      .directSheets, .focusedContinuity, .destructionContinuity,
    ] { XCTAssertTrue(assessment.unproven.contains(requirement)) }
  }

  func testNestedPositiveFindingsExcludeEvenWhenScanIsIncomplete() {
    let summary = NestedDialogScanner.scan(
      root: 0, equal: ==, stop: { nil },
      read: { _ in
        .success(StructuralNodeRead(role: .value("AXSheet"), subrole: .value("AXDialog")))
      },
      children: { node, _ in
        if node == 0 { return .success(StructuralChildren(nodes: [1], truncated: false)) }
        return .failure(StructuralScanFailure(.unsupported))
      })
    let observed = evidence(nestedDialogs: summary)
    XCTAssertEqual(observed.eligibilityAssessment.exclusions, [.sheetPresent, .dialogPresent])
    XCTAssertEqual(observed.controlObservation?.eligibility, .ineligible)
    XCTAssertTrue(observed.report.contains("outcomes=unsupported"))
  }

  func testTabGroupExclusionSurvivesIncompleteScansAndBlocksControl() throws {
    for issues in [[NestedDialogScanIssue](), [.unsupported], [.cycle], [.budget], [.cancelled]] {
      let summary = NestedDialogScanSummary(
        observedSheets: 0, observedDialogs: 0, examinedNodes: 2, issues: issues,
        observedTabGroups: 1)
      let observed = evidence(nestedDialogs: summary)
      XCTAssertEqual(observed.eligibilityAssessment.exclusions, [.tabGroupPresent])
      XCTAssertTrue(observed.eligibilityAssessment.unproven.contains(.nativeTabSafety))
      let control = try XCTUnwrap(observed.controlObservation)
      XCTAssertEqual(control.eligibility, .ineligible)
      var model = ControlModel()
      _ = model.reduce(.permission(true), at: 0)
      _ = model.reduce(.attach(app), at: 0)
      for _ in 0..<3 { _ = model.reduce(.environmentChanged(.environmentChanged), at: 0) }
      _ = model.reduce(.observation(control), at: 10.1)
      XCTAssertTrue(
        model.reduce(.tile([token: control.frame]), at: 10.1).contains(.rejected(.invalidPlan)))
      XCTAssertEqual(model.state, .paused)
    }
  }

  func testCompleteStructuralSampleDoesNotClearSafetyRequirements() {
    let summary = NestedDialogScanner.scan(
      root: 0, equal: ==, stop: { nil },
      read: { _ in .failure(StructuralScanFailure(.readFailure)) },
      children: { _, _ in .success(StructuralChildren<Int>(nodes: [], truncated: false)) })
    XCTAssertTrue(summary.complete)
    let observed = evidence(nestedDialogs: summary)
    XCTAssertEqual(observed.eligibility, .unknown)
    XCTAssertEqual(
      observed.eligibilityAssessment.unproven,
      [.currentDesktopVisibility, .nativeTabSafety, .nestedDialogSafety])
  }

  func testOnScreenBoundsCannotClearVisibilityOrAdmitControl() throws {
    let frame = Rect(x: -100, y: -400, width: 800, height: 600)
    let window = OnScreenWindowMetadata(layer: 0, frame: frame)
    for sample in [
      OnScreenBoundsEvidence.notSampled,
      OnScreenBoundsEvidence(issue: .metadataUnavailable),
      OnScreenBoundsEvidence(frame: frame, windows: []),
      OnScreenBoundsEvidence(frame: frame, windows: [window]),
      OnScreenBoundsEvidence(frame: frame, windows: [window, window]),
      OnScreenBoundsEvidence(frame: frame, windows: [window], issues: [.entryLimit]),
    ] {
      let observed = evidence(onScreenBounds: sample)
      XCTAssertEqual(observed.eligibility, .unknown)
      XCTAssertTrue(observed.eligibilityAssessment.exclusions.isEmpty)
      XCTAssertTrue(observed.eligibilityAssessment.unproven.contains(.currentDesktopVisibility))
      let control = try XCTUnwrap(observed.controlObservation)
      var model = ControlModel()
      _ = model.reduce(.permission(true), at: 0)
      _ = model.reduce(.attach(app), at: 0)
      for _ in 0..<3 { _ = model.reduce(.environmentChanged(.environmentChanged), at: 0) }
      _ = model.reduce(.observation(control), at: 10.1)
      XCTAssertTrue(
        model.reduce(.tile([token: control.frame]), at: 10.1).contains(.rejected(.invalidPlan)))
    }
  }

  func testMalformedGeometryCannotReachControlProjection() {
    let frames = [
      Rect(x: .nan, y: 0, width: 800, height: 600),
      Rect(x: 0, y: .infinity, width: 800, height: 600),
      Rect(x: 0, y: 0, width: 0, height: 600),
      Rect(x: 0, y: 0, width: 800, height: -1),
      Rect(x: .greatestFiniteMagnitude, y: 0, width: .greatestFiniteMagnitude, height: 1),
    ]
    for frame in frames {
      let sample = evidence(frame: .value(frame))
      XCTAssertNil(sample.controlObservation)
      XCTAssertEqual(sample.eligibility, .unknown)
      XCTAssertTrue(sample.eligibilityAssessment.unproven.contains(.geometry))
    }
    XCTAssertNotNil(evidence().controlObservation)  // Valid negative origins are preserved.
  }

  func testInvalidIntervalsAndZeroSequencesCannotReachControlProjection() {
    let samples = [
      evidence(startedAt: .nan), evidence(finishedAt: .infinity),
      evidence(startedAt: -1), evidence(finishedAt: 9), evidence(sequence: 0),
    ]
    for sample in samples {
      XCTAssertNil(sample.controlObservation)
      XCTAssertEqual(sample.eligibility, .unknown)
    }
    XCTAssertTrue(evidence(sequence: 0).eligibilityAssessment.unproven.contains(.workerSequence))
    XCTAssertNotNil(evidence(startedAt: 0, finishedAt: 0, sequence: 1).controlObservation)
  }
}
