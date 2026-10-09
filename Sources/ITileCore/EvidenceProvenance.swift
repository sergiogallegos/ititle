/// Diagnostic requirements have no initial safety-provider coverage.
public enum EvidenceRequirement: String, CaseIterable, Equatable, Sendable {
  case currentDesktopVisibility, nativeTabSafety, nestedDialogSafety
}
public enum EvidenceSource: String, Equatable, Sendable {
  case focusedAX, boundedAXStructure, uncorrelatedCGBounds
}
public enum EvidenceCoverage: String, Equatable, Sendable {
  case sampledPrerequisite, positiveExclusionOnly, unsupportedRequirement
}
public enum EvidenceSamplingOutcome: String, Equatable, Sendable {
  case notSampled, findings, noFinding, incomplete
}
public enum EvidenceIntervalAttribution: String, Equatable, Sendable { case enclosingRequest }
public enum EvidenceIssue: Equatable, Sendable {
  case structural(NestedDialogScanIssue)
  case onScreenBounds(OnScreenBoundsIssue)
  case directSheetsUnavailable, directSheetsInvalidType, directSheetsIncomplete

  var diagnosticCode: String {
    switch self {
    case .structural(let issue): return "structure.\(issue.rawValue)"
    case .onScreenBounds(let issue): return "bounds.\(issue.rawValue)"
    case .directSheetsUnavailable: return "direct.unavailable"
    case .directSheetsInvalidType: return "direct.invalidType"
    case .directSheetsIncomplete: return "direct.incomplete"
    }
  }
}

public struct RequirementEvidence: Equatable, Sendable {
  public let requirement: EvidenceRequirement
  public let source: EvidenceSource
  public let sourceRevision: UInt64
  public let coverage: EvidenceCoverage
  public let outcome: EvidenceSamplingOutcome
  public let issues: [EvidenceIssue]
  public let interval: EvidenceIntervalAttribution
}

/// Captured by the owner, never asserted by the AX reader.
public struct EvidenceUseContext: Equatable, Sendable {
  public let request: UInt64
  public let activationRevision: UInt64
  public let revocationGeneration: UInt64

  public init(request: UInt64, activationRevision: UInt64, revocationGeneration: UInt64) {
    self.request = request
    self.activationRevision = activationRevision
    self.revocationGeneration = revocationGeneration
  }
}

/// Diagnostic policy only. No default or measured production control age.
public struct DiagnosticAgePolicy: Equatable, Sendable {
  public let maximumAge: Double
  public let revision: UInt64
  public init(maximumAge: Double, revision: UInt64) {
    self.maximumAge = maximumAge
    self.revision = revision
  }
}
public enum DiagnosticFreshness: Equatable, Sendable {
  case unmeasured, invalid
  case unexpired(expiresAt: Double)
  case expired(expiresAt: Double)
}
public enum EvidenceRejection: String, Equatable, Sendable {
  case malformedRecords, malformedCounts, invalidIdentity, invalidInterval, invalidTime,
    futureSample
  case invalidPolicy, invalidExpiry, expired, staleSequence, staleContext, registryRejected
  case permissionRequired, paused, stopped, invalidProjection
}

/// Caller supplies its current registry/sequence authority. Assessment stores no cache.
public struct EvidenceAssessmentContext: Sendable {
  public let window: WindowToken?
  public let environmentEpoch: UInt64
  public let use: EvidenceUseContext
  public let registry: ProbeRegistrySnapshot?
  public let latestWorkerSequence: UInt64
  public let trusted: Bool
  public let paused: Bool
  public let stopped: Bool

  public init(
    window: WindowToken?, environmentEpoch: UInt64, use: EvidenceUseContext,
    registry: ProbeRegistrySnapshot?, latestWorkerSequence: UInt64,
    trusted: Bool, paused: Bool, stopped: Bool
  ) {
    self.window = window
    self.environmentEpoch = environmentEpoch
    self.use = use
    self.registry = registry
    self.latestWorkerSequence = latestWorkerSequence
    self.trusted = trusted
    self.paused = paused
    self.stopped = stopped
  }
}

public struct DiagnosticEvidenceAssessment: Sendable {
  public let freshness: DiagnosticFreshness
  public let rejections: [EvidenceRejection]
  /// Original historical exclusions and missing requirements, even on rejection.
  public let eligibilityAssessment: WindowEligibilityAssessment
  /// Available only with accepted context and an unexpired explicit diagnostic policy.
  /// This projection can still only be unknown or ineligible; it is never a permit.
  public let observation: WindowObservation?
}

/// A whole focused sample, without merging attributes or fabricating per-read timing.
public struct DiagnosticEvidenceEnvelope: Sendable {
  public let evidence: FocusedWindowEvidence
  public let useContext: EvidenceUseContext
  public let records: [RequirementEvidence]

  public init(evidence: FocusedWindowEvidence, useContext: EvidenceUseContext) {
    self.init(evidence: evidence, useContext: useContext, records: Self.records(for: evidence))
  }

  // Internal malformed-value construction for boundary tests; no public source override.
  init(
    evidence: FocusedWindowEvidence, useContext: EvidenceUseContext, records: [RequirementEvidence]
  ) {
    self.evidence = evidence
    self.useContext = useContext
    self.records = records
  }

  public func assess(
    in context: EvidenceAssessmentContext, policy: DiagnosticAgePolicy? = nil, at now: Double
  ) -> DiagnosticEvidenceAssessment {
    var rejected: [EvidenceRejection] = []
    func reject(_ reason: EvidenceRejection) {
      if !rejected.contains(reason) { rejected.append(reason) }
    }
    let expected = Self.records(for: evidence)
    if records.count != 3 || !expected.allSatisfy({ records.contains($0) }) {
      reject(.malformedRecords)
    }
    if !Self.validCounts(evidence) { reject(.malformedCounts) }
    if evidence.token.app.pid <= 0 || evidence.token.app.generation == 0
      || evidence.token.serial == 0
    {
      reject(.invalidIdentity)
    }
    let validInterval =
      evidence.startedAt.isFinite && evidence.startedAt >= 0
      && evidence.finishedAt.isFinite && evidence.finishedAt >= evidence.startedAt
    if !validInterval { reject(.invalidInterval) }
    let validTime = now.isFinite && now >= 0
    if !validTime { reject(.invalidTime) }
    if validInterval && validTime && now < evidence.finishedAt { reject(.futureSample) }
    if evidence.workerSequence == 0 || evidence.workerSequence <= context.latestWorkerSequence {
      reject(.staleSequence)
    }
    if useContext.request == 0 || context.use.request == 0 || useContext != context.use
      || context.window != evidence.token || context.environmentEpoch != evidence.environmentEpoch
    {
      reject(.staleContext)
    }
    if let registry = context.registry,
      registry.app == evidence.token.app, registry.environmentEpoch == evidence.environmentEpoch,
      registry.revision > 0, registry.windows.count <= 64,
      registry.windows.contains(evidence.token),
      registry.windows.allSatisfy({
        $0.app == registry.app && $0.serial > 0 && $0.serial <= registry.highestSerial
      })
    {
    } else {
      reject(.registryRejected)
    }
    if !context.trusted { reject(.permissionRequired) }
    if context.paused { reject(.paused) }
    if context.stopped { reject(.stopped) }

    var freshness: DiagnosticFreshness = validInterval && validTime ? .unmeasured : .invalid
    if let policy {
      if !policy.maximumAge.isFinite || policy.maximumAge <= 0 || policy.revision == 0 {
        reject(.invalidPolicy)
        freshness = .invalid
      } else if validInterval && validTime {
        let expiry = evidence.startedAt + policy.maximumAge
        if !expiry.isFinite || expiry <= evidence.startedAt {
          reject(.invalidExpiry)
          freshness = .invalid
        } else if now >= expiry {
          freshness = .expired(expiresAt: expiry)
          reject(.expired)
        } else {
          freshness = .unexpired(expiresAt: expiry)
        }
      }
    }
    let projection = evidence.controlObservation
    if projection == nil { reject(.invalidProjection) }
    let observation: WindowObservation?
    if rejected.isEmpty, case .unexpired = freshness {
      observation = projection
    } else {
      observation = nil
    }
    return DiagnosticEvidenceAssessment(
      freshness: freshness, rejections: rejected,
      eligibilityAssessment: evidence.eligibilityAssessment, observation: observation)
  }

  private static func records(for evidence: FocusedWindowEvidence) -> [RequirementEvidence] {
    func record(
      _ requirement: EvidenceRequirement, source: EvidenceSource, positive: Bool,
      notSampled: Bool, issues: [EvidenceIssue]
    ) -> RequirementEvidence {
      var unique: [EvidenceIssue] = []
      for issue in issues where !unique.contains(issue) { unique.append(issue) }
      unique.sort { $0.diagnosticCode < $1.diagnosticCode }
      let outcome: EvidenceSamplingOutcome =
        positive
        ? .findings
        : (notSampled ? .notSampled : (unique.isEmpty ? .noFinding : .incomplete))
      return RequirementEvidence(
        requirement: requirement, source: source, sourceRevision: 1,
        coverage: source == .uncorrelatedCGBounds || notSampled
          ? .unsupportedRequirement : .positiveExclusionOnly,
        outcome: outcome, issues: unique, interval: .enclosingRequest)
    }
    let nested = evidence.nestedDialogs
    let bounds = evidence.onScreenBounds
    let structural = nested.issues.map(EvidenceIssue.structural)
    var dialogIssues = structural
    var directPositive = false
    switch evidence.directSheetCount {
    case .value(let count): directPositive = count > 0
    case .unavailable: dialogIssues.append(.directSheetsUnavailable)
    case .invalidType: dialogIssues.append(.directSheetsInvalidType)
    }
    if !evidence.directSheetScanComplete { dialogIssues.append(.directSheetsIncomplete) }
    return [
      record(
        .currentDesktopVisibility, source: .uncorrelatedCGBounds,
        positive: bounds.boundsCandidates > 0, notSampled: bounds.issues.contains(.notSampled),
        issues: bounds.issues.map(EvidenceIssue.onScreenBounds)),
      record(
        .nativeTabSafety, source: .boundedAXStructure,
        positive: nested.observedTabGroups > 0, notSampled: nested.issues.contains(.notScanned),
        issues: structural),
      record(
        .nestedDialogSafety, source: .boundedAXStructure,
        positive: directPositive || nested.observedSheets > 0 || nested.observedDialogs > 0,
        notSampled: nested.issues.contains(.notScanned) && !evidence.directSheetScanComplete,
        issues: dialogIssues),
    ]
  }

  private static func validCounts(_ evidence: FocusedWindowEvidence) -> Bool {
    let nested = evidence.nestedDialogs
    guard (0...64).contains(nested.examinedNodes) else { return false }
    let descendants = max(0, nested.examinedNodes - 1)
    guard
      [nested.observedSheets, nested.observedDialogs, nested.observedTabGroups]
        .allSatisfy({ (0...descendants).contains($0) })
    else { return false }
    if case .value(let count) = evidence.directSheetCount, !(0...16).contains(count) {
      return false
    }
    let bounds = evidence.onScreenBounds
    return (0...128).contains(bounds.examinedEntries)
      && (0...bounds.examinedEntries).contains(bounds.ordinaryEntries)
      && (0...bounds.ordinaryEntries).contains(bounds.boundsCandidates)
  }
}
