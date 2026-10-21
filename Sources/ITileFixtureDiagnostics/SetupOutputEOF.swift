import Foundation

/// Pure opt-in selection state. Consumed once, even if descriptor replacement fails.
public struct FixtureOutputEOFOnce: Sendable {
  public static let armCommand = "arm-setup-output-eof"
  public static let armedMarker = "setup-output-eof-armed"
  public static let selectedMarker = "setup-output-eof-selected"
  public static let failedMarker = "setup-output-eof-failed"
  private enum State { case disabled, available, armed, consumed }
  private var state: State
  private var armedAt: Double?

  public init(enabled: Bool, safety: Bool, nested: Bool, acknowledgmentDelay: Bool) {
    state = enabled && safety && nested && !acknowledgmentDelay ? .available : .disabled
  }

  public mutating func arm(at time: Double) -> String? {
    guard state == .available, time.isFinite, time >= 0 else { return nil }
    state = .armed
    armedAt = time
    return "\(Self.armedMarker) \(time)"
  }

  /// This marker precedes the adapter's descriptor operation; it is intent, not EOF.
  public mutating func select(for command: String, at time: Double) -> String? {
    guard command == "close-sheet", state == .armed, time.isFinite, time >= armedAt! else {
      return nil
    }
    state = .consumed
    return "\(Self.selectedMarker) \(time)"
  }
}

public enum FixtureOutputEOFResult: String, Codable, Sendable {
  case notSubmitted, submitted, armed, selected, eof
}

/// One terminal EOF observation. Liveness is sampled only at the actual zero-byte read.
public struct FixtureOutputEOFRecord: Codable, Sendable {
  public private(set) var kind = "setupFault"
  public private(set) var fault = FixtureSetupFault.normalizationOutputEOFOnce
  public private(set) var sent: Double?
  public private(set) var armed: Double?
  public private(set) var armReceipt: Double?
  public private(set) var write: Double?
  public private(set) var wait: Double?
  public private(set) var limit: Double?
  public private(set) var selected: Double?
  public private(set) var receipt: Double?
  public private(set) var eof: Double?
  public private(set) var end: Double?
  public private(set) var running: Bool?
  public private(set) var result = FixtureOutputEOFResult.notSubmitted
  public private(set) var category: FixtureStopCategory?
  public typealias Failure = FixtureSetupFaultRecord.Failure

  public init() {}

  public mutating func submit(at time: Double) throws {
    guard sent == nil, end == nil, time.isFinite, time >= 0 else { throw Failure.clockFailure }
    sent = time
    result = .submitted
  }

  public mutating func observe(_ line: String, at time: Double) throws {
    guard end == nil, eof == nil, let sent else { throw Failure.protocolFailure }
    let parts = line.split(separator: " ", omittingEmptySubsequences: false)
    guard parts.count == 2, let value = Double(parts[1]), String(value) == parts[1] else {
      throw Failure.protocolFailure
    }
    guard value.isFinite, time.isFinite, value >= sent, value <= time else {
      throw Failure.clockFailure
    }
    switch parts[0] {
    case Substring(FixtureOutputEOFOnce.armedMarker):
      guard armed == nil, write == nil else { throw Failure.protocolFailure }
      armed = value
      armReceipt = time
      result = .armed
    case Substring(FixtureOutputEOFOnce.selectedMarker):
      guard let write, let wait, selected == nil else { throw Failure.protocolFailure }
      guard value >= write, time >= wait, time < limit! else { throw Failure.clockFailure }
      selected = value
      receipt = time
      result = .selected
    case Substring(FixtureOutputEOFOnce.failedMarker):
      guard let selected, let receipt else { throw Failure.protocolFailure }
      guard value >= selected, time >= receipt else { throw Failure.clockFailure }
      throw Failure.protocolFailure
    default: throw Failure.protocolFailure
    }
  }

  public mutating func normalizationWrite(at time: Double) throws {
    guard end == nil, write == nil, let armReceipt else { throw Failure.protocolFailure }
    guard time.isFinite, time >= armReceipt else { throw Failure.clockFailure }
    write = time
  }

  public mutating func beginWait(at time: Double, deadline: Double) throws {
    guard end == nil, wait == nil, let write else { throw Failure.protocolFailure }
    guard time.isFinite, deadline.isFinite, time >= write, deadline > time,
      deadline <= time + 5
    else { throw Failure.clockFailure }
    wait = time
    limit = deadline
  }

  public mutating func observeEOF(at time: Double, running: Bool) throws {
    guard end == nil, eof == nil, sent != nil else { throw Failure.protocolFailure }
    guard time.isFinite, time >= 0, observedClocks.allSatisfy({ $0 <= time }),
      limit.map({ time < $0 }) ?? true
    else { throw Failure.clockFailure }
    eof = time
    self.running = running
    result = .eof
  }

  private var observedClocks: [Double] {
    [sent, armed, armReceipt, write, wait, selected, receipt, eof].compactMap { $0 }
  }

  public mutating func finish(at time: Double, category: FixtureStopCategory) throws {
    guard end == nil, time.isFinite, time >= 0, observedClocks.allSatisfy({ $0 <= time }) else {
      throw Failure.clockFailure
    }
    guard category == .childEOF ? eof == time : eof == nil else { throw Failure.protocolFailure }
    end = time
    self.category = category
  }

  public var valid: Bool {
    guard kind == "setupFault", fault == .normalizationOutputEOFOnce, let end, let category else {
      return false
    }
    var rebuilt = Self()
    do {
      if let sent { try rebuilt.submit(at: sent) }
      if let armed, let armReceipt {
        try rebuilt.observe("\(FixtureOutputEOFOnce.armedMarker) \(armed)", at: armReceipt)
      } else if armed != nil || armReceipt != nil {
        return false
      }
      if let write { try rebuilt.normalizationWrite(at: write) }
      if let wait, let limit {
        try rebuilt.beginWait(at: wait, deadline: limit)
      } else if wait != nil || limit != nil {
        return false
      }
      if let selected, let receipt {
        try rebuilt.observe("\(FixtureOutputEOFOnce.selectedMarker) \(selected)", at: receipt)
      } else if selected != nil || receipt != nil {
        return false
      }
      if let eof, let running {
        try rebuilt.observeEOF(at: eof, running: running)
      } else if eof != nil || running != nil {
        return false
      }
      try rebuilt.finish(at: end, category: category)
      return rebuilt.result == result
    } catch { return false }
  }

  public var observedLiveSelectedEOF: Bool {
    valid && running == true && eof != nil && selected != nil && wait != nil
  }

  private enum CodingKeys: String, CodingKey {
    case kind, fault, sent, armed, armReceipt, write, wait, limit, selected, receipt, eof, end
    case running, result, category
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
    try values.encode(limit, forKey: .limit)
    try values.encode(selected, forKey: .selected)
    try values.encode(receipt, forKey: .receipt)
    try values.encode(eof, forKey: .eof)
    try values.encode(end, forKey: .end)
    try values.encode(running, forKey: .running)
    try values.encode(result, forKey: .result)
    try values.encode(category, forKey: .category)
  }
}

enum FixtureOutputEOFReplay {
  static func validate(
    manifest: FixtureTimingManifest?, fault: FixtureOutputEOFRecord?,
    setups: [FixtureSetupRecord], stop: FixtureFirstStop?, attempts: Int, records: Int,
    occupied: Bool, complete: Bool, suitable: Bool
  ) throws {
    typealias Failure = FixtureTimingReplay.Failure
    guard attempts == 0, records == 0, !occupied, !complete, !suitable,
      let stop, stop.pairs == 0, !stop.pairOccupied, !stop.readerOccupied
    else {
      throw Failure.mismatch
    }
    guard let manifest else {
      guard fault == nil, setups.isEmpty else { throw Failure.malformed }
      return
    }
    guard let fault, fault.valid, fault.end == stop.time, fault.category == stop.category,
      (fault.sent ?? fault.end!) >= manifest.runStart!, fault.end! >= manifest.runStart!,
      fault.eof.map({ $0 < manifest.collectionDeadline! }) ?? true,
      setups.count <= 1
    else { throw Failure.mismatch }
    if let setup = setups.first {
      guard setup.sequence == 1, setup.nextIndex == 1, setup.cohort == .ordinary,
        setup.purpose == .cohort, setup.failure != nil, setup.issued >= 1,
        [.setupPrecondition, .normalizationWrite, .normalizationAck].contains(setup.stage),
        setup.issued == setup.correlated, !setup.pairOccupied, !setup.readerOccupied,
        stop.setup == 1, stop.request == nil,
        let armedReceipt = fault.armReceipt, armedReceipt <= setup.start,
        let end = stop.time, end >= setup.start, end <= setup.end!
      else { throw Failure.mismatch }
      if let write = fault.write {
        guard write >= setup.start, write <= end else { throw Failure.mismatch }
      }
      if let wait = fault.wait {
        guard setup.stage == .normalizationAck, setup.completed == 3,
          wait >= setup.lastObservation, wait <= end,
          fault.limit == min(wait + 5, manifest.collectionDeadline!)
        else { throw Failure.mismatch }
      }
      if stop.category == .unexpectedAcknowledgment {
        guard stop.stage == .normalizationAck, fault.wait != nil else { throw Failure.mismatch }
      }
      if stop.category == .responseDeadline, let limit = fault.limit {
        guard end >= limit, end < manifest.collectionDeadline! else { throw Failure.mismatch }
      }
    } else {
      guard stop.setup == nil, fault.write == nil, fault.wait == nil, fault.selected == nil else {
        throw Failure.mismatch
      }
    }
  }
}
