import AppKit
import ITilePlatform

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "iTile"
        let menu = NSMenu()
        let status = NSMenuItem(title: "Foundation preview — tiling not enabled", action: nil, keyEquivalent: "")
        menu.addItem(status)
        let permission = AccessibilityStatus.isTrusted ? "Accessibility: granted" : "Accessibility: not granted (not needed for preview)"
        menu.addItem(NSMenuItem(title: permission, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit iTile", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
