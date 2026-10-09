import Foundation
import XCTest

@testable import ITileCore
@testable import ITilePlatform

@MainActor
final class SimulatedDeliveryTests: XCTestCase {
  private let frame = Rect(x: 0, y: 30, width: 700, height: 500)
  private let a = AppToken(pid: 1, generation: 1)
  private let b = AppToken(pid: 2, generation: 2)
  private func token(_ app: AppToken) -> WindowToken { WindowToken(app: app, serial: 1) }
  private func sample(_ app: AppToken, epoch: UInt64 = 0, sequence: UInt64 = 1)
    -> WindowObservation
  {
    WindowObservation(
      token: token(app), frame: frame, eligibility: .eligible,
      positionSettable: .supported, sizeSettable: .supported, environmentEpoch: epoch,
      workerSequence: sequence, sampledAt: 1)
  }
  private func ready(
    _ owner: SimulatedControlOwner, delivery: SimulatedDelivery,
    scheduler: HeldDrains, apps: [AppToken]
  ) throws {
    for app in apps { XCTAssertTrue(delivery.attach(app, at: 0)) }
    owner.trust(true, at: 0)
    XCTAssertEqual(delivery.enqueue(.enable), .accepted(1))
    try XCTUnwrap(scheduler.take())()
    for app in apps { XCTAssertEqual(owner.observe(sample(app), at: 1), []) }
    _ = delivery.enqueue(.tile(Dictionary(uniqueKeysWithValues: apps.map { (token($0), frame) })))
    try XCTUnwrap(scheduler.take())()
  }
  private func operation(_ owner: SimulatedControlOwner, _ app: AppToken) throws
    -> ControlOperationID
  { try XCTUnwrap(owner.prepare(app, at: 1)) }
  private func size(_ owner: SimulatedControlOwner, _ id: ControlOperationID) throws
    -> SimulatedStepReceipt
  {
    guard case .permit(let permit) = owner.gate.admit(id, setter: .size, at: 1) else {
      throw Failure.noPermit
    }
    return try XCTUnwrap(owner.gate.finish(permit, outcome: .succeeded))
  }
  private enum Failure: Error { case noPermit }

  func testSixteenReplySlotsEightReplyAndEightCommandBatchesShareOneChain() throws {
    let owner = SimulatedControlOwner()
    let scheduler = HeldDrains()
    var commands: [SimulatedControlOwner.Disposition] = []
    let delivery = SimulatedDelivery(
      owner: owner, time: { 1 }, schedule: scheduler.schedule,
      commands: { commands.append(contentsOf: $0) })
    let apps = (1...16).map { AppToken(pid: Int32($0), generation: UInt64($0)) }
    try ready(owner, delivery: delivery, scheduler: scheduler, apps: apps)
    commands.removeAll()
    for app in apps {
      XCTAssertTrue(delivery.submit(try size(owner, operation(owner, app))))
    }
    for _ in 0..<128 { _ = delivery.enqueue(.focus(token(a))) }
    XCTAssertEqual(delivery.enqueue(.focus(token(a))), .rejected(.capacity))
    XCTAssertFalse(delivery.attach(AppToken(pid: 17, generation: 17), at: 1))
    XCTAssertEqual(delivery.retainedReplies, 16)
    XCTAssertEqual(scheduler.count, 1)
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(delivery.retainedReplies, 8)
    XCTAssertEqual(commands.count, 8)
    XCTAssertEqual(owner.gate.operationCount, 16)
    XCTAssertEqual(scheduler.count, 1)
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(delivery.retainedReplies, 0)
    XCTAssertEqual(commands.count, 16)
    while let pass = scheduler.take() { pass() }
    XCTAssertEqual(commands, (3...130).map { .unsupported(UInt64($0)) })
    XCTAssertEqual(scheduler.count, 0)
  }

  func testDisableWithFullQueueClosesImmediatelyAndPriorityPrecedesCommands() throws {
    let owner = SimulatedControlOwner()
    let scheduler = HeldDrains()
    var commands: [SimulatedControlOwner.Disposition] = []
    let delivery = SimulatedDelivery(
      owner: owner, time: { 1 }, schedule: scheduler.schedule,
      commands: { commands.append(contentsOf: $0) })
    try ready(owner, delivery: delivery, scheduler: scheduler, apps: [a])
    commands.removeAll()
    let id = try operation(owner, a)
    _ = delivery.enqueue(.enable)
    for _ in 0..<127 { _ = delivery.enqueue(.focus(token(a))) }
    delivery.revoke(.disable, at: .nan)
    guard case .denied(let receipt) = owner.gate.admit(id, setter: .size, at: 1) else {
      return XCTFail("Backlog deferred Disable")
    }
    XCTAssertTrue(delivery.submit(receipt))
    XCTAssertEqual(scheduler.count, 1)
    while let pass = scheduler.take() { pass() }
    XCTAssertEqual(commands, (3...130).map { .rejected(UInt64($0), .stale) })
    XCTAssertEqual(owner.model.state, .paused)
    XCTAssertEqual(owner.model.inFlightCount, 0)
    XCTAssertEqual(delivery.enqueue(.focus(token(a))), .rejected(.disabled))
  }

  func testPublicationAndSafetyDuringConsumptionAndAfterFinalizationCannotLoseWakeup() throws {
    let owner = SimulatedControlOwner()
    let scheduler = HeldDrains()
    var delivery: SimulatedDelivery!
    var peer: SimulatedStepReceipt?
    var visits: [ControlOperationID] = []
    delivery = SimulatedDelivery(
      owner: owner, time: { 1 }, schedule: scheduler.schedule,
      beforeAcknowledgment: { id in
        visits.append(id)
        if id.app == self.a, let receipt = peer {
          XCTAssertTrue(delivery.submit(receipt))
          delivery.revoke(.pause, at: 1)
          XCTAssertEqual(scheduler.count, 0)
        }
      })
    try ready(owner, delivery: delivery, scheduler: scheduler, apps: [a, b])
    let first = try operation(owner, a)
    let second = try operation(owner, b)
    peer = try size(owner, second)
    XCTAssertTrue(delivery.submit(try size(owner, first)))
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(visits, [first, second])
    XCTAssertEqual(delivery.retainedReplies, 0)
    XCTAssertEqual(owner.model.inFlightCount, 0)
    XCTAssertEqual(owner.gate.operationCount, 0)
    XCTAssertEqual(owner.model.state, .paused)
    XCTAssertEqual(scheduler.count, 0)
    _ = delivery.enqueue(.resume)
    XCTAssertEqual(scheduler.count, 1)
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(scheduler.count, 0)
  }

  func testDuplicateAndReplayQuarantineWithoutOverwritingOrLeakingMatchingReply() throws {
    let owner = SimulatedControlOwner()
    let scheduler = HeldDrains()
    let delivery = SimulatedDelivery(owner: owner, time: { 1 }, schedule: scheduler.schedule)
    try ready(owner, delivery: delivery, scheduler: scheduler, apps: [a])
    let id = try operation(owner, a)
    let receipt = try size(owner, id)
    XCTAssertTrue(delivery.submit(receipt))
    XCTAssertFalse(delivery.submit(receipt))
    XCTAssertTrue(delivery.hasFailed(a))
    XCTAssertEqual(delivery.retainedReplies, 1)
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(owner.model.inFlightCount, 0)
    XCTAssertEqual(owner.gate.operationCount, 0)
    XCTAssertFalse(delivery.submit(receipt))
    XCTAssertEqual(scheduler.count, 0)
    XCTAssertEqual(owner.observe(sample(a, sequence: 2), at: 1), [])
    _ = delivery.enqueue(.tile([token(a): frame]))
    try XCTUnwrap(scheduler.take())()
    XCTAssertNil(owner.prepare(a, at: 1))
    XCTAssertEqual(owner.model.inFlightCount, 0)
  }

  func testQuarantinedExecutingCallCanStillDeliverItsExactLateCleanupReceipt() throws {
    let owner = SimulatedControlOwner()
    let scheduler = HeldDrains()
    let delivery = SimulatedDelivery(owner: owner, time: { 1 }, schedule: scheduler.schedule)
    try ready(owner, delivery: delivery, scheduler: scheduler, apps: [a])
    let id = try operation(owner, a)
    guard case .permit(let permit) = owner.gate.admit(id, setter: .size, at: 1) else {
      return XCTFail("Missing permit")
    }
    // A result cannot be routed before the backend actually finishes.
    XCTAssertFalse(delivery.submit(SimulatedStepReceipt(permit: permit, outcome: .succeeded)))
    XCTAssertTrue(delivery.hasFailed(a))
    XCTAssertEqual(owner.gate.operationCount, 1)
    let actual = try XCTUnwrap(owner.gate.finish(permit, outcome: .unknownOutcome))
    XCTAssertTrue(delivery.submit(actual))
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(owner.model.inFlightCount, 0)
    XCTAssertEqual(owner.gate.operationCount, 0)
    XCTAssertEqual(delivery.retainedReplies, 0)
    XCTAssertTrue(delivery.hasFailed(a))
  }

  func testSafetyAfterCommandReductionBeforePublicationCannotReopenAdmission() throws {
    let owner = SimulatedControlOwner()
    let scheduler = HeldDrains()
    var delivery: SimulatedDelivery!
    var revokeAfterTile = false
    delivery = SimulatedDelivery(
      owner: owner, time: { 1 }, schedule: scheduler.schedule,
      commands: { _ in
        if revokeAfterTile { delivery.revoke(.pause, at: 1) }
      })
    try ready(owner, delivery: delivery, scheduler: scheduler, apps: [a])
    revokeAfterTile = true
    _ = delivery.enqueue(.tile([token(a): frame]))
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(owner.model.layoutRevision, 2)
    XCTAssertNil(owner.prepare(a, at: 1))
    XCTAssertEqual(owner.gate.operationCount, 0)
    XCTAssertEqual(scheduler.count, 1)
    revokeAfterTile = false
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(owner.model.state, .paused)
    XCTAssertEqual(scheduler.count, 0)
  }

  func testCoalescedEpochStormStaysAlignedAndCreatesOneWakeup() throws {
    let owner = SimulatedControlOwner()
    let scheduler = HeldDrains()
    let delivery = SimulatedDelivery(owner: owner, time: { 1 }, schedule: scheduler.schedule)
    try ready(owner, delivery: delivery, scheduler: scheduler, apps: [a])
    for _ in 0..<1_000 {
      delivery.revoke(.environmentChanged, at: .nan)
      delivery.revoke(.permissionLost, at: .nan)
    }
    XCTAssertEqual(scheduler.count, 1)
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(owner.model.environmentEpoch, 2)
    XCTAssertEqual(owner.model.state, .permissionRequired)
    XCTAssertEqual(scheduler.count, 0)
    owner.trust(true, at: 1)
    _ = delivery.enqueue(.resume)
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(owner.observe(sample(a, epoch: 2, sequence: 2), at: 1), [])
    _ = delivery.enqueue(.tile([token(a): frame]))
    try XCTUnwrap(scheduler.take())()
    let fresh = try operation(owner, a)
    _ = try size(owner, fresh)
  }

  func testRetiredProcessRoutingPersistsThroughActualReceiptWithoutAffectingReplacement() throws {
    let owner = SimulatedControlOwner()
    let scheduler = HeldDrains()
    let delivery = SimulatedDelivery(owner: owner, time: { 1 }, schedule: scheduler.schedule)
    try ready(owner, delivery: delivery, scheduler: scheduler, apps: [a])
    let old = try operation(owner, a)
    let late = try size(owner, old)
    delivery.retire(a, at: 1)
    XCTAssertEqual(delivery.attachmentCount, 1)
    let replacement = AppToken(pid: a.pid, generation: 2)
    XCTAssertTrue(delivery.attach(replacement, at: 1))
    XCTAssertEqual(owner.observe(sample(replacement), at: 1), [])
    _ = delivery.enqueue(.tile([token(replacement): frame]))
    try XCTUnwrap(scheduler.take())()
    let fresh = try operation(owner, replacement)
    XCTAssertTrue(delivery.submit(late))
    XCTAssertFalse(delivery.submit(late))
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(delivery.attachmentCount, 1)
    XCTAssertEqual(owner.model.inFlightCount, 1)
    XCTAssertEqual(owner.gate.operationCount, 1)
    XCTAssertFalse(delivery.submit(late))
    _ = try size(owner, fresh)
  }

  func testBlockedProducerWakeupCoalescesCommandReplyAndQuitIngress() async throws {
    let owner = SimulatedControlOwner()
    let scheduler = HeldDrains()
    let posting = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let held = LockedFlag()
    let delivery = SimulatedDelivery(
      owner: owner, time: { 1 },
      schedule: { work in
        if held.value {
          posting.signal()
          XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
        }
        scheduler.schedule(work)
      })
    try ready(owner, delivery: delivery, scheduler: scheduler, apps: [a])
    let id = try operation(owner, a)
    let receipt = try size(owner, id)
    let posted = expectation(description: "Producer posted the one wakeup")
    held.value = true
    DispatchQueue.global().async {
      XCTAssertTrue(delivery.submit(receipt))
      posted.fulfill()
    }
    XCTAssertEqual(posting.wait(timeout: .now() + 2), .success)
    _ = delivery.enqueue(.resume)
    delivery.revoke(.quit, at: .nan)
    XCTAssertEqual(owner.gate.enqueue(.enable), .rejected(.stopped))
    XCTAssertEqual(scheduler.count, 0)
    held.value = false
    release.signal()
    await fulfillment(of: [posted], timeout: 2)
    XCTAssertEqual(scheduler.count, 1)
    try XCTUnwrap(scheduler.take())()
    XCTAssertEqual(owner.model.state, .stopping)
    XCTAssertEqual(owner.model.inFlightCount, 0)
    XCTAssertEqual(owner.gate.operationCount, 0)
    XCTAssertEqual(scheduler.count, 0)
  }
}

private final class LockedFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var stored = false
  var value: Bool {
    get {
      lock.lock()
      defer { lock.unlock() }
      return stored
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      stored = newValue
    }
  }
}
