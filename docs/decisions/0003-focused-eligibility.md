# ADR 0003: Focused eligibility requires evidence, not consent alone

Status: accepted; conservative assessment implemented, eligible production scope not implemented. Date: 2026-10-04.

## Context

M2.2 has scoped manual evidence for focused revalidation and stale-result rejection across focus, permission, desktop, and display changes. Finder tab switches changed tokens; direct sheets were detected; an occluded Chrome window still appeared in the on-screen list. These observations do not establish generic native-tab, nested-dialog, or current-desktop visibility safety. See [validation](../validation.md) for the experiments and their limits.

The pure control simulation accepts synthetic eligible observations. A production adapter must not supply that status merely because a window has a standard role, writable geometry, matching bounds, or explicit user consent.

## Decision

The intended initial mutation scope remains explicitly selected ordinary windows on one desktop/display. **The currently enforceable production mutation scope is empty.** Read-only diagnostics remain available. This is a source policy checkpoint, not live enrollment or a platform acceptance pass.

`WindowEligibilityAssessment` is a pure value assessment of `FocusedWindowEvidence`. It separates positive exclusions from missing evidence. Any positive exclusion yields `ineligible`; otherwise the result is `unknown`. Missing requirements remain visible even when an exclusion already blocks the window. The current assessment has no `eligible` branch or user-settable override.

| Evidence | Positive exclusion | Unknown requirement |
| --- | --- | --- |
| Role and subrole | Non-window or non-standard window | Missing or malformed read |
| Minimized, fullscreen, modal | Any observed true flag | Missing or malformed state |
| Position and size capabilities | Either observed unsupported | Missing or malformed capability |
| Focused continuity | Observed focus change | No positive sampled continuity |
| Historical token comparison, when requested | Token mismatch | No comparison requested does not establish historical continuity |
| Destruction notification | Registration alone never grants eligibility | No successful registration |
| Direct sheets | Any positive count, including incomplete scans | Negative/missing count or incomplete scan |
| Geometry | No state exclusion inferred from malformed input | Missing, non-finite, non-positive dimensions, or overflowing edges |
| Observation interval and worker sequence | No state exclusion inferred from malformed input | Non-finite/backward/negative interval or zero sequence |
| Nested sheets/dialogs | Positive descendant findings exclude, even in incomplete scans | Structural scans never establish lifecycle safety |
| Desktop visibility, native tabs | Future positive unsupported-state evidence must exclude | Always unproven in the current generic probe |

Valid negative geometry origins are allowed. A zero-duration interval is valid. Malformed geometry, intervals, or sequences cannot be projected into a `WindowObservation`; otherwise projection preserves the unknown/ineligible assessment. Fixed report reason codes contain no application content.

Successful notification registration and before/after focus checks are sampled prerequisites, not proof against every intervening transition. Token checks, process lifetime, environment/activation generations, current trust, pause, freshness, and admission remain separate lifecycle gates. Neither an eligibility assessment nor user opt-in is a mutation permit. Future integration must recheck the applicable gates before a plan and each setter according to [control contracts](../control-contracts.md).

A future eligible scope must have an enforceable evidence provider tied to the window token and environment, with explicit invalidation and supported app/OS coverage. Application names, equal AX/CG bounds, or a user's declaration of “no tabs” cannot clear unknown requirements. Any narrower scope proposal must document its acquisition, expiry, unsupported transitions, and manual checks before enabling eligibility. The present API deliberately offers no Boolean “safe” override.

## Consequences and next task

M2.3 implements explainable blocking decisions and rejects malformed control records. It does not close the three remaining proof requirements or connect the control reducer to the app. Mutation stays disabled.

Follow-up source implemented in [M2.4](../m2-nested-dialogs.md): bounded read-only nested-dialog evidence on the existing dedicated worker, with a pure scan summary. The original acceptance requirements remain: Record positive sheets/dialogs and explicit incomplete, unsupported, cycle, depth/node-limit, and budget outcomes without reading contents. Tests must show positive findings exclude even in incomplete scans and incomplete scans never prove absence. A complete structural scan only describes the examined tree at that sample; it must not automatically clear tab/visibility requirements or claim lifecycle safety. Manual owned-fixture checks remain separate from unit verification.
