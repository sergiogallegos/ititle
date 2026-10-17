import AppKit
import ApplicationServices
import Darwin
import Foundation
import ITileFixtureDiagnostics

if CommandLine.arguments == [CommandLine.arguments[0], "--timing-setup-ack-delay-preflight"] {
  runSetupAckDelayPreflight()
}

if CommandLine.arguments.dropFirst().first == "--compare-diagnostic-ages" {
  runAgeComparison(arguments: CommandLine.arguments)
}

// Offline replay runs before application/trust setup and never creates a fixture.
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--replay-timing" {
  do {
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: CommandLine.arguments[2]))
    defer { try? handle.close() }
    var data = Data()
    while let chunk = try handle.read(upToCount: 16384), !chunk.isEmpty {
      guard data.count + chunk.count <= FixtureTimingBudget.outputBytes else {
        throw FixtureTimingReplay.Failure.bound
      }
      data.append(chunk)
    }
    let report = try FixtureTimingReplay.review(data)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var output = try encoder.encode(report)
    output.append(10)
    try FileHandle.standardOutput.write(contentsOf: output)
    exit(report.complete ? 0 : 1)
  } catch {
    let reason = (error as? FixtureTimingReplay.Failure)?.rawValue ?? "malformed"
    print("{\"kind\":\"replayFailure\",\"reason\":\"\(reason)\"}")
    exit(1)
  }
}

private enum LabFailure: Error { case incomplete(String) }

/// Fixed owned-process lab. AX is opt-in; no permission mutation or production model.
@MainActor
private final class SnapshotLab {
  private let child = Process()
  private let input = Pipe()
  private let output = Pipe()
  private var buffer = Data()
  private var lines: [(text: String, receipt: Double)] = []
  private var lastReceipt: Double = 0
  private var lastSelection: Double = 0
  private var lastSnapshotTimes: [FixtureTimingPoint: Double] = [:]
  private var activeTimingReader: OwnedAXIdentityReader?
  private let timingMode: Bool
  private let exclusionMode: Bool
  private let setupExitMode: Bool
  private let setupAckDelayMode: Bool
  private var timingCollector: FixtureTimingCollector
  private var setupFault: FixtureSetupFaultRecord?
  private var activeSetup: FixtureSetupRecord?
  private var currentStage: FixtureLabStage = .trustPreflight
  private var correlatedRequest: UInt64 = 0
  private var received = 0
  private var request: UInt64 = 0
  private var consumer: FixtureSnapshotConsumer?
  private var monitor: LabLifecycleMonitor?
  private let deadline: Double
  private let runStart: Double

  init(
    operatorMode: Bool = false, timingMode: Bool = false, exclusionMode: Bool = false,
    setupExitMode: Bool = false, setupAckDelayMode: Bool = false
  ) {
    self.timingMode = timingMode
    self.exclusionMode = exclusionMode
    self.setupExitMode = setupExitMode
    self.setupAckDelayMode = setupAckDelayMode
    timingCollector = FixtureTimingCollector(
      attemptLimit: FixtureTimingBudget.attempts, schema: setupAckDelayMode ? 4 : 3,
      failureClock: { ProcessInfo.processInfo.systemUptime })
    runStart = ProcessInfo.processInfo.systemUptime
    deadline = runStart + (operatorMode || timingMode ? 180 : 30)
  }

  private func log(_ text: String) { if !timingMode { print(text) } }

  func start(identityMode: Bool, hostMode: Bool = false) throws {
    guard
      !NSRunningApplication.runningApplications(withBundleIdentifier: "local.itile.axfixture")
        .contains(where: { !$0.isTerminated })
    else { throw LabFailure.incomplete("existing-fixture") }
    let screens = NSScreen.screens
    guard screens.count <= 16 else { throw LabFailure.incomplete("display-bound") }
    log(
      "lab-environment os=\(ProcessInfo.processInfo.operatingSystemVersionString) displays=\(screens.count)"
    )
    for (index, screen) in screens.enumerated() {
      log(
        "lab-display index=\(index) frame=\(screen.frame) usable=\(screen.visibleFrame) scale=\(screen.backingScaleFactor)"
      )
    }
    child.executableURL = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath
        + "/dist/iTile AX Fixture.app/Contents/MacOS/iTileAXFixture")
    child.arguments = [
      "--safety-probe", "--focused-probe", "--nested-probe", "--tab-probe", "--visibility-probe",
    ]
    if identityMode { child.arguments!.append("--identity-probe") }
    if setupAckDelayMode { child.arguments!.append("--setup-ack-delay-probe") }
    child.standardInput = input
    child.standardOutput = output
    child.standardError = FileHandle.nullDevice
    try child.run()
    try input.fileHandleForReading.close()
    try output.fileHandleForWriting.close()
    guard fcntl(output.fileHandleForReading.fileDescriptor, F_SETFL, O_NONBLOCK) == 0 else {
      throw LabFailure.incomplete("pipe-configuration")
    }
    _ = try wait { $0.hasPrefix("ready ") }
    let ready = try wait { $0.hasPrefix("safety-ready schema=2 run=") }
    let parts = ready.split(separator: " ")
    guard parts.count == 4, let run = UUID(uuidString: String(parts[2].dropFirst(4))) else {
      throw LabFailure.incomplete("invalid-ready")
    }
    consumer = FixtureSnapshotConsumer(run: run)
    if hostMode {
      monitor = try LabLifecycleMonitor(
        run: run, pid: child.processIdentifier,
        ownedRunning: { [weak self] in self?.child.isRunning == true })
    }
  }

  private func pump() {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
    if monitor != nil {
      // NSApplication.run normally dispatches queued AppKit events. This bounded
      // standalone pump must do that too; run-loop pumping alone is insufficient.
      for _ in 0..<16 {
        guard
          let event = NSApplication.shared.nextEvent(
            matching: .any,
            until: Date(), inMode: .default, dequeue: true)
        else { break }
        NSApplication.shared.sendEvent(event)
      }
    }
    monitor?.sample(trusted: AXIsProcessTrusted(), running: child.isRunning)
  }

  private func send(_ command: String) throws {
    guard child.isRunning else { throw LabFailure.incomplete("child-exited") }
    do { try input.fileHandleForWriting.write(contentsOf: Data((command + "\n").utf8)) } catch {
      throw LabFailure.incomplete("pipe-write")
    }
  }

  private func wait(matching: (String) -> Bool) throws -> String {
    let end = min(deadline, ProcessInfo.processInfo.systemUptime + 5)
    while ProcessInfo.processInfo.systemUptime < end {
      pump()
      guard ProcessInfo.processInfo.systemUptime < end else { break }
      if let index = lines.firstIndex(where: { matching($0.text) }) {
        let line = lines.remove(at: index)
        lastReceipt = line.receipt
        lastSelection = ProcessInfo.processInfo.systemUptime
        return line.text
      }
      var bytes = [UInt8](repeating: 0, count: 4096)
      let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
      if count < 0 {
        guard errno == EAGAIN || errno == EINTR else { throw LabFailure.incomplete("pipe-read") }
      } else {
        guard count > 0 else { throw LabFailure.incomplete("child-eof") }
        buffer.append(contentsOf: bytes.prefix(count))
        guard buffer.count <= 8192 else { throw LabFailure.incomplete("line-bound") }
        while let lineEnd = buffer.firstIndex(of: 10) {
          let line = String(decoding: buffer[..<lineEnd], as: UTF8.self)
          buffer.removeSubrange(...lineEnd)
          received += 1
          guard received <= 512 else { throw LabFailure.incomplete("event-bound") }
          let receipt = ProcessInfo.processInfo.systemUptime
          if setupAckDelayMode && line.hasPrefix("setup-ack-delay")
            && timingCollector.firstStop == nil && receipt < end
          {
            guard setupFault != nil else { throw FixtureSetupFaultRecord.Failure.protocolFailure }
            try setupFault!.observe(line, at: receipt)
          }
          lines.append((line, receipt))
          log(line)
        }
      }
      Thread.sleep(forTimeInterval: 0.01)
    }
    if !child.isRunning { throw LabFailure.incomplete("child-exited") }
    throw LabFailure.incomplete("event-deadline")
  }

  func command(_ command: String, acknowledgment: String? = nil) throws {
    try send(command)
    _ = try wait { $0.hasPrefix((acknowledgment ?? command + "-ready") + " ") }
  }

  func activate() throws {
    try send("activate")
    _ = try wait { $0.hasPrefix("activation-requested ") }
    let result = try wait {
      $0.hasPrefix("activation-confirmed ") || $0.hasPrefix("activation-not-frontmost ")
    }
    guard result.hasPrefix("activation-confirmed ") else {
      throw LabFailure.incomplete("not-frontmost")
    }
  }

  @discardableResult
  func snapshot(_ name: String, expecting: [String: String]) throws -> FixtureSafetySnapshot {
    // Only observations retry; fixture actions are issued once. One request is outstanding.
    for _ in 0..<10 {
      guard request < UInt64.max else { throw LabFailure.incomplete("request-exhaustion") }
      request += 1
      let submission = ProcessInfo.processInfo.systemUptime
      lastSnapshotTimes = [.beforeSubmission: submission]
      try consumer!.begin(request: request, at: submission)
      try send("safety-snapshot \(request)")
      lastSnapshotTimes[.beforeWrite] = ProcessInfo.processInfo.systemUptime
      let line = try wait {
        $0.hasPrefix("safety-snapshot ") || $0.hasPrefix("safety-rejected ")
          || $0.hasPrefix("safety-unavailable ")
      }
      lastSnapshotTimes[.beforeReceipt] = lastReceipt
      lastSnapshotTimes[.beforeSelection] = lastSelection
      lastSnapshotTimes[.beforeParseEntry] = ProcessInfo.processInfo.systemUptime
      let sample = try consumer!.consume(line, at: lastReceipt)
      correlatedRequest = sample.request
      lastSnapshotTimes[.beforeStart] = sample.startedAt
      lastSnapshotTimes[.beforeEnd] = sample.finishedAt
      lastSnapshotTimes[.beforeParse] = ProcessInfo.processInfo.systemUptime
      if expecting.allSatisfy({ sample.value($0.key) == $0.value }) {
        log("lab-sample \(name) accepted request=\(request) coverage=ownedFixtureOnly")
        return sample
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    throw LabFailure.incomplete("unexpected-state-\(name)")
  }

  func pair(_ name: String, original: Bool, peer: Bool = false) throws {
    let before = try snapshot(name + "-before", expecting: [:])
    let ax = try OwnedAXIdentityReader().read(pid: child.processIdentifier, pump: { self.pump() })
    let after = try snapshot(name + "-after", expecting: [:])
    guard ax.focused.run == before.run, ax.windows.allSatisfy({ $0.run == before.run }) else {
      throw LabFailure.incomplete("identity-run-\(name)")
    }
    log(
      "lab-identity-sample \(name) focused=\(ax.focused.serial) windows=\(ax.windows.map(\.serial))"
    )
    log("lab-ax-interval \(name) start=\(ax.startedAt) end=\(ax.finishedAt)")
    guard child.isRunning, before.run == after.run,
      before.finishedAt <= ax.startedAt, ax.finishedAt <= after.startedAt,
      ax.focused.run == before.run, ax.windows.allSatisfy({ $0.run == before.run }),
      ax.focused.matchesOriginal(in: before) == original,
      ax.focused.matchesOriginal(in: after) == original,
      ax.windows.contains(ax.focused),
      !original || ax.windows.contains(where: { $0.matchesOriginal(in: after) }),
      !peer || ax.windows.contains(where: { !$0.matchesOriginal(in: after) })
    else { throw LabFailure.incomplete("identity-pair-\(name)") }
    log(
      "lab-identity \(name) original=\(original) windows=\(ax.windows.count) coverage=ownedFixtureOnly"
    )
  }

  func lifecyclePair(_ name: String, transition: String? = nil) throws {
    // Source scenario is normalized before this pair; no policy age is supplied.
    try command("close-sheet")
    let before = try snapshot(name + "-before", expecting: [:])
    let context = FixtureUseContext(
      expected: try FixtureWindowIdentity(run: before.run, serial: 1),
      trusted: AXIsProcessTrusted())
    var assessment = FixturePairAssessment()
    try assessment.begin(request: before.request, context: context)
    if let transition {
      try command(transition)
      try command(transition == "native-sheet" ? "close-sheet" : "native-tabs-close")
      if transition == "native-tabs-open" { try command("native-tabs-hide-bar") }
    }
    let ax = try OwnedAXIdentityReader().read(pid: child.processIdentifier, pump: { self.pump() })
    let after = try snapshot(name + "-after", expecting: [:])
    var currentContext = context
    currentContext.trusted = AXIsProcessTrusted() && child.isRunning
    let result = assessment.consume(
      request: before.request, before: before, focused: ax.focused,
      axStart: ax.startedAt, axEnd: ax.finishedAt, after: after, context: currentContext,
      now: ProcessInfo.processInfo.systemUptime)
    let expected: FixturePairResult = transition == nil ? .historicalConsistent : .sourceChanged
    guard result == expected else {
      throw LabFailure.incomplete("lifecycle-\(name)-\(result.rawValue)")
    }
    if transition != nil {
      let varying: Set<String> = [
        "request", "sequence", "start", "end", "stateRevision", "registryRevision",
      ]
      guard
        FixtureSafetySnapshot.keys.allSatisfy({
          varying.contains($0) || before.value($0) == after.value($0)
        })
      else { throw LabFailure.incomplete("reversal-fields-\(name)") }
    }
    log(
      "lab-lifecycle \(name) result=\(result.rawValue) freshness=unmeasured before=\(before.value("stateRevision")!) after=\(after.value("stateRevision")!)"
    )
  }

  func lifecycleRegistry() throws {
    try command("visibility-peer-open", acknowledgment: "visibility-peer-equal")
    let first = try snapshot("first-peer", expecting: [:])
    guard let old = first.liveSerials?.last, old > 1 else {
      throw LabFailure.incomplete("peer-registry")
    }
    try command("visibility-peer-close")
    let retired = try snapshot("retired-peer", expecting: [:])
    guard retired.liveSerials == [1] else { throw LabFailure.incomplete("retired-peer") }
    try command("visibility-peer-open", acknowledgment: "visibility-peer-equal")
    let recreated = try snapshot("recreated-peer", expecting: [:])
    guard let new = recreated.liveSerials?.last, new > old else {
      throw LabFailure.incomplete("reused-peer")
    }
    try command("visibility-peer-close")
    try activate()
    try command("native-tabs-open")
    try command("native-tabs-second")
    let inactive = try snapshot("inactive-original", expecting: ["tabSelected": "false"])
    guard inactive.liveSerials?.contains(1) == true, inactive.liveSerials?.count == 2 else {
      throw LabFailure.incomplete("inactive-retired")
    }
    try pair("inactive-live-original", original: false)
    try command("native-tabs-close")
    try command("native-tabs-hide-bar")
    log("lab-lifecycle registry old=\(old) recreated=\(new) inactive-original-live=true")
  }

  private func hostPair(_ name: String, pause: Bool = false, focusFault: Bool = false) throws {
    guard let monitor else { throw LabFailure.incomplete("missing-host") }
    try command("close-sheet")
    if focusFault { try command("arm-focus-loss", acknowledgment: "focus-loss-armed") }
    let before = try snapshot(name + "-before", expecting: [:])
    try monitor.host.begin(request: before.request)
    let activations = monitor.activationEvents
    let reader = OwnedAXIdentityReader()
    try reader.start(pid: child.processIdentifier)
    if pause {
      monitor.pause(true)
      guard monitor.host.current == .contextRevoked else {
        throw LabFailure.incomplete("pause-not-immediate")
      }
      monitor.pause(false)
    }
    let readDeadline = min(deadline, ProcessInfo.processInfo.systemUptime + 5)
    var completion: Result<OwnedAXIdentitySample, Error>?
    while ProcessInfo.processInfo.systemUptime < readDeadline {
      pump()
      if let result = reader.poll() {
        completion = result
        break
      }
    }
    guard let completion else { throw LabFailure.incomplete("host-reader-deadline") }
    if focusFault {
      let eventDeadline = min(deadline, ProcessInfo.processInfo.systemUptime + 2)
      while monitor.activationEvents == activations
        && ProcessInfo.processInfo.systemUptime < eventDeadline
      { pump() }
      guard monitor.activationEvents > activations, monitor.host.current == .contextRevoked else {
        throw LabFailure.incomplete("native-activation-not-observed")
      }
    }
    let result: FixturePairResult
    let readOutcome: String
    switch completion {
    case .success(let ax):
      readOutcome = "identitySample"
      log("lab-host-AX \(name) start=\(ax.startedAt) end=\(ax.finishedAt)")
      let after = try snapshot(name + "-after", expecting: [:])
      result = monitor.host.finish(
        request: before.request, before: before, focused: ax.focused,
        axStart: ax.startedAt, axEnd: ax.finishedAt, after: after,
        now: ProcessInfo.processInfo.systemUptime)
    case .failure:
      readOutcome = "failedRead"
      result = monitor.host.abandon(request: before.request)
      if !focusFault { throw LabFailure.incomplete("unexpected-host-AX-failure") }
    }
    guard !monitor.overflow,
      result == (pause || focusFault ? .contextRevoked : .historicalConsistent),
      monitor.host.pendingRequest == nil
    else { throw LabFailure.incomplete("host-pair-\(name)-\(result.rawValue)") }
    log(
      "lab-host-pair \(name) result=\(result.rawValue) revocation=\(monitor.host.context.revocation) pending=false read=\(readOutcome)"
    )
  }

  func hostLifecycleChecks() throws {
    guard let monitor else { throw LabFailure.incomplete("missing-host") }
    try hostPair("baseline")
    try hostPair("pause-resume", pause: true)
    try hostPair("pause-recovery")
    try hostPair("native-focus-loss", focusFault: true)
    try activate()
    try snapshot(
      "host-focus-recovery",
      expecting: ["hidden": "false", "frontmost": "true", "focusedFault": "false"])
    try hostPair("native-focus-recovery")
    let before = try snapshot("exit-before", expecting: [:])
    try monitor.host.begin(request: before.request)
    let reader = OwnedAXIdentityReader()
    try reader.start(pid: child.processIdentifier)
    try send("quit")
    let end = min(deadline, ProcessInfo.processInfo.systemUptime + 3)
    while child.isRunning && ProcessInfo.processInfo.systemUptime < end { pump() }
    pump()
    guard !child.isRunning, monitor.host.context.stopped, monitor.host.current == .contextRevoked
    else {
      throw LabFailure.incomplete("owned-exit-not-revoked")
    }
    // Drain the one physical reader before admitting a replacement process.
    let readEnd = min(deadline, ProcessInfo.processInfo.systemUptime + 5)
    while reader.poll() == nil && ProcessInfo.processInfo.systemUptime < readEnd { pump() }
    guard reader.poll() != nil else { throw LabFailure.incomplete("exit-reader-deadline") }
    guard monitor.host.abandon(request: before.request) == .contextRevoked else {
      throw LabFailure.incomplete("exit-late-result")
    }
    log(
      "lab-host-exit revoked=true nativeNotifications=\(monitor.terminationEvents) readerDrained=true"
    )
    guard cleanup() else { throw LabFailure.incomplete("old-child-cleanup") }
    let oldRun = monitor.host.context.expected.run
    let replacement = SnapshotLab()
    do {
      try replacement.start(identityMode: true, hostMode: true)
      guard replacement.monitor?.host.context.expected.run != oldRun else {
        throw LabFailure.incomplete("replacement-run-reused")
      }
      try replacement.activate()
      try replacement.hostPair("replacement-fresh")
      guard replacement.cleanup() else { throw LabFailure.incomplete("replacement-cleanup") }
    } catch {
      _ = replacement.cleanup()
      throw error
    }
    guard monitor.host.context.stopped, monitor.host.current == .contextRevoked else {
      throw LabFailure.incomplete("old-attachment-revived")
    }
    log("lab-host-replacement freshRun=true oldAttachmentStopped=true")
  }

  private func awaitOperator(_ code: String, until ready: () -> Bool) throws {
    let end = min(deadline, ProcessInfo.processInfo.systemUptime + 120)
    while ProcessInfo.processInfo.systemUptime < end {
      pump()
      guard child.isRunning, monitor?.overflow != true else {
        throw LabFailure.incomplete("operator-owner-closed")
      }
      if ready() { return }
      Thread.sleep(forTimeInterval: 0.02)
    }
    throw LabFailure.incomplete("operator-deadline-\(code)")
  }

  func nativeOperatorChecks(permission: Bool) throws {
    guard let monitor else { throw LabFailure.incomplete("missing-host") }
    try hostPair("operator-baseline")
    let before = try snapshot("operator-before", expecting: ["active": "true"])
    try monitor.host.begin(request: before.request)
    let reader = OwnedAXIdentityReader()
    try reader.start(pid: child.processIdentifier)
    // Drain the physical reader before the potentially long operator wait.
    // Its completed value remains pending diagnostic work; no live-call overlap is claimed.
    let end = min(deadline, ProcessInfo.processInfo.systemUptime + 5)
    while reader.poll() == nil && ProcessInfo.processInfo.systemUptime < end { pump() }
    guard let completion = reader.poll() else {
      throw LabFailure.incomplete("operator-reader-deadline")
    }
    let spaces = monitor.spaceEvents
    let losses = monitor.trustLosses
    let restores = monitor.trustRestorations
    log(
      "lab-operator-armed kind=\(permission ? "permission" : "space") request=\(before.request) readerDrained=true"
    )
    fflush(stdout)
    if permission {
      try awaitOperator("permission-loss") {
        monitor.trustLosses > losses && !monitor.host.context.trusted
      }
    } else {
      try awaitOperator("native-space") { monitor.spaceEvents > spaces }
    }
    let after = try snapshot("operator-away", expecting: permission ? [:] : ["active": "false"])
    let result: FixturePairResult
    switch completion {
    case .success(let ax):
      result = monitor.host.finish(
        request: before.request, before: before, focused: ax.focused,
        axStart: ax.startedAt, axEnd: ax.finishedAt, after: after,
        now: ProcessInfo.processInfo.systemUptime)
    case .failure: result = monitor.host.abandon(request: before.request)
    }
    guard result == .contextRevoked, monitor.host.pendingRequest == nil else {
      throw LabFailure.incomplete("operator-late-pair")
    }
    log(
      "lab-operator-rejected kind=\(permission ? "permission" : "space") result=\(result.rawValue) active=\(after.value("active")!)"
    )
    fflush(stdout)
    if permission {
      try awaitOperator("permission-restoration") {
        monitor.trustRestorations > restores && monitor.host.context.trusted
      }
    } else {
      let awaySpaces = monitor.spaceEvents
      try awaitOperator("space-return") { monitor.spaceEvents > awaySpaces }
      // Do not activate an off-desktop fixture to force the desktop to return.
      try snapshot("operator-return", expecting: ["active": "true"])
    }
    try activate()
    try hostPair(permission ? "native-permission-recovery" : "native-space-recovery")
    log("lab-operator-recovery kind=\(permission ? "permission" : "space") freshPair=true")
  }

  func timingChecks() throws {
    guard let monitor else { throw LabFailure.incomplete("missing-host") }
    setStage(.manifest)
    guard
      FixtureDiagnosticBudget.reservedBytes(schema: setupAckDelayMode ? 4 : 3)
        <= FixtureTimingBudget.outputBytes
    else {
      throw LabFailure.incomplete("timing-output-reservation")
    }
    let manifest = FixtureTimingManifest(
      os: ProcessInfo.processInfo.operatingSystemVersionString,
      utc: ISO8601DateFormatter().string(from: Date()),
      labHash: try labArtifactHash(CommandLine.arguments[0]),
      fixtureHash: try labArtifactHash(child.executableURL!.path),
      initialContext: monitor.host.context,
      controlledExclusion: exclusionMode, runStart: runStart, collectionDeadline: deadline,
      controlledSetupFailure: setupExitMode || setupAckDelayMode,
      setupFault: setupAckDelayMode ? .normalizationAckDelayOnce : nil)
    guard manifest.valid else { throw FixtureSetupFaultRecord.Failure.protocolFailure }
    try timingCollector.append(manifest, maximumBytes: FixtureDiagnosticBudget.manifestBytes)
    monitor.timingSink = { [weak self] event in
      try? self?.timingCollector.event(event)
    }
    if setupAckDelayMode {
      // One arm command after the existing activation/baseline. Submission is
      // distinct from the observed fixed arming and scheduling markers.
      setupFault = FixtureSetupFaultRecord()
      try setupFault!.submit(at: ProcessInfo.processInfo.systemUptime)
      try send(FixtureAckDelayOnce.armCommand)
      _ = try wait { $0.hasPrefix(FixtureAckDelayOnce.armedMarker + " ") }
      try timingSetup(cohort: .ordinary, purpose: .cohort)
      // The normalization step must stop before any pair or activation stage.
      throw FixtureSetupFaultRecord.Failure.protocolFailure
    }
    if setupExitMode {
      setStage(.controlledExit)
      // One declared owned-child fault. No replacement or permission mutation.
      try send("quit")
      let end = min(deadline, ProcessInfo.processInfo.systemUptime + 3)
      while child.isRunning && ProcessInfo.processInfo.systemUptime < end { pump() }
      guard !child.isRunning else { throw LabFailure.incomplete("controlled-exit-timeout") }
    }
    let delays = [0.0, 0.05, 0.2, 0.5]
    for cohort in FixtureTimingCohort.allCases {
      // Normalize only at declared cohort setup or recovery boundaries. These
      // operations precede admission and are never retries of a measured pair.
      try timingSetup(cohort: cohort, purpose: .cohort)
      for offset in 0..<FixtureTimingBudget.cohortAttempts[cohort.rawValue]! {
        let phase: FixtureTimingPhase =
          exclusionMode && cohort == .ordinary && offset == 0
          ? .exclusion : FixtureTimingBudget.phase(cohort: cohort, offset: offset)
        if phase == .exclusion { try timingSetup(cohort: cohort, purpose: .exclusion) }
        if phase == .recovery || (exclusionMode && cohort == .ordinary && offset == 1) {
          try timingSetup(cohort: cohort, purpose: phase == .recovery ? .recovery : .reset)
        }
        setStage(.admissionChecks)
        guard ProcessInfo.processInfo.systemUptime < deadline, !monitor.overflow,
          !timingCollector.stopped
        else { throw LabFailure.incomplete("timing-bound") }
        let index = try timingCollector.begin(cohort)
        let delay = cohort == .dispatch || cohort == .assessment ? delays[offset % 4] : 0
        var record = FixtureTimingRecord(
          index: index, cohort: cohort, requestedDelay: delay,
          run: monitor.host.context.expected.run, schema: 3)
        record.phase = phase
        var drained = true
        do {
          setStage(.beforeSnapshot)
          let before: FixtureSafetySnapshot
          do { before = try snapshot("timing-before", expecting: [:]) } catch {
            for (point, time) in lastSnapshotTimes { record.mark(point, at: time) }
            throw error
          }
          for (point, time) in lastSnapshotTimes { record.mark(point, at: time) }
          record.request = before.request
          record.before = before
          setStage(.hostAdmission)
          record.mark(.hostAdmission, at: ProcessInfo.processInfo.systemUptime)
          try monitor.host.begin(request: before.request)
          record.admitted = monitor.host.context
          let reader = OwnedAXIdentityReader()
          setStage(.reader)
          activeTimingReader = reader
          let failureProbe = phase == .failureProbe
          try reader.start(
            pid: failureProbe ? 0 : child.processIdentifier,
            dispatchDelay: cohort == .dispatch ? delay : 0)
          drained = false
          let readDeadline = min(deadline, ProcessInfo.processInfo.systemUptime + 5)
          var completion: Result<OwnedAXIdentitySample, Error>?
          while ProcessInfo.processInfo.systemUptime < readDeadline {
            pump()
            if let result = reader.poll() {
              completion = result
              break
            }
          }
          for (point, time) in reader.timingAtReceipt() { record.mark(point, at: time) }
          guard let completion else {
            record.outcome = .timedOut
            throw LabFailure.incomplete("timing-reader-deadline")
          }
          drained = true
          activeTimingReader = nil
          switch completion {
          case .failure:
            _ = monitor.host.abandon(request: before.request)
            record.outcome = .failed
            guard failureProbe else { throw LabFailure.incomplete("timing-read-failure") }
          case .success(let ax):
            record.focused = ax.focused
            record.axStart = ax.startedAt
            record.axEnd = ax.finishedAt
            if phase == .sheet {
              setStage(.sheetTransition)
              try command("native-sheet")
              try command("close-sheet")
            }
            let afterPoints: [FixtureTimingPoint: FixtureTimingPoint] = [
              .beforeSubmission: .afterSubmission, .beforeWrite: .afterWrite,
              .beforeStart: .afterStart, .beforeEnd: .afterEnd,
              .beforeReceipt: .afterReceipt, .beforeParse: .afterParse,
              .beforeSelection: .afterSelection, .beforeParseEntry: .afterParseEntry,
            ]
            let after: FixtureSafetySnapshot
            setStage(.afterSnapshot)
            do { after = try snapshot("timing-after", expecting: [:]) } catch {
              for (point, time) in lastSnapshotTimes {
                if let afterPoint = afterPoints[point] { record.mark(afterPoint, at: time) }
              }
              throw error
            }
            for (point, time) in lastSnapshotTimes {
              if let afterPoint = afterPoints[point] { record.mark(afterPoint, at: time) }
            }
            record.after = after
            let ready = ProcessInfo.processInfo.systemUptime
            setStage(.assessment)
            record.mark(.inputsReady, at: ready)
            if phase == .pause {
              monitor.pause(true)
              monitor.pause(false)
            }
            let due = ready + (cohort == .assessment ? delay : cohort == .invalidation ? 0.05 : 0)
            while ProcessInfo.processInfo.systemUptime < due
              && ProcessInfo.processInfo.systemUptime < deadline
            { pump() }
            pump()
            guard ProcessInfo.processInfo.systemUptime < deadline, !monitor.overflow,
              !timingCollector.stopped
            else { throw LabFailure.incomplete("timing-bound") }
            let entry = ProcessInfo.processInfo.systemUptime
            record.mark(.assessmentEntry, at: entry)
            let result = monitor.host.finish(
              request: before.request, before: before, focused: ax.focused,
              axStart: ax.startedAt, axEnd: ax.finishedAt, after: after, now: entry)
            record.mark(.assessmentExit, at: ProcessInfo.processInfo.systemUptime)
            record.assessment = result
            record.outcome =
              result == .historicalConsistent
              ? .completed
              : result == .contextRevoked ? .revoked : .rejected
          // Retain unexpected outcomes. Terminal suitability distinguishes
          // complete collection from passing episode/recovery acceptance.
          }
          let context = monitor.host.context
          record.final = context
          record.mark(.terminal, at: ProcessInfo.processInfo.systemUptime)
          try timingCollector.finish(record, readerDrained: drained)
          guard !timingCollector.stopped else { throw LabFailure.incomplete("timing-invalid") }
        } catch {
          recordFailure(error)
          if timingCollector.occupied == index && timingCollector.records.count < index {
            if record.outcome != .timedOut && record.outcome != .failed {
              record.outcome = .incomplete
            }
            record.final = monitor.host.context
            record.mark(.terminal, at: ProcessInfo.processInfo.systemUptime)
            try? timingCollector.finish(record, readerDrained: drained)
          }
          throw error
        }
      }
    }
  }

  private func timingSetup(cohort: FixtureTimingCohort, purpose: FixtureSetupPurpose) throws {
    activeSetup = FixtureSetupRecord(
      sequence: timingCollector.setups.count + 1, nextIndex: timingCollector.admissions + 1,
      cohort: cohort, purpose: purpose, at: ProcessInfo.processInfo.systemUptime,
      issued: request, correlated: correlatedRequest, revocation: monitor!.host.context.revocation,
      pairOccupied: monitor!.host.pendingRequest != nil, readerOccupied: activeTimingReader != nil)
    do {
      try setupStep(.setupPrecondition) {
        guard monitor?.host.pendingRequest == nil, activeTimingReader == nil else {
          throw LabFailure.incomplete("timing-setup-occupied")
        }
      }
      if purpose == .exclusion {
        try setupStep(.exclusionWrite) { try send("tree-ordinary") }
        try setupStep(.exclusionAck) { _ = try wait { $0.hasPrefix("tree-ordinary-ready ") } }
      } else {
        try setupStep(.normalizationWrite) {
          if setupAckDelayMode {
            try setupFault!.normalizationWrite(at: ProcessInfo.processInfo.systemUptime)
          }
          try send("close-sheet")
        }
        try setupStep(.normalizationAck) {
          if setupAckDelayMode {
            try setupFault!.beginWait(at: ProcessInfo.processInfo.systemUptime)
          }
          _ = try wait { $0.hasPrefix("close-sheet-ready ") }
          if setupAckDelayMode { throw LabFailure.incomplete("unexpected-acknowledgment") }
        }
        try setupStep(.activationWrite) { try send("activate") }
        try setupStep(.activationAck) { _ = try wait { $0.hasPrefix("activation-requested ") } }
        try setupStep(.activationConfirmation) {
          let result = try wait {
            $0.hasPrefix("activation-confirmed ") || $0.hasPrefix("activation-not-frontmost ")
          }
          if !result.hasPrefix("activation-confirmed ") {
            try activeSetup!.complete(at: ProcessInfo.processInfo.systemUptime)
            throw LabFailure.incomplete("not-frontmost")
          }
        }
        try setupStep(.settle) {
          let end = min(deadline, ProcessInfo.processInfo.systemUptime + 0.1)
          while ProcessInfo.processInfo.systemUptime < end { pump() }
        }
      }
      try finishSetup(failure: nil)
    } catch {
      recordFailure(error)
      try? finishSetup(failure: timingCollector.firstStop?.category ?? .unclassified)
      activeSetup = nil
      throw error
    }
  }

  private func setupStep(_ stage: FixtureLabStage, _ action: () throws -> Void) throws {
    setStage(stage)
    try activeSetup!.enter(stage, at: ProcessInfo.processInfo.systemUptime)
    try action()
    try activeSetup!.complete(at: ProcessInfo.processInfo.systemUptime)
  }

  private func finishSetup(failure: FixtureStopCategory?) throws {
    activeSetup!.issued = request
    activeSetup!.correlated = correlatedRequest
    activeSetup!.revocationAfter = monitor!.host.context.revocation
    activeSetup!.pairOccupied = monitor!.host.pendingRequest != nil
    activeSetup!.readerOccupied = activeTimingReader != nil
    try activeSetup!.finish(at: ProcessInfo.processInfo.systemUptime, failure: failure)
    try timingCollector.setup(activeSetup!)
    activeSetup = nil
  }

  func setStage(_ stage: FixtureLabStage) { currentStage = stage }

  func recordFailure(_ error: any Error) {
    guard timingMode else { return }
    let category: FixtureStopCategory
    if let failure = error as? LabFailure, case .incomplete(let code) = failure {
      switch code {
      case "identity-reader-not-trusted": category = .untrusted
      case "not-frontmost": category = .activationRefused
      case "event-deadline":
        category =
          ProcessInfo.processInfo.systemUptime >= deadline ? .collectionDeadline : .responseDeadline
      case "child-exited": category = .childExited
      case "child-eof": category = .childEOF
      case "pipe-read": category = .pipeRead
      case "pipe-write": category = .pipeWrite
      case "unexpected-acknowledgment": category = .unexpectedAcknowledgment
      case "timing-setup-occupied": category = .occupiedSetup
      case "timing-reader-deadline": category = .readerWatchdog
      case "timing-read-failure": category = .readerFailure
      case "timing-bound":
        category =
          ProcessInfo.processInfo.systemUptime >= deadline
          ? .collectionDeadline
          : monitor?.overflow == true ? .observerLimit : .unclassified
      case "line-bound", "event-bound", "pipe-configuration": category = .protocolFailure
      default: category = .unclassified
      }
    } else if let error = error as? FixtureSetupFaultRecord.Failure {
      category = error == .clockFailure ? .clockFailure : .protocolFailure
    } else if let error = error as? FixtureSnapshotError {
      category = error == .exhausted ? .counterFailure : .protocolFailure
    } else {
      category = .unclassified
    }
    stop(category)
    if setupFault != nil, setupFault!.end == nil, let first = timingCollector.firstStop,
      let time = first.time
    {
      try? setupFault!.finish(at: time, category: first.category, running: child.isRunning)
    }
  }

  private func stop(_ category: FixtureStopCategory) {
    timingCollector.latchStop(
      FixtureFirstStop(
        stage: currentStage, category: category, at: ProcessInfo.processInfo.systemUptime,
        setup: activeSetup?.sequence, request: monitor?.host.pendingRequest,
        pairs: timingCollector.records.count, pairOccupied: monitor?.host.pendingRequest != nil,
        readerOccupied: activeTimingReader != nil))
  }

  func exportTiming(orderly: Bool, passed: Bool) -> Bool {
    setStage(.drain)
    if let reader = activeTimingReader {
      let end = ProcessInfo.processInfo.systemUptime + 5
      while reader.poll() == nil && ProcessInfo.processInfo.systemUptime < end { pump() }
      if reader.poll() != nil, let index = timingCollector.occupied {
        try? timingCollector.drained(index: index)
      }
      activeTimingReader = nil
    }
    setStage(.summary)
    if let setupFault { try? timingCollector.setupFault(setupFault) }
    try? timingCollector.append(
      FixtureTimingSummary(records: timingCollector.records),
      maximumBytes: FixtureDiagnosticBudget.summaryBytes(schema: setupAckDelayMode ? 4 : 3))
    let complete = passed && orderly && !timingCollector.stopped && timingCollector.occupied == nil
    timingCollector.close(orderly: orderly, passed: passed)
    do { try FileHandle.standardOutput.write(contentsOf: timingCollector.bytes) } catch {
      return false
    }
    return complete && timingCollector.records.count == FixtureTimingBudget.attempts
      && timingCollector.records.allSatisfy(\.expectedOutcome)
  }

  func cleanup() -> Bool {
    setStage(.cleanup)
    defer { monitor?.detach() }
    guard child.processIdentifier > 0 else { return true }
    if child.isRunning { try? send("quit") }
    try? input.fileHandleForWriting.close()
    let end = ProcessInfo.processInfo.systemUptime + 3
    while child.isRunning && ProcessInfo.processInfo.systemUptime < end {
      pump()
      Thread.sleep(forTimeInterval: 0.02)
    }
    var orderly = !child.isRunning
    if child.isRunning {
      if timingMode { stop(.forcedCleanup) }
      child.terminate()
      let end = ProcessInfo.processInfo.systemUptime + 1
      while child.isRunning && ProcessInfo.processInfo.systemUptime < end {
        pump()
        Thread.sleep(forTimeInterval: 0.02)
      }
      if child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
    } else {
      orderly = child.terminationStatus == 0
      if timingMode && !orderly { stop(.childExitNonzero) }
    }
    try? output.fileHandleForReading.close()
    if timingMode && monitor?.overflow == true { stop(.observerLimit) }
    orderly = orderly && monitor?.overflow != true
    log("lab-cleanup orderly=\(orderly)")
    return orderly
  }
}

signal(SIGPIPE, SIG_IGN)
private let spaceMode = CommandLine.arguments == [CommandLine.arguments[0], "--space-run"]
private let permissionApp =
  Bundle.main.bundleIdentifier == "local.itile.safetypermissionlab"
  && CommandLine.arguments.count == 1
private let permissionMode =
  permissionApp || CommandLine.arguments == [CommandLine.arguments[0], "--permission-run"]
private let exclusionMode =
  CommandLine.arguments == [CommandLine.arguments[0], "--timing-exclusion-run"]
private let setupExitMode =
  CommandLine.arguments == [CommandLine.arguments[0], "--timing-setup-exit-run"]
private let setupAckDelayMode =
  CommandLine.arguments == [CommandLine.arguments[0], "--timing-setup-ack-delay-run"]
private let timingMode =
  setupAckDelayMode || setupExitMode || exclusionMode
  || CommandLine.arguments == [CommandLine.arguments[0], "--timing-run"]
private let lab = SnapshotLab(
  operatorMode: spaceMode || permissionMode, timingMode: timingMode, exclusionMode: exclusionMode,
  setupExitMode: setupExitMode, setupAckDelayMode: setupAckDelayMode)
private var passed = false
private var identityMode = false
private let hostMode = CommandLine.arguments == [CommandLine.arguments[0], "--host-run"]
private let lifecycleMode = CommandLine.arguments == [CommandLine.arguments[0], "--lifecycle-run"]
do {
  if permissionApp { try preparePermissionAppReport() }
  identityMode =
    timingMode || spaceMode || permissionMode || hostMode || lifecycleMode
    || CommandLine.arguments == [CommandLine.arguments[0], "--identity-run"]
  guard identityMode || CommandLine.arguments == [CommandLine.arguments[0], "--run"] else {
    throw LabFailure.incomplete(
      "usage: iTileSafetySnapshotLab --run or --identity-run or --lifecycle-run or --host-run or --space-run or --permission-run or --timing-run or --timing-exclusion-run or --timing-setup-exit-run or --timing-setup-ack-delay-run or --replay-timing FILE"
    )
  }
  if identityMode && !AXIsProcessTrusted() {
    throw LabFailure.incomplete("identity-reader-not-trusted")
  }
  lab.setStage(.startup)
  try lab.start(
    identityMode: identityMode, hostMode: timingMode || hostMode || spaceMode || permissionMode)
  lab.setStage(.baseline)
  try lab.activate()
  try lab.snapshot(
    "baseline",
    expecting: [
      "active": "true", "visible": "true", "hidden": "false", "tabCount": "1", "sheetCount": "0",
      "synthetic": "false",
    ])
  if timingMode {
    try lab.timingChecks()
  } else if spaceMode || permissionMode {
    try lab.nativeOperatorChecks(permission: permissionMode)
  } else if hostMode {
    try lab.hostLifecycleChecks()
  } else {
    if lifecycleMode {
      try lab.lifecycleRegistry()
      try lab.lifecyclePair("stable")
      try lab.lifecyclePair("tab-reversal", transition: "native-tabs-open")
      try lab.lifecyclePair("sheet-reversal", transition: "native-sheet")
    }
    if identityMode {
      try lab.pair("baseline", original: true)
      try lab.command("visibility-peer-open", acknowledgment: "visibility-peer-equal")
      try lab.activate()
      try lab.pair("equal-frame-peer", original: true, peer: true)
      try lab.command("visibility-peer-close")
    }
    try lab.command("visibility-hide")
    try lab.snapshot("hidden", expecting: ["hidden": "true"])
    try lab.activate()
    try lab.snapshot("recovery", expecting: ["hidden": "false", "frontmost": "true"])
    try lab.command("native-tabs-open")
    try lab.snapshot("native-tabs", expecting: ["tabCount": "2", "tabSelected": "true"])
    try lab.command("native-tabs-second")
    try lab.snapshot("second-tab", expecting: ["tabSelected": "false"])
    if identityMode { try lab.pair("second-tab", original: false) }
    try lab.command("native-tabs-close")
    try lab.snapshot("closed-tab", expecting: ["tabCount": "1"])
    // AppKit may require the bar while multiple tabs remain. Exercise one tab.
    try lab.command("native-tabs-show-bar")
    try lab.snapshot("visible-single-tab-bar", expecting: ["tabCount": "1", "tabBar": "true"])
    try lab.command("native-tabs-hide-bar")
    try lab.snapshot("hidden-single-tab-bar", expecting: ["tabCount": "1", "tabBar": "false"])
    if identityMode { try lab.pair("closed-tab", original: true) }
    try lab.command("native-sheet")
    try lab.snapshot("native-sheet", expecting: ["attached": "true", "sheetCount": "1"])
    try lab.command("close-sheet")
    try lab.snapshot("closed-sheet", expecting: ["attached": "false", "sheetCount": "0"])
    if identityMode { try lab.pair("closed-sheet", original: true) }
    try lab.command("tree-focus-loss")
    try lab.snapshot(
      "synthetic-fault",
      expecting: ["scenario": "tree-focus-loss", "synthetic": "true", "structuralFault": "true"])
    try lab.snapshot("synthetic-fault-retained", expecting: ["structuralFault": "true"])
    try lab.command("close-sheet")
    try lab.command("arm-focus-loss", acknowledgment: "focus-loss-armed")
    try lab.snapshot("focused-fault", expecting: ["focusedFault": "true", "synthetic": "false"])
    try lab.snapshot(
      "focused-fault-retained", expecting: ["focusedFault": "true", "hidden": "false"])
  }
  passed = true
} catch {
  lab.recordFailure(error)
  if !timingMode { print("lab-incomplete \(error)") }
}
let cleaned = lab.cleanup()
if timingMode {
  passed = lab.exportTiming(orderly: cleaned, passed: passed)
} else if passed && cleaned {
  print(
    spaceMode || permissionMode
      ? "lab-owned-operator-passed; no production eligibility claim"
      : hostMode
        ? "lab-owned-host-passed; no production eligibility claim"
        : lifecycleMode
          ? "lab-owned-lifecycle-passed; no production eligibility claim"
          : identityMode
            ? "lab-owned-identity-passed; no production eligibility claim"
            : "lab-owned-snapshot-passed; no AX identity or eligibility claim")
} else {
  print("lab-incomplete")
}
exit(passed && cleaned ? 0 : 1)
