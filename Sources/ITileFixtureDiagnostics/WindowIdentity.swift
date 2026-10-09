import Foundation

/// Explicit fixture-controlled AX identifier. Never interpreted on a user app.
public struct FixtureWindowIdentity: Equatable, Sendable {
  public let run: UUID
  public let serial: UInt64

  public init(run: UUID, serial: UInt64) throws {
    guard serial > 0 else { throw FixtureSnapshotError.malformed }
    self.run = run
    self.serial = serial
  }

  public init(identifier: String) throws {
    guard identifier.utf8.count <= 96 else { throw FixtureSnapshotError.malformed }
    let parts = identifier.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0] == "itile-fixture-v1",
      let run = UUID(uuidString: String(parts[1])), run.uuidString == parts[1],
      let serial = UInt64(parts[2]), serial > 0, String(serial) == parts[2]
    else { throw FixtureSnapshotError.malformed }
    try self.init(run: run, serial: serial)
  }

  public var identifier: String { "itile-fixture-v1:\(run.uuidString):\(serial)" }

  public func matchesOriginal(in snapshot: FixtureSafetySnapshot) -> Bool {
    run == snapshot.run && String(serial) == snapshot.value("original")
  }
}
