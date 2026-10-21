import Foundation

public enum FixtureSetupFault: String, Codable, Sendable {
  case normalizationAckDelayOnce
  case normalizationOutputEOFOnce
}

/// Fixture-only state. A command cannot rearm this fault, even after consumption.
public struct FixtureAckDelayOnce: Sendable {
  public static let seconds = 6.0
  public static let responseSeconds = 5.0
  public static let armCommand = "arm-setup-ack-delay"
  public static let armedMarker = "setup-ack-delay-armed"
  public static let deferredMarker = "setup-ack-delay-deferred"
  private enum State { case disabled, available, armed, consumed }
  private var state: State
  private var armedAt: Double?

  public init(enabled: Bool) { state = enabled ? .available : .disabled }

  public mutating func arm(at time: Double) -> String? {
    guard state == .available, time.isFinite, time >= 0 else { return nil }
    state = .armed
    armedAt = time
    return "\(Self.armedMarker) \(time)"
  }

  /// Called only after the real close-sheet operation has completed.
  public mutating func deferAcknowledgment(for command: String, at time: Double) -> String? {
    guard command == "close-sheet", state == .armed, time.isFinite, time >= armedAt!,
      (time + Self.seconds).isFinite,
      time + Self.seconds > time
    else { return nil }
    state = .consumed
    return "\(Self.deferredMarker) \(time) \(time + Self.seconds)"
  }
}

public enum FixtureSetupFaultResult: String, Codable, Sendable {
  case notSubmitted, submitted, armed, deferred
}

/// One bounded terminal observation. Absent markers are encoded as null, never inferred.
public struct FixtureSetupFaultRecord: Codable, Sendable {
  public private(set) var kind = "setupFault"
  public private(set) var fault = FixtureSetupFault.normalizationAckDelayOnce
  public private(set) var sent: Double?
  public private(set) var armed: Double?
  public private(set) var armReceipt: Double?
  public private(set) var write: Double?
  public private(set) var wait: Double?
  public private(set) var scheduled: Double?
  public private(set) var due: Double?
  public private(set) var receipt: Double?
  public private(set) var end: Double?
  public private(set) var result = FixtureSetupFaultResult.notSubmitted
  public private(set) var category: FixtureStopCategory?
  public private(set) var running: Bool?

  public init() {}

  public mutating func submit(at time: Double) throws {
    guard sent == nil, end == nil, time.isFinite, time >= 0 else { throw Failure.clockFailure }
    sent = time
    result = .submitted
  }

  /// Exact marker grammar and causal cross-process monotonic clocks are required.
  public mutating func observe(_ line: String, at time: Double) throws {
    guard end == nil, let sent else { throw Failure.protocolFailure }
    let parts = line.split(separator: " ", omittingEmptySubsequences: false)
    guard time.isFinite, time >= sent else { throw Failure.clockFailure }
    if parts.first == Substring(FixtureAckDelayOnce.armedMarker) {
      guard parts.count == 2, armed == nil, write == nil,
        let value = Double(parts[1]), String(value) == parts[1]
      else { throw Failure.protocolFailure }
      guard value.isFinite, value >= sent, value <= time else { throw Failure.clockFailure }
      armed = value
      armReceipt = time
      result = .armed
    } else if parts.first == Substring(FixtureAckDelayOnce.deferredMarker) {
      guard parts.count == 3, let armed, let write, scheduled == nil,
        let value = Double(parts[1]), let deadline = Double(parts[2]),
        String(value) == parts[1], String(deadline) == parts[2]
      else { throw Failure.protocolFailure }
      guard value.isFinite, deadline.isFinite, value >= armed, value >= write, value <= time,
        deadline == value + FixtureAckDelayOnce.seconds, deadline > value, time < deadline
      else { throw Failure.clockFailure }
      scheduled = value
      due = deadline
      receipt = time
      result = .deferred
    } else {
      throw Failure.protocolFailure
    }
  }

  public mutating func normalizationWrite(at time: Double) throws {
    guard end == nil, write == nil, let armReceipt else { throw Failure.protocolFailure }
    guard time.isFinite, time >= armReceipt else { throw Failure.clockFailure }
    write = time
  }

  public mutating func beginWait(at time: Double) throws {
    guard end == nil, wait == nil, let write else { throw Failure.protocolFailure }
    guard time.isFinite, time >= write else { throw Failure.clockFailure }
    wait = time
  }

  public mutating func finish(at time: Double, category: FixtureStopCategory, running: Bool) throws
  {
    guard end == nil, time.isFinite, time >= 0,
      [sent, armed, armReceipt, write, wait, scheduled, receipt].compactMap({ $0 })
        .allSatisfy({ $0 <= time })
    else { throw Failure.clockFailure }
    end = time
    self.category = category
    self.running = running
  }

  public var valid: Bool {
    guard kind == "setupFault", fault == .normalizationAckDelayOnce,
      let end, let category, let running, end.isFinite, end >= 0
    else {
      return false
    }
    var rebuilt = Self()
    do {
      if let sent { try rebuilt.submit(at: sent) }
      if let armed, let armReceipt {
        try rebuilt.observe("\(FixtureAckDelayOnce.armedMarker) \(armed)", at: armReceipt)
      } else if armed != nil || armReceipt != nil {
        return false
      }
      if let write { try rebuilt.normalizationWrite(at: write) }
      if let wait { try rebuilt.beginWait(at: wait) }
      if let scheduled, let due, let receipt {
        try rebuilt.observe(
          "\(FixtureAckDelayOnce.deferredMarker) \(scheduled) \(due)", at: receipt)
      } else if scheduled != nil || due != nil || receipt != nil {
        return false
      }
      try rebuilt.finish(at: end, category: category, running: running)
      return rebuilt.result == result
    } catch { return false }
  }

  private enum CodingKeys: String, CodingKey {
    case kind, fault, sent, armed, armReceipt, write, wait, scheduled, due, receipt, end, result,
      category
    case running
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(kind, forKey: .kind)
    try values.encode(fault, forKey: .fault)
    try values.encode(sent, forKey: .sent)
    try values.encode(armed, forKey: .armed)
    try values.encode(armReceipt, forKey: .armReceipt)
    try values.encode(write, forKey: .write)
    try values.encode(wait, forKey: .wait)
    try values.encode(scheduled, forKey: .scheduled)
    try values.encode(due, forKey: .due)
    try values.encode(receipt, forKey: .receipt)
    try values.encode(end, forKey: .end)
    try values.encode(result, forKey: .result)
    try values.encode(category, forKey: .category)
    try values.encode(running, forKey: .running)
  }

  public enum Failure: Error { case protocolFailure, clockFailure }
}

/// Schema-4/5 fault validation; this controlled failure can never admit a pair.
enum FixtureSetupFaultReplay {
  static func validate(
    manifest: FixtureTimingManifest?, fault: FixtureSetupFaultRecord?,
    setups: [FixtureSetupRecord], stop: FixtureFirstStop?, attempts: Int, records: Int,
    occupied: Bool, complete: Bool, suitable: Bool
  ) throws {
    typealias Failure = FixtureTimingReplay.Failure
    guard attempts == 0, records == 0, !occupied, !complete, !suitable,
      let stop, stop.pairs == 0, !stop.pairOccupied, !stop.readerOccupied
    else { throw Failure.mismatch }
    guard let manifest else {
      guard fault == nil, setups.isEmpty else { throw Failure.malformed }
      return
    }
    // Missing rows cannot establish fault attribution, even after export failure.
    guard let fault else { throw Failure.malformed }
    guard fault.valid, fault.end == stop.time, fault.category == stop.category,
      (fault.sent ?? fault.end!) >= manifest.runStart!, fault.end! >= manifest.runStart!
    else { throw Failure.mismatch }
    guard setups.count <= 1 else { throw Failure.malformed }
    if let setup = setups.first {
      guard setup.sequence == 1, setup.nextIndex == 1, setup.cohort == .ordinary,
        setup.purpose == .cohort, setup.failure != nil, setup.issued >= 1,
        setup.issued == setup.correlated, !setup.pairOccupied, !setup.readerOccupied,
        stop.setup == 1, stop.request == nil,
        let armedReceipt = fault.armReceipt, armedReceipt <= setup.start,
        let end = stop.time, end >= setup.start, end <= setup.end!
      else { throw Failure.mismatch }
      if let write = fault.write {
        guard write >= setup.start, write <= end else { throw Failure.malformed }
      }
      if let wait = fault.wait {
        guard setup.stage == .normalizationAck, setup.completed == 3,
          wait >= fault.write!, wait <= end
        else { throw Failure.mismatch }
      }
      if let receipt = fault.receipt {
        guard let wait = fault.wait, receipt >= wait, receipt <= end else {
          throw Failure.malformed
        }
      }
      if stop.stage == .normalizationAck && stop.category == .responseDeadline {
        guard let wait = fault.wait, end >= wait + FixtureAckDelayOnce.responseSeconds,
          end < manifest.collectionDeadline!, fault.running == true,
          fault.due.map({ end < $0 }) ?? true
        else { throw Failure.mismatch }
      }
      if stop.category == .unexpectedAcknowledgment {
        guard stop.stage == .normalizationAck, fault.wait != nil else { throw Failure.mismatch }
      }
    } else {
      guard stop.setup == nil, fault.write == nil, fault.wait == nil,
        fault.scheduled == nil
      else { throw Failure.mismatch }
    }
  }
}
