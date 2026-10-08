/// Content-free window-server metadata scoped to the inspected application.
/// A matching rectangle is a candidate, never an AX identity or visibility proof.
public struct OnScreenWindowMetadata: Equatable, Sendable {
  public let layer: Int?
  public let frame: Rect?

  public init(layer: Int?, frame: Rect?) {
    self.layer = layer
    self.frame = frame
  }
}

public enum OnScreenBoundsIssue: String, Equatable, Sendable {
  case notSampled, metadataUnavailable, frameUnavailable, invalidGeometry, invalidMetadata
  case entryLimit, budget, cancelled
}

public struct OnScreenBoundsEvidence: Equatable, Sendable {
  public let examinedEntries: Int
  public let ordinaryEntries: Int
  public let boundsCandidates: Int
  public let issues: [OnScreenBoundsIssue]

  public static let notSampled = OnScreenBoundsEvidence(issue: .notSampled)

  public init(issue: OnScreenBoundsIssue) {
    examinedEntries = 0
    ordinaryEntries = 0
    boundsCandidates = 0
    issues = [issue]
  }

  /// Compare finite positive rectangles at a fixed one-logical-point tolerance.
  /// Even one candidate can belong to another same-app window on another desktop.
  public init(
    frame: Rect, windows: [OnScreenWindowMetadata], entryLimit: Int = 128,
    issues initialIssues: [OnScreenBoundsIssue] = []
  ) {
    var issues: [OnScreenBoundsIssue] = []
    func record(_ issue: OnScreenBoundsIssue) {
      if !issues.contains(issue) { issues.append(issue) }
    }
    for issue in initialIssues { record(issue) }
    if !Self.valid(frame) { record(.invalidGeometry) }
    if entryLimit <= 0 || windows.count > entryLimit { record(.entryLimit) }
    var ordinary = 0
    var candidates = 0
    let entries = windows.prefix(max(0, entryLimit))
    for window in entries {
      guard let layer = window.layer else {
        record(.invalidMetadata)
        continue
      }
      guard layer == 0 else { continue }
      ordinary += 1
      guard let candidate = window.frame, Self.valid(candidate) else {
        record(.invalidMetadata)
        continue
      }
      if Self.valid(frame),
        zip(
          [frame.x, frame.y, frame.width, frame.height],
          [candidate.x, candidate.y, candidate.width, candidate.height]
        ).allSatisfy({ abs($0 - $1) <= 1 })
      {
        candidates += 1
      }
    }
    examinedEntries = entries.count
    ordinaryEntries = ordinary
    boundsCandidates = candidates
    self.issues = issues
  }

  private static func valid(_ rect: Rect) -> Bool {
    [rect.x, rect.y, rect.width, rect.height, rect.x + rect.width, rect.y + rect.height]
      .allSatisfy { $0.isFinite } && rect.width > 0 && rect.height > 0
  }

  public var report: String {
    let result: String
    if boundsCandidates > 1 {
      result = "ambiguousBoundsCandidates"
    } else if !issues.isEmpty {
      result = "incomplete"
    } else {
      result = boundsCandidates == 1 ? "singleBoundsCandidate" : "noBoundsCandidate"
    }
    let outcomes = issues.isEmpty ? "complete" : issues.map(\.rawValue).joined(separator: ",")
    return """
      on-screen-bounds: candidates=\(boundsCandidates); ordinary-entries=\(ordinaryEntries); examined=\(examinedEntries); result=\(result); outcomes=\(outcomes)
      CG/AX identity and current-desktop visibility remain unproven; tolerance=1 logical point.
      """
  }
}
