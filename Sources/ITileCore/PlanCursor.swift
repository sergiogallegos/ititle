/// Bounded ordered targets belonging to one explicit command and layout revision.
/// This cursor never creates a command, retries work, or proves eligibility.
public struct PlanCursor: Equatable, Sendable {
  public let app: AppToken
  public let commandSerial: UInt64
  public let layoutRevision: UInt64
  private let windows: [WindowToken]
  private var index = 0

  public init?(
    app: AppToken, commandSerial: UInt64, layoutRevision: UInt64,
    windows: [WindowToken]
  ) {
    guard app.pid > 0, app.generation > 0, commandSerial > 0, layoutRevision > 0, !windows.isEmpty,
      windows.count <= 64,
      Set(windows).count == windows.count,
      windows.allSatisfy({ $0.app == app && $0.serial > 0 })
    else { return nil }
    self.app = app
    self.commandSerial = commandSerial
    self.layoutRevision = layoutRevision
    self.windows = windows.sorted { $0.serial < $1.serial }
  }
  public var next: WindowToken? { index < windows.count ? windows[index] : nil }
  public var remainingWindows: [WindowToken] { Array(windows.dropFirst(index)) }
  public var remainingCount: Int { windows.count - index }
  @discardableResult
  public mutating func advance(completed token: WindowToken) -> Bool {
    guard next == token else { return false }
    index += 1
    return true
  }
}
