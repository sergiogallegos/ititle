/// Historical presentation only. Acceptance never supplies a current observation or permit.
public struct FocusedDiagnosticReport: Sendable {
  public let acceptedHistoricalSample: Bool
  public let assessment: DiagnosticEvidenceAssessment
  public let report: String
}

/// One scalar receipt watermark per existing app attachment; no new sequence issuer
/// or retained evidence cache. The serialized owner removes this state on retirement.
public struct FocusedDiagnosticState: Sendable {
  public let app: AppToken
  public private(set) var latestWorkerSequence: UInt64 = 0

  public init(app: AppToken) { self.app = app }

  public mutating func consume(
    _ envelope: DiagnosticEvidenceEnvelope, in context: EvidenceAssessmentContext, at now: Double
  ) -> FocusedDiagnosticReport {
    // This attachment's watermark is authoritative for presentation. Never trust
    // a caller-provided baseline or let a retired route consume a replacement's sequence.
    let current = EvidenceAssessmentContext(
      window: context.window?.app == app ? context.window : nil,
      environmentEpoch: context.environmentEpoch, use: context.use,
      registry: context.registry, latestWorkerSequence: latestWorkerSequence,
      trusted: context.trusted, paused: context.paused, stopped: context.stopped)
    let assessment = envelope.assess(in: current, at: now)
    let accepted = assessment.rejections.isEmpty
    if accepted { latestWorkerSequence = envelope.evidence.workerSequence }
    let reasons =
      assessment.rejections.isEmpty
      ? "none" : assessment.rejections.map(\.rawValue).joined(separator: ",")
    let freshness = assessment.freshness == .unmeasured ? "unmeasured" : "invalid"
    var lines = [
      "Read-only evidence provenance: historical; freshness=\(freshness) (no diagnostic age policy).",
      "owner-request=\(envelope.useContext.request); activation-revision=\(envelope.useContext.activationRevision); revocation-generation=\(envelope.useContext.revocationGeneration)",
      "acquisition=enclosingRequest; start=\(envelope.evidence.startedAt); end=\(envelope.evidence.finishedAt)",
      "historical-sample-accepted=\(accepted); rejection-reasons=\(reasons)",
    ]
    // Records are always derived by the public envelope initializer. Fixed codes,
    // counters, and times only; original window content is never copied here.
    for record in envelope.records {
      let issues =
        record.issues.isEmpty
        ? "none" : record.issues.map(\.diagnosticCode).joined(separator: ",")
      lines.append(
        "requirement=\(record.requirement.rawValue); source=\(record.source.rawValue); source-revision=\(record.sourceRevision); coverage=\(record.coverage.rawValue); sample=\(record.outcome.rawValue); interval=\(record.interval.rawValue); issues=\(issues)"
      )
    }
    lines.append(
      "Sample completeness does not prove lifecycle safety. No enrollment or window mutation.")
    return FocusedDiagnosticReport(
      acceptedHistoricalSample: accepted, assessment: assessment,
      report: lines.joined(separator: "\n"))
  }
}
