# M2.19 — Read-only evidence provenance and expiry contract

Status: specified; [M2.20](m2-evidence-values.md) implements the pure value/assessment subset. [M2.21](m2-focused-provenance-report.md) adds historical focused reply/report presentation; new acquisition providers and measured age policies remain proposed. Production eligibility remains unknown or ineligible under [ADR 0004](decisions/0004-supported-scope.md). This contract supplies no new provider or proof of window safety.

## Purpose and boundary

Make each outstanding requirement explain which reader supplied its evidence, what that reader covers, when it sampled, and why that evidence cannot authorize control. Separate sample completeness, provider coverage, freshness, and current lifecycle context. None implies the others.

The initial implementation must represent only diagnostics and exclusions. It must offer no externally asserted `eligible`, `safe`, or provider-approved Boolean, and no initializer that turns a source label into authority. A future narrower eligibility provider requires a separate scope decision and acceptance; adding metadata cannot reopen mutation.

The existing [focused evidence](../Sources/ITileCore/FocusedProbe.swift) carries token, epoch, worker sequence, and a whole-request interval. It does not carry an independently measured interval for each structural/CG read, a reviewed safety provider, or a measured production age policy. [Eligibility assessment](../Sources/ITileCore/WindowEligibility.swift) retains three requirements unconditionally. Preserve those semantics.

## Proposed immutable values

Use pure Swift value types with no AX/AppKit objects, closures, system clock reads, arbitrary diagnostic strings, or application content. The owner supplies current context and monotonic time explicitly.

| Value | Required fields and meaning |
| --- | --- |
| Evidence envelope | WindowToken (including process attachment), environment epoch, worker sequence, request started/finished times, three fixed requirement records |
| Requirement record | Requirement code, closed source code, source schema revision, coverage code, sampling outcome, fixed issue codes, acquisition interval attribution |
| Source code | Initially `focusedAX`, `boundedAXStructure`, or `uncorrelatedCGBounds`; a source describes acquisition, never authority |
| Coverage | Initially `sampledPrerequisite`, `positiveExclusionOnly`, or `unsupportedRequirement`; no initial coverage case asserts lifecycle safety |
| Sampling outcome | `notSampled`, `findings`, `noFinding`, or `incomplete`; findings and incomplete issues may coexist |
| Interval attribution | Initially `enclosingRequest`; claim-specific timing may be added only when the reader measures it |
| Owner-use context | Captured request identity, activation revision, and owner revocation generation, checked against current values; this is owner metadata, never worker proof |
| Freshness policy | Optional explicit positive finite maximum diagnostic age and policy revision, supplied by the owner; no production default is approved here |
| Assessment | Fixed context/interval/freshness reasons alongside unchanged eligibility exclusions and unproven requirements |

Exactly one record is required for each of `currentDesktopVisibility`, `nativeTabSafety`, and `nestedDialogSafety`. Missing or duplicate records reject the envelope as malformed; do not silently select one. Fixed source/requirement pairings prevent relabeling an uncorrelated candidate as an identity provider. Source revisions are positive known constants; unknown revisions reject projection rather than falling back to an older interpretation.

Use existing bounded summaries for counts/issues; do not duplicate AX trees or CG metadata lists in the envelope. Retain fixed enum issue sets in deterministic order and validate nonnegative counts against their existing reader bounds. No new identifiers need to be issued: the worker sequence identifies the envelope within its app attachment. This remains session-local evidence, not a persistent OS identity or native desktop number.

## Initial source mapping

| Requirement | Diagnostic source | Supported coverage | Mandatory retained reason |
| --- | --- | --- | --- |
| Current desktop visibility | Uncorrelated on-screen CG bounds, with the focused AX read as context | Candidate counts/ambiguity/incomplete outcomes; no AX-to-CG identity link | `currentDesktopVisibility` |
| Native-tab safety | Bounded AX structural sample | Positive tab-group exclusion; no native-tab absence or transition guarantee | `nativeTabSafety` |
| Nested-dialog safety | Bounded AX structure and existing direct-sheet sample | Positive sheet/dialog exclusion; no complete lifecycle coverage | `nestedDialogSafety` |

`focusedAX` may describe sampled role, focus, capability, and token prerequisites, but cannot replace a source in this table to clear any retained reason. A direct-sheet result and nested sample keep their separate completeness outcomes. Any observed positive finding survives an incomplete sample and contributes its existing exclusion.

A zero count means `noFinding` only within the actual sampled structure; unsupported reads or bounded traversal issues remain explicit. A single CG bounds candidate is a diagnostic finding, not a positive identity/visibility finding or an exclusion. Zero candidates do not prove the AX window is off-desktop. These mappings reflect [the reviewed implementation](m2-production-readiness.md), not universal claims about public APIs.

## Time and expiry rules

1. Validate finite nonnegative `startedAt`, finite `finishedAt >= startedAt`, and a positive worker sequence. Require a finite owner time `now >= finishedAt`; future or malformed samples cannot be current. Different clock domains cannot be compared or silently converted.
2. Use request start as the conservative acquisition time until per-read timing exists. The enclosing interval cannot establish that all attributes were simultaneously true or that state remained unchanged between reads.
3. Without an explicit diagnostic age policy, freshness is `unmeasured`, never current-for-control. Reports may still display historical observations under existing delivery guards. The model's simulation age of 0.5 seconds is not a policy approval.
4. With a policy, compute `expiresAt = startedAt + maximumAge`. Reject nonfinite sums, a sum that fails to advance the start time, and nonpositive/nonfinite age limits. `now >= expiresAt` is expired, including equality. A request already expired when it finishes is historical. Policy changes require re-assessment; extending a policy cannot revive evidence invalidated by a lifecycle event.
5. Reply acknowledgment, report opening, preview calculation, or revalidation failure cannot refresh the sample time. Fresh inspection yields a new sequence; it does not mutate an old envelope.

Diagnostic freshness is a presentation/rejection classification. Even a context-matching, unexpired diagnostic envelope retains all three unproven requirements. It is not a setter permit, enrollment record, or future proof-provider lease.

## Context and supersession

The app retains its existing request and activation guards; the worker owns only worker evidence. Do not copy activation revision into an AX observation as if the worker measured it. Validate the envelope against the current app attachment, accepted tracked registry, environment epoch, owner request/activation/revocation context, trust, pause, and stopped state before current projection.

Proposed implementation order:

1. Validate shape/source/interval fields and exact app/window/epoch context.
2. Validate the sequence against the existing per-app worker sequence watermark. A strictly newer accepted envelope supersedes the prior envelope, even when its evidence is incomplete or unsupported. Do not use an older complete sample as a fallback.
3. Derive freshness and coverage independently; combine existing positive exclusions and retained unknown reasons. Duplicate/replayed or older replies cannot refresh or overwrite current evidence.
4. Only then publish diagnostic values. An uncertainty/protocol failure on a current route invalidates the relevant current evidence; a stale retired-process reply does not invalidate a replacement process. Never partially merge attributes from separate envelopes into a stronger proof.

Capture an owner revocation generation when the explicit request is admitted; a generation change invalidates its later use even after resume. Do not issue or reset a second generation that competes with the existing control boundary. Metadata projection alone does not implement the future synchronized safety gate.

The initial stage needs no extra persistent evidence cache. Derive one envelope per accepted focused reply. If a later stage retains envelopes, use existing registry bounds (64 windows per app, 256 total, 16 apps), one latest envelope per tracked window, and the existing app-wide sequence authority. Registry removal retires evidence; no extra unbounded tombstones, queues, or per-notification tasks are allowed.

## Invalidation and recovery

| Event | Required effect on any current evidence |
| --- | --- |
| Request replacement or focus/activation change | Reject prior request/context; require fresh focused inspection |
| Desktop/display, sleep/wake, or observed trust loss | Invalidate the authoritative epoch/context; old samples cannot cross recovery |
| Pause, Disable, Quit, or issuer exhaustion | End current use immediately; resume/enable cannot revive stored evidence |
| Window destruction, registry retirement, app termination/replacement | Remove exact token evidence; preserve process-generation isolation |
| Structural uncertainty, unsupported reads, budget/cancellation, or route overload | Retain explicit limitations; suspend any stronger proposed use and require explicit fresh inspection |
| New positive tab/sheet/dialog evidence | Preserve the exclusion alongside incomplete/expired historical status |

These are implementation obligations for evidence use, not a claim that the current reader observes every transition promptly. [M2.17](m2-production-readiness.md) identifies the missing continuous safety ingress; a blocked worker can delay observer processing. A timestamp or notification registration cannot repair missing coverage or eliminate the race after a sample. Live admission must later check its own authority immediately before each platform call.

Expired or context-rejected findings may remain visible only as historical diagnostics with their original reasons. They cannot become current exclusions/observations for a different token or silently contaminate a replacement attachment. Recovery performs a fresh explicit read; there is no automatic polling, action, or retry introduced here.

## Acceptance for the next source task

M2.20 now implements pure provenance values, a deterministic diagnostic assessment, and projection from the existing focused evidence; see [its acceptance and limits](m2-evidence-values.md). Keep platform/UI wiring as a separate follow-up after value acceptance. It must preserve unknown/ineligible eligibility for every projection and cannot expose an eligible production branch.

Required value tests:

- Complete zero-finding samples, positive incomplete samples, single/ambiguous/missing CG candidates, and absent scans retain the exact supported source mapping and all three unproven requirements.
- Unknown source revisions, duplicate/missing records, invalid pairings, malformed counts, nonfinite/reversed intervals, zero sequence, future finish, invalid policy, and overflowed expiry reject current projection.
- No policy yields unmeasured freshness; below/equal/above expiry boundaries and a read finishing after expiry produce deterministic results using injected times.
- App/window/epoch/request/activation mismatch, pause/trust loss/stopping, and process replacement reject current use. No acknowledgment or report formatting refreshes time.
- Projection preserves existing positive exclusions, structural issue codes, geometry/capability validation, and enclosing-request attribution without fabricating per-read timing or simultaneous sampling.

Run format/verify for source changes. Actual reader/menu delivery, topology, notifications, and measured freshness remain separate manual checks. No test here establishes a real visibility/tab/dialog provider.

## Review result

M2.19 specifies the contract and next source acceptance only. No Swift source, installed app, permission, display, window, or keyboard behavior changed. The latest recorded source verification remains M2.18's 177 passing tests. Production mutation scope remains empty.
