import AppKit
import Darwin
import Foundation

// Explicit local foreground-handler lab. No AX reads or user-window setters.
private enum LabFailure: Error {
  case incomplete(String)
}

private struct Snapshot {
  let app: UInt64
  let sequence: UInt64
  let request: UInt64
  let start: Double
  let frame: String

  init(_ report: String) throws {
    func capture(_ pattern: String) throws -> String {
      let expression = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
      let range = NSRange(report.startIndex..., in: report)
      let matches = expression.matches(in: report, range: range)
      guard matches.count == 1, let value = Range(matches[0].range(at: 1), in: report) else {
        throw LabFailure.incomplete("malformed-report")
      }
      return String(report[value])
    }
    guard report.contains("\nhistorical-sample-accepted=true; rejection-reasons=none\n"),
      report.contains("\neligibility=unknown;"),
      report.contains("freshness=unmeasured (no diagnostic age policy)."),
      report.contains(
        "eligibility-unproven=currentDesktopVisibility, nativeTabSafety, nestedDialogSafety"),
      let app = UInt64(try capture("^Focused read-only snapshot: app-([0-9]+)/")), app > 0,
      let sequence = UInt64(try capture("^Focused read-only snapshot: .*; sequence=([0-9]+)$")),
      sequence > 0,
      let request = UInt64(try capture("^owner-request=([0-9]+);")), request > 0,
      let start = Double(try capture("^start=([^;]+);")), start.isFinite, start >= 0
    else { throw LabFailure.incomplete("unaccepted-report") }
    self.app = app
    self.sequence = sequence
    self.request = request
    self.start = start
    frame = try capture("^frame=(.+)$")
  }

  func isRecovery(from baseline: Snapshot, submitted: Double) -> Bool {
    app == baseline.app && sequence > baseline.sequence && request > baseline.request
      && start >= submitted && frame == baseline.frame
  }
}

private final class Lab {
  private var children: [String: Process] = [:]
  private var inputs: [String: Pipe] = [:]
  private var outputs: [String: Pipe] = [:]
  private var buffers: [String: Data] = [:]
  private var pending: [(String, String)] = []
  private var eventCount = 0
  private let deadline = ProcessInfo.processInfo.systemUptime + 30

  private func emit(_ text: String) { print(text) }

  func launch(_ lane: String, path: String, arguments: [String]) throws {
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    children[lane] = process
    inputs[lane] = input
    outputs[lane] = output
    buffers[lane] = Data()
    try output.fileHandleForWriting.close()
    try input.fileHandleForReading.close()
    let fd = output.fileHandleForReading.fileDescriptor
    guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
      throw LabFailure.incomplete("pipe-configuration")
    }
  }

  @discardableResult
  func send(_ lane: String, _ command: String) throws -> Double {
    guard let input = inputs[lane], children[lane]?.isRunning == true else {
      throw LabFailure.incomplete("child-exited-\(lane)")
    }
    let submitted = ProcessInfo.processInfo.systemUptime
    try input.fileHandleForWriting.write(contentsOf: Data((command + "\n").utf8))
    emit("parent \(lane) \(command) uptime=\(submitted)")
    return submitted
  }

  private func pump() throws {
    guard ProcessInfo.processInfo.systemUptime < deadline, eventCount < 2048 else {
      throw LabFailure.incomplete("run-bound")
    }
    for lane in ["fixture", "app"] {
      guard let output = outputs[lane] else { continue }
      var bytes = [UInt8](repeating: 0, count: 4096)
      let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
      if count < 0 {
        guard errno == EAGAIN || errno == EINTR else {
          throw LabFailure.incomplete("pipe-read-\(lane)")
        }
        continue
      }
      guard count > 0 else { throw LabFailure.incomplete("child-eof-\(lane)") }
      buffers[lane]!.append(contentsOf: bytes.prefix(count))
      guard buffers[lane]!.count <= 16384 else {
        throw LabFailure.incomplete("line-bound")
      }
      while let end = buffers[lane]!.firstIndex(of: 10) {
        let line = String(decoding: buffers[lane]![..<end], as: UTF8.self)
        buffers[lane]!.removeSubrange(...end)
        eventCount += 1
        guard eventCount <= 2048 else { throw LabFailure.incomplete("event-bound") }
        pending.append((lane, line))
        if lane == "fixture" || line.hasPrefix("manual-command") || line.hasPrefix("manual-ready") {
          emit("\(lane) \(line)")
        }
      }
    }
    Thread.sleep(forTimeInterval: 0.01)
  }

  func wait(_ lane: String, matching: (String) -> Bool) throws -> String {
    let end = min(deadline, ProcessInfo.processInfo.systemUptime + 5)
    while ProcessInfo.processInfo.systemUptime < end {
      if let index = pending.firstIndex(where: { $0.0 == lane && matching($0.1) }) {
        return pending.remove(at: index).1
      }
      try pump()
    }
    throw LabFailure.incomplete("event-deadline-\(lane)")
  }

  func activate() throws {
    try send("fixture", "activate")
    _ = try wait("fixture") { $0.hasPrefix("activation-requested ") }
    let outcome = try wait("fixture") {
      $0.hasPrefix("activation-confirmed ") || $0.hasPrefix("activation-not-frontmost ")
    }
    guard outcome.hasPrefix("activation-confirmed ") else {
      throw LabFailure.incomplete("activation-not-frontmost")
    }
    try send("fixture", "desktop-status")
    let status = try wait("fixture") { $0.hasPrefix("desktop-status ") }
    guard status.contains("original-active=true"), status.contains("focused=original"),
      status.contains("frontmost=true")
    else { throw LabFailure.incomplete("fixture-not-active-focused") }
  }

  private func report() throws -> String {
    try send("app", "report")
    _ = try wait("app") { $0 == "manual-report-begin" }
    var lines: [String] = []
    var bytes = 0
    while true {
      let line = try wait("app") { !$0.hasPrefix("manual-command ") }
      if line == "manual-report-end" { return lines.joined(separator: "\n") + "\n" }
      guard line != "manual-report-begin" else {
        throw LabFailure.incomplete("nested-report")
      }
      bytes += line.utf8.count + 1
      guard bytes <= 16384, lines.count < 128 else {
        throw LabFailure.incomplete("report-bound")
      }
      lines.append(line)
    }
  }

  func sample(_ name: String, matching: (String) -> Bool) throws -> String {
    var lastReport = ""
    do {
      for _ in 0..<60 {
        let text = try report()
        lastReport = text
        if matching(text) {
          emit("sample-begin \(name)\n\(text)sample-end \(name)")
          return text
        }
        Thread.sleep(forTimeInterval: 0.05)
      }
      throw LabFailure.incomplete("sample-deadline-\(name)")
    } catch {
      emit("sample-unmatched \(name)\n\(lastReport)")
      throw error
    }
  }

  func cleanup() -> Bool {
    var clean = true
    for lane in ["fixture", "app"] {
      guard let process = children[lane] else { continue }
      if process.isRunning { _ = try? send(lane, "quit") }
      try? inputs[lane]?.fileHandleForWriting.close()
      let end = ProcessInfo.processInfo.systemUptime + 3
      while process.isRunning && ProcessInfo.processInfo.systemUptime < end {
        Thread.sleep(forTimeInterval: 0.02)
      }
      if process.isRunning {
        clean = false
        process.terminate()
        let end = ProcessInfo.processInfo.systemUptime + 1
        while process.isRunning && ProcessInfo.processInfo.systemUptime < end {
          Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
      } else if process.terminationStatus != 0 {
        clean = false
      }
      try? outputs[lane]?.fileHandleForReading.close()
      emit("cleanup \(lane) orderly=\(!process.isRunning && process.terminationStatus == 0)")
    }
    return clean
  }
}

private func selfTest() throws {
  let report = """
    fixture
    Focused read-only snapshot: app-1/window-1; epoch=0; sequence=1
    frame=Rect(x: 200, y: 722, width: 420, height: 158)
    eligibility=unknown; safety unproven
    eligibility-unproven=currentDesktopVisibility, nativeTabSafety, nestedDialogSafety
    start=10; end=11
    Read-only evidence provenance: historical; freshness=unmeasured (no diagnostic age policy).
    owner-request=1; activation-revision=1; revocation-generation=2
    historical-sample-accepted=true; rejection-reasons=none

    """
  let baseline = try Snapshot(report)
  let freshText = report.replacingOccurrences(of: "sequence=1", with: "sequence=3")
    .replacingOccurrences(of: "owner-request=1", with: "owner-request=5")
    .replacingOccurrences(of: "start=10", with: "start=20")
  let fresh = try Snapshot(freshText)
  guard fresh.isRecovery(from: baseline, submitted: 19),
    (try Snapshot(freshText.replacingOccurrences(of: "sequence=3", with: "sequence=2")))
      .isRecovery(from: baseline, submitted: 19),
    !baseline.isRecovery(from: baseline, submitted: 9),
    !fresh.isRecovery(from: baseline, submitted: 21),
    !(try Snapshot(freshText.replacingOccurrences(of: "app-1", with: "app-2")))
      .isRecovery(from: baseline, submitted: 19),
    !(try Snapshot(freshText.replacingOccurrences(of: "width: 420", with: "width: 421")))
      .isRecovery(from: baseline, submitted: 19)
  else { throw LabFailure.incomplete("correlation-self-test") }
  for malformed in [
    report + "owner-request=2;\n",
    report.replacingOccurrences(of: "start=10", with: "start=nan"),
    report.replacingOccurrences(
      of: "historical-sample-accepted=true", with: "historical-sample-accepted=false"),
  ] {
    do {
      _ = try Snapshot(malformed)
    } catch { continue }
    throw LabFailure.incomplete("malformed-self-test")
  }
  print("lab-self-test passed")
}

// A closed owned-child pipe must become a reported delivery error.
signal(SIGPIPE, SIG_IGN)

private let lab = Lab()
private var passed = false
private var focusDiscardCaptured = false

do {
  if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    try selfTest()
    exit(0)
  }
  guard CommandLine.arguments == [CommandLine.arguments[0], "--run"] else {
    throw LabFailure.incomplete("usage: focus-recovery-lab --self-test or --run")
  }
  let identifiers = ["local.itile.app", "local.itile.axfixture"]
  guard
    !NSWorkspace.shared.runningApplications.contains(where: {
      identifiers.contains($0.bundleIdentifier ?? "")
    })
  else { throw LabFailure.incomplete("quit-existing-itile-and-fixture") }
  let root = FileManager.default.currentDirectoryPath
  try lab.launch(
    "fixture", path: root + "/dist/iTile AX Fixture.app/Contents/MacOS/iTileAXFixture",
    arguments: ["--focused-probe", "--nested-probe", "--tab-probe", "--desktop-probe"])
  _ = try lab.wait("fixture") { $0.hasPrefix("ready ") }
  try lab.launch(
    "app", path: root + "/dist/iTile.app/Contents/MacOS/iTile",
    arguments: ["--manual-probe", "--show-probe-report"])
  let ready = try lab.wait("app") { $0.hasPrefix("manual-ready ") }
  guard ready == "manual-ready trusted=true" else {
    throw LabFailure.incomplete("accessibility-not-trusted")
  }
  try lab.activate()
  let submitted = try lab.send("app", "inspect")
  let baselineText = try lab.sample("baseline") {
    guard let snapshot = try? Snapshot($0) else { return false }
    return snapshot.start >= submitted
  }
  let baseline = try Snapshot(baselineText)
  // desktop-status invokes the fixture focused accessor; finish it before arming.
  try lab.activate()
  try lab.send("fixture", "arm-focus-loss")
  _ = try lab.wait("fixture") { $0.hasPrefix("focus-loss-armed ") }
  try lab.send("app", "inspect")
  _ = try lab.wait("fixture") { $0.hasPrefix("focused-read-begin ") }
  _ = try lab.wait("fixture") { $0.hasPrefix("focused-read-hide ") }
  // Capture the transient discard while the owned accessor is still outstanding.
  let discard = try lab.sample("discard") {
    let message = $0.trimmingCharacters(in: .whitespacesAndNewlines)
    return message == "Focus changed during inspection. Result discarded; inspect again."
      || message
        == "Desktop/display or sleep state changed. Previous observations are stale; inspect again."
  }
  focusDiscardCaptured =
    discard.trimmingCharacters(in: .whitespacesAndNewlines)
    == "Focus changed during inspection. Result discarded; inspect again."
  print(
    focusDiscardCaptured
      ? "discard-kind focus" : "discard-kind environment; focus-specific capture inconclusive")
  _ = try lab.wait("fixture") { $0.hasPrefix("focused-read-end ") }
  try lab.activate()
  let recoverySubmitted = try lab.send("app", "inspect")
  _ = try lab.sample("recovery") {
    guard let snapshot = try? Snapshot($0) else { return false }
    return snapshot.isRecovery(from: baseline, submitted: recoverySubmitted)

  }
  passed = true
} catch { print("lab-incomplete \(error)") }
let cleaned = lab.cleanup()
if passed && cleaned {
  print(
    focusDiscardCaptured
      ? "lab-scoped-focus-recovery-passed"
      : "lab-scoped-environment-recovery-passed; focus-specific capture inconclusive")
} else {
  print("lab-incomplete")
}
exit(passed && cleaned ? 0 : 1)
