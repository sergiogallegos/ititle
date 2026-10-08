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

/// Synthetic structural elements owned by this disposable fixture. These are
/// public AppKit AX objects, not a claim about native application's tree shape.
@MainActor
final class StructuralFault {
  var childDelay: Double = 0
  var hideOnChildrenRead = false
  var stallOnChildrenRead = false
  var transitionOnChildrenRead: (@MainActor () -> Void)?

  func run() {
    if let transition = transitionOnChildrenRead {
      transitionOnChildrenRead = nil
      transition()
    }
    if hideOnChildrenRead {
      hideOnChildrenRead = false
      emitFixtureEvent("nested-focus-loss-begin")
      let accepted = NSRunningApplication.current.hide()
      emitFixtureEvent(accepted ? "nested-hide-accepted" : "nested-hide-rejected")
      // Let this owned fixture process the asynchronous hide request. Sleeping
      // in this accessor can prevent the main loop from applying it at all.
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
      emitFixtureEvent(
        NSWorkspace.shared.frontmostApplication?.processIdentifier
          == ProcessInfo.processInfo.processIdentifier
          ? "nested-still-frontmost" : "nested-no-longer-frontmost")
      emitFixtureEvent("nested-focus-loss-end")
    }
    if stallOnChildrenRead {
      stallOnChildrenRead = false
      emitFixtureEvent("nested-stall-begin")
      Thread.sleep(forTimeInterval: 1.5)
      emitFixtureEvent("nested-stall-end")
    }
    if childDelay > 0 { Thread.sleep(forTimeInterval: childDelay) }
  }
}

@MainActor
final class FixtureStructuralNode: NSAccessibilityElement {
  let fault = StructuralFault()

  nonisolated override func accessibilityChildren() -> [Any]? {
    // AppKit's element protocol is nonisolated. Only fault on its main-thread
    // callback; never access fixture UI state from an unexpected callback lane.
    if Thread.isMainThread {
      let fault = fault
      MainActor.assumeIsolated { fault.run() }
    }
    return super.accessibilityChildren()
  }
}

/// Stalls a window read after AXFocusedWindow has already been acquired. The
/// worker can encounter several bounded timeouts while this fixture recovers.
@MainActor
final class FixtureWindow: NSWindow {
  var stallOnRoleRead = false
  var structuralChildren: [Any]?

  override func accessibilityChildren() -> [Any]? {
    structuralChildren ?? super.accessibilityChildren()
  }

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
  private var structuralNodes: [FixtureStructuralNode] = []
  private var sheet: NSWindow?
  private var secondTab: NSWindow?
  private var visibilityPeer: NSWindow?
  private let state = NSTextField(labelWithString: "Ready — controlled by iTile P3 Lab")

  func applicationDidFinishLaunching(_ notification: Notification) {
    let label = CommandLine.arguments.contains("--slow") ? "Delayed" : "Control"
    let window = FixtureWindow(
      contentRect: NSRect(x: 200, y: 200, width: 420, height: 130),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    if CommandLine.arguments.contains("--tab-probe") {
      window.styleMask.insert(.resizable)
      window.tabbingMode = .preferred
      window.tabbingIdentifier = "local.itile.owned-tabs"
    }
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
    if CommandLine.arguments.contains("--desktop-probe") {
      NSWorkspace.shared.notificationCenter.addObserver(
        self, selector: #selector(desktopChanged),
        name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }
    emit("ready")
    // Only this process's parent owns stdin. EOF exits; no listener or network service.
    Thread.detachNewThread { [weak self] in
      while let command = readLine() {
        guard
          [
            "stall", "quit", "arm-focus-loss", "arm-window-stall", "activate",
            "tree-ordinary", "tree-direct-sheet", "tree-nested-sheet", "tree-dialog",
            "tree-system-dialog", "tree-wide", "tree-deep", "tree-cycle", "tree-budget",
            "tree-focus-loss", "tree-focus-switch", "tree-stall", "tree-sheet-remove",
            "tree-native-sheet-open",
            "native-sheet", "close-sheet", "tree-tab-group", "tree-tab-group-cycle",
            "native-tabs-open", "native-tabs-first", "native-tabs-second", "native-tabs-close",
            "visibility-peer-open", "visibility-peer-close", "visibility-hide", "desktop-status",
          ].contains(command)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              emitFixtureEvent(
                NSWorkspace.shared.frontmostApplication?.processIdentifier
                  == ProcessInfo.processInfo.processIdentifier
                  ? "activation-confirmed" : "activation-not-frontmost")
            }
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
          if command == "desktop-status" {
            guard CommandLine.arguments.contains("--desktop-probe") else { return }
            self?.emitDesktopStatus()
            return
          }
          if command.hasPrefix("visibility-") {
            guard CommandLine.arguments.contains("--visibility-probe") else { return }
            self?.configureVisibility(command)
            return
          }
          if command.hasPrefix("native-tabs-") {
            guard CommandLine.arguments.contains("--tab-probe") else { return }
            self?.configureNativeTabs(command)
            return
          }
          if command.hasPrefix("tree-") || ["native-sheet", "close-sheet"].contains(command) {
            guard CommandLine.arguments.contains("--nested-probe") else { return }
            self?.configureStructure(command)
            return
          }
          self?.stall()
        }
      }
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }
  }

  private func configureStructure(_ command: String) {
    guard let window else { return }
    if let sheet {
      window.endSheet(sheet)
      sheet.orderOut(nil)
    }
    sheet = nil
    // Break deliberately cyclic child links before releasing an old scenario.
    window.structuralChildren = nil
    for node in structuralNodes {
      node.fault.transitionOnChildrenRead = nil
      node.setAccessibilityChildren([])
    }
    structuralNodes.removeAll()
    if command == "native-sheet" {
      openNativeSheet()
    } else if command != "close-sheet" {
      func node(_ role: NSAccessibility.Role = .group, parent: AnyObject) -> FixtureStructuralNode {
        let node = FixtureStructuralNode()
        node.setAccessibilityElement(true)
        node.setAccessibilityRole(role)
        node.setAccessibilityParent(parent)
        node.setAccessibilityFrame(window.frame)
        node.setAccessibilityChildren([])
        structuralNodes.append(node)
        return node
      }
      let group = node(parent: window)
      window.structuralChildren = [group]
      switch command {
      case "tree-direct-sheet": window.structuralChildren = [node(.sheet, parent: window)]
      case "tree-nested-sheet": group.setAccessibilityChildren([node(.sheet, parent: group)])
      case "tree-dialog", "tree-system-dialog":
        let dialog = node(.window, parent: group)
        dialog.setAccessibilitySubrole(command == "tree-dialog" ? .dialog : .systemDialog)
        group.setAccessibilityChildren([dialog])
      case "tree-wide":
        var children = [node(.sheet, parent: group)]
        for _ in 0..<79 { children.append(node(parent: group)) }
        group.setAccessibilityChildren(children)
      case "tree-deep":
        var parent = group
        for _ in 0..<8 {
          let child = node(parent: parent)
          parent.setAccessibilityChildren([child])
          parent = child
        }
        parent.setAccessibilityChildren([node(.sheet, parent: parent)])
      case "tree-tab-group", "tree-tab-group-cycle":
        let tabs = node(.tabGroup, parent: group)
        group.setAccessibilityChildren([tabs])
        if command == "tree-tab-group-cycle" { tabs.setAccessibilityChildren([tabs]) }
      case "tree-cycle": group.setAccessibilityChildren([group])
      case "tree-budget":
        group.fault.transitionOnChildrenRead = { emitFixtureEvent("nested-budget-begin") }
        var children: [FixtureStructuralNode] = []
        for _ in 0..<20 {
          let child = node(parent: group)
          child.fault.childDelay = 0.08
          children.append(child)
        }
        children.append(node(.sheet, parent: group))
        group.setAccessibilityChildren(children)
      case "tree-sheet-remove":
        let sheetNode = node(.sheet, parent: group)
        group.setAccessibilityChildren([sheetNode])
        sheetNode.fault.transitionOnChildrenRead = { [weak group] in
          emitFixtureEvent("nested-sheet-remove-begin")
          group?.setAccessibilityChildren([])
          emitFixtureEvent("nested-sheet-remove-end")
        }
      case "tree-native-sheet-open":
        group.fault.transitionOnChildrenRead = { [weak self] in
          emitFixtureEvent("nested-native-sheet-open-begin")
          self?.openNativeSheet()
          emitFixtureEvent("nested-native-sheet-open-end")
        }
      case "tree-focus-loss": group.fault.hideOnChildrenRead = true
      case "tree-focus-switch":
        group.fault.transitionOnChildrenRead = {
          emitFixtureEvent("nested-focus-switch-begin")
          let control = NSRunningApplication.runningApplications(
            withBundleIdentifier: "local.itile.axfixture.control"
          ).first
          let accepted = control?.activate(options: []) == true
          emitFixtureEvent(accepted ? "nested-switch-accepted" : "nested-switch-rejected")
          RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
          emitFixtureEvent(
            NSWorkspace.shared.frontmostApplication?.processIdentifier == control?.processIdentifier
              && control != nil ? "nested-control-frontmost" : "nested-control-not-frontmost")
          emitFixtureEvent("nested-focus-switch-end")
        }
      case "tree-stall": group.fault.stallOnChildrenRead = true
      default: break
      }
    }
    state.stringValue = "Nested probe scenario: \(command)"
    emitFixtureEvent(command + "-ready")
  }

  @objc private func desktopChanged() {
    emitFixtureEvent("desktop-space-changed")
    emitDesktopStatus()
  }

  /// Own-process AppKit ground truth, unavailable to production for other apps.
  private func emitDesktopStatus() {
    guard let window else { return }
    let focused = NSApp.accessibilityFocusedWindow() as? NSWindow
    let source: String
    if focused === window {
      source = "original"
    } else if let visibilityPeer, focused === visibilityPeer {
      source = "peer"
    } else {
      source = focused == nil ? "none" : "other"
    }
    let peerState = visibilityPeer.map { String($0.isOnActiveSpace) } ?? "absent"
    let equal = visibilityPeer.map { String($0.frame == window.frame) } ?? "absent"
    let frontmost =
      NSWorkspace.shared.frontmostApplication?.processIdentifier
      == ProcessInfo.processInfo.processIdentifier
    emitFixtureEvent(
      "desktop-status original-active=\(window.isOnActiveSpace) peer-active=\(peerState) equal=\(equal) focused=\(source) frontmost=\(frontmost) displays=\(NSScreen.screens.count)"
    )
  }

  /// Controlled occlusion/identical-bounds evidence, never another app's windows.
  private func configureVisibility(_ command: String) {
    guard let window, sheet == nil, secondTab == nil, window.structuralChildren == nil else {
      emitFixtureEvent("visibility-rejected")
      return
    }
    switch command {
    case "visibility-peer-open":
      guard visibilityPeer == nil else { break }
      let peer = NSWindow(
        contentRect: window.contentRect(forFrameRect: window.frame),
        styleMask: window.styleMask, backing: .buffered, defer: false)
      peer.isReleasedWhenClosed = false
      peer.tabbingMode = .disallowed
      if CommandLine.arguments.contains("--desktop-probe") {
        peer.collectionBehavior = .moveToActiveSpace
      }
      peer.title = "Owned visibility peer"
      peer.orderFront(nil)
      visibilityPeer = peer
      emitFixtureEvent(
        peer.frame == window.frame ? "visibility-peer-equal" : "visibility-peer-different")
    case "visibility-peer-close":
      visibilityPeer?.close()
      visibilityPeer = nil
    case "visibility-hide": NSApp.hide(nil)
    default: return
    }
    emitFixtureEvent(command + "-ready")
  }

  /// Changes only this disposable application's windows using public AppKit APIs.
  private func configureNativeTabs(_ command: String) {
    guard let window, window.structuralChildren == nil, sheet == nil else {
      emitFixtureEvent("native-tabs-rejected")
      return
    }
    switch command {
    case "native-tabs-open":
      guard secondTab == nil else { break }
      let tab = NSWindow(
        contentRect: window.frame, styleMask: [.titled, .closable, .resizable],
        backing: .buffered, defer: false)
      tab.title = "Owned second tab"
      tab.isReleasedWhenClosed = false
      tab.tabbingMode = .preferred
      tab.tabbingIdentifier = window.tabbingIdentifier
      secondTab = tab
      window.addTabbedWindow(tab, ordered: .above)
      window.tabGroup?.selectedWindow = window
      window.makeKeyAndOrderFront(nil)
    case "native-tabs-first":
      window.tabGroup?.selectedWindow = window
      window.makeKeyAndOrderFront(nil)
    case "native-tabs-second":
      guard let secondTab else { break }
      window.tabGroup?.selectedWindow = secondTab
      secondTab.makeKeyAndOrderFront(nil)
    case "native-tabs-close":
      secondTab?.close()
      secondTab = nil
      window.makeKeyAndOrderFront(nil)
    default: return
    }
    emitFixtureEvent(command + "-ready")
    // Ground truth for this owned AppKit group, never a production AX proof.
    emitFixtureEvent("native-tabs-count-\(window.tabGroup?.windows.count ?? 1)")
  }

  private func openNativeSheet() {
    guard let window, sheet == nil else { return }
    let sheet = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    sheet.isReleasedWhenClosed = false
    sheet.title = "Owned native sheet"
    let label = NSTextField(labelWithString: "Native AppKit sheet — fixture only")
    label.frame = NSRect(x: 15, y: 25, width: 270, height: 40)
    sheet.contentView?.addSubview(label)
    self.sheet = sheet
    window.beginSheet(sheet)
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
