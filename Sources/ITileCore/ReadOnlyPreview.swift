/// Fixed, content-free outcomes from the production read-only control boundary.
public enum PreviewBlock: String, Equatable, Sendable {
  case permissionRequired, paused, stopped, staleContext, invalidProjection
  case invalidTarget, registryRejected, observationRejected, planRejected, unexpectedControlWork
}

public struct ReadOnlyPreviewResult: Equatable, Sendable {
  public let block: PreviewBlock
  public let target: Rect?
  public let modelRejection: ControlRejection?

  public var report: String {
    """
    Read-only tiling preview: blocked (\(block.rawValue)).
    Proposed frame: \(target.map { String(describing: $0) } ?? "unavailable")
    Control-model rejection: \(modelRejection.map { String(describing: $0) } ?? "none")
    No window was enrolled or moved. A new preview requires a fresh inspection.
    """
  }
}

/// Serialized by its owner. Accepts only focused evidence, never externally
/// asserted eligibility or control events. No effect can execute platform work.
public struct ReadOnlyPreview: Sendable {
  private var model = ControlModel()
  private var trusted = false
  private var paused = false
  private var stopped = false
  private var failed = false
  private var registries: Set<AppToken> = []

  public init() {}

  /// First usable area containing the sampled window center. Invalid geometry
  /// or an offscreen center has no primary-display fallback.
  public static func target(for frame: Rect, areas: [Rect]) -> Rect? {
    guard (try? LayoutEngine.frames(for: .window(0), in: frame)) != nil else { return nil }
    let x = frame.x + frame.width / 2
    let y = frame.y + frame.height / 2
    return areas.first {
      (try? LayoutEngine.frames(for: .window(0), in: $0)) != nil
        && x >= $0.x && x < $0.x + $0.width && y >= $0.y && y < $0.y + $0.height
    }
  }

  public var environmentEpoch: UInt64 { model.environmentEpoch }
  public var observationCount: Int { model.observations.count }

  public mutating func setTrust(_ value: Bool, at now: Double) {
    guard trusted != value else { return }
    trusted = value
    _ = consume(.permission(value), at: now)
  }

  public mutating func setPaused(_ value: Bool, at now: Double) {
    paused = value
    _ = consume(value ? .pause : .resume, at: now)
  }

  public mutating func attach(_ app: AppToken, at now: Double) {
    registries = registries.filter { $0.pid != app.pid || $0 == app }
    _ = consume(.attach(app), at: now)
  }

  /// Synchronize only a complete worker-owned tracked set, before using its reply.
  /// Rejected snapshots never partially replace model state.
  @discardableResult
  public mutating func synchronize(_ snapshot: ProbeRegistrySnapshot, at now: Double) -> Bool {
    guard !stopped, !failed else { return false }
    guard consume(.registrySnapshot(snapshot), at: now) == nil else { return false }
    registries.insert(snapshot.app)
    return true
  }

  public mutating func terminate(_ app: AppToken, at now: Double) {
    registries.remove(app)
    _ = consume(.appTerminated(app), at: now)
  }

  public mutating func invalidate(at now: Double) {
    _ = consume(.environmentChanged(.environmentChanged), at: now)
  }

  /// Activation/request replacement revokes prior evidence without changing the
  /// desktop epoch or the inspection pause preference. Only fresh reads follow.
  public mutating func revoke(at now: Double) {
    _ = consume(.pause, at: now)
  }

  public mutating func stop(at now: Double) {
    stopped = true
    _ = consume(.quit, at: now)
  }

  public mutating func preview(
    _ evidence: FocusedWindowEvidence, target: Rect, context: FocusRequestContext,
    currentApp: AppToken?, activationRevision: UInt64, at now: Double
  ) -> ReadOnlyPreviewResult {
    func result(_ block: PreviewBlock, _ rejection: ControlRejection? = nil)
      -> ReadOnlyPreviewResult
    {
      ReadOnlyPreviewResult(block: block, target: target, modelRejection: rejection)
    }
    guard !stopped else { return result(.stopped) }
    guard !failed else { return result(.unexpectedControlWork) }
    guard trusted else { return result(.permissionRequired) }
    guard !paused else { return result(.paused) }
    guard
      context.accepts(
        currentApp: currentApp, environmentEpoch: environmentEpoch,
        activationRevision: activationRevision, trusted: trusted, paused: paused),
      evidence.token.app == context.app,
      evidence.environmentEpoch == environmentEpoch,
      evidence.finishedAt <= now
    else { return result(.staleContext) }
    guard let observation = evidence.controlObservation else {
      return result(.invalidProjection)
    }
    guard (try? LayoutEngine.frames(for: .window(0), in: target)) != nil else {
      return result(.invalidTarget)
    }
    guard registries.contains(evidence.token.app) else { return result(.registryRejected) }
    let observationRejection = consume(.observation(observation), at: now)
    guard !failed else { return result(.unexpectedControlWork) }
    if let observationRejection { return result(.observationRejected, observationRejection) }
    let rejection = consume(.tile([observation.token: target]), at: now)
    // Even an unexpected successful plan is an internal failure in this path.
    // There is no dispatcher, setter handler, or automatic reconcile handler.
    guard !failed, let rejection, model.pending.isEmpty, model.state != .active else {
      failed = true
      _ = consume(.pause, at: now)
      return result(.unexpectedControlWork)
    }
    return result(.planRejected, rejection)
  }

  /// Effects are consumed locally; only fixed rejection data leaves this type.
  private mutating func consume(_ event: ControlEvent, at now: Double) -> ControlRejection? {
    var rejection: ControlRejection?
    for effect in model.reduce(event, at: now) {
      switch effect {
      case .rejected(let reason): rejection = reason
      case .admissionRevoked, .reconcile: break
      case .prepare, .perform, .readback: failed = true
      }
    }
    return rejection
  }
}
