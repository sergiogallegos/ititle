/// Semantic intents for simulation. No keyboard binding or layout policy is implemented.
public enum SemanticCommand: Equatable, Sendable {
  case enable, resume
  case tile([WindowToken: Rect])
  case resize(WindowToken, Double)
  case swap(WindowToken, WindowToken)
  case focus(WindowToken)
  case toggleFloating(WindowToken)

  fileprivate var windows: [WindowToken] {
    switch self {
    case .enable, .resume: return []
    case .tile(let frames): return Array(frames.keys)
    case .resize(let token, _), .focus(let token), .toggleFloating(let token): return [token]
    case .swap(let first, let second): return [first, second]
    }
  }
}

public struct CommandStamp: Equatable, Sendable {
  public let global: UInt64
  public let apps: [AppToken: UInt64]
}

public struct CommandTicket: Equatable, Sendable {
  public let serial: UInt64
  public let command: SemanticCommand
  public let stamp: CommandStamp
}

public enum CommandRejection: Equatable, Sendable {
  case stopped, disabled, permission, capacity, malformed, stale
}

public enum CommandEnqueueResult: Equatable, Sendable {
  case accepted(UInt64)
  case rejected(CommandRejection)
}

public enum CommandDisposition: Equatable, Sendable {
  case ready(CommandTicket)
  case revalidationRequired(UInt64)
  case rejected(UInt64, CommandRejection)
}

public enum CommandRevocation: Sendable {
  case pause, disable, quit, permissionLost, environmentChanged
  case appUncertain(AppToken)
}

/// Bounded pure FIFO and revocation state. Its owner supplies synchronization.
/// Accepted intents retain ordered dispositions, even when superseded by safety controls.
public struct CommandBoundary: Sendable {
  private var queue: [CommandTicket] = []
  private var apps: [AppToken: UInt64] = [:]
  private var highestAttachment: UInt64 = 0
  private var serial: UInt64 = 0
  public private(set) var generation: UInt64
  public private(set) var stopped = false
  public private(set) var enabled = false
  public private(set) var trusted = false
  public private(set) var paused = true
  public let capacity: Int

  public init(capacity: Int = 128, initialGeneration: UInt64 = 0) {
    precondition(capacity > 0 && capacity <= 128)
    self.capacity = capacity
    generation = initialGeneration
  }

  public var queuedCount: Int { queue.count }
  public var attachedCount: Int { apps.count }
  public func contains(_ app: AppToken) -> Bool { apps[app] != nil }

  @discardableResult
  public mutating func attach(_ app: AppToken) -> Bool {
    guard !stopped else { return false }
    if contains(app) { return true }
    guard app.pid > 0, app.generation > highestAttachment, apps.count < 16,
      !apps.keys.contains(where: { $0.pid == app.pid })
    else { return false }
    highestAttachment = app.generation
    apps[app] = 0
    return true
  }

  public mutating func retire(_ app: AppToken) { apps.removeValue(forKey: app) }

  public mutating func setTrust(_ value: Bool) {
    guard !stopped, trusted != value else { return }
    if value {
      trusted = true
      paused = true
    } else {
      revoke(.permissionLost)
    }
  }

  public mutating func revoke(_ reason: CommandRevocation) {
    guard !stopped else { return }
    switch reason {
    case .appUncertain(let app):
      guard let value = apps[app] else {
        // Unknown routing closes globally, never silently drops uncertainty.
        advance()
        paused = true
        return
      }
      guard value < UInt64.max else {
        stopped = true
        paused = true
        return
      }
      apps[app] = value + 1
    case .quit:
      stopped = true
      paused = true
    case .disable:
      enabled = false
      paused = true
      advance()
    case .pause, .environmentChanged:
      paused = true
      advance()
    case .permissionLost:
      trusted = false
      paused = true
      advance()
    }
  }

  public func accepts(_ stamp: CommandStamp) -> Bool {
    !stopped && stamp.global == generation
      && stamp.apps.allSatisfy { apps[$0.key] == $0.value }
  }

  public mutating func enqueue(_ command: SemanticCommand) -> CommandEnqueueResult {
    guard !stopped else { return .rejected(.stopped) }
    if case .tile(let frames) = command, frames.isEmpty || frames.count > 256 {
      return .rejected(.malformed)
    }
    if case .resize(_, let delta) = command, !delta.isFinite || delta == 0 || abs(delta) > 1 {
      return .rejected(.malformed)
    }
    if case .tile(let frames) = command,
      frames.values.contains(where: { (try? LayoutEngine.frames(for: .window(0), in: $0)) == nil })
    {
      return .rejected(.malformed)
    }
    if case .swap(let a, let b) = command, a == b { return .rejected(.malformed) }
    let windows = command.windows
    guard windows.allSatisfy({ $0.serial > 0 && contains($0.app) }) else {
      return .rejected(.stale)
    }
    if command != .enable {
      guard enabled else { return .rejected(.disabled) }
      guard trusted else { return .rejected(.permission) }
    }
    guard queue.count < capacity else { return .rejected(.capacity) }
    guard serial < UInt64.max else {
      stopped = true
      paused = true
      return .rejected(.stopped)
    }
    serial += 1
    var affected: [AppToken: UInt64] = [:]
    for token in windows { affected[token.app] = apps[token.app]! }
    queue.append(
      CommandTicket(
        serial: serial, command: command,
        stamp: CommandStamp(global: generation, apps: affected)))
    return .accepted(serial)
  }

  /// At most eight ordered reductions per owner pass. No semantic coalescing.
  public mutating func drain(limit: Int = 8) -> [CommandDisposition] {
    precondition(limit > 0 && limit <= 8)
    var results: [CommandDisposition] = []
    for _ in 0..<min(limit, queue.count) {
      let ticket = queue.removeFirst()
      guard !stopped else {
        results.append(.rejected(ticket.serial, .stopped))
        continue
      }
      guard accepts(ticket.stamp) else {
        results.append(.rejected(ticket.serial, .stale))
        continue
      }
      switch ticket.command {
      case .enable, .resume:
        enabled = true
        paused = true
        advance()
        results.append(
          stopped ? .rejected(ticket.serial, .stopped) : .revalidationRequired(ticket.serial))
      default:
        guard enabled, trusted else {
          results.append(.rejected(ticket.serial, enabled ? .permission : .disabled))
          continue
        }
        results.append(.ready(ticket))
      }
    }
    return results
  }

  /// Called only after the simulation owner accepts an explicit Tile plan.
  /// This does not prove eligibility, register windows, or dispatch effects.
  public mutating func activate(_ ticket: CommandTicket) -> Bool {
    guard enabled, trusted, accepts(ticket.stamp), case .tile = ticket.command else { return false }
    paused = false
    return true
  }

  private mutating func advance() {
    guard generation < UInt64.max else {
      stopped = true
      paused = true
      return
    }
    generation += 1
  }
}
