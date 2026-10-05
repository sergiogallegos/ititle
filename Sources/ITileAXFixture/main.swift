import AppKit

@MainActor
private func emitFixtureEvent(_ event: String) {
  let line = "\(event) \(ProcessInfo.processInfo.systemUptime)\n"
  FileHandle.standardOutput.write(Data(line.utf8))
}

/// A one-shot fault in this owned fixture's public AX accessor. Arming does not
/// itself change focus; the subsequent focused-window read causes the fault.
@MainActor
final class FixtureApplication: NSApplication {
  var hideOnFocusedRead = false

  override func accessibilityFocusedWindow() -> Any? {
    let focusedWindow = super.accessibilityFocusedWindow()
    guard hideOnFocusedRead else { return focusedWindow }
    hideOnFocusedRead = false
    emitFixtureEvent("focused-read-begin")
    hide(nil)
    emitFixtureEvent("focused-read-hide")
    // Keep the request outstanding across activation delivery. This bounded
    // pause affects only the disposable fixture, never a user's application.
    Thread.sleep(forTimeInterval: 0.1)
    emitFixtureEvent("focused-read-end")
    return focusedWindow
  }
}

/// Stalls a window read after AXFocusedWindow has already been acquired. The
/// worker can encounter several bounded timeouts while this fixture recovers.
@MainActor
final class FixtureWindow: NSWindow {
  var stallOnRoleRead = false

  override func accessibilityRole() -> NSAccessibility.Role? {
    guard stallOnRoleRead else { return super.accessibilityRole() }
    stallOnRoleRead = false
    emitFixtureEvent("window-read-begin")
    Thread.sleep(forTimeInterval: 1.5)
    emitFixtureEvent("window-read-end")
    return super.accessibilityRole()
  }
}

/// Deliberately stalls only this disposable process. Never sends AX calls to other apps.
@MainActor
final class FixtureDelegate: NSObject, NSApplicationDelegate {
  private var window: FixtureWindow?
  private let state = NSTextField(labelWithString: "Ready — controlled by iTile P3 Lab")

  func applicationDidFinishLaunching(_ notification: Notification) {
    let label = CommandLine.arguments.contains("--slow") ? "Delayed" : "Control"
    let window = FixtureWindow(
      contentRect: NSRect(x: 200, y: 200, width: 420, height: 130),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "iTile P3 \(label) Fixture"
    window.isReleasedWhenClosed = false
    state.frame = NSRect(x: 20, y: 45, width: 380, height: 40)
    window.contentView?.addSubview(state)
    window.orderFront(nil)
    if CommandLine.arguments.contains("--focused-probe") {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    self.window = window
    emit("ready")
    // Only this process's parent owns stdin. EOF exits; no listener or network service.
    Thread.detachNewThread { [weak self] in
      while let command = readLine() {
        guard ["stall", "quit", "arm-focus-loss", "arm-window-stall", "activate"].contains(command)
        else { continue }
        DispatchQueue.main.async { [weak self] in
          if command == "quit" {
            NSApp.terminate(nil)
            return
          }
          if command == "activate" {
            guard CommandLine.arguments.contains("--focused-probe") else { return }
            NSApp.unhide(nil)
            self?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            emitFixtureEvent("activation-requested")
            return
          }
          if command == "arm-focus-loss" {
            guard CommandLine.arguments.contains("--focused-probe"),
              let app = NSApp as? FixtureApplication
            else { return }
            app.hideOnFocusedRead = true
            emitFixtureEvent("focus-loss-armed")
            return
          }
          if command == "arm-window-stall" {
            guard CommandLine.arguments.contains("--focused-probe") else { return }
            self?.window?.stallOnRoleRead = true
            emitFixtureEvent("window-stall-armed")
            return
          }
          self?.stall()
        }
      }
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }
  }

  private func stall() {
    guard CommandLine.arguments.contains("--slow") else { return }
    state.stringValue = "Pausing this fixture's event loop for 1.5 seconds…"
    state.displayIfNeeded()
    emit("begin")
    // Intentional fixture fault, not production AX dispatch. Finite, no busy spin.
    Thread.sleep(forTimeInterval: 1.5)
    state.stringValue = "Recovered — ready for another measurement"
    // This public accessibility notification provides observer-lag evidence without
    // changing a real title or collecting any content from user applications.
    emit("notification")
    if let window { NSAccessibility.post(element: window, notification: .titleChanged) }
    emit("end")
  }

  private func emit(_ event: String) {
    emitFixtureEvent(event)
  }
}

let app = FixtureApplication.shared
let delegate = FixtureDelegate()
app.delegate = delegate
// Explicit manual-test mode only: make this disposable process selectable as
// the frontmost app by the M2.2 probe. P3's default accessory behavior is unchanged.
app.setActivationPolicy(CommandLine.arguments.contains("--focused-probe") ? .regular : .accessory)
app.run()
