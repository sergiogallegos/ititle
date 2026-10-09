import XCTest

@testable import ITileCore

final class FocusedDiagnosticReportTests: XCTestCase {
  private let app = AppToken(pid: 42, generation: 1)
  private var window: WindowToken { WindowToken(app: app, serial: 1) }
  private var use: EvidenceUseContext {
    EvidenceUseContext(request: 1, activationRevision: 2, revocationGeneration: 1)
  }
  private var frame: Rect { Rect(x: 0, y: 30, width: 600, height: 400) }

  private func sample(
    token: WindowToken? = nil, sequence: UInt64 = 7,
    nested: NestedDialogScanSummary = .notScanned, finish: Double = 1.1,
    role: ProbeRead<String> = .value("AXWindow")
  ) -> FocusedWindowEvidence {
    FocusedWindowEvidence(
      token: token ?? window, environmentEpoch: 0, workerSequence: sequence,
      startedAt: 1, finishedAt: finish, role: role, subrole: .value("AXStandardWindow"),
      minimized: .value(false), fullscreen: .value(false), modal: .value(false),
      frame: .value(frame),
      positionSettable: .value(true), sizeSettable: .value(true), directSheetCount: .value(0),
      directSheetScanComplete: true, destructionNotification: .value(true),
      focusedWindowUnchanged: .value(true), expectedToken: nil, nestedDialogs: nested)
  }

  private func context(
    _ evidence: FocusedWindowEvidence, captured: EvidenceUseContext? = nil,
    epoch: UInt64 = 0, trusted: Bool = true, paused: Bool = false, stopped: Bool = false,
    retired: Bool = false, callerSequence: UInt64 = 0
  ) -> EvidenceAssessmentContext {
    EvidenceAssessmentContext(
      window: evidence.token, environmentEpoch: epoch, use: captured ?? use,
      registry: ProbeRegistrySnapshot(
        app: evidence.token.app, environmentEpoch: epoch,
        revision: 1, highestSerial: evidence.token.serial, windows: retired ? [] : [evidence.token]),
      latestWorkerSequence: callerSequence, trusted: trusted, paused: paused, stopped: stopped)
  }

  func testAcceptedHistoricalReportHasFixedProvenanceAndNoObservation() {
    let evidence = sample()
    let envelope = DiagnosticEvidenceEnvelope(evidence: evidence, useContext: use)
    var state = FocusedDiagnosticState(app: app)
    let result = state.consume(envelope, in: context(evidence), at: 1.2)
    XCTAssertTrue(result.acceptedHistoricalSample)
    XCTAssertEqual(result.assessment.freshness, .unmeasured)
    XCTAssertNil(result.assessment.observation)
    XCTAssertEqual(state.latestWorkerSequence, 7)
    XCTAssertTrue(result.report.contains("freshness=unmeasured (no diagnostic age policy)"))
    XCTAssertTrue(
      result.report.contains("owner-request=1; activation-revision=2; revocation-generation=1"))
    XCTAssertTrue(result.report.contains("acquisition=enclosingRequest; start=1.0; end=1.1"))
    XCTAssertTrue(
      result.report.contains(
        "source=uncorrelatedCGBounds; source-revision=1; coverage=unsupportedRequirement"))
    XCTAssertTrue(result.report.contains("source=boundedAXStructure"))
    XCTAssertTrue(result.report.contains("issues=structure.notScanned"))
    XCTAssertEqual(result.assessment.eligibilityAssessment.eligibility, .unknown)
    XCTAssertTrue(
      result.assessment.eligibilityAssessment.unproven.contains(.currentDesktopVisibility))
    XCTAssertTrue(result.assessment.eligibilityAssessment.unproven.contains(.nativeTabSafety))
    XCTAssertTrue(result.assessment.eligibilityAssessment.unproven.contains(.nestedDialogSafety))
  }

  func testDuplicateCallerWatermarkAndNewerIncompleteReplyUseOneAuthority() {
    var state = FocusedDiagnosticState(app: app)
    let original = sample()
    let envelope = DiagnosticEvidenceEnvelope(evidence: original, useContext: use)
    XCTAssertTrue(
      state.consume(envelope, in: context(original, callerSequence: UInt64.max), at: 1.2)
        .acceptedHistoricalSample)
    let duplicate = state.consume(envelope, in: context(original, callerSequence: 0), at: 1.3)
    XCTAssertFalse(duplicate.acceptedHistoricalSample)
    XCTAssertTrue(duplicate.assessment.rejections.contains(.staleSequence))
    let newer = sample(
      sequence: 8,
      nested: NestedDialogScanSummary(
        observedSheets: 0, observedDialogs: 0, examinedNodes: 2, issues: [.cycle],
        observedTabGroups: 1))
    let accepted = state.consume(
      DiagnosticEvidenceEnvelope(evidence: newer, useContext: use), in: context(newer), at: 1.3)
    XCTAssertTrue(accepted.acceptedHistoricalSample)
    XCTAssertTrue(
      accepted.report.contains("sample=findings; interval=enclosingRequest; issues=structure.cycle")
    )
    XCTAssertEqual(accepted.assessment.eligibilityAssessment.eligibility, .ineligible)
    XCTAssertEqual(state.latestWorkerSequence, 8)
    XCTAssertFalse(state.consume(envelope, in: context(original), at: 1.4).acceptedHistoricalSample)
  }

  func testRejectedContextDoesNotConsumeSequenceOrBecomeCurrentAfterRecovery() {
    let evidence = sample(sequence: 100)
    let envelope = DiagnosticEvidenceEnvelope(evidence: evidence, useContext: use)
    let contexts = [
      context(
        evidence,
        captured: EvidenceUseContext(request: 2, activationRevision: 2, revocationGeneration: 1)),
      context(
        evidence,
        captured: EvidenceUseContext(request: 1, activationRevision: 3, revocationGeneration: 1)),
      context(
        evidence,
        captured: EvidenceUseContext(request: 1, activationRevision: 2, revocationGeneration: 2)),
      context(evidence, epoch: 1), context(evidence, trusted: false),
      context(evidence, paused: true),
      context(evidence, stopped: true), context(evidence, retired: true),
    ]
    for current in contexts {
      var state = FocusedDiagnosticState(app: app)
      let rejected = state.consume(envelope, in: current, at: 1.2)
      XCTAssertFalse(rejected.acceptedHistoricalSample)
      XCTAssertNil(rejected.assessment.observation)
      XCTAssertEqual(state.latestWorkerSequence, 0)
      let fresh = sample()
      XCTAssertTrue(
        state.consume(
          DiagnosticEvidenceEnvelope(evidence: fresh, useContext: use), in: context(fresh), at: 1.2
        ).acceptedHistoricalSample)
    }
    // Resume with an advanced authoritative revocation generation still rejects the old envelope.
    var resumed = FocusedDiagnosticState(app: app)
    let afterResume = context(
      evidence,
      captured: EvidenceUseContext(request: 1, activationRevision: 2, revocationGeneration: 2))
    XCTAssertFalse(resumed.consume(envelope, in: afterResume, at: 1.2).acceptedHistoricalSample)
  }

  func testRetiredRouteCannotAdvanceReplacementProcessWatermark() {
    let old = sample(sequence: 100)
    let replacement = AppToken(pid: app.pid, generation: 2)
    var state = FocusedDiagnosticState(app: replacement)
    XCTAssertFalse(
      state.consume(
        DiagnosticEvidenceEnvelope(evidence: old, useContext: use), in: context(old), at: 1.2
      ).acceptedHistoricalSample)
    XCTAssertEqual(state.latestWorkerSequence, 0)
    let fresh = sample(token: WindowToken(app: replacement, serial: 1), sequence: 1)
    XCTAssertTrue(
      state.consume(
        DiagnosticEvidenceEnvelope(evidence: fresh, useContext: use), in: context(fresh), at: 1.2
      ).acceptedHistoricalSample)
    XCTAssertEqual(state.latestWorkerSequence, 1)
  }

  func testProvenanceAndPreviewShareRevocationButPreviewRemainsBlocked() {
    var preview = ReadOnlyPreview()
    preview.setTrust(true, at: 0)
    preview.attach(app, at: 0)
    preview.revoke(at: 0)
    let captured = EvidenceUseContext(
      request: 1, activationRevision: 2, revocationGeneration: preview.revocationGeneration)
    XCTAssertEqual(captured.revocationGeneration, 1)
    let evidence = sample()
    let registry = ProbeRegistrySnapshot(
      app: app, environmentEpoch: 0, revision: 1, highestSerial: 1, windows: [window])
    XCTAssertTrue(preview.synchronize(registry, at: 1.2))
    var state = FocusedDiagnosticState(app: app)
    let envelope = DiagnosticEvidenceEnvelope(evidence: evidence, useContext: captured)
    let historical = state.consume(envelope, in: context(evidence, captured: captured), at: 1.2)
    XCTAssertTrue(historical.acceptedHistoricalSample)
    XCTAssertNil(historical.assessment.observation)
    let result = preview.preview(
      evidence, target: frame,
      context: FocusRequestContext(app: app, environmentEpoch: 0, activationRevision: 2),
      currentApp: app, activationRevision: 2, at: 1.2)
    XCTAssertEqual(result.block, .planRejected)
    XCTAssertEqual(result.modelRejection, .invalidPlan)
    XCTAssertFalse(preview.isStopped)
    XCTAssertGreaterThan(preview.revocationGeneration, captured.revocationGeneration)
    let revoked = state.consume(
      envelope,
      in: context(
        evidence,
        captured: EvidenceUseContext(
          request: 1, activationRevision: 2, revocationGeneration: preview.revocationGeneration)),
      at: 1.3)
    XCTAssertTrue(revoked.assessment.rejections.contains(.staleContext))
    XCTAssertTrue(historical.report.contains("revocation-generation=1"))
  }

  func testMalformedAndFutureSamplesStayHistoricalWithoutWatermarkAdvance() {
    for evidence in [
      sample(finish: .nan), sample(finish: 2),
      sample(
        nested: NestedDialogScanSummary(
          observedSheets: -1, observedDialogs: 0, examinedNodes: 1, issues: [])),
    ] {
      var state = FocusedDiagnosticState(app: app)
      let result = state.consume(
        DiagnosticEvidenceEnvelope(evidence: evidence, useContext: use), in: context(evidence),
        at: 1.2)
      XCTAssertFalse(result.acceptedHistoricalSample)
      XCTAssertNil(result.assessment.observation)
      XCTAssertEqual(state.latestWorkerSequence, 0)
      XCTAssertTrue(result.report.contains("historical-sample-accepted=false"))
    }
    var state = FocusedDiagnosticState(app: app)
    let invalid = sample(finish: .nan)
    XCTAssertTrue(
      state.consume(
        DiagnosticEvidenceEnvelope(evidence: invalid, useContext: use), in: context(invalid),
        at: 1.2
      ).report.contains("freshness=invalid"))
  }

  func testFormattingAddsNoContentAndDoesNotInventAnAgePolicy() {
    let evidence = sample(role: .value("private title or document path"))
    var state = FocusedDiagnosticState(app: app)
    let result = state.consume(
      DiagnosticEvidenceEnvelope(evidence: evidence, useContext: use), in: context(evidence),
      at: 100)
    XCTAssertTrue(result.acceptedHistoricalSample)
    XCTAssertEqual(result.assessment.freshness, .unmeasured)
    XCTAssertNil(result.assessment.observation)
    XCTAssertFalse(result.report.contains("private title or document path"))
    XCTAssertFalse(result.report.contains("expiresAt"))
    XCTAssertEqual(evidence.startedAt, 1)
    XCTAssertEqual(evidence.finishedAt, 1.1)
  }
}
