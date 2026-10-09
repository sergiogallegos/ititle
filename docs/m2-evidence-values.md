# M2.20 — Pure diagnostic evidence values

Status: source implemented and automated acceptance passed. [M2.21](m2-focused-provenance-report.md) now wires historical app/report presentation without changing platform acquisition; production eligibility remains unknown or ineligible.

## Implemented boundary

[EvidenceProvenance.swift](../Sources/ITileCore/EvidenceProvenance.swift) implements the value subset of [M2.19](m2-evidence-provenance.md): a whole focused envelope, fixed requirement/source/coverage/outcome values, canonical issue sets, enclosing-request attribution, captured owner-use context, explicit diagnostic age policy, current assessment context, and deterministic rejection/freshness assessment.

`DiagnosticEvidenceEnvelope(evidence:useContext:)` derives all three requirement records from the existing focused sample. There is no public record/source override, eligibility assertion, or safety coverage case. Malformed-record construction is internal for tests. Assessment compares records with the canonical derivation, so unknown source revisions, missing/duplicate records, relabeling, or inconsistent outcomes cannot become accepted diagnostic projections.

The envelope retains the original bounded summaries rather than copying AX trees or CG metadata. Tab/dialog records carry structural issues and dialog records also carry separate direct-sheet read/completeness issues. Positive findings coexist with incomplete issues. CG candidate counts remain unsupported for identity-correlated visibility. Canonical issue ordering is deterministic and duplicate issues collapse.

Count checks reflect the existing reader bounds: nested scans examine at most 64 nodes and each descendant finding count is bounded by examined descendants; direct sheets are sampled from at most 16 child roles; CG metadata retains at most 128 entries. Finding counts are checked independently because role/subrole classifications may overlap. Negative or overflowing input counts reject projection without arithmetic traps.

## Assessment and authority

The caller supplies an immutable `EvidenceAssessmentContext`, an optional `DiagnosticAgePolicy`, and monotonic `now`. No system clock, AX object, AppKit import, callback, cache, or automatic worker action exists in this file.

The context includes the current exact window/process attachment, environment epoch, accepted tracked registry, prior app-wide worker sequence watermark, current owner request/activation/revocation values, trust, pause, and stopped state. `latestWorkerSequence` is the watermark **before accepting this envelope**: the envelope must be strictly newer. The future owner integration must advance its existing sequence authority after accepting a newer sample, including incomplete evidence, and must not fall back to older complete evidence. These values do not implement that integration or replace a synchronized safety gate.

Assessment preserves the original historical eligibility assessment alongside fixed rejection codes. A context/shape/time-rejected envelope cannot produce a current observation. Without a policy, freshness is `unmeasured` and the original sample remains available only as historical evidence. With a valid explicit policy, expiry is measured from request start; equality is expired. Invalid/nonfinite policy or interval values, future completion, overflowed/nonadvancing expiry, and replayed sequence reject current projection.

Freshness describes the diagnostic deadline independently of context rejection. An unexpired deadline cannot overcome a stale context, unsupported coverage, or missing eligibility. A longer policy cannot repair a changed revocation generation. Neither assessment nor policy alters the original sample times.

A returned observation comes exclusively from the existing focused projection after all checks and an unexpired diagnostic policy. Its eligibility remains unknown or ineligible and all three scope requirements remain unproven. Source attribution does not grant enrollment, control admission, or mutation; no production age policy is selected by this task.

## Acceptance

`scripts/format` and `scripts/verify` passed 188 tests (123 core, 65 platform). Eleven new tests cover:

- Complete zero-finding and positive incomplete samples; absent scans; deterministic issues; single/ambiguous/missing CG candidates; retained eligibility requirements.
- Malformed record cardinality, source/revision/coverage/outcome relabeling, count bounds, identity, intervals, future completion, owner time, and replay rejection.
- No-policy assessment; exact expiry boundaries; reads finishing after expiry; invalid policies; nonfinite/nonadvancing expiry.
- App/window/epoch/request/activation/revocation mismatch, trust/pause/stop, registry retirement/replacement/absence/malformed snapshots, and failure to revive evidence by extending policy.
- Newer incomplete evidence with caller-supplied sequence authority; geometry/capability validation; preserved unknown/ineligible projection and original acquisition times.

The verification build also emitted three existing captured-variable warnings in `SimulatedDeliveryTests`; no new evidence-value warning was emitted. No real application/window, AX call, permission change, menu report, monitor, installed bundle, or latency acceptance was exercised.

The follow-up [M2.21](m2-focused-provenance-report.md) now integrates the envelope as historical read-only provenance in the existing focused reply/report path. Capture owner-use context at request admission, keep current delivery/registry guards and sequence ownership, show fixed source/coverage/interval metadata and unmeasured freshness, and preserve blocked preview semantics. Do not add a default age policy, extra issuer/cache, eligibility override, AX reads, or mutation. Separate manual menu acceptance follows source checks.
