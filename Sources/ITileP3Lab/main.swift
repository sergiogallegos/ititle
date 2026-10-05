import AppKit
import ITileCore
import ITilePlatform

private struct Sample {
  let phase: String
  let trial: Int
  let lane: String
  let start: Double
  let end: Double
  let report: String
  var duration: Double { end - start }
}

/// Owns only processes launched by this lab. Pipe reads stay on a dedicated thread.
@MainActor
private final class Fixture {
  let process = Process()
  private let input = Pipe()
  private let output = Pipe()

  init(slow: Bool, event: @escaping @MainActor @Sendable (String, Double) -> Void) throws {
    let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/iTileAXFixture")
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
      throw CocoaError(.fileNoSuchFile)
    }
    process.executableURL = executable
    process.arguments = slow ? ["--slow"] : []
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    // Parent does not retain child-only pipe ends; EOF remains observable.
    try? output.fileHandleForWriting.close()
    try? input.fileHandleForReading.close()
    let reader = output.fileHandleForReading
    Thread.detachNewThread {
      var buffered = Data()
      do {
        while let chunk = try FixturePipe.readChunk(from: reader) {
          buffered.append(chunk)
          guard buffered.count <= 4096 else { break }
          while let end = buffered.firstIndex(of: 10) {
            let line = String(decoding: buffered[..<end], as: UTF8.self)
            buffered.removeSubrange(...end)
            let fields = line.split(separator: " ")
            guard fields.count == 2,
              ["ready", "begin", "notification", "end"].contains(String(fields[0])),
              let time = Double(fields[1]), time.isFinite, time >= 0
            else { continue }
            let name = String(fields[0])
            DispatchQueue.main.async { event(name, time) }
          }
        }
      } catch {
        // EOF/error becomes a visible fixture exit event.
      }
      try? reader.close()
      DispatchQueue.main.async { event("exit", ProcessInfo.processInfo.systemUptime) }
    }
  }

  func stall() throws { try input.fileHandleForWriting.write(contentsOf: Data("stall\n".utf8)) }
  func stop() {
    try? input.fileHandleForWriting.close()
    if process.isRunning { process.terminate() }
  }
}

@MainActor
final class LabDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow!
  private var text: NSTextView!
  private var startButton: NSButton!
  private var stopButton: NSButton!
  private var fixtures: [String: Fixture] = [:]
  private var probes: [String: WindowProbe] = [:]
  private var ready: Set<String> = []
  private var samples: [Sample] = []
  private var notices: [String] = []
  private var begins: [Int: Double] = [:]
  private var ends: [Int: Double] = [:]
  private var posts: [Int: Double] = [:]
  private var arrivals: [Double] = []
  private var runID = UUID()
  private var running = false
  private var phase = "idle"
  private var trial = 0
  private var pending: Set<String> = []
  private var pairID = UUID()
  private var stallEnded = false
  private var heartbeat: Timer?
  private var previousBeat: Double?
  private var beats: [Double] = []
  private let trials = 5
  private var header = ""
  private var summaryText = ""

  func applicationDidFinishLaunching(_ notification: Notification) {
    let menu = NSMenu()
    let root = NSMenuItem()
    menu.addItem(root)
    let appMenu = NSMenu()
    root.submenu = appMenu
    appMenu.addItem(
      withTitle: "Quit P3 Lab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    NSApp.mainMenu = menu
    window = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 920, height: 650),
      styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false
    )
    window.title = "iTile P3 Lab — Read-only AX isolation experiment"
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace]
    let view = window.contentView!
    startButton = button("Start 5-trial experiment", #selector(start), x: 16, width: 210)
    stopButton = button("Stop", #selector(stop), x: 240, width: 70)
    stopButton.isEnabled = false
    _ = button("Enable Accessibility…", #selector(permission), x: 322, width: 190)
    _ = button("Copy summary", #selector(copyReport), x: 525, width: 130)
    _ = button("Copy full report", #selector(copyFullReport), x: 667, width: 150)
    let scroll = NSScrollView(frame: NSRect(x: 16, y: 16, width: 888, height: 570))
    scroll.autoresizingMask = [.width, .height]
    scroll.hasVerticalScroller = true
    text = NSTextView(frame: scroll.bounds)
    text.isEditable = false
    text.isVerticallyResizable = true
    text.autoresizingMask = [.width]
    text.textContainer?.widthTracksTextView = true
    text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    scroll.documentView = text
    view.addSubview(scroll)
    text.string =
      "This lab opens two disposable fixture windows and reads only those processes.\n\nFive trials pause one fixture's event loop for 1.5 seconds while the other remains responsive. The production AX worker uses a 0.2-second per-handle timeout. The lab measures AXWindows IPC, whole-request times, fixture intervals, notification arrival, and its own UI heartbeat.\n\nStart requires this lab's Accessibility permission. Stop and Quit terminate only the lab's fixture processes. No existing windows are changed; no results are saved unless you copy the report.\n\nThe experiment takes roughly 15–25 seconds. Keep the Mac awake and remain on this desktop. Results require review; completing a run does not mean P3 passed."
    summaryText = text.string
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func button(_ title: String, _ action: Selector, x: Double, width: Double) -> NSButton {
    let button = NSButton(title: title, target: self, action: action)
    button.frame = NSRect(x: x, y: 603, width: width, height: 30)
    button.autoresizingMask = [.minYMargin]
    window.contentView?.addSubview(button)
    return button
  }

  @objc private func permission() {
    AccessibilityStatus.requestAccess()
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
  }

  @objc private func start() {
    guard !running else { return }
    guard AccessibilityStatus.isTrusted else {
      text.string =
        "Accessibility permission required for iTile P3 Lab. Use Enable Accessibility…, enable this lab in System Settings, then try Start again. Your existing iTile app is separate and unchanged."
      summaryText = text.string
      return
    }
    runID = UUID()
    let id = runID
    running = true
    phase = "launch"
    trial = 0
    fixtures.removeAll()
    probes.removeAll()
    ready.removeAll()
    samples.removeAll()
    begins.removeAll()
    ends.removeAll()
    posts.removeAll()
    arrivals.removeAll()
    notices.removeAll()
    beats.removeAll()
    previousBeat = nil
    header =
      "iTile P3 Lab v1\nRequested: \(Date().ISO8601Format())\nOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nMachine architecture: \(architecture)\nPer-handle timeout: 0.2 s; induced main-loop pause: 1.5 s; trials: \(trials)\nAll IPC is read-only and targets only the two disposable child processes.\n"
    startButton.isEnabled = false
    stopButton.isEnabled = true
    heartbeat = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = self.previousBeat, self.beats.count < 2000 {
          self.beats.append(now - previous)
        }
        self.previousBeat = now
        if self.phase == "launch", self.beats.count.isMultiple(of: 20) { self.render() }
      }
    }
    if let heartbeat { RunLoop.main.add(heartbeat, forMode: .common) }
    do {
      for lane in ["delayed", "control"] {
        fixtures[lane] = try Fixture(slow: lane == "delayed") { [weak self] event, time in
          guard let self, self.running, self.runID == id else { return }
          self.receive(lane: lane, event: event, time: time)
        }
      }
    } catch {
      finish("Fixture launch failed. Use the packaged P3 Lab app.")
      return
    }
    render()
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
      guard let self, self.running, self.runID == id, self.phase == "launch" else { return }
      self.finish("Fixture ready timeout after 10 seconds; no AX measurements collected.")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
      guard let self, self.running, self.runID == id else { return }
      self.finish(
        "Run watchdog expired; incomplete. Workers are stopped without waiting for blocked IPC.")
    }
  }

  private var architecture: String {
    #if arch(arm64)
      return "arm64"
    #else
      return "x86_64"
    #endif
  }

  private func receive(lane: String, event: String, time: Double) {
    switch event {
    case "ready":
      ready.insert(lane)
      render()
      if ready.count == 2 && phase == "launch" {
        let id = runID
        for (index, name) in ["delayed", "control"].enumerated() {
          guard let fixture = fixtures[name] else { return }
          let token = AppToken(
            pid: fixture.process.processIdentifier, generation: UInt64(index + 1))
          let notification: (@Sendable (Double) -> Void)?
          if name == "delayed" {
            notification = { [weak self] arrival in
              DispatchQueue.main.async { [weak self] in
                guard let self, self.running, self.runID == id, self.arrivals.count < 64 else {
                  return
                }
                self.arrivals.append(arrival)
              }
            }
          } else {
            notification = nil
          }
          probes[name] = WindowProbe(token: token, diagnosticNotification: notification)
        }
        runPair("baseline")
      }
    case "begin":
      guard lane == "delayed", phase == "arming" else { return }
      begins[trial] = time
      runPair("stalled")
    case "notification":
      guard lane == "delayed" else { return }
      posts[trial] = time
    case "end":
      guard lane == "delayed", phase == "stalled" else { return }
      ends[trial] = time
      stallEnded = true
      if pending.isEmpty { runPair("recovery") }
    case "exit": finish("A fixture exited unexpectedly; incomplete.")
    default: break
    }
  }

  private func runPair(_ name: String) {
    phase = name
    pending = ["delayed", "control"]
    pairID = UUID()
    let pair = pairID
    let id = runID
    let sampleTrial = trial
    for lane in ["delayed", "control"] {
      let start = ProcessInfo.processInfo.systemUptime
      let accepted =
        probes[lane]?.inspect(environmentEpoch: 0) { [weak self] report in
          let end = ProcessInfo.processInfo.systemUptime
          Task { @MainActor in
            guard let self, self.running, self.runID == id, self.pairID == pair else { return }
            self.samples.append(
              Sample(
                phase: name, trial: sampleTrial, lane: lane, start: start, end: end, report: report)
            )
            self.pending.remove(lane)
            self.render()
            if self.pending.isEmpty { self.pairFinished() }
          }
        } ?? false
      if !accepted {
        finish("Worker rejected a scheduled request; incomplete.")
        return
      }
    }
    render()
  }

  private func pairFinished() {
    switch phase {
    case "baseline":
      // A failed baseline cannot provide a valid delayed/healthy comparison.
      guard samples.suffix(2).allSatisfy({ $0.report.contains("subrole=AXStandardWindow") }) else {
        finish(
          "Baseline did not discover both fixture windows. Review raw observations; do not infer isolation."
        )
        return
      }
      armNext()
    case "stalled": if stallEnded { runPair("recovery") }
    case "recovery":
      if trial < trials {
        armNext()
      } else {
        phase = "settling"
        let id = runID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
          guard let self, self.running, self.runID == id else { return }
          self.finish(
            "Sampling complete — review timings, errors, overlap, and missing notifications. No automatic P3 pass."
          )
        }
      }
    default: break
    }
  }

  private func armNext() {
    trial += 1
    stallEnded = false
    phase = "arming"
    do { try fixtures["delayed"]?.stall() } catch {
      finish("Could not arm fixture; incomplete.")
      return
    }
    render()
  }

  @objc private func stop() { if running { finish("Stopped by user; partial observations only.") } }

  private func finish(_ message: String) {
    running = false
    phase = "finished"
    heartbeat?.invalidate()
    heartbeat = nil
    notices.append(message)
    for probe in probes.values { probe.stop() }
    for fixture in fixtures.values { fixture.stop() }
    startButton.isEnabled = true
    stopButton.isEnabled = false
    render()
  }

  private func summary(_ label: String, _ values: [Double]) -> String {
    guard let s = LatencySummary(values) else { return "\(label): no valid samples" }
    return String(
      format: "%@: n=%d min=%.3f median=%.3f p95=%.3f max=%.3f ms", label, s.count,
      s.minimum * 1000, s.median * 1000, s.p95 * 1000, s.maximum * 1000)
  }

  private func render() {
    var lines =
      [header, "State: \(phase); trial: \(trial)/\(trials); fixtures ready: \(ready.count)/2"]
      + notices
    for lane in ["delayed", "control"] {
      for group in ["baseline", "stalled", "recovery"] {
        lines.append(
          summary(
            "\(lane) \(group) whole request",
            samples.filter { $0.lane == lane && $0.phase == group }.map(\.duration)))
      }
    }
    lines.append(summary("Lab main-loop heartbeat interval (nominal 50 ms)", beats))
    lines.append(
      "Small empirical samples, not performance guarantees. IPC durations exclude surrounding worker cleanup; whole-request durations include it."
    )
    lines.append("\nPer-sample timing / AX result:")
    for sample in samples {
      let ipc =
        sample.report.split(separator: "\n").first { $0.hasPrefix("AXWindows IPC:") }.map(
          String.init) ?? "AXWindows timing unavailable"
      var overlap = ""
      if sample.phase == "stalled", let begin = begins[sample.trial], let end = ends[sample.trial] {
        overlap =
          "; started-during-pause=\(sample.start >= begin && sample.start < end); finished-before-resume=\(sample.end < end)"
      }
      lines.append(
        String(
          format: "trial %d %@ %@: %.3f ms; %@%@", sample.trial, sample.phase, sample.lane,
          sample.duration * 1000, ipc, overlap))
    }
    lines.append("\nFixture and notification evidence (same host monotonic clock):")
    var unmatched = arrivals.sorted()
    var observerLags: [Double] = []
    for n in 1...trials {
      guard let begin = begins[n], let end = ends[n] else { continue }
      lines.append(
        String(
          format: "trial %d fixture pause: %.3f ms; begin=%.6f; end=%.6f", n, (end - begin) * 1000,
          begin, end))
      if let post = posts[n],
        let index = unmatched.firstIndex(where: { $0 >= post && $0 <= end + 1 })
      {
        let arrived = unmatched.remove(at: index)
        observerLags.append(arrived - post)
        lines.append(
          String(
            format: "  post-to-worker observer arrival: %.3f ms (candidate correlation)",
            (arrived - post) * 1000))
      } else {
        lines.append("  observer arrival: missing/unmatched (not zero lag)")
      }
    }
    lines.append(summary("Matched observer arrivals (candidate correlations)", observerLags))
    summaryText = lines.joined(separator: "\n")
    lines.append("\nRaw redacted observations:")
    for sample in samples {
      lines.append(
        "--- trial \(sample.trial), \(sample.phase), \(sample.lane) ---\n\(sample.report)")
    }
    text.string = lines.joined(separator: "\n")
  }

  @objc private func copyReport() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(summaryText, forType: .string)
  }

  @objc private func copyFullReport() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text.string, forType: .string)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func applicationWillTerminate(_ notification: Notification) {
    heartbeat?.invalidate()
    for probe in probes.values { probe.stop() }
    for fixture in fixtures.values { fixture.stop() }
  }
}

let app = NSApplication.shared
let delegate = LabDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
