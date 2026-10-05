import AppKit
import Darwin
import Foundation

// Explicit local lab only: fixed bundle paths, private FIFO commands, public
// LaunchServices launches, and metadata-only trace output. No AX calls here.
private struct Event: Sendable {
  let sequence: UInt64
  let lane: String
  let line: String
}

private final class Events: @unchecked Sendable {
  private let condition = NSCondition()
  private var records: [Event] = []
  private var sequence: UInt64 = 0
  private var stopped = false
  private var transcript: FileHandle?

  func record(to url: URL) throws {
    condition.lock()
    defer { condition.unlock() }
    guard
      FileManager.default.createFile(
        atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
    else { throw LabError.failed("Transcript creation failed.") }
    transcript = try FileHandle(forWritingTo: url)
  }

  var cursor: UInt64 {
    condition.lock()
    defer { condition.unlock() }
    return sequence
  }

  var isStopped: Bool {
    condition.lock()
    defer { condition.unlock() }
    return stopped
  }

  func append(_ lane: String, _ line: String) {
    condition.lock()
    defer { condition.unlock() }
    sequence += 1
    records.append(Event(sequence: sequence, lane: lane, line: line))
    if records.count > 1024 { records.removeFirst() }
    let data = Data("\(lane) \(line)\n".utf8)
    FileHandle.standardOutput.write(data)
    transcript?.write(data)
    condition.broadcast()
  }

  func wait(after: UInt64, timeout: Double = 10, matching: (Event) -> Bool) throws -> Event {
    condition.lock()
    defer { condition.unlock() }
    let deadline = Date(timeIntervalSinceNow: timeout)
    while !stopped {
      if let event = records.first(where: { $0.sequence > after && matching($0) }) { return event }
      if !condition.wait(until: deadline) { break }
    }
    throw LabError.failed("Timed out waiting for a fresh event; run is incomplete.")
  }

  func stop() {
    condition.lock()
    stopped = true
    try? transcript?.close()
    transcript = nil
    condition.broadcast()
    condition.unlock()
  }
}

private enum LabError: Error {
  case failed(String)
}

private final class Channel {
  let launcher = Process()
  let input: Int32

  init(lane: String, bundle: String, arguments: [String], directory: URL, events: Events) throws {
    let fifo = directory.appendingPathComponent(lane + ".input")
    let output = directory.appendingPathComponent(lane + ".log")
    guard mkfifo(fifo.path, 0o600) == 0 else { throw LabError.failed("FIFO creation failed.") }
    input = Darwin.open(fifo.path, O_RDWR | O_NONBLOCK)
    guard input >= 0,
      FileManager.default.createFile(
        atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
    else { throw LabError.failed("Private channel creation failed.") }
    launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    launcher.arguments =
      ["-W", "-i", fifo.path, "-o", output.path, "--stderr", "/dev/null", bundle, "--args"]
      + arguments
    try launcher.run()
    Thread.detachNewThread {
      do {
        let handle = try FileHandle(forReadingFrom: output)
        defer { try? handle.close() }
        var buffered = Data()
        while !events.isStopped {
          let data = try handle.read(upToCount: 4096) ?? Data()
          if data.isEmpty {
            Thread.sleep(forTimeInterval: 0.03)
            continue
          }
          buffered.append(data)
          guard buffered.count < 16384 else { break }
          while let end = buffered.firstIndex(of: 10) {
            let line = String(decoding: buffered[..<end], as: UTF8.self)
            buffered.removeSubrange(...end)
            events.append(lane, line)
          }
        }
      } catch { events.append(lane, "output-read-failed") }
    }
  }

  func send(_ command: String) throws {
    let data = Data((command + "\n").utf8)
    let count = data.withUnsafeBytes { Darwin.write(input, $0.baseAddress, $0.count) }
    guard count == data.count else { throw LabError.failed("Command delivery failed.") }
  }

  func stop() {
    try? send("quit")
    Darwin.close(input)
    let deadline = Date(timeIntervalSinceNow: 5)
    while launcher.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.03) }
    // Terminate only this helper's open/wait process if cleanup is incomplete.
    if launcher.isRunning { launcher.terminate() }
  }
}

private func field(_ name: String, in line: String) -> String? {
  line.split(separator: " ").first(where: { $0.hasPrefix(name + "=") })
    .map { String($0.dropFirst(name.count + 1)) }
}

private let events = Events()
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
  "itile-lifecycle-" + UUID().uuidString)
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private var channels: [String: Channel] = [:]
let trace = Process()

do {
  let identifiers = ["local.itile.app", "local.itile.axfixture", "local.itile.axfixture.control"]
  guard
    !NSWorkspace.shared.runningApplications.contains(where: {
      identifiers.contains($0.bundleIdentifier ?? "")
    })
  else {
    throw LabError.failed("Quit existing iTile and fixture instances before starting the lab.")
  }
  try FileManager.default.createDirectory(
    at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  try events.record(to: directory.appendingPathComponent("transcript.log"))
  let pipe = Pipe()
  trace.executableURL = URL(fileURLWithPath: "/usr/bin/log")
  trace.arguments = [
    "stream", "--level", "info", "--style", "compact", "--predicate",
    "subsystem == 'local.itile.app' AND category == 'FocusedProbeTrace'",
  ]
  trace.standardOutput = pipe
  trace.standardError = FileHandle.nullDevice
  try trace.run()
  let traceReader = pipe.fileHandleForReading
  try? pipe.fileHandleForWriting.close()
  Thread.detachNewThread {
    var buffered = Data()
    while !events.isStopped {
      let chunk = traceReader.availableData
      if chunk.isEmpty { break }
      buffered.append(chunk)
      guard buffered.count < 16384 else { break }
      while let end = buffered.firstIndex(of: 10) {
        let line = String(decoding: buffered[..<end], as: UTF8.self)
        buffered.removeSubrange(...end)
        if let start = line.range(of: "phase=") {
          events.append("trace", String(line[start.lowerBound...]))
        }
      }
    }
    try? traceReader.close()
  }
  channels["app"] = try Channel(
    lane: "app", bundle: root.appendingPathComponent("dist/iTile.app").path,
    arguments: ["--manual-probe", "--trace-focused-probe", "--show-probe-report"],
    directory: directory, events: events)
  _ = try events.wait(after: 0) { $0.lane == "app" && $0.line == "manual-ready trusted=true" }
  channels["control"] = try Channel(
    lane: "control", bundle: root.appendingPathComponent("dist/iTile AX Control Fixture.app").path,
    arguments: ["--focused-probe"], directory: directory, events: events)
  _ = try events.wait(after: 0) { $0.lane == "control" && $0.line.hasPrefix("ready ") }
  channels["fixture"] = try Channel(
    lane: "fixture", bundle: root.appendingPathComponent("dist/iTile AX Fixture.app").path,
    arguments: ["--focused-probe", "--nested-probe"], directory: directory, events: events)
  _ = try events.wait(after: 0) { $0.lane == "fixture" && $0.line.hasPrefix("ready ") }
  print("lab-ready; private evidence directory: \(directory.path)")
  print(
    "Commands: prepare-menu, sample, sheet-remove, sheet-open, focus-loss, focus-switch, permission-prepare, permission-run, permission-cycle, app <command>, fixture <command>, quit"
  )

  func configure(_ scenario: String) throws {
    let cursor = events.cursor
    try channels["fixture"]!.send(scenario)
    _ = try events.wait(after: cursor) {
      $0.lane == "fixture" && $0.line.hasPrefix(scenario + "-ready ")
    }
  }
  func activate() throws {
    let cursor = events.cursor
    try channels["fixture"]!.send("activate")
    _ = try events.wait(after: cursor) {
      $0.lane == "fixture" && $0.line.hasPrefix("activation-confirmed ")
    }
  }
  func inspect(pollTrust: Bool = false) throws {
    let cursor = events.cursor
    try channels["app"]!.send("inspect")
    let admission = try events.wait(after: cursor) {
      $0.lane == "trace" && field("phase", in: $0.line) == "admitted"
    }
    guard let request = field("request", in: admission.line) else {
      throw LabError.failed("Missing request identity.")
    }
    // Fixed, bounded metadata-only trust sampling through the existing app
    // status command. This host thread owns no AX objects and is joined before
    // channel teardown. FIFO writes are smaller than PIPE_BUF and atomic.
    let sampling = DispatchGroup()
    if pollTrust {
      let input = channels["app"]!.input
      sampling.enter()
      Thread.detachNewThread {
        defer { sampling.leave() }
        let deadline = Date(timeIntervalSinceNow: 1.2)
        let data = Data("status\n".utf8)
        while Date() < deadline {
          let count = data.withUnsafeBytes { Darwin.write(input, $0.baseAddress, $0.count) }
          if count != data.count { break }
          Thread.sleep(forTimeInterval: 0.05)
        }
      }
    }
    defer { sampling.wait() }
    _ = try events.wait(after: cursor) {
      $0.lane == "trace" && field("request", in: $0.line) == request
        && ["presented", "discarded", "contextRejected"].contains(field("phase", in: $0.line) ?? "")
    }
    let reportCursor = events.cursor
    try channels["app"]!.send("report")
    _ = try events.wait(after: reportCursor) { $0.lane == "app" && $0.line == "manual-report-end" }
    print("lab-inspection-complete request=\(request)")
  }

  while let command = readLine() {
    if command == "quit" { break }
    do {
      switch command {
      case "prepare-menu":
        try configure("tree-nested-sheet")
        try activate()
      case "sample":
        try configure("tree-nested-sheet")
        try activate()
        try inspect()
      case "sheet-remove":
        try configure("tree-sheet-remove")
        try activate()
        try inspect()
      case "sheet-open":
        try configure("tree-native-sheet-open")
        try activate()
        try inspect()
      case "focus-loss":
        try configure("tree-focus-loss")
        try activate()
        try inspect()
      case "focus-switch":
        try configure("tree-focus-switch")
        try activate()
        try inspect()
      case "permission-prepare":
        try configure("tree-budget")
        try activate()
      case "permission-run": try inspect()
      case "permission-cycle":
        for _ in 0..<3 {
          try configure("tree-budget")
          try activate()
          try inspect(pollTrust: true)
        }
      default:
        let fields = command.split(separator: " ", maxSplits: 1)
        guard fields.count == 2, let channel = channels[String(fields[0])] else {
          throw LabError.failed("Unknown command.")
        }
        try channel.send(String(fields[1]))
      }
      print("lab-command-done \(command)")
    } catch { print("lab-incomplete \(error)") }
  }
} catch { print("lab-failed \(error)") }
for channel in channels.values { channel.stop() }
if trace.isRunning { trace.terminate() }
events.stop()
print("lab-stopped; inspect evidence and process cleanup before accepting a run.")
