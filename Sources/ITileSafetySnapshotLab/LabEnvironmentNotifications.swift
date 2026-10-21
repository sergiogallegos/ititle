import AppKit
import Darwin
import ITileFixtureDiagnostics

/// Name mapping only. Reading these constants does not start an application or post events.
@MainActor
enum LabEnvironmentNotifications {
  static let workspaceNames: [Notification.Name] = [
    NSWorkspace.activeSpaceDidChangeNotification,
    NSWorkspace.willSleepNotification,
    NSWorkspace.didWakeNotification,
  ]
  static let screenName = NSApplication.didChangeScreenParametersNotification

  static func source(for name: Notification.Name) -> FixtureEnvironmentSource? {
    switch name {
    case NSWorkspace.activeSpaceDidChangeNotification: .nativeSpace
    case NSApplication.didChangeScreenParametersNotification: .screenParameters
    case NSWorkspace.willSleepNotification: .willSleep
    case NSWorkspace.didWakeNotification: .didWake
    default: nil
    }
  }

  static func selfCheck() -> Bool {
    workspaceNames == [
      NSWorkspace.activeSpaceDidChangeNotification,
      NSWorkspace.willSleepNotification,
      NSWorkspace.didWakeNotification,
    ]
      && workspaceNames.compactMap { source(for: $0) } == [.nativeSpace, .willSleep, .didWake]
      && screenName == NSApplication.didChangeScreenParametersNotification
      && source(for: screenName) == .screenParameters
      && source(for: Notification.Name("itile-unknown-self-check")) == nil
      && source(for: NSWorkspace.didActivateApplicationNotification) == nil
  }
}

/// Inert adapter check: no monitor, permission sampling, application or fixture setup.
@MainActor
func runEnvironmentSourceSelfCheck() -> Never {
  let passed = LabEnvironmentNotifications.selfCheck()
  print(
    "{\"kind\":\"environmentSourceSelfCheck\",\"passed\":\(passed),\"synthetic\":true,\"nativeCollection\":false}"
  )
  exit(passed ? 0 : 1)
}
