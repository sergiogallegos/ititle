/// Tokens are scoped to one process attachment, never to a title or an OS window ID.
public struct AppToken: Hashable, Sendable {
  public let pid: Int32
  public let generation: UInt64
  public init(pid: Int32, generation: UInt64) {
    self.pid = pid
    self.generation = generation
  }
}

public struct WindowToken: Hashable, Sendable, CustomStringConvertible {
  public let app: AppToken
  public let serial: UInt64
  public var description: String { "app-\(app.generation)/window-\(serial)" }
}

/// Adapter-owned integer identities; no platform objects cross into the core.
public struct ProbeRegistry: Sendable {
  public let app: AppToken
  private var nextSerial: UInt64 = 0
  private var tokens: [Int: WindowToken] = [:]
  public init(app: AppToken) { self.app = app }

  public mutating func reconcile(_ identities: [Int]) -> [WindowToken] {
    let live = Set(identities)
    tokens = tokens.filter { live.contains($0.key) }
    return identities.map { identity in
      if let existing = tokens[identity] { return existing }
      nextSerial += 1
      let token = WindowToken(app: app, serial: nextSerial)
      tokens[identity] = token
      return token
    }
  }

  /// Complete tracked identities, not proof of all OS windows or visibility.
  public func snapshot(environmentEpoch: UInt64, revision: UInt64) -> ProbeRegistrySnapshot {
    ProbeRegistrySnapshot(
      app: app, environmentEpoch: environmentEpoch, revision: revision,
      highestSerial: nextSerial, windows: Set(tokens.values))
  }

  public mutating func invalidate() { tokens.removeAll() }

  /// Unobservable elements expire without retiring unrelated observable windows.
  public mutating func invalidate(_ identities: Set<Int>) {
    tokens = tokens.filter { !identities.contains($0.key) }
  }
}

public enum ProbeRead<Value: Sendable>: Sendable {
  case value(Value)
  case unavailable(Int32)
  case invalidType
}

/// AppKit-to-AX conversion about the primary display's upper edge; negative origins survive.
public enum DesktopCoordinates {
  public static func flip(_ rect: Rect, primaryTop: Double) -> Rect {
    Rect(
      x: rect.x, y: primaryTop - rect.y - rect.height,
      width: rect.width, height: rect.height)
  }
}

/// Replacement state carried with an explicit worker reply. A serial watermark
/// retires absent identities without an unbounded tombstone/event queue.
public struct ProbeRegistrySnapshot: Equatable, Sendable {
  public let app: AppToken
  public let environmentEpoch: UInt64
  public let revision: UInt64
  public let highestSerial: UInt64
  public let windows: Set<WindowToken>

  public init(
    app: AppToken, environmentEpoch: UInt64, revision: UInt64,
    highestSerial: UInt64, windows: Set<WindowToken>
  ) {
    self.app = app
    self.environmentEpoch = environmentEpoch
    self.revision = revision
    self.highestSerial = highestSerial
    self.windows = windows
  }
}
