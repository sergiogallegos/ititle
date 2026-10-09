import Foundation

/// Laboratory protocol only. This module is not a production evidence provider.
public enum FixtureSnapshotError: Error {
  case malformed, unsupported, stale, context, pending, exhausted
}

public struct FixtureSafetySnapshot: Sendable {
  public static let keys = [
    "schema", "coverage", "run", "request", "sequence", "start", "end", "original", "number",
    "active", "visible", "minimized", "fullscreen", "hidden", "frontmost", "key", "main",
    "tabCount", "tabSelected", "tabBar", "sheetCount", "attached", "modal", "synthetic",
    "scenario", "focusedFault", "windowFault", "structuralFault",
  ]
  public static let flags = [
    "active", "visible", "minimized", "fullscreen", "hidden", "frontmost", "key", "main",
    "tabSelected", "tabBar", "attached", "modal", "synthetic", "focusedFault", "windowFault",
    "structuralFault",
  ]
  public static let scenarios = [
    "ordinary", "native-sheet", "close-sheet", "tree-ordinary", "tree-direct-sheet",
    "tree-nested-sheet", "tree-dialog", "tree-system-dialog", "tree-wide", "tree-deep",
    "tree-cycle", "tree-budget", "tree-focus-loss", "tree-focus-switch", "tree-stall",
    "tree-sheet-remove", "tree-native-sheet-open", "tree-tab-group", "tree-tab-group-cycle",
  ]
  private let fields: [String: String]
  public let run: UUID
  public let request: UInt64
  public let sequence: UInt64
  public let startedAt: Double
  public let finishedAt: Double

  public init(line: String) throws {
    guard line.utf8.count <= 4096, !line.contains("\n"), !line.contains("\r") else {
      throw FixtureSnapshotError.malformed
    }
    let parts = line.split(separator: " ", omittingEmptySubsequences: false)
    guard parts.count == Self.keys.count + 1, parts.first == "safety-snapshot" else {
      throw FixtureSnapshotError.malformed
    }
    var fields: [String: String] = [:]
    for part in parts.dropFirst() {
      let pair = part.split(separator: "=", omittingEmptySubsequences: false)
      guard pair.count == 2, !pair[1].isEmpty, fields[String(pair[0])] == nil else {
        throw FixtureSnapshotError.malformed
      }
      fields[String(pair[0])] = String(pair[1])
    }
    try self.init(fields: fields)
  }

  public init(fields: [String: String]) throws {
    guard Set(fields.keys) == Set(Self.keys) else { throw FixtureSnapshotError.malformed }
    guard fields["schema"] == "1", fields["coverage"] == "ownedFixtureOnly" else {
      throw FixtureSnapshotError.unsupported
    }
    func positive(_ name: String) throws -> UInt64 {
      guard let raw = fields[name], let value = UInt64(raw), value > 0, String(value) == raw else {
        throw FixtureSnapshotError.malformed
      }
      return value
    }
    guard let run = UUID(uuidString: fields["run"]!), run.uuidString == fields["run"],
      let start = Double(fields["start"]!), let end = Double(fields["end"]!),
      start.isFinite, end.isFinite, start >= 0, end >= start,
      fields["original"] == "1", Self.scenarios.contains(fields["scenario"]!),
      Self.flags.allSatisfy({
        ["true", "false", "unavailable", "notApplicable"].contains(fields[$0]!)
      })
    else { throw FixtureSnapshotError.malformed }
    for name in ["tabCount", "sheetCount", "number"] {
      let raw = fields[name]!
      if raw == "unavailable" { continue }
      guard let value = UInt64(raw), String(value) == raw,
        name == "number" ? (value > 0 && value <= UInt64(Int32.max)) : value <= 64
      else { throw FixtureSnapshotError.malformed }
    }
    self.run = run
    request = try positive("request")
    sequence = try positive("sequence")
    startedAt = start
    finishedAt = end
    self.fields = fields
    guard line.utf8.count <= 4096 else { throw FixtureSnapshotError.malformed }
  }

  /// Fixed protocol keys only; unavailable/out-of-coverage states remain strings.
  public func value(_ key: String) -> String? { fields[key] }
  public var line: String {
    "safety-snapshot " + Self.keys.map { "\($0)=\(fields[$0]!)" }.joined(separator: " ")
  }
}

/// One outstanding laboratory request; never a window token or mutation permit.
public struct FixtureSnapshotConsumer {
  public let run: UUID
  private var latestSequence: UInt64 = 0
  private var latestRequest: UInt64 = 0
  private var pending: (request: UInt64, submittedAt: Double)?

  public init(run: UUID) { self.run = run }

  public mutating func begin(request: UInt64, at time: Double) throws {
    guard pending == nil else { throw FixtureSnapshotError.pending }
    guard request > latestRequest, time.isFinite, time >= 0 else {
      throw FixtureSnapshotError.stale
    }
    latestRequest = request
    pending = (request, time)
  }

  public mutating func consume(_ line: String, at time: Double) throws -> FixtureSafetySnapshot {
    guard let pending else { throw FixtureSnapshotError.pending }
    let snapshot = try FixtureSafetySnapshot(line: line)
    guard snapshot.run == run, snapshot.request == pending.request else {
      throw FixtureSnapshotError.context
    }
    guard time.isFinite, snapshot.startedAt >= pending.submittedAt,
      snapshot.finishedAt <= time, snapshot.sequence > latestSequence
    else { throw FixtureSnapshotError.stale }
    latestSequence = snapshot.sequence
    self.pending = nil
    return snapshot
  }
}

/// Fixture-owned issuance; checked exhaustion never reuses an identifier.
public struct FixtureSnapshotIssuer {
  private var sequence: UInt64
  private var request: UInt64 = 0
  private var closed = false

  public init(sequence: UInt64 = 0) { self.sequence = sequence }

  public mutating func issue(request: UInt64) throws -> UInt64 {
    guard !closed else { throw FixtureSnapshotError.exhausted }
    guard request > self.request else { throw FixtureSnapshotError.stale }
    let (next, overflow) = sequence.addingReportingOverflow(1)
    guard !overflow else {
      closed = true
      throw FixtureSnapshotError.exhausted
    }
    self.request = request
    sequence = next
    return next
  }
}
