# M2.21 — Historical provenance in focused reports

Status: production source wired and automated checks passed; [M2.22](m2-native-provenance-acceptance.md) records scoped native inspection/blocked preview and same-handler acceptance; remaining native/recovery coverage is partial. Production remains read-only with an empty mutation scope.

## Implemented behavior

The existing focused inspection, historical-token revalidation, and blocked-preview reply path now appends a fixed provenance section to a received observation. It identifies the three requirement sources, schema revisions, coverage, sampling outcomes/issues, enclosing acquisition interval, and captured owner request/activation/revocation context. Freshness is explicitly `unmeasured` because no diagnostic age policy has been selected. Invalid timing produces `invalid` freshness rather than an unmeasured label.

[FocusedDiagnosticReport.swift](../Sources/ITileCore/FocusedDiagnosticReport.swift) implements pure historical formatting and receipt consumption. It returns no current observation or control permit. The report says whether the historical sample passed metadata/context checks and lists rejection codes. That acceptance is not eligible window control. Positive exclusions and all unproven requirements remain in the original focused report and assessment.

Each existing app attachment holds one `FocusedDiagnosticState` with the latest accepted worker sequence. This is a scalar watermark for the existing worker issuer, not a new issuer or stored-envelope cache. Consumption uses that watermark rather than trusting a caller-supplied baseline. Accepted newer incomplete evidence advances it; rejected evidence does not. The app removes the state with its process attachment, and a retired route cannot advance a replacement process's watermark. Existing worker, registry, and reply resource bounds remain unchanged.

[The app](../Sources/ITileApp/main.swift) captures `EvidenceUseContext` after request replacement revokes the preview and before enqueueing the focused read. The revocation value comes from [ReadOnlyPreview](../Sources/ITileCore/ReadOnlyPreview.swift)'s existing model admission generation. No parallel generation is issued. Counter exhaustion is checked before enqueueing.

At owner consumption, the existing exact receipt route, request, process lifetime/frontmost, environment, activation, trust, pause, and registry checks still apply. The provenance assessment receives only an accepted registry replacement and the current owner-use context. A metadata/context-rejected sample remains historical in the report but cannot become a historical revalidation candidate or enter the blocked-preview calculation. Existing early stale-delivery guards still discard results before report presentation.

Accepted provenance does not update the model's control observations: the existing blocked preview separately projects the same raw focused sample through its original checks and simulation-age rule. Formatting introduces no age default, timer, polling, AX read, setter, focus action, raw-content logging, or stronger eligibility. The report's acquisition time remains the original request start/end; opening/copying it cannot refresh evidence. The lab-only targeted backend driver and application-wide reports do not acquire foreground provenance through this path.

## Automated acceptance

`scripts/format` and `scripts/verify` passed 195 tests (130 core, 65 platform), including app compilation, formatting, metadata lint, shell syntax, and lab script typecheck. Seven new tests cover:

- Fixed historical source/coverage/interval/context output, unmeasured freshness, retained unknown requirements, and absent current observation.
- Exact duplicate rejection, authoritative scalar watermark despite a caller baseline, newer incomplete findings, and rejection of older evidence.
- Request/activation/revocation/environment/permission/pause/stop/registry rejection without consuming the sequence; resume cannot revive an old context.
- Retired-route isolation from a replacement process with the same PID and a fresh worker sequence.
- Composition with the real pure preview boundary: capture its generation, accept historical provenance, retain `planRejected/invalidPlan`, and reject the original context after preview revocation.
- Malformed/future samples, invalid freshness labeling, and no watermark advance.
- Content-free formatting, unchanged acquisition times, and no invented expiry for a historical sample.

The build emitted the three existing captured-variable warnings in `SimulatedDeliveryTests`; no new provenance/report warning was emitted. These tests do not exercise the native menu, frontmost event ordering, effective rebuilt bundle permission, or real multi-monitor behavior.

## Next: scoped manual report acceptance

Use the rebuilt app only after source checks, recording effective signing/permission state and exact OS/app/display context. The previous installed bundle has not been replaced by this task. Keep the user's closed-laptop/two-monitor description distinct from the actual displayed count/scales in each report.

1. Perform focused inspection from an ordinary disposable source window through the native menu. Confirm the original evidence plus all three provenance rows, enclosing timing, captured counters, and unmeasured freshness. Record unknown/ineligible status and no source-window movement.
2. Revalidate the historical token, then request the read-only preview. Confirm a fresh sample and blocked plan; no eligible scope or setter is introduced. Opening the report may change focus, so return to the source before each request.
3. Exercise Pause and fresh Resume plus an observed stale-context rejection using the existing scoped fixture/handler procedure. Confirm prior evidence is not revived and new accepted reports carry a new request/context. Desktop and permission transitions remain separately scoped checks; authentication, if needed, stays with the user.
4. Record native delivery separately from targeted backend/lab output. Keep actual results and remaining uncertainty in validation rather than marking the manual gate complete from compilation or tests.

No new manual, timing, topology, or mutation acceptance is claimed by M2.21. [ADR 0004](decisions/0004-supported-scope.md) still applies.

The follow-up [M2.22 audit](m2-native-provenance-acceptance.md) now records actual results, timed-capture limitations, and the unresolved owned-fixture reactivation case.
