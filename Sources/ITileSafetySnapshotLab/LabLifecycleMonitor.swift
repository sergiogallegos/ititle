import AppKit
import ApplicationServices
import ITileFixtureDiagnostics

/// Main-thread laboratory attachment. Callbacks are observations, not complete event coverage.
@MainActor
final class LabLifecycleMonitor: NSObject {
  private static var applicationPrepared = false
  var host: FixtureDiagnosticHost
  private let pid: Int32
  private let ownedRunning: () -> Bool
  private(set) var activationEvents = 0
  private(set) var terminationEvents = 0
  private(set) var spaceEvents = 0
  private(set) var trustLosses = 0
  private(set) var trustRestorations = 0
  var timingSink: ((FixtureTimingEvent) -> Void)?
  private var events = 0
  private(set) var overflow = false

  init(run: UUID, pid: Int32, ownedRunning: @escaping () -> Bool) throws {
    if !Self.applicationPrepared {
      _ = NSApplication.shared.setActivationPolicy(.prohibited)
      NSApplication.shared.finishLaunching()
      Self.applicationPrepared = true
    }
    self.pid = pid
    self.ownedRunning = ownedRunning
    host = FixtureDiagnosticHost(
      context: FixtureUseContext(
        expected: try FixtureWindowIdentity(run: run, serial: 1), trusted: AXIsProcessTrusted()))
    super.init()
    let center = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didActivateApplicationNotification,
      NSWorkspace.didDeactivateApplicationNotification,
    ] {
      center.addObserver(self, selector: #selector(activation), name: name, object: nil)
    }
    center.addObserver(
      self, selector: #selector(termination),
      name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    for name in LabEnvironmentNotifications.workspaceNames {
      center.addObserver(self, selector: #selector(environment), name: name, object: nil)
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(environment),
      name: LabEnvironmentNotifications.screenName, object: nil)
  }

  func detach() {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    NotificationCenter.default.removeObserver(self)
    host.observe(.stop)
  }

  private func record(
    _ event: FixtureHostEvent, code: String, direction: FixtureActivationDirection? = nil,
    relation: FixtureActivationRelation? = nil, source: FixtureEnvironmentSource? = nil
  ) {
    guard !overflow else { return }
    guard events < 128 else {
      overflow = true
      host.observe(.stop)
      return
    }
    events += 1
    let time = ProcessInfo.processInfo.systemUptime
    host.observe(event)
    if let timingSink {
      timingSink(
        FixtureTimingEvent(
          code: code, time: time, revocation: host.context.revocation,
          pending: host.pendingRequest, context: host.context, direction: direction,
          relation: relation, source: source))
      return
    }
    print(
      "lab-host-event code=\(code) source=\(source?.rawValue ?? "notApplicable") revocation=\(host.context.revocation) pending=\(host.pendingRequest != nil) result=\(host.current.rawValue) time=\(time)"
    )
  }

  @objc private func activation(_ notification: Notification) {
    if activationEvents < 128 { activationEvents += 1 }
    let direction: FixtureActivationDirection =
      notification.name == NSWorkspace.didActivateApplicationNotification ? .activate : .deactivate
    let relation: FixtureActivationRelation
    if !ownedRunning() || host.context.stopped {
      relation = .unavailable
    } else if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
      as? NSRunningApplication
    {
      relation = app.processIdentifier == pid ? .owned : .unrelated
    } else {
      relation = .unavailable
    }
    record(.activation, code: "activation", direction: direction, relation: relation)
  }

  @objc private func environment(_ notification: Notification) {
    guard let source = LabEnvironmentNotifications.source(for: notification.name) else { return }
    if source == .nativeSpace && spaceEvents < 128 { spaceEvents += 1 }
    record(.environment, code: source.eventCode, source: source)
  }

  @objc private func termination(_ notification: Notification) {
    guard
      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
      app.processIdentifier == pid
    else { return }
    if terminationEvents < 128 { terminationEvents += 1 }
    record(.processExit, code: "ownedTermination")
  }

  func sample(trusted: Bool, running: Bool) {
    guard !host.context.stopped else { return }
    if trusted != host.context.trusted {
      if trusted {
        if trustRestorations < 128 { trustRestorations += 1 }
      } else {
        if trustLosses < 128 { trustLosses += 1 }
      }
      record(.trust(trusted), code: trusted ? "sampledTrustRestored" : "sampledTrustLost")
    }
    if !running && !host.context.stopped { record(.processExit, code: "sampledExit") }
  }

  func pause(_ value: Bool) { record(.pause(value), code: value ? "pause" : "resume") }
}
