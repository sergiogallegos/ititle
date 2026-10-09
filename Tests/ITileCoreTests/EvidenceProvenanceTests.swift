import XCTest

@testable import ITileCore

final class EvidenceProvenanceTests: XCTestCase {
  private let app = AppToken(pid: 42, generation: 1)
  private var window: WindowToken { WindowToken(app: app, serial: 1) }
  private var use: EvidenceUseContext {
    EvidenceUseContext(request: 4, activationRevision: 2, revocationGeneration: 3)
  }
  private var policy: DiagnosticAgePolicy { DiagnosticAgePolicy(maximumAge: 1, revision: 1) }
  private var frame: Rect { Rect(x: -100, y: -200, width: 600, height: 400) }
  private var complete: NestedDialogScanSummary {
    NestedDialogScanSummary(observedSheets: 0, observedDialogs: 0, examinedNodes: 1, issues: [])
  }

  private func sample(
    nested: NestedDialogScanSummary? = nil, bounds: OnScreenBoundsEvidence = .notSampled,
    sheets: ProbeRead<Int> = .value(0), directComplete: Bool = true,
    start: Double = 10, finish: Double = 10.1, sequence: UInt64 = 7,
    sampledWindow: WindowToken? = nil, geometry: ProbeRead<Rect>? = nil,
    capability: ProbeRead<Bool> = .value(true)
  ) -> FocusedWindowEvidence {
    FocusedWindowEvidence(
      token: sampledWindow ?? window, environmentEpoch: 3, workerSequence: sequence,
      startedAt: start, finishedAt: finish, role: .value("AXWindow"),
      subrole: .value("AXStandardWindow"),
      minimized: .value(false), fullscreen: .value(false), modal: .value(false),
      frame: geometry ?? .value(frame), positionSettable: capability, sizeSettable: capability,
      directSheetCount: sheets, directSheetScanComplete: directComplete,
      destructionNotification: .value(true), focusedWindowUnchanged: .value(true),
      expectedToken: nil,
      nestedDialogs: nested ?? complete, onScreenBounds: bounds)
  }

  private func context(
    for evidence: FocusedWindowEvidence, currentWindow: WindowToken? = nil,
    epoch: UInt64 = 3, captured: EvidenceUseContext? = nil, latest: UInt64 = 6,
    trusted: Bool = true, paused: Bool = false, stopped: Bool = false,
    registry: ProbeRegistrySnapshot? = nil
  ) -> EvidenceAssessmentContext {
    EvidenceAssessmentContext(
      window: currentWindow ?? evidence.token, environmentEpoch: epoch, use: captured ?? use,
      registry: registry
        ?? ProbeRegistrySnapshot(
          app: evidence.token.app, environmentEpoch: epoch, revision: 1,
          highestSerial: evidence.token.serial, windows: [evidence.token]),
      latestWorkerSequence: latest, trusted: trusted, paused: paused, stopped: stopped)
  }

  private func assess(_ evidence: FocusedWindowEvidence, at time: Double = 10.2)
    -> DiagnosticEvidenceAssessment
  {
    DiagnosticEvidenceEnvelope(evidence: evidence, useContext: use)
      .assess(in: context(for: evidence), policy: policy, at: time)
  }

  private func assertUnknownRequirements(_ result: DiagnosticEvidenceAssessment) {
    for reason in [
      UnprovenWindowRequirement.currentDesktopVisibility, .nativeTabSafety, .nestedDialogSafety,
    ] {
      XCTAssertTrue(result.eligibilityAssessment.unproven.contains(reason))
    }
    XCTAssertNotEqual(result.eligibilityAssessment.eligibility, .eligible)
    if let observation = result.observation {
      XCTAssertNotEqual(observation.eligibility, .eligible)
    }
  }

  func testCompleteNegativeSamplesRetainSourcesAndUnknownCoverage() throws {
    let evidence = sample(bounds: OnScreenBoundsEvidence(frame: frame, windows: []))
    let envelope = DiagnosticEvidenceEnvelope(evidence: evidence, useContext: use)
    XCTAssertEqual(envelope.records.map(\.requirement), EvidenceRequirement.allCases)
    XCTAssertEqual(
      envelope.records.map(\.source),
      [.uncorrelatedCGBounds, .boundedAXStructure, .boundedAXStructure])
    XCTAssertEqual(
      envelope.records.map(\.coverage),
      [.unsupportedRequirement, .positiveExclusionOnly, .positiveExclusionOnly])
    XCTAssertTrue(
      envelope.records.allSatisfy {
        $0.sourceRevision == 1 && $0.interval == .enclosingRequest && $0.outcome == .noFinding
      })
    let result = assess(evidence)
    XCTAssertEqual(result.rejections, [])
    let observation = try XCTUnwrap(result.observation)
    XCTAssertEqual(observation.eligibility, .unknown)
    XCTAssertEqual(observation.sampledAt, 10)
    XCTAssertEqual(observation.frame, frame)
    assertUnknownRequirements(result)
  }

  func testPositiveIncompleteAndAbsentSamplesPreserveLimitations() throws {
    let nested = NestedDialogScanSummary(
      observedSheets: 1, observedDialogs: 1, examinedNodes: 3,
      issues: [.cycle, .unsupported, .cycle], observedTabGroups: 1)
    let evidence = sample(nested: nested, sheets: .value(1), directComplete: false)
    let envelope = DiagnosticEvidenceEnvelope(evidence: evidence, useContext: use)
    XCTAssertEqual(envelope.records[1].outcome, .findings)
    XCTAssertEqual(envelope.records[1].issues, [.structural(.cycle), .structural(.unsupported)])
    XCTAssertTrue(envelope.records[2].issues.contains(.directSheetsIncomplete))
    let result = assess(evidence)
    XCTAssertEqual(try XCTUnwrap(result.observation).eligibility, .ineligible)
    XCTAssertTrue(result.eligibilityAssessment.exclusions.contains(.sheetPresent))
    XCTAssertTrue(result.eligibilityAssessment.exclusions.contains(.dialogPresent))
    XCTAssertTrue(result.eligibilityAssessment.exclusions.contains(.tabGroupPresent))
    assertUnknownRequirements(result)
    let absent = DiagnosticEvidenceEnvelope(
      evidence: sample(nested: .notScanned, sheets: .unavailable(-1), directComplete: false),
      useContext: use)
    XCTAssertTrue(
      absent.records.allSatisfy {
        $0.coverage == .unsupportedRequirement && $0.outcome == .notSampled
      })
    XCTAssertTrue(absent.records[2].issues.contains(.directSheetsUnavailable))
    assertUnknownRequirements(
      absent.assess(in: context(for: absent.evidence), policy: policy, at: 10.2))
  }

  func testBoundsCandidatesNeverBecomeIdentityOrVisibilityProof() {
    for count in 0...2 {
      let bounds = OnScreenBoundsEvidence(
        frame: frame,
        windows: Array(repeating: OnScreenWindowMetadata(layer: 0, frame: frame), count: count))
      let evidence = sample(bounds: bounds)
      let envelope = DiagnosticEvidenceEnvelope(evidence: evidence, useContext: use)
      XCTAssertEqual(envelope.records[0].outcome, count > 0 ? .findings : .noFinding)
      XCTAssertEqual(envelope.records[0].coverage, .unsupportedRequirement)
      XCTAssertEqual(assess(evidence).eligibilityAssessment.eligibility, .unknown)
      assertUnknownRequirements(assess(evidence))
    }
    for issue in [OnScreenBoundsIssue.metadataUnavailable, .budget, .cancelled] {
      let evidence = sample(bounds: OnScreenBoundsEvidence(issue: issue))
      let envelope = DiagnosticEvidenceEnvelope(evidence: evidence, useContext: use)
      XCTAssertEqual(envelope.records[0].outcome, .incomplete)
      XCTAssertEqual(envelope.records[0].issues, [.onScreenBounds(issue)])
      assertUnknownRequirements(assess(evidence))
    }
  }

  func testMalformedRecordsCannotRelabelEvidence() {
    let evidence = sample()
    let envelope = DiagnosticEvidenceEnvelope(evidence: evidence, useContext: use)
    let original = envelope.records[0]
    func altered(
      source: EvidenceSource? = nil, revision: UInt64 = 1, coverage: EvidenceCoverage? = nil,
      outcome: EvidenceSamplingOutcome? = nil, issues: [EvidenceIssue]? = nil
    ) -> RequirementEvidence {
      RequirementEvidence(
        requirement: original.requirement, source: source ?? original.source,
        sourceRevision: revision, coverage: coverage ?? original.coverage,
        outcome: outcome ?? original.outcome, issues: issues ?? original.issues,
        interval: .enclosingRequest)
    }
    var variants = [Array(envelope.records.dropLast()), [original, original, envelope.records[2]]]
    for replacement in [
      altered(source: .focusedAX), altered(revision: 0), altered(revision: 2),
      altered(coverage: .sampledPrerequisite), altered(outcome: .noFinding), altered(issues: []),
    ] {
      variants.append([replacement] + envelope.records.dropFirst())
    }
    for records in variants {
      let result = DiagnosticEvidenceEnvelope(evidence: evidence, useContext: use, records: records)
        .assess(in: context(for: evidence), policy: policy, at: 10.2)
      XCTAssertTrue(result.rejections.contains(.malformedRecords))
      XCTAssertNil(result.observation)
      assertUnknownRequirements(result)
    }
  }

  func testMalformedCountsRejectInsteadOfTrappingOrProjecting() {
    for nested in [
      NestedDialogScanSummary(observedSheets: -1, observedDialogs: 0, examinedNodes: 1, issues: []),
      NestedDialogScanSummary(observedSheets: 0, observedDialogs: 2, examinedNodes: 1, issues: []),
      NestedDialogScanSummary(observedSheets: 0, observedDialogs: 0, examinedNodes: 65, issues: []),
      NestedDialogScanSummary(
        observedSheets: 0, observedDialogs: 0, examinedNodes: Int.min, issues: []),
    ] {
      let result = assess(sample(nested: nested))
      XCTAssertTrue(result.rejections.contains(.malformedCounts))
      XCTAssertNil(result.observation)
    }
    for count in [-1, 17, Int.max] {
      XCTAssertTrue(assess(sample(sheets: .value(count))).rejections.contains(.malformedCounts))
    }
    let bounds = OnScreenBoundsEvidence(
      frame: frame,
      windows: Array(repeating: OnScreenWindowMetadata(layer: 0, frame: frame), count: 129),
      entryLimit: 129)
    XCTAssertTrue(assess(sample(bounds: bounds)).rejections.contains(.malformedCounts))
  }

  func testInvalidIntervalsFutureFinishIdentityAndReplayRejectCurrentUse() {
    for evidence in [
      sample(start: .nan), sample(start: -1), sample(finish: .infinity), sample(finish: 9),
    ] {
      let result = assess(evidence)
      XCTAssertTrue(result.rejections.contains(.invalidInterval))
      XCTAssertNil(result.observation)
    }
    XCTAssertTrue(assess(sample(finish: 10.3)).rejections.contains(.futureSample))
    XCTAssertTrue(assess(sample(sequence: 0)).rejections.contains(.staleSequence))
    XCTAssertTrue(assess(sample(sequence: 6)).rejections.contains(.staleSequence))
    for token in [
      WindowToken(app: app, serial: 0),
      WindowToken(app: AppToken(pid: 0, generation: 1), serial: 1),
      WindowToken(app: AppToken(pid: 42, generation: 0), serial: 1),
    ] {
      XCTAssertTrue(assess(sample(sampledWindow: token)).rejections.contains(.invalidIdentity))
    }
    for time in [Double.nan, .infinity, -1] {
      XCTAssertTrue(assess(sample(), at: time).rejections.contains(.invalidTime))
    }
  }

  func testNoPolicyAndExactExpiryDoNotRefreshTheEnvelope() throws {
    let evidence = sample()
    let envelope = DiagnosticEvidenceEnvelope(evidence: evidence, useContext: use)
    let current = context(for: evidence)
    let unmeasured = envelope.assess(in: current, at: 10.2)
    XCTAssertEqual(unmeasured.freshness, .unmeasured)
    XCTAssertNil(unmeasured.observation)
    XCTAssertEqual(unmeasured.rejections, [])
    let before = envelope.assess(in: current, policy: policy, at: 10.999)
    XCTAssertEqual(before.freshness, .unexpired(expiresAt: 11))
    XCTAssertNotNil(before.observation)
    for time in [11.0, 12.0] {
      let result = envelope.assess(in: current, policy: policy, at: time)
      XCTAssertEqual(result.freshness, .expired(expiresAt: 11))
      XCTAssertTrue(result.rejections.contains(.expired))
      XCTAssertNil(result.observation)
    }
    XCTAssertEqual(envelope.evidence.startedAt, 10)
    XCTAssertEqual(envelope.evidence.finishedAt, 10.1)
    XCTAssertTrue(assess(sample(finish: 11.5), at: 11.6).rejections.contains(.expired))
  }

  func testInvalidPolicyOverflowAndUnrepresentableExpiryReject() {
    let evidence = sample()
    let envelope = DiagnosticEvidenceEnvelope(evidence: evidence, useContext: use)
    for age in [0.0, -1, .nan, .infinity] {
      let result = envelope.assess(
        in: context(for: evidence), policy: DiagnosticAgePolicy(maximumAge: age, revision: 1),
        at: 10.2)
      XCTAssertEqual(result.freshness, .invalid)
      XCTAssertTrue(result.rejections.contains(.invalidPolicy))
      XCTAssertNil(result.observation)
    }
    XCTAssertTrue(
      envelope.assess(
        in: context(for: evidence), policy: DiagnosticAgePolicy(maximumAge: 1, revision: 0),
        at: 10.2
      ).rejections.contains(.invalidPolicy))
    let huge = sample(start: Double.greatestFiniteMagnitude, finish: Double.greatestFiniteMagnitude)
    let hugeEnvelope = DiagnosticEvidenceEnvelope(evidence: huge, useContext: use)
    for age in [1.0, Double.greatestFiniteMagnitude] {
      let result = hugeEnvelope.assess(
        in: context(for: huge), policy: DiagnosticAgePolicy(maximumAge: age, revision: 1),
        at: Double.greatestFiniteMagnitude)
      XCTAssertTrue(result.rejections.contains(.invalidExpiry))
      XCTAssertNil(result.observation)
    }
  }

  func testContextMismatchAndRevocationCannotBeRepairedByLongerPolicy() {
    let evidence = sample()
    let envelope = DiagnosticEvidenceEnvelope(evidence: evidence, useContext: use)
    let replacement = WindowToken(app: AppToken(pid: app.pid, generation: 2), serial: 1)
    let contexts = [
      context(for: evidence, currentWindow: WindowToken(app: app, serial: 2)),
      context(for: evidence, currentWindow: replacement), context(for: evidence, epoch: 4),
      context(
        for: evidence,
        captured: EvidenceUseContext(request: 5, activationRevision: 2, revocationGeneration: 3)),
      context(
        for: evidence,
        captured: EvidenceUseContext(request: 4, activationRevision: 3, revocationGeneration: 3)),
      context(
        for: evidence,
        captured: EvidenceUseContext(request: 4, activationRevision: 2, revocationGeneration: 4)),
      context(
        for: evidence,
        captured: EvidenceUseContext(request: 0, activationRevision: 2, revocationGeneration: 3)),
      context(for: evidence, trusted: false), context(for: evidence, paused: true),
      context(for: evidence, stopped: true),
    ]
    for current in contexts {
      let result = envelope.assess(
        in: current, policy: DiagnosticAgePolicy(maximumAge: 100, revision: 2), at: 10.2)
      XCTAssertFalse(result.rejections.isEmpty)
      XCTAssertNil(result.observation)
      assertUnknownRequirements(result)
    }
  }

  func testRetiredAbsentAndMalformedRegistriesReject() {
    let evidence = sample()
    let envelope = DiagnosticEvidenceEnvelope(evidence: evidence, useContext: use)
    for registry in [
      ProbeRegistrySnapshot(
        app: app, environmentEpoch: 3, revision: 2, highestSerial: 1, windows: []),
      ProbeRegistrySnapshot(
        app: app, environmentEpoch: 3, revision: 0, highestSerial: 1, windows: [window]),
      ProbeRegistrySnapshot(
        app: app, environmentEpoch: 3, revision: 1, highestSerial: 0, windows: [window]),
      ProbeRegistrySnapshot(
        app: AppToken(pid: app.pid, generation: 2), environmentEpoch: 3, revision: 1,
        highestSerial: 1, windows: [window]),
    ] {
      let result = envelope.assess(
        in: context(for: evidence, registry: registry), policy: policy, at: 10.2)
      XCTAssertTrue(result.rejections.contains(.registryRejected))
      XCTAssertNil(result.observation)
    }
    let missing = EvidenceAssessmentContext(
      window: nil, environmentEpoch: 3, use: use, registry: nil,
      latestWorkerSequence: 6, trusted: true, paused: false, stopped: false)
    let rejected = envelope.assess(in: missing, policy: policy, at: 10.2)
    XCTAssertTrue(rejected.rejections.contains(.registryRejected))
    XCTAssertTrue(rejected.rejections.contains(.staleContext))
  }

  func testIncompleteNewerSampleAndGeometryCapabilityProjectionStayConservative() throws {
    let old = sample()
    let fresh = sample(nested: .notScanned, sequence: 8, capability: .unavailable(-1))
    let oldResult = DiagnosticEvidenceEnvelope(evidence: old, useContext: use)
      .assess(in: context(for: old, latest: 8), policy: policy, at: 10.2)
    XCTAssertTrue(oldResult.rejections.contains(.staleSequence))
    let result = DiagnosticEvidenceEnvelope(evidence: fresh, useContext: use)
      .assess(in: context(for: fresh, latest: 7), policy: policy, at: 10.2)
    let observation = try XCTUnwrap(result.observation)
    XCTAssertEqual(observation.positionSettable, .unknown)
    XCTAssertEqual(observation.eligibility, .unknown)
    assertUnknownRequirements(result)
    for geometry in [
      ProbeRead<Rect>.unavailable(-1), .value(Rect(x: 0, y: 0, width: 0, height: 1)),
    ] {
      let result = assess(sample(geometry: geometry))
      XCTAssertTrue(result.rejections.contains(.invalidProjection))
      XCTAssertNil(result.observation)
    }
  }
}
