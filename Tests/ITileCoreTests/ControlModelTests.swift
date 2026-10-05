import XCTest
@testable import ITileCore

final class ControlModelTests: XCTestCase {
    private let a = AppToken(pid: 10, generation: 1)
    private let b = AppToken(pid: 20, generation: 2)
    private let original = Rect(x: 10, y: 10, width: 600, height: 400)
    private let destination = Rect(x: 0, y: 40, width: 800, height: 600)

    private func token(_ app: AppToken, _ serial: UInt64 = 1) -> WindowToken {
        WindowToken(app: app, serial: serial)
    }

    private func sample(_ window: WindowToken, sequence: UInt64 = 1, epoch: UInt64 = 0,
                        time: Double = 1, eligibility: ControlEligibility = .eligible,
                        capability: ControlCapability = .supported, frame: Rect? = nil) -> WindowObservation {
        WindowObservation(token: window, frame: frame ?? original, eligibility: eligibility,
                          positionSettable: capability, sizeSettable: capability,
                          environmentEpoch: epoch, workerSequence: sequence, sampledAt: time)
    }

    private func ready(twoApps: Bool = false, limit: Int = 256) -> ControlModel {
        var model = ControlModel(maximumWindows: limit)
        XCTAssertEqual(model.reduce(.permission(true), at: 0), [])
        XCTAssertEqual(model.reduce(.attach(a), at: 0), [])
        XCTAssertEqual(model.reduce(.observation(sample(token(a))), at: 1), [])
        if twoApps {
            XCTAssertEqual(model.reduce(.attach(b), at: 1), [])
            XCTAssertEqual(model.reduce(.observation(sample(token(b))), at: 1), [])
        }
        return model
    }

    private func dispatch(_ model: inout ControlModel, app: AppToken, at time: Double = 1) throws -> FrameTarget {
        let effects = model.reduce(.dispatch(app), at: time)
        guard case .prepare(let target) = effects.first else {
            XCTFail("Expected prepared work, got \(effects)"); throw TestFailure.unexpectedEffect
        }
        return target
    }

    private func admit(_ model: inout ControlModel, target: FrameTarget,
                       setter: SimulatedSetter, at time: Double = 1) throws -> SetterPermit {
        let effects = model.reduce(.admit(target, setter), at: time)
        guard case .perform(let permit) = effects.first else {
            XCTFail("Expected simulated admission, got \(effects)"); throw TestFailure.unexpectedEffect
        }
        return permit
    }

    private func runToReadback(_ model: inout ControlModel, target: FrameTarget) throws {
        let size = try admit(&model, target: target, setter: .size)
        XCTAssertEqual(model.reduce(.setterFinished(size, .succeeded), at: 1), [])
        let position = try admit(&model, target: target, setter: .position)
        XCTAssertEqual(model.reduce(.setterFinished(position, .succeeded), at: 1), [.readback(target)])
    }

    private enum TestFailure: Error { case unexpectedEffect }

    func testStartupAndPermissionNeverAdmitWithoutExplicitTile() {
        var model = ControlModel()
        XCTAssertEqual(model.state, .permissionRequired)
        XCTAssertEqual(model.reduce(.tile([token(a): destination]), at: 0), [.rejected(.permission)])
        _ = model.reduce(.permission(true), at: 0)
        XCTAssertEqual(model.state, .paused)
        XCTAssertEqual(model.reduce(.dispatch(a), at: 0), [])
        XCTAssertEqual(model.pending.count, 0)
    }

    func testUnknownIneligibleAndUnknownCapabilitiesBlockWholePlan() {
        let cases: [(ControlEligibility, ControlCapability)] = [
            (.unknown, .supported), (.ineligible, .supported),
            (.eligible, .unknown), (.eligible, .unsupported)
        ]
        for (eligibility, capability) in cases {
            var model = ready(twoApps: true)
            _ = model.reduce(.observation(sample(token(b), sequence: 2,
                eligibility: eligibility, capability: capability)), at: 1)
            let effects = model.reduce(.tile([token(a): destination, token(b): destination]), at: 1)
            XCTAssertTrue(effects.contains(.rejected(.invalidPlan)))
            XCTAssertEqual(model.state, .paused)
            XCTAssertTrue(model.pending.isEmpty)
        }
    }

    func testObservationFreshnessSequenceEpochAndGeometryAreValidated() {
        var model = ready()
        for bad in [sample(token(a)), sample(token(a), sequence: 2, epoch: 1),
                    sample(token(a), sequence: 2, time: 2),
                    sample(token(a), sequence: 2, time: .nan),
                    sample(token(a), sequence: 2, frame: Rect(x: .infinity, y: 0, width: 1, height: 1))] {
            XCTAssertEqual(model.reduce(.observation(bad), at: 1), [.rejected(.staleObservation)])
        }
        XCTAssertTrue(model.reduce(.tile([token(a): destination]), at: 1.6).contains(.rejected(.invalidPlan)))
        XCTAssertEqual(model.state, .paused)
    }

    func testInvalidPlanDoesNotPartiallyReplaceDesiredState() {
        var model = ready()
        _ = model.reduce(.tile([token(a): destination]), at: 1)
        let invalid = Rect(x: 0, y: 0, width: -1, height: 100)
        _ = model.reduce(.tile([token(a): invalid]), at: 1)
        XCTAssertEqual(model.desired[token(a)], destination)
        XCTAssertEqual(model.layoutRevision, 1)
        XCTAssertEqual(model.state, .paused)
        XCTAssertTrue(model.pending.isEmpty)
    }

    func testPauseBeforeDispatchAndBeforeFirstSetter() throws {
        var model = ready()
        _ = model.reduce(.tile([token(a): destination]), at: 1)
        _ = model.reduce(.pause, at: 1)
        XCTAssertEqual(model.reduce(.dispatch(a), at: 1), [])
        _ = model.reduce(.observation(sample(token(a), sequence: 2)), at: 1)
        _ = model.reduce(.tile([token(a): destination]), at: 1)
        let target = try dispatch(&model, app: a)
        _ = model.reduce(.pause, at: 1)
        XCTAssertEqual(model.reduce(.admit(target, .size), at: 1), [.rejected(.staleWork)])
        XCTAssertEqual(model.inFlightCount, 0)
    }

    func testPauseBetweenSettersPreventsPosition() throws {
        var model = ready()
        _ = model.reduce(.tile([token(a): destination]), at: 1)
        let target = try dispatch(&model, app: a)
        let size = try admit(&model, target: target, setter: .size)
        _ = model.reduce(.setterFinished(size, .succeeded), at: 1)
        _ = model.reduce(.pause, at: 1)
        XCTAssertEqual(model.reduce(.admit(target, .position), at: 1), [.rejected(.staleWork)])
        XCTAssertEqual(model.state, .paused)
    }

    func testInFlightCallSurvivesPauseButLateFinishCannotContinue() throws {
        var model = ready()
        _ = model.reduce(.tile([token(a): destination]), at: 1)
        let target = try dispatch(&model, app: a)
        let size = try admit(&model, target: target, setter: .size)
        _ = model.reduce(.pause, at: 1)
        XCTAssertEqual(model.inFlightCount, 1)
        XCTAssertEqual(model.reduce(.setterFinished(size, .succeeded), at: 1.1), [.reconcile(a)])
        XCTAssertEqual(model.inFlightCount, 0)
        XCTAssertTrue(model.dirty.contains(token(a)))
        XCTAssertEqual(model.desired[token(a)], destination)
        XCTAssertEqual(model.reduce(.admit(target, .position), at: 1.1), [.rejected(.staleWork)])
    }

    func testResumeRequiresFreshObservationAndAnotherExplicitTile() {
        var model = ready()
        _ = model.reduce(.tile([token(a): destination]), at: 1)
        _ = model.reduce(.pause, at: 1)
        XCTAssertTrue(model.reduce(.resume, at: 1.1).contains(.reconcile(a)))
        XCTAssertEqual(model.state, .paused)
        XCTAssertTrue(model.pending.isEmpty)
        _ = model.reduce(.observation(sample(token(a), sequence: 2, time: 1.1)), at: 1.1)
        XCTAssertEqual(model.reduce(.dispatch(a), at: 1.1), [])
        XCTAssertEqual(model.reduce(.tile([token(a): destination]), at: 1.1), [])
        XCTAssertEqual(model.state, .active)
    }

    func testEnvironmentAndTrustLossRejectOldWorkAndOldObservations() throws {
        for change in [ControlEvent.environmentChanged(.environmentChanged), .permission(false)] {
            var model = ready()
            _ = model.reduce(.tile([token(a): destination]), at: 1)
            let target = try dispatch(&model, app: a)
            try runToReadback(&model, target: target)
            _ = model.reduce(change, at: 1)
            let result = ApplyResult(target: target,
                observation: sample(token(a), sequence: 2, frame: destination),
                startedAt: 1, finishedAt: 1, outcome: .succeeded)
            XCTAssertEqual(model.reduce(.completed(result), at: 1), [.reconcile(a)])
            XCTAssertTrue(model.observations.isEmpty)
            XCTAssertTrue(model.desired.isEmpty)
            XCTAssertEqual(model.environmentEpoch, 1)
            _ = model.reduce(.permission(true), at: 1)
            XCTAssertEqual(model.reduce(.observation(sample(token(a), sequence: 3)), at: 1),
                           [.rejected(.staleObservation)])
        }
    }

    func testLateReadbackAfterPauseCannotRestoreObservedOrDesiredState() throws {
        var model = ready()
        _ = model.reduce(.tile([token(a): destination]), at: 1)
        let target = try dispatch(&model, app: a)
        try runToReadback(&model, target: target)
        _ = model.reduce(.pause, at: 1)
        let result = ApplyResult(target: target, observation: sample(token(a), sequence: 2, frame: destination),
                                 startedAt: 1, finishedAt: 1, outcome: .succeeded)
        XCTAssertEqual(model.reduce(.completed(result), at: 1), [.reconcile(a)])
        XCTAssertEqual(model.observations[token(a)]?.frame, original)
        XCTAssertEqual(model.desired[token(a)], destination)
        XCTAssertEqual(model.state, .paused)
    }

    func testObsoleteRevisionCompletionReconcilesWithoutRollingBackDesired() throws {
        var model = ready()
        _ = model.reduce(.tile([token(a): destination]), at: 1)
        let old = try dispatch(&model, app: a)
        try runToReadback(&model, target: old)
        let newer = Rect(x: 800, y: 40, width: 800, height: 600)
        _ = model.reduce(.tile([token(a): newer]), at: 1)
        let result = ApplyResult(target: old, observation: sample(token(a), sequence: 2, frame: destination),
                                 startedAt: 1, finishedAt: 1, outcome: .succeeded)
        XCTAssertEqual(model.reduce(.completed(result), at: 1), [.reconcile(a)])
        XCTAssertEqual(model.desired[token(a)], newer)
        XCTAssertEqual(model.layoutRevision, 2)
        XCTAssertTrue(model.pending.isEmpty)
        XCTAssertTrue(model.dirty.contains(token(a)))
    }

    func testLatestAbsolutePlanCoalescesAndDispatchOrderIsDeterministic() throws {
        var model = ready()
        let second = token(a, 2)
        _ = model.reduce(.observation(sample(second, sequence: 2)), at: 1)
        for offset in 0..<100 {
            let frame = Rect(x: Double(offset), y: 0, width: 100, height: 100)
            _ = model.reduce(.tile([second: frame, token(a): frame]), at: 1)
            XCTAssertEqual(model.pending.count, 2)
        }
        let target = try dispatch(&model, app: a)
        XCTAssertEqual(target.token, token(a))
        XCTAssertEqual(target.frame.x, 99)
        XCTAssertEqual(model.reduce(.dispatch(a), at: 1), [])
        XCTAssertEqual(model.inFlightCount, 1)
    }

    func testOverflowInvalidatesOnlyAffectedAppAndDoesNotReplaceBlockedWorker() throws {
        var model = ready(twoApps: true)
        _ = model.reduce(.tile([token(a): destination, token(b): destination]), at: 1)
        let target = try dispatch(&model, app: a)
        let size = try admit(&model, target: target, setter: .size)
        XCTAssertEqual(model.reduce(.overflow(a), at: 1), [.reconcile(a)])
        XCTAssertEqual(model.reduce(.dispatch(a), at: 1), [])
        XCTAssertEqual(model.inFlightCount, 1)
        let healthy = try dispatch(&model, app: b)
        try runToReadback(&model, target: healthy)
        let result = ApplyResult(target: healthy, observation: sample(token(b), sequence: 2, frame: destination),
                                 startedAt: 1, finishedAt: 1, outcome: .succeeded)
        XCTAssertEqual(model.reduce(.completed(result), at: 1), [])
        XCTAssertEqual(model.observations[token(b)]?.frame, destination)
        XCTAssertEqual(model.inFlightCount, 1)
        XCTAssertEqual(model.reduce(.setterFinished(size, .unknownOutcome), at: 1), [.reconcile(a)])
        XCTAssertEqual(model.state, .active)
    }

    func testCapacityIsBoundedAndExcessPlanRevokesAdmission() {
        var model = ready(limit: 1)
        XCTAssertEqual(model.reduce(.observation(sample(token(a, 2), sequence: 2)), at: 1),
                       [.rejected(.staleObservation)])
        XCTAssertEqual(model.observations.count, 1)
        let effects = model.reduce(.tile([token(a): destination, token(a, 2): destination]), at: 1)
        XCTAssertTrue(effects.contains(.rejected(.capacity)))
        XCTAssertEqual(model.state, .paused)
        XCTAssertTrue(model.pending.isEmpty)
        var apps = ControlModel(maximumApps: 1)
        _ = apps.reduce(.attach(a), at: 0)
        XCTAssertEqual(apps.reduce(.attach(b), at: 0), [.rejected(.capacity)])
    }

    func testDestroyedWindowCannotBeRevivedByLateReadOrResult() throws {
        var model = ready()
        _ = model.reduce(.tile([token(a): destination]), at: 1)
        let target = try dispatch(&model, app: a)
        try runToReadback(&model, target: target)
        _ = model.reduce(.windowDestroyed(token(a)), at: 1)
        let result = ApplyResult(target: target, observation: sample(token(a), sequence: 2, frame: destination),
                                 startedAt: 1, finishedAt: 1, outcome: .succeeded)
        _ = model.reduce(.completed(result), at: 1)
        XCTAssertEqual(model.reduce(.observation(sample(token(a), sequence: 3)), at: 1),
                       [.rejected(.staleObservation)])
        XCTAssertTrue(model.desired.isEmpty)
        XCTAssertTrue(model.observations.isEmpty)
        XCTAssertEqual(model.reduce(.observation(sample(token(a, 2), sequence: 4)), at: 1), [])
    }

    func testPIDReuseRejectsOldAttachmentCallbacksAndTokens() throws {
        var model = ready()
        _ = model.reduce(.tile([token(a): destination]), at: 1)
        let old = try dispatch(&model, app: a)
        let permit = try admit(&model, target: old, setter: .size)
        let replacement = AppToken(pid: a.pid, generation: 2)
        _ = model.reduce(.attach(replacement), at: 1)
        XCTAssertEqual(model.inFlightCount, 0)
        XCTAssertEqual(model.reduce(.attach(a), at: 1), [.rejected(.staleWork)])
        _ = model.reduce(.appTerminated(a), at: 1)
        XCTAssertEqual(model.reduce(.setterFinished(permit, .succeeded), at: 1), [.rejected(.staleWork)])
        XCTAssertEqual(model.reduce(.observation(sample(token(a), sequence: 2)), at: 1),
                       [.rejected(.staleObservation)])
        XCTAssertEqual(model.reduce(.observation(sample(token(replacement))), at: 1), [])
        XCTAssertEqual(model.observations.count, 1)
        XCTAssertTrue(model.desired.isEmpty)
    }

    func testSuccessfulReadbackAdvancesObservationWithoutDuplicateSetterAdmission() throws {
        var model = ready()
        _ = model.reduce(.tile([token(a): destination]), at: 1)
        let target = try dispatch(&model, app: a)
        let permit = try admit(&model, target: target, setter: .size)
        XCTAssertEqual(model.reduce(.admit(target, .size), at: 1), [.rejected(.staleWork)])
        _ = model.reduce(.setterFinished(permit, .succeeded), at: 1)
        XCTAssertEqual(model.reduce(.setterFinished(permit, .succeeded), at: 1), [.rejected(.staleWork)])
        let position = try admit(&model, target: target, setter: .position)
        _ = model.reduce(.setterFinished(position, .succeeded), at: 1)
        let result = ApplyResult(target: target, observation: sample(token(a), sequence: 2, frame: destination),
                                 startedAt: 1, finishedAt: 1, outcome: .succeeded)
        XCTAssertEqual(model.reduce(.completed(result), at: 1), [])
        XCTAssertEqual(model.observations[token(a)]?.workerSequence, 2)
        XCTAssertEqual(model.reduce(.completed(result), at: 1), [.rejected(.staleWork)])
        XCTAssertEqual(model.inFlightCount, 0)
    }

    func testExpiryBetweenSettersStopsAndReconciles() throws {
        var model = ready()
        _ = model.reduce(.tile([token(a): destination]), at: 1)
        let target = try dispatch(&model, app: a)
        let permit = try admit(&model, target: target, setter: .size)
        _ = model.reduce(.setterFinished(permit, .succeeded), at: 1.1)
        XCTAssertTrue(model.reduce(.admit(target, .position), at: 1.6).contains(.reconcile(a)))
        XCTAssertTrue(model.dirty.contains(token(a)))
        XCTAssertEqual(model.inFlightCount, 0)
    }

    func testFailureOrMismatchingReadbackDoesNotRetry() throws {
        for outcome in [ControlOutcome.succeeded, .unavailable, .unknownOutcome] {
            var model = ready()
            _ = model.reduce(.tile([token(a): destination]), at: 1)
            let target = try dispatch(&model, app: a)
            try runToReadback(&model, target: target)
            let result = ApplyResult(target: target, observation: sample(token(a), sequence: 2),
                                     startedAt: 1, finishedAt: 1, outcome: outcome)
            XCTAssertEqual(model.reduce(.completed(result), at: 1), [.reconcile(a)])
            XCTAssertTrue(model.pending.isEmpty)
            XCTAssertEqual(model.reduce(.dispatch(a), at: 1), [])
            XCTAssertEqual(model.desired[token(a)], destination)
        }
    }

    func testSafetyControlsBypassBadClockAndQuitIsTerminal() throws {
        var model = ready()
        _ = model.reduce(.tile([token(a): destination]), at: 1)
        let target = try dispatch(&model, app: a)
        _ = try admit(&model, target: target, setter: .size)
        XCTAssertEqual(model.reduce(.dispatch(a), at: .nan), [.rejected(.invalidTime)])
        XCTAssertTrue(model.reduce(.quit, at: .nan).contains(.admissionRevoked(1)))
        XCTAssertEqual(model.state, .stopping)
        XCTAssertEqual(model.inFlightCount, 1) // No pretend cancellation or join.
        XCTAssertEqual(model.reduce(.permission(true), at: 1), [.rejected(.stopped)])
        XCTAssertEqual(model.reduce(.resume, at: 1), [.rejected(.stopped)])
        XCTAssertEqual(model.reduce(.admit(target, .position), at: 1), [.rejected(.stopped)])
    }

    func testDelayedPreInvalidationObservationCannotClearDirtyState() {
        for invalidation in [ControlEvent.pause, .overflow(a), .resume] {
            var model = ready()
            _ = model.reduce(invalidation, at: 1.2)
            XCTAssertEqual(model.reduce(.observation(sample(token(a), sequence: 2, time: 1.1)), at: 1.3),
                           [.rejected(.staleObservation)])
            XCTAssertTrue(model.dirty.contains(token(a)))
            XCTAssertEqual(model.reduce(.observation(sample(token(a), sequence: 3, time: 1.3)), at: 1.3), [])
            XCTAssertFalse(model.dirty.contains(token(a)))
        }
    }

    func testRegressingSampleTimeCannotOverwriteNewerObservation() {
        var model = ready()
        _ = model.reduce(.observation(sample(token(a), sequence: 2, time: 1.2)), at: 1.2)
        XCTAssertEqual(model.reduce(.observation(sample(token(a), sequence: 3, time: 1.1)), at: 1.3),
                       [.rejected(.staleObservation)])
        XCTAssertEqual(model.observations[token(a)]?.sampledAt, 1.2)
    }

    func testObservationDuringBlockedCallCannotClearOverflow() throws {
        var model = ready()
        _ = model.reduce(.tile([token(a): destination]), at: 1)
        let target = try dispatch(&model, app: a)
        _ = try admit(&model, target: target, setter: .size)
        _ = model.reduce(.overflow(a), at: 1.1)
        XCTAssertEqual(model.reduce(.observation(sample(token(a), sequence: 2, time: 1.2)), at: 1.2),
                       [.rejected(.staleObservation)])
        XCTAssertEqual(model.inFlightCount, 1)
        XCTAssertTrue(model.dirty.contains(token(a)))
    }

    func testReadbackMustFollowLastSetterAndHaveOrderedTiming() throws {
        for invalidTime in [0.9, 1.05, 1.3, Double.nan] {
            var model = ready()
            _ = model.reduce(.tile([token(a): destination]), at: 1)
            let target = try dispatch(&model, app: a)
            let size = try admit(&model, target: target, setter: .size)
            _ = model.reduce(.setterFinished(size, .succeeded), at: 1)
            let position = try admit(&model, target: target, setter: .position)
            _ = model.reduce(.setterFinished(position, .succeeded), at: 1.1)
            let result = ApplyResult(target: target,
                observation: sample(token(a), sequence: 2, time: invalidTime, frame: destination),
                startedAt: 1, finishedAt: 1.2, outcome: .succeeded)
            XCTAssertEqual(model.reduce(.completed(result), at: 1.2), [.reconcile(a)])
            XCTAssertEqual(model.observations[token(a)]?.frame, original)
        }
    }

    func testTerminationRetiresAppAndCannotBeUndoneByOldAttachment() {
        var model = ready()
        _ = model.reduce(.tile([token(a): destination]), at: 1)
        _ = model.reduce(.appTerminated(a), at: 1)
        XCTAssertTrue(model.observations.isEmpty)
        XCTAssertTrue(model.pending.isEmpty)
        XCTAssertTrue(model.desired.isEmpty)
        XCTAssertEqual(model.reduce(.attach(a), at: 1), [.rejected(.staleWork)])
    }

    func testDestructionBeforeFirstObservationStillRetiresToken() {
        var model = ready()
        _ = model.reduce(.windowDestroyed(token(a, 2)), at: 1)
        XCTAssertEqual(model.reduce(.observation(sample(token(a, 2), sequence: 2)), at: 1),
                       [.rejected(.staleObservation)])
        XCTAssertEqual(model.reduce(.observation(sample(token(a), sequence: 3)), at: 1), [])
        XCTAssertEqual(model.reduce(.observation(sample(token(a, 3), sequence: 4)), at: 1), [])
    }
}
