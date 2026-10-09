import Foundation

public enum FixtureHostEvent: Equatable, Sendable {
  case pause(Bool)
  case trust(Bool)
  case environment, activation, stop, processExit, runReplacement
}

/// One attached run and one outstanding pair, including revoked work awaiting completion.
/// This laboratory owner never admits setters or supplies production evidence.
public struct FixtureDiagnosticHost {
  public private(set) var authority: FixtureHostAuthority
  public private(set) var assessment = FixturePairAssessment()
  public private(set) var pendingRequest: UInt64?
  private var revoked = false

  public init(context: FixtureUseContext) { authority = FixtureHostAuthority(context: context) }
  public var context: FixtureUseContext { authority.context }
  public var current: FixturePairResult { assessment.current }

  public mutating func observe(_ event: FixtureHostEvent) {
    switch event {
    case .pause(let value):
      guard value != context.paused else { return }
      authority.update(paused: value)
    case .trust(let value):
      guard value != context.trusted else { return }
      authority.update(trusted: value)
    case .environment: authority.update(environmentChanged: true)
    case .activation: authority.update(activationChanged: true)
    case .stop, .processExit, .runReplacement: authority.update(stopped: true)
    }
    assessment.invalidate()
    if pendingRequest != nil { revoked = true }
  }

  public mutating func begin(request: UInt64) throws {
    guard pendingRequest == nil else { throw FixtureSnapshotError.pending }
    guard !authority.closed, context.trusted, !context.paused, !context.stopped else {
      throw FixtureSnapshotError.context
    }
    try assessment.begin(request: request, context: context)
    pendingRequest = request
    revoked = false
  }

  @discardableResult
  public mutating func finish(
    request: UInt64, before: FixtureSafetySnapshot,
    focused: FixtureWindowIdentity, axStart: Double, axEnd: Double, after: FixtureSafetySnapshot,
    now: Double
  ) -> FixturePairResult {
    guard pendingRequest == request else { return .wrongRequest }
    pendingRequest = nil
    guard !revoked else { return .contextRevoked }
    return assessment.consume(
      request: request, before: before, focused: focused,
      axStart: axStart, axEnd: axEnd, after: after, context: context, now: now)
  }

  /// A failed/missing read releases only the matching outstanding request.
  @discardableResult
  public mutating func abandon(request: UInt64) -> FixturePairResult {
    guard pendingRequest == request else { return .wrongRequest }
    pendingRequest = nil
    if !revoked { assessment.discard() }
    return current
  }
}
