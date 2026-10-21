import Foundation

/// Delivered laboratory callback identity, never a physical-event or coverage guarantee.
public enum FixtureEnvironmentSource: String, Codable, CaseIterable, Sendable {
  case nativeSpace, screenParameters, willSleep, didWake

  public var eventCode: String { self == .nativeSpace ? "nativeSpace" : "environment" }
}

public enum FixtureEventSourceContract: String, Codable, Sendable {
  case environmentCallbacks
}
