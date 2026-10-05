import AppKit

/// Deliberately stalls only this disposable process. Never sends AX calls to other apps.
@MainActor
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let state = NSTextField(labelWithString: "Ready — controlled by iTile P3 Lab")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let label = CommandLine.arguments.contains("--slow") ? "Delayed" : "Control"
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 420, height: 130),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "iTile P3 \(label) Fixture"
        window.isReleasedWhenClosed = false
        state.frame = NSRect(x: 20, y: 45, width: 380, height: 40)
        window.contentView?.addSubview(state)
        window.orderFront(nil)
        self.window = window
        emit("ready")
        // Only this process's parent owns stdin. EOF exits; no listener or network service.
        Thread.detachNewThread { [weak self] in
            while let command = readLine() {
                guard command == "stall" || command == "quit" else { continue }
                DispatchQueue.main.async { [weak self] in
                    if command == "quit" { NSApp.terminate(nil); return }
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
        let line = "\(event) \(ProcessInfo.processInfo.systemUptime)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }
}

let app = NSApplication.shared
let delegate = FixtureDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
