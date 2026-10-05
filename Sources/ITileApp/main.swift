import AppKit
import ITileCore
import ITilePlatform

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private var statusItem: NSStatusItem?
  private let permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private let applicationsMenu = NSMenu()
  private var workers: [Int32: (app: NSRunningApplication, probe: WindowProbe)] = [:]
  private var generation: UInt64 = 0
  private var epoch: UInt64 = 0
  private var environmentEpoch: UInt64 = 0
  private var paused = false
  private var reportWindow: NSWindow?
  private var reportView: NSTextView?
  private var activationRevision: UInt64 = 0
  private var focusedRequest: UInt64?
  // Historical comparison only, never live enrollment or an admission permit.
  private var focusedCandidate: WindowToken?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "iTile"
    let menu = NSMenu()
    menu.delegate = self
    menu.addItem(
      NSMenuItem(title: "M1 read-only probe — no window control", action: nil, keyEquivalent: ""))
    menu.addItem(permissionItem)
    add("Enable Accessibility for inspection…", action: #selector(requestPermission), to: menu)
    let inspect = NSMenuItem(title: "Inspect application", action: nil, keyEquivalent: "")
    inspect.submenu = applicationsMenu
    menu.addItem(inspect)
    add("Inspect focused window (read-only)", action: #selector(inspectFocused), to: menu)
    add(
      "Revalidate last focused window (read-only)", action: #selector(revalidateFocused), to: menu)
    add("Pause inspections", action: #selector(togglePause(_:)), to: menu)
    add("Copy diagnostic report", action: #selector(copyReport), to: menu)
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(
        title: "Quit iTile", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    item.menu = menu
    statusItem = item
    let workspace = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification,
      NSWorkspace.willSleepNotification,
    ] {
      workspace.addObserver(self, selector: #selector(environmentChanged), name: name, object: nil)
    }
    workspace.addObserver(
      self, selector: #selector(frontmostChanged),
      name: NSWorkspace.didActivateApplicationNotification, object: nil)
    workspace.addObserver(
      self, selector: #selector(applicationTerminated(_:)),
      name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(environmentChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
  }

  private func add(_ title: String, action: Selector, to menu: NSMenu) {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    menu.addItem(item)
  }

  func menuWillOpen(_ menu: NSMenu) {
    permissionItem.title =
      AccessibilityStatus.isTrusted
      ? "Accessibility: granted" : "Accessibility: required for inspection"
    if !AccessibilityStatus.isTrusted {
      invalidateReport("Accessibility permission is missing. Previous observations are stale.")
    }
    applicationsMenu.removeAllItems()
    for app in NSWorkspace.shared.runningApplications
      .filter({
        $0.activationPolicy == .regular
          && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
      })
      .sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") })
    {
      let item = NSMenuItem(
        title: app.localizedName ?? "Application", action: #selector(inspect(_:)), keyEquivalent: ""
      )
      item.target = self
      item.representedObject = app
      item.isEnabled = !paused
      applicationsMenu.addItem(item)
    }
  }

  @objc private func requestPermission() {
    let alert = NSAlert()
    alert.messageText = "Allow read-only window inspection"
    alert.informativeText =
      "Enable iTile in System Settings → Privacy & Security → Accessibility. iTile will inspect an application only when you choose it. It never moves windows or reads window titles. Rebuilt ad-hoc apps may need permission granted again."
    alert.addButton(withTitle: "Open Accessibility Settings")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn,
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      AccessibilityStatus.requestAccess()
      NSWorkspace.shared.open(url)
    }
  }

  @objc private func togglePause(_ sender: NSMenuItem) {
    paused.toggle()
    sender.title = paused ? "Resume inspections" : "Pause inspections"
    invalidateReport(
      paused
        ? "Inspections paused. In-flight reads may finish; their results are discarded."
        : "Ready. Choose an application to inspect.")
  }

  @objc private func environmentChanged() {
    invalidateReport(
      "Desktop/display or sleep state changed. Previous observations are stale; inspect again.")
  }

  @objc private func frontmostChanged() {
    activationRevision += 1
    if focusedRequest != nil {
      epoch += 1
      focusedRequest = nil
      focusedCandidate = nil
      statusItem?.button?.toolTip = "Focus changed during inspection. Inspect again."
      reportView?.string = "Focus changed during inspection. Result discarded; inspect again."
    }
  }

  private func invalidateReport(_ reason: String) {
    focusedRequest = nil
    focusedCandidate = nil
    statusItem?.button?.toolTip = nil
    epoch += 1
    environmentEpoch += 1
    reportView?.string = reason
  }

  @objc private func applicationTerminated(_ notification: Notification) {
    guard
      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    else { return }
    workers.removeValue(forKey: app.processIdentifier)?.probe.stop()
    invalidateReport("An application exited. Inspect again for a fresh snapshot.")
  }

  @objc private func inspect(_ sender: NSMenuItem) {
    guard !paused, let app = sender.representedObject as? NSRunningApplication, !app.isTerminated
    else { return }
    guard AccessibilityStatus.isTrusted else {
      showReport("Accessibility permission required. Use Enable Accessibility for inspection…")
      return
    }
    guard let probe = worker(for: app) else { return }
    let pid = app.processIdentifier
    focusedRequest = nil
    // Each UI request supersedes the previous displayed report, without enqueuing extra work.
    epoch += 1
    let requestEpoch = epoch
    let displays = displayReport()
    let accepted = probe.inspect(environmentEpoch: environmentEpoch) { [weak self] report in
      Task { @MainActor in
        guard let self, self.epoch == requestEpoch, !self.paused,
          !app.isTerminated, AccessibilityStatus.isTrusted,
          self.workers[pid]?.probe.token == probe.token
        else { return }
        self.showReport(displays + "\n\n" + report)
      }
    }
    showReport(
      accepted
        ? "Inspecting app-\(probe.token.generation)… Menu and Quit remain available."
        : "This application's worker is still busy. Try again after it finishes; no additional request was queued."
    )
  }

  private func worker(for app: NSRunningApplication) -> WindowProbe? {
    let pid = app.processIdentifier
    if let existing = workers[pid],
      existing.app.isTerminated || existing.app.launchDate != app.launchDate
    {
      existing.probe.stop()
      workers.removeValue(forKey: pid)
    }
    if workers[pid] == nil {
      guard workers.count < 16 else {
        showReport(
          "Worker limit (16) reached. Quit and reopen iTile to inspect a different set of applications."
        )
        return nil
      }
      generation += 1
      workers[pid] = (app, WindowProbe(token: AppToken(pid: pid, generation: generation)))
    }
    return workers[pid]!.probe
  }

  @objc private func inspectFocused() { beginFocusedInspection(revalidate: false) }
  @objc private func revalidateFocused() { beginFocusedInspection(revalidate: true) }

  private func beginFocusedInspection(revalidate: Bool) {
    guard !paused else { return }
    guard AccessibilityStatus.isTrusted else {
      invalidateReport("Accessibility permission required.")
      showReport("Accessibility permission required. Use Enable Accessibility for inspection…")
      return
    }
    guard let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated,
      app.activationPolicy == .regular,
      app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else {
      showReport(
        "Activate the window you want to inspect, then use the iTile menu. No focus action was performed."
      )
      return
    }
    guard let probe = worker(for: app) else { return }
    let expected = revalidate ? focusedCandidate : nil
    if revalidate && (expected == nil || expected?.app != probe.token) {
      showReport(
        "No matching historical focused token for this app. Choose Inspect focused window first.")
      return
    }
    epoch += 1
    let request = epoch
    let context = FocusRequestContext(
      app: probe.token, environmentEpoch: environmentEpoch,
      activationRevision: activationRevision)
    let displays = displayReport().replacingOccurrences(of: "iTile M1", with: "iTile M2.2")
    focusedRequest = request
    let accepted = probe.inspectFocused(environmentEpoch: environmentEpoch, expected: expected) {
      [weak self] result in
      Task { @MainActor in
        guard let self, self.epoch == request, self.focusedRequest == request else { return }
        self.focusedRequest = nil
        let front = NSWorkspace.shared.frontmostApplication
        let sameProcess =
          !app.isTerminated && front?.processIdentifier == app.processIdentifier
          && front?.launchDate == app.launchDate
          && self.workers[app.processIdentifier]?.probe.token == probe.token
        guard
          context.accepts(
            currentApp: sameProcess ? probe.token : nil,
            environmentEpoch: self.environmentEpoch, activationRevision: self.activationRevision,
            trusted: AccessibilityStatus.isTrusted, paused: self.paused)
        else {
          self.focusedCandidate = nil
          self.statusItem?.button?.toolTip = "Focused result stale. Inspect again."
          self.reportView?.string = "Focused result stale. Inspect again."
          return
        }
        self.focusedCandidate = nil
        if case .observation(let evidence) = result,
          case .value(true) = evidence.focusedWindowUnchanged,
          case .value(true) = evidence.destructionNotification,
          evidence.expectedWindowMatches != false
        {
          self.focusedCandidate = evidence.token
        }
        self.statusItem?.button?.toolTip = nil
        self.showReport(
          displays + "\n\n" + result.report
            + "\nFrontmost app checked before presentation. Opening this report can change focus; revalidation requires returning to the source window."
        )
      }
    }
    if accepted {
      // Do not show/activate the report until the final frontmost check.
      statusItem?.button?.toolTip = "Inspecting focused window…"
    } else {
      focusedRequest = nil
      showReport("This application's worker is busy. No focused request was queued.")
    }
  }

  private func displayReport() -> String {
    let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
    var lines = [
      "iTile M1 — explicit read-only diagnostic",
      "OS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
      "Requested: \(Date().ISO8601Format()); environment epoch: \(environmentEpoch)",
      "Coordinates: logical points, x rightward, y downward. Snapshots are not atomic.",
    ]
    for (index, screen) in NSScreen.screens.enumerated() {
      let frame = screen.visibleFrame
      let converted = DesktopCoordinates.flip(
        Rect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
        primaryTop: primaryTop)
      lines.append(
        "Display \(index): usable=(\(converted.x), \(converted.y), \(converted.width), \(converted.height)), scale=\(screen.backingScaleFactor)"
      )
    }
    return lines.joined(separator: "\n")
  }

  private func showReport(_ report: String) {
    if reportWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
        styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered,
        defer: false)
      window.title = "iTile — Read-only diagnostic"
      window.isReleasedWhenClosed = false
      // Bring our report to the user's desktop instead of activating its old Space.
      // Otherwise showing a diagnostic invalidates the environment being inspected.
      window.collectionBehavior = [.moveToActiveSpace]
      let scroll = NSScrollView(frame: window.contentView!.bounds)
      scroll.autoresizingMask = [.width, .height]
      scroll.hasVerticalScroller = true
      let text = NSTextView(frame: scroll.bounds)
      text.isEditable = false
      text.isVerticallyResizable = true
      text.autoresizingMask = [.width]
      text.textContainer?.widthTracksTextView = true
      text.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
      scroll.documentView = text
      window.contentView?.addSubview(scroll)
      window.center()
      reportWindow = window
      reportView = text
    }
    reportView?.string = report
    reportWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func copyReport() {
    guard let report = reportView?.string else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(report, forType: .string)
  }

  func applicationWillTerminate(_ notification: Notification) {
    for worker in workers.values { worker.probe.stop() }
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    NotificationCenter.default.removeObserver(self)
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
