import XCTest

@testable import ITileCore

final class ReadOnlyPreviewTests: XCTestCase {
  private let app = AppToken(pid: 42, generation: 1)
  private let target = Rect(x: -1920, y: 30, width: 1920, height: 1050)

  private func ready() -> ReadOnlyPreview {
    var preview = ReadOnlyPreview()
    preview.setTrust(true, at: 0)
    preview.attach(app, at: 0)
    XCTAssertTrue(preview.synchronize(snapshot([1, 2], revision: 1, watermark: 2), at: 0))
    return preview
  }

  private func snapshot(
    _ serials: [UInt64], revision: UInt64, watermark: UInt64, epoch: UInt64 = 0,
    app: AppToken? = nil
  ) -> ProbeRegistrySnapshot {
    let app = app ?? self.app
    return ProbeRegistrySnapshot(
      app: app, environmentEpoch: epoch, revision: revision, highestSerial: watermark,
      windows: Set(serials.map { WindowToken(app: app, serial: $0) }))
  }

  private func evidence(
    app: AppToken? = nil, serial: UInt64 = 1, epoch: UInt64 = 0,
    sequence: UInt64 = 1, start: Double = 1, finish: Double = 1.1,
    frame: ProbeRead<Rect>? = nil, size: ProbeRead<Bool> = .value(true)
  ) -> FocusedWindowEvidence {
    FocusedWindowEvidence(
      token: WindowToken(app: app ?? self.app, serial: serial), environmentEpoch: epoch,
      workerSequence: sequence, startedAt: start, finishedAt: finish,
      role: .value("AXWindow"), subrole: .value("AXStandardWindow"),
      minimized: .value(false), fullscreen: .value(false), modal: .value(false),
      frame: frame ?? .value(target), positionSettable: .value(true), sizeSettable: size,
      directSheetCount: .value(0), directSheetScanComplete: true,
      destructionNotification: .value(true), focusedWindowUnchanged: .value(true),
      expectedToken: nil)
  }

  private func run(
    _ preview: inout ReadOnlyPreview, _ sample: FocusedWindowEvidence,
    contextApp: AppToken? = nil, contextEpoch: UInt64? = nil,
    revision: UInt64 = 4, now: Double = 1.1, target: Rect? = nil
  ) -> ReadOnlyPreviewResult {
    preview.preview(
      sample, target: target ?? self.target,
      context: FocusRequestContext(
        app: contextApp ?? app, environmentEpoch: contextEpoch ?? preview.environmentEpoch,
        activationRevision: 4),
      currentApp: contextApp ?? app, activationRevision: revision, at: now)
  }

  func testRealProjectionBlocksBothUnknownAndPositiveExclusion() {
    for capability: ProbeRead<Bool> in [.value(true), .value(false)] {
      var preview = ready()
      let sample = evidence(size: capability)
      XCTAssertNotEqual(sample.eligibility, .eligible)
      let result = run(&preview, sample)
      XCTAssertEqual(result.block, .planRejected)
      XCTAssertEqual(result.modelRejection, .invalidPlan)
      XCTAssertEqual(result.target, target)
      XCTAssertEqual(preview.observationCount, 1)
      XCTAssertTrue(result.report.contains("No window was enrolled or moved"))
    }
  }

  func testOldSequenceAndExpiredDeliveryCannotReuseObservation() {
    var preview = ready()
    XCTAssertEqual(run(&preview, evidence()).block, .planRejected)
    XCTAssertEqual(run(&preview, evidence()).block, .observationRejected)
    XCTAssertEqual(
      run(&preview, evidence(sequence: 2, start: 1.2, finish: 1.3), now: 2).modelRejection,
      .staleObservation)
  }

  func testPauseResumeRequiresSampleAfterRevocation() {
    var preview = ready()
    preview.setPaused(true, at: 1)
    XCTAssertEqual(run(&preview, evidence()).block, .paused)
    preview.setPaused(false, at: 2)
    XCTAssertEqual(run(&preview, evidence(), now: 2).block, .observationRejected)
    XCTAssertEqual(
      run(&preview, evidence(sequence: 2, start: 2.1, finish: 2.2), now: 2.2).block,
      .planRejected)
  }

  func testPermissionLossChangesAuthoritativeEpochAndRecoveryRejectsOldEvidence() {
    var preview = ready()
    preview.setTrust(false, at: 1)
    XCTAssertEqual(preview.environmentEpoch, 1)
    preview.setTrust(false, at: 1.1)
    XCTAssertEqual(preview.environmentEpoch, 1)
    XCTAssertEqual(run(&preview, evidence()).block, .permissionRequired)
    preview.setTrust(true, at: 2)
    XCTAssertEqual(run(&preview, evidence(), now: 2).block, .staleContext)
    XCTAssertEqual(
      run(&preview, evidence(epoch: 1, start: 2.1, finish: 2.2), now: 2.2).block,
      .planRejected)
  }

  func testDesktopInvalidationAndActivationRevisionRejectPendingResult() {
    var preview = ready()
    preview.invalidate(at: 1)
    XCTAssertEqual(run(&preview, evidence()).block, .staleContext)
    XCTAssertEqual(run(&preview, evidence(epoch: 1), revision: 5).block, .staleContext)
    XCTAssertEqual(run(&preview, evidence(epoch: 1), contextEpoch: 0).block, .staleContext)
    XCTAssertEqual(run(&preview, evidence(epoch: 1)).block, .planRejected)
  }

  func testRequestReplacementRevokesEvidenceWithoutChangingDesktopEpoch() {
    var preview = ready()
    preview.revoke(at: 1.2)
    XCTAssertEqual(preview.environmentEpoch, 0)
    XCTAssertEqual(run(&preview, evidence(), now: 1.3).block, .observationRejected)
    XCTAssertEqual(
      run(&preview, evidence(sequence: 2, start: 1.3, finish: 1.4), now: 1.4).block,
      .planRejected)
  }

  func testProcessReplacementCannotAcceptOldToken() {
    var preview = ready()
    preview.terminate(app, at: 0.5)
    let replacement = AppToken(pid: app.pid, generation: 2)
    preview.attach(replacement, at: 0.5)
    XCTAssertTrue(
      preview.synchronize(
        snapshot([1], revision: 1, watermark: 1, app: replacement), at: 0.5))
    XCTAssertEqual(run(&preview, evidence()).block, .registryRejected)
    XCTAssertEqual(
      run(&preview, evidence(app: replacement), contextApp: replacement).block, .planRejected)
    XCTAssertEqual(
      run(&preview, evidence(app: replacement, sequence: 2)).block, .staleContext)
  }

  func testInvalidProjectionAndFutureCompletionDoNotReachPlan() {
    var preview = ready()
    XCTAssertEqual(run(&preview, evidence(frame: .invalidType)).block, .invalidProjection)
    XCTAssertEqual(run(&preview, evidence(finish: 0.9)).block, .invalidProjection)
    XCTAssertEqual(run(&preview, evidence(sequence: 0)).block, .invalidProjection)
    XCTAssertEqual(run(&preview, evidence(finish: 2)).block, .staleContext)
    XCTAssertEqual(preview.observationCount, 0)
    let invalid = Rect(x: .infinity, y: 0, width: 1, height: 1)
    XCTAssertEqual(run(&preview, evidence(), target: invalid).block, .invalidTarget)
    XCTAssertEqual(preview.observationCount, 0)
  }

  func testQuitIsTerminalEvenWithInvalidClockAndPermissionRecovery() {
    var preview = ready()
    preview.stop(at: .nan)
    preview.setTrust(false, at: 1)
    preview.setTrust(true, at: 2)
    preview.setPaused(false, at: 2)
    XCTAssertEqual(run(&preview, evidence(), now: 2).block, .stopped)
  }

  func testCompleteRegistryAllowsRetainedWindowsInEitherObservationOrder() {
    var preview = ready()
    XCTAssertEqual(run(&preview, evidence(serial: 2)).block, .planRejected)
    XCTAssertEqual(
      run(&preview, evidence(serial: 1, sequence: 2, start: 1.2, finish: 1.3), now: 1.3).block,
      .planRejected)
    XCTAssertEqual(preview.observationCount, 2)
  }

  func testDisplayTargetPreservesNegativeOriginsAndRejectsOffscreenOrInvalidGeometry() {
    let other = Rect(x: 0, y: 30, width: 1920, height: 1050)
    XCTAssertEqual(ReadOnlyPreview.target(for: target, areas: [other, target]), target)
    XCTAssertNil(ReadOnlyPreview.target(for: target, areas: [other]))
    XCTAssertNil(ReadOnlyPreview.target(for: target, areas: []))
    let invalid = Rect(x: .nan, y: 0, width: 10, height: 10)
    XCTAssertNil(ReadOnlyPreview.target(for: invalid, areas: [target]))
    XCTAssertNil(ReadOnlyPreview.target(for: target, areas: [invalid]))
    let edge = Rect(x: -10, y: 100, width: 20, height: 20)
    XCTAssertEqual(ReadOnlyPreview.target(for: edge, areas: [target, other]), other)
  }

  func testWindowChurnRetiresRecordsWithoutReachingCapacity() {
    var preview = ReadOnlyPreview()
    preview.setTrust(true, at: 0)
    preview.attach(app, at: 0)
    for index in 1...256 {
      let start = Double(index)
      // The platform tracks at most 64 windows per app. This test exercises
      // replacement churn rather than an impossible 256-window worker snapshot.
      XCTAssertTrue(
        preview.synchronize(
          snapshot([UInt64(index)], revision: UInt64(index + 1), watermark: UInt64(index)),
          at: start))
      XCTAssertEqual(
        run(
          &preview,
          evidence(
            serial: UInt64(index), sequence: UInt64(index),
            start: start, finish: start + 0.1), now: start + 0.1
        ).block,
        .planRejected)
    }
    XCTAssertEqual(preview.observationCount, 1)
    XCTAssertFalse(preview.synchronize(snapshot([1], revision: 258, watermark: 256), at: 257))
    XCTAssertEqual(
      run(&preview, evidence(serial: 1, sequence: 257, start: 257, finish: 257.1), now: 257.1)
        .block,
      .observationRejected)
    XCTAssertEqual(preview.observationCount, 1)
  }

  func testMissingRegistryCannotIntroduceWindowFromEvidence() {
    var preview = ReadOnlyPreview()
    preview.setTrust(true, at: 0)
    preview.attach(app, at: 0)
    XCTAssertEqual(run(&preview, evidence()).block, .registryRejected)
    XCTAssertEqual(preview.observationCount, 0)
  }

  func testRegistryRetirementRejectsLateEvidenceAndSnapshotResurrection() {
    var preview = ready()
    XCTAssertEqual(run(&preview, evidence()).block, .planRejected)
    XCTAssertTrue(preview.synchronize(snapshot([2], revision: 2, watermark: 2), at: 1.2))
    XCTAssertEqual(preview.observationCount, 0)
    XCTAssertEqual(
      run(&preview, evidence(sequence: 2, start: 1.3, finish: 1.4), now: 1.4).block,
      .observationRejected)
    XCTAssertFalse(preview.synchronize(snapshot([1, 2], revision: 1, watermark: 2), at: 1.5))
    XCTAssertFalse(preview.synchronize(snapshot([1, 2], revision: 3, watermark: 2), at: 1.5))
    XCTAssertTrue(preview.synchronize(snapshot([2, 3], revision: 3, watermark: 3), at: 1.5))
    XCTAssertEqual(
      run(&preview, evidence(serial: 3, sequence: 3, start: 1.6, finish: 1.7), now: 1.7).block,
      .planRejected)
  }

  func testMalformedStaleEpochAndReplacedProcessSnapshotsCannotChangeRecords() {
    var preview = ready()
    XCTAssertEqual(run(&preview, evidence()).block, .planRejected)
    XCTAssertFalse(preview.synchronize(snapshot([0], revision: 2, watermark: 2), at: 1.2))
    XCTAssertFalse(preview.synchronize(snapshot([3], revision: 2, watermark: 2), at: 1.2))
    XCTAssertFalse(preview.synchronize(snapshot([1], revision: 2, watermark: 1), at: 1.2))
    XCTAssertFalse(preview.synchronize(snapshot([], revision: 2, watermark: 2, epoch: 1), at: 1.2))
    XCTAssertEqual(preview.observationCount, 1)
    preview.terminate(app, at: 1.3)
    XCTAssertFalse(preview.synchronize(snapshot([1], revision: 2, watermark: 2), at: 1.4))
    XCTAssertEqual(preview.observationCount, 0)
  }

  func testGlobalAndPerWorkerRegistryBoundsRejectAtomicallyAndRecoverAfterRetirement() {
    var preview = ReadOnlyPreview()
    preview.setTrust(true, at: 0)
    for index in 1...5 {
      let app = AppToken(pid: Int32(index), generation: UInt64(index))
      preview.attach(app, at: 0)
      XCTAssertEqual(
        preview.synchronize(
          snapshot(Array(1...64), revision: 1, watermark: 64, app: app), at: 0),
        index <= 4)
    }
    let fifth = AppToken(pid: 5, generation: 5)
    XCTAssertFalse(
      preview.synchronize(
        snapshot(Array(1...65), revision: 2, watermark: 65, app: fifth), at: 0))
    preview.terminate(AppToken(pid: 1, generation: 1), at: 0)
    XCTAssertTrue(
      preview.synchronize(
        snapshot(Array(1...64), revision: 1, watermark: 64, app: fifth), at: 0))
  }

}
