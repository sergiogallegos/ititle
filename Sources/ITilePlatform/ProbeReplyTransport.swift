import Foundation
import ITileCore

/// One exact terminal read acknowledgment. Duplicate/late acknowledgments fail.
public struct ProbeReceipt: Sendable {
  public let id: ReadReceiptID
  private let consume: @Sendable (ReadReceiptID) -> Bool

  init(id: ReadReceiptID, consume: @escaping @Sendable (ReadReceiptID) -> Bool) {
    self.id = id
    self.consume = consume
  }

  @discardableResult
  public func acknowledge() -> Bool { consume(id) }
}

/// Bounded value routing only. Owner callbacks execute serially without locks.
/// One scheduled chain serves all workers; no task per reply is created.
public final class ProbeReplyTransport: @unchecked Sendable {
  private struct Entry: Sendable {
    let receipt: ProbeReceipt
    let consume: @MainActor @Sendable () -> Void
  }
  private let lock = NSLock()
  private var entries: [AppToken: Entry] = [:]
  private var attachments: [AppToken] = []
  private var cursor = 0
  private var highestGeneration: UInt64 = 0
  private var failed: Set<AppToken> = []
  private var lastOperation: [AppToken: UInt64] = [:]
  private var scheduled = false
  private var stopped = false
  public let maximumApps: Int
  private let schedule: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void

  public convenience init() {
    self.init(maximumApps: 16, schedule: { work in Task { @MainActor in work() } })
  }

  init(
    maximumApps: Int,
    schedule: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
  ) {
    precondition(maximumApps > 0 && maximumApps <= 16)
    self.maximumApps = maximumApps
    self.schedule = schedule
  }

  @discardableResult
  public func attach(_ app: AppToken) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !stopped else { return false }
    if attachments.contains(app) { return true }
    guard app.generation > highestGeneration, attachments.count < maximumApps,
      !attachments.contains(where: { $0.pid == app.pid })
    else { return false }
    highestGeneration = app.generation
    attachments.append(app)
    return true
  }

  /// Caller first stops the corresponding worker. Old receipts cannot free new work.
  public func retire(_ app: AppToken) {
    lock.lock()
    let abandoned = entries.removeValue(forKey: app)
    attachments.removeAll { $0 == app }
    failed.remove(app)
    lastOperation.removeValue(forKey: app)
    lock.unlock()
    abandoned?.receipt.acknowledge()
  }

  @discardableResult
  public func submit(
    _ receipt: ProbeReceipt, consume: @escaping @MainActor @Sendable () -> Void
  ) -> Bool {
    lock.lock()
    let app = receipt.id.operation.app
    guard !stopped, attachments.contains(app), !failed.contains(app), entries[app] == nil,
      receipt.id.reply == 1, receipt.id.operation.serial > (lastOperation[app] ?? 0)
    else {
      if !stopped, attachments.contains(app) { failed.insert(app) }
      lock.unlock()
      // Do not acknowledge a duplicate occupied receipt: the first owner still
      // owns it. Unknown routing is terminalized by the caller stopping its worker.
      return false
    }
    lastOperation[app] = receipt.id.operation.serial
    entries[app] = Entry(receipt: receipt, consume: consume)
    let wake = !scheduled
    scheduled = true
    lock.unlock()
    if wake { postDrain() }
    return true
  }

  public func hasFailed(_ app: AppToken) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return failed.contains(app)
  }

  /// Stop workers first; disposal cannot revive a stopped receipt state.
  public func stop() {
    lock.lock()
    stopped = true
    let abandoned = Array(entries.values)
    entries.removeAll()
    attachments.removeAll()
    failed.removeAll()
    lastOperation.removeAll()
    lock.unlock()
    for entry in abandoned { entry.receipt.acknowledge() }
  }

  private func postDrain() { schedule { [weak self] in self?.drain() } }

  @MainActor
  private func drain() {
    // Entries remain occupied even while the callback owns a local copy.
    for _ in 0..<8 {
      lock.lock()
      var chosen: AppToken?
      if !stopped, !attachments.isEmpty {
        for _ in 0..<attachments.count {
          cursor %= attachments.count
          let app = attachments[cursor]
          cursor = (cursor + 1) % attachments.count
          if entries[app] != nil {
            chosen = app
            break
          }
        }
      }
      let entry = chosen.flatMap { entries[$0] }
      lock.unlock()
      guard let app = chosen, let entry else { break }
      entry.consume()
      // Remove the exact reserved entry before acknowledging. Worker remains
      // busy until acknowledgment, so it cannot publish into this gap.
      lock.lock()
      if entries[app]?.receipt.id == entry.receipt.id { entries.removeValue(forKey: app) }
      lock.unlock()
      entry.receipt.acknowledge()
    }
    lock.lock()
    let again = !stopped && !entries.isEmpty
    scheduled = again
    lock.unlock()
    if again { postDrain() }
  }
}
