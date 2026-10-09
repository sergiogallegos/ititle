import ApplicationServices
import Foundation
import ITileFixtureDiagnostics

struct OwnedAXIdentitySample: Sendable {
  let focused: FixtureWindowIdentity
  let windows: [FixtureWindowIdentity]
  let startedAt: Double
  let finishedAt: Double
}

/// One dedicated blocking thread; AX handles never cross to the host or executor.
final class OwnedAXIdentityReader: @unchecked Sendable {
  private let lock = NSLock()
  private var result: Result<OwnedAXIdentitySample, Error>?

  private var started = false
  private var timing: [FixtureTimingPoint: Double] = [:]

  func timingAtReceipt() -> [FixtureTimingPoint: Double] {
    lock.lock()
    defer { lock.unlock() }
    var values = timing
    if result != nil { values[.receipt] = ProcessInfo.processInfo.systemUptime }
    return values
  }

  func start(pid: Int32, dispatchDelay: Double = 0) throws {
    lock.lock()
    guard !started, dispatchDelay.isFinite, dispatchDelay >= 0, dispatchDelay <= 0.5 else {
      lock.unlock()
      throw ReadFailure.incomplete
    }
    started = true
    timing[.admission] = ProcessInfo.processInfo.systemUptime
    lock.unlock()
    Thread.detachNewThread { [self] in
      if dispatchDelay > 0 { Thread.sleep(forTimeInterval: dispatchDelay) }
      let entry = ProcessInfo.processInfo.systemUptime
      let result = Result { try Self.inspect(pid: pid) }
      let exit = ProcessInfo.processInfo.systemUptime
      lock.lock()
      timing[.entry] = entry
      timing[.exit] = exit
      timing[.publication] = ProcessInfo.processInfo.systemUptime
      self.result = result
      lock.unlock()
    }
  }

  func poll() -> Result<OwnedAXIdentitySample, Error>? {
    lock.lock()
    defer { lock.unlock() }
    return result
  }

  func read(pid: Int32, pump: () -> Void = {}) throws -> OwnedAXIdentitySample {
    try start(pid: pid)
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    while ProcessInfo.processInfo.systemUptime < deadline {
      pump()
      if let result = poll() { return try result.get() }
      Thread.sleep(forTimeInterval: 0.005)
    }
    // Caller ends the workflow on timeout; never overlaps a replacement reader.
    throw ReadFailure.incomplete
  }

  private enum ReadFailure: Error { case incomplete }

  private static func inspect(pid: Int32) throws -> OwnedAXIdentitySample {
    guard pid > 0, AXIsProcessTrusted() else { throw ReadFailure.incomplete }
    let start = ProcessInfo.processInfo.systemUptime
    let app = AXUIElementCreateApplication(pid)
    guard AXUIElementSetMessagingTimeout(app, 0.2) == .success else { throw ReadFailure.incomplete }
    var focusedValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedValue)
        == .success,
      let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
    else { throw ReadFailure.incomplete }
    let focused = unsafeDowncast(focusedValue, to: AXUIElement.self)
    func identity(_ window: AXUIElement) throws -> FixtureWindowIdentity {
      guard AXUIElementSetMessagingTimeout(window, 0.2) == .success else {
        throw ReadFailure.incomplete
      }
      var value: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(window, kAXIdentifierAttribute as CFString, &value)
          == .success,
        let identifier = value as? String
      else { throw ReadFailure.incomplete }
      // Parse only the fixed fixture vocabulary. Never export unknown attribute text.
      return try FixtureWindowIdentity(identifier: identifier)
    }
    let focusedIdentity = try identity(focused)
    var count: CFIndex = 0
    guard
      AXUIElementGetAttributeValueCount(app, kAXWindowsAttribute as CFString, &count) == .success,
      count > 0, count <= 8
    else { throw ReadFailure.incomplete }
    var values: CFArray?
    guard
      AXUIElementCopyAttributeValues(app, kAXWindowsAttribute as CFString, 0, count, &values)
        == .success,
      let windows = values as? [AXUIElement], windows.count == count
    else { throw ReadFailure.incomplete }
    let identities = try windows.map(identity)
    guard Set(identities.map(\.identifier)).count == identities.count else {
      throw ReadFailure.incomplete
    }
    var after: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &after) == .success,
      let after, CFEqual(focused, after)
    else { throw ReadFailure.incomplete }
    return OwnedAXIdentitySample(
      focused: focusedIdentity, windows: identities, startedAt: start,
      finishedAt: ProcessInfo.processInfo.systemUptime)
  }
}
