/// Session-local read identity. No platform handles or eligibility assertions.
public struct ReadOperationID: Equatable, Sendable {
  public let app: AppToken
  public let serial: UInt64
}

public struct ReadReceiptID: Equatable, Sendable {
  public let operation: ReadOperationID
  public let reply: UInt64
}

/// One read stays occupied through consumption, including discarded replies.
/// Its owner serializes access; the platform supplies synchronization.
public struct ReadOnlyReceiptState: Sendable {
  public enum Phase: Equatable, Sendable {
    case idle
    case queued(ReadOperationID)
    case executing(ReadOperationID)
    case awaitingAcknowledgment(ReadReceiptID)
    case stopped
  }

  public let app: AppToken
  public private(set) var phase: Phase = .idle
  private var serial: UInt64
  private var invalidated = false

  public init(app: AppToken, initialSerial: UInt64 = 0) {
    self.app = app
    serial = initialSerial
  }

  public mutating func admit() -> ReadOperationID? {
    guard phase == .idle else { return nil }
    guard serial < UInt64.max else {
      stop()
      return nil
    }
    serial += 1
    let id = ReadOperationID(app: app, serial: serial)
    invalidated = false
    phase = .queued(id)
    return id
  }

  public mutating func begin(_ id: ReadOperationID) -> Bool {
    guard phase == .queued(id) else { return false }
    phase = .executing(id)
    return true
  }

  public func isCancelled(_ id: ReadOperationID) -> Bool {
    guard !invalidated, id.app == app else { return true }
    switch phase {
    case .queued(let current), .executing(let current): return current != id
    case .awaitingAcknowledgment(let receipt): return receipt.operation != id
    case .idle, .stopped: return true
    }
  }

  public mutating func invalidate() { invalidated = true }

  public mutating func publish(_ id: ReadOperationID) -> ReadReceiptID? {
    guard phase == .executing(id) else { return nil }
    let receipt = ReadReceiptID(operation: id, reply: 1)
    phase = .awaitingAcknowledgment(receipt)
    return receipt
  }

  @discardableResult
  public mutating func acknowledge(_ receipt: ReadReceiptID) -> Bool {
    guard phase == .awaitingAcknowledgment(receipt) else { return false }
    phase = .idle
    return true
  }

  public mutating func stop() { phase = .stopped }
}
