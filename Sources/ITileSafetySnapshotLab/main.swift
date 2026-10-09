import AppKit
import Darwin
import Foundation
import ITileFixtureDiagnostics

private enum LabFailure: Error { case incomplete(String) }

/// Fixed owned-process lab. No AX client, permissions, or production model.
private final class SnapshotLab {
  private let child = Process()
  private let input = Pipe()
  private let output = Pipe()
  private var buffer = Data()
  private var lines: [String] = []
  private var received = 0
  private var request: UInt64 = 0
  private var consumer: FixtureSnapshotConsumer?
  private let deadline = ProcessInfo.processInfo.systemUptime + 30

  func start() throws {
    guard
      !NSRunningApplication.runningApplications(withBundleIdentifier: "local.itile.axfixture")
        .contains(where: { !$0.isTerminated })
    else { throw LabFailure.incomplete("existing-fixture") }
    let screens = NSScreen.screens
    guard screens.count <= 16 else { throw LabFailure.incomplete("display-bound") }
    print(
      "lab-environment os=\(ProcessInfo.processInfo.operatingSystemVersionString) displays=\(screens.count)"
    )
    for (index, screen) in screens.enumerated() {
      print(
        "lab-display index=\(index) frame=\(screen.frame) usable=\(screen.visibleFrame) scale=\(screen.backingScaleFactor)"
      )
    }
    child.executableURL = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath
        + "/dist/iTile AX Fixture.app/Contents/MacOS/iTileAXFixture")
    child.arguments = [
      "--safety-probe", "--focused-probe", "--nested-probe", "--tab-probe", "--visibility-probe",
    ]
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
    let ready = try wait { $0.hasPrefix("safety-ready schema=1 run=") }
    let parts = ready.split(separator: " ")
    guard parts.count == 4, let run = UUID(uuidString: String(parts[2].dropFirst(4))) else {
      throw LabFailure.incomplete("invalid-ready")
    }
    consumer = FixtureSnapshotConsumer(run: run)
  }

  private func send(_ command: String) throws {
    guard child.isRunning else { throw LabFailure.incomplete("child-exited") }
    try input.fileHandleForWriting.write(contentsOf: Data((command + "\n").utf8))
  }

  private func wait(matching: (String) -> Bool) throws -> String {
    let end = min(deadline, ProcessInfo.processInfo.systemUptime + 5)
    while ProcessInfo.processInfo.systemUptime < end {
      if let index = lines.firstIndex(where: matching) { return lines.remove(at: index) }
      var bytes = [UInt8](repeating: 0, count: 4096)
      let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
      if count < 0 {
        guard errno == EAGAIN || errno == EINTR else { throw LabFailure.incomplete("pipe-read") }
      } else {
        guard count > 0 else { throw LabFailure.incomplete("child-eof") }
        buffer.append(contentsOf: bytes.prefix(count))
        guard buffer.count <= 8192 else { throw LabFailure.incomplete("line-bound") }
        while let end = buffer.firstIndex(of: 10) {
          let line = String(decoding: buffer[..<end], as: UTF8.self)
          buffer.removeSubrange(...end)
          received += 1
          guard received <= 512 else { throw LabFailure.incomplete("event-bound") }
          print(line)
          lines.append(line)
        }
      }
      Thread.sleep(forTimeInterval: 0.01)
    }
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

  func snapshot(_ name: String, expecting: [String: String]) throws {
    // Only observations retry; fixture actions are issued once. One request is outstanding.
    for _ in 0..<10 {
      guard request < UInt64.max else { throw LabFailure.incomplete("request-exhaustion") }
      request += 1
      try consumer!.begin(request: request, at: ProcessInfo.processInfo.systemUptime)
      try send("safety-snapshot \(request)")
      let line = try wait {
        $0.hasPrefix("safety-snapshot ") || $0.hasPrefix("safety-rejected ")
          || $0.hasPrefix("safety-unavailable ")
      }
      let sample = try consumer!.consume(line, at: ProcessInfo.processInfo.systemUptime)
      if expecting.allSatisfy({ sample.value($0.key) == $0.value }) {
        print("lab-sample \(name) accepted request=\(request) coverage=ownedFixtureOnly")
        return
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    throw LabFailure.incomplete("unexpected-state-\(name)")
  }

  func cleanup() -> Bool {
    guard child.processIdentifier > 0 else { return true }
    if child.isRunning { try? send("quit") }
    try? input.fileHandleForWriting.close()
    let end = ProcessInfo.processInfo.systemUptime + 3
    while child.isRunning && ProcessInfo.processInfo.systemUptime < end {
      Thread.sleep(forTimeInterval: 0.02)
    }
    var orderly = !child.isRunning
    if child.isRunning {
      child.terminate()
      let end = ProcessInfo.processInfo.systemUptime + 1
      while child.isRunning && ProcessInfo.processInfo.systemUptime < end {
        Thread.sleep(forTimeInterval: 0.02)
      }
      if child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
    } else {
      orderly = child.terminationStatus == 0
    }
    try? output.fileHandleForReading.close()
    print("lab-cleanup orderly=\(orderly)")
    return orderly
  }
}

signal(SIGPIPE, SIG_IGN)
private let lab = SnapshotLab()
private var passed = false
do {
  guard CommandLine.arguments == [CommandLine.arguments[0], "--run"] else {
    throw LabFailure.incomplete("usage: iTileSafetySnapshotLab --run")
  }
  try lab.start()
  try lab.activate()
  try lab.snapshot(
    "baseline",
    expecting: [
      "active": "true", "visible": "true", "hidden": "false", "tabCount": "1", "sheetCount": "0",
      "synthetic": "false",
    ])
  try lab.command("visibility-hide")
  try lab.snapshot("hidden", expecting: ["hidden": "true"])
  try lab.activate()
  try lab.snapshot("recovery", expecting: ["hidden": "false", "frontmost": "true"])
  try lab.command("native-tabs-open")
  try lab.snapshot("native-tabs", expecting: ["tabCount": "2", "tabSelected": "true"])
  try lab.command("native-tabs-second")
  try lab.snapshot("second-tab", expecting: ["tabSelected": "false"])
  try lab.command("native-tabs-close")
  try lab.snapshot("closed-tab", expecting: ["tabCount": "1"])
  // AppKit may require the bar while multiple tabs remain. Exercise one tab.
  try lab.command("native-tabs-show-bar")
  try lab.snapshot("visible-single-tab-bar", expecting: ["tabCount": "1", "tabBar": "true"])
  try lab.command("native-tabs-hide-bar")
  try lab.snapshot("hidden-single-tab-bar", expecting: ["tabCount": "1", "tabBar": "false"])
  try lab.command("native-sheet")
  try lab.snapshot("native-sheet", expecting: ["attached": "true", "sheetCount": "1"])
  try lab.command("close-sheet")
  try lab.snapshot("closed-sheet", expecting: ["attached": "false", "sheetCount": "0"])
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
  passed = true
} catch { print("lab-incomplete \(error)") }
let cleaned = lab.cleanup()
print(
  passed && cleaned
    ? "lab-owned-snapshot-passed; no AX identity or eligibility claim" : "lab-incomplete")
exit(passed && cleaned ? 0 : 1)
