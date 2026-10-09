# M2.28 — Fixture lifecycle and expiry contract

Status: contract specified; [M2.29](m2-fixture-lifecycle-assessment.md) implements the source/value subset with scoped owned transition checks. [M2.30](m2-fixture-host-invalidation.md) adds laboratory host event wiring and scoped activation/exit recovery; remaining native event acceptance is separate. This contract extends the [M2.26 snapshots](m2-fixture-safety-snapshot.md) and [M2.27 identity experiment](m2-fixture-ax-identity.md) for read-only laboratory assessment. Production mutation scope remains empty under [ADR 0004](decisions/0004-supported-scope.md).

## Decision and existing gap

An explicit fixture run/window identifier supplies sampled own-object mapping. It does not establish continued visibility, tab/dialog safety, or permission to act later. Schema 1 has request/sequence and an enclosing interval but no source-state revision, live-window registry, or invalidation authority. It remains a historical diagnostic protocol. Do not retrofit a lifetime guarantee onto the recorded successful pairs.

Select a schema-2 **read-only lifecycle assessment**, with checked source revisions and exact host context. No eligibility projection, lease, action dispatcher, or setter is part of this contract. Initially report freshness as unmeasured; no measured age policy has been selected. The existing 30-second lab watchdog, five-second event wait, 0.2-second AX timeout, and 0.5-second simulation age are not evidence-lifetime policies.

## Proposed source schema and ownership

Retain schema 1's fixed fields and add the following in schema 2; schema-1 consumers must reject schema 2 rather than silently ignore fields. The fixture and new consumer upgrade together.

| Field | Authority and meaning |
| --- | --- |
| `stateRevision` | Fixture-main-thread checked counter, initially 1; advances before covered transition intents and when relevant delivered notifications/state differences are observed |
| `registryRevision` | Checked counter, initially 1; advances on owned-window creation/retirement or registry uncertainty |
| `liveSerials` | Canonical sorted unique list of at most eight current owned window serials; explicit unavailable status on overflow/uncertainty |
| `originalLive` | Whether serial 1 remains in that registry; unavailable stays explicit |
| `lifecycleCoverage` | Closed vocabulary: `controlledFixtureTransitions`, `observedEventsOnly`, or `unavailable`; never continuous/global safety coverage |
| `uncertainty` | Fixed reason code: `none`, `unsupportedScenario`, `unavailableState`, `registryLimit`, `notificationFailure`, or `counterExhausted` |

The same fixture run UUID owns these counters, serials, and snapshots. The snapshot sequence orders replies; it is not a state revision. A stable diagnostic read must not advance `stateRevision` merely because another snapshot was requested. A rejected reply cannot lower any watermark.

Registry membership comes from fixture-owned window creation/retirement bookkeeping, not `AXWindows` enumeration. An inactive native tab may remain live while absent from that AX list, as observed in M2.27. Remove a serial before an explicit close is attempted and on a delivered close notification; uncertainty about completion cannot revive it. A retired identity never becomes live again. Recreating a peer/tab/sheet must allocate a new serial, even for a retained object. Retirement of original serial 1 requires restarting the fixture with a new run before original-window assessment can recover. Do not reuse a retired serial, CG number, or PID as identity.

Retain only the bounded live registry and counter watermarks. Historical membership is never accepted by default, so an unbounded tombstone set is unnecessary. Reject unknown/absent identities, excessive live windows, and unavailable registries. Registry publication must be a whole main-thread snapshot; do not merge fragments from different revisions.

## Covered transitions and conservative invalidation

For each accepted fixture command that can change window, tab, sheet, focus, visibility, geometry, synthetic structure, or fault state, advance the source state revision **before** executing its intent. Failed/no-op intents may conservatively advance it. Creation/close intents additionally update registry authority before publishing their acknowledgments. A tab or sheet that opens and closes between samples must leave a different revision even if the final fields equal the initial fields.

Accessor faults also advance revision before their own hide/stall/structure transition begins. Snapshot reads must inspect fault flags without executing those accessors. Arming and consuming a fault are different transitions. A known armed fault or synthetic scenario outside the assessed coverage prevents a lifecycle-consistent assessment; it remains useful diagnostic evidence.

Relevant delivered own-window/app notifications and workspace/display/sleep observations invalidate source state. Delivered callbacks are observations, not proof that every intervening transition was reported. Sampled own-state differences can catch an additional missed change and advance revision before returning the new record, but cannot detect an unobserved change followed by reversal. `observedEventsOnly` must preserve that limit. No callback registration, equal revisions, or equal before/after flags can create continuous lifecycle coverage.

The laboratory host separately owns a checked context containing the fixture run, expected window identity, environment epoch, activation revision, revocation generation, trust, paused/stopped status, and pending request identity. It does not copy numeric values from production model counters or let the fixture assert host trust/consent. Host context changes invalidate pending pairs immediately when observed, independently of source replies.

| Trigger | Required host/source result |
| --- | --- |
| Pause, disable, stop, or permission loss | Revoke pending pair use; late completion stays historical; resume/restored trust requires a new request/context |
| Observed activation, Space/display, sleep/wake change | Advance the relevant host context and invalidate pending/current assessment; no automatic reuse |
| Fixture exit, replaced process/run, original retirement | Drop current assessment and reject its identities; a new process gets a fresh attachment/run |
| Covered tab/sheet/window/fault transition | Advance source authority before intent; pre-transition pair cannot match the new revision |
| Unsupported/malformed/uncertain state, overflow, missing reply | Incomplete assessment, never inferred absence or safe coverage |
| Checked counter exhaustion | Terminal closure for that authority; preserve cleanup of existing owned work; no reset or wrapping |

The fixture cannot intercept every external client or freeze macOS environment changes. A missed/delayed notification is a residual uncertainty, not a lease extension. No source revision is presented as an atomic global event stream.

## Paired assessment and expiry

A pair comprises one fresh before-snapshot, one bounded AX read, and one fresh after-snapshot under one host use context. The AX values carry parsed fixture identities and their own enclosing interval. Retain at most one pending pair and one current diagnostic assessment; each accepted new pair replaces the prior current assessment, including when its result is incomplete. Never keep an older favorable sample as a fallback.

Assessment requires all of the following before calling a pair **consistent in its declared diagnostic coverage**:

1. Exact run/window identity and pending request binding; strictly newer snapshot sequences; canonical schema/fields and finite ordered intervals.
2. Before-snapshot end no later than AX start; AX end no later than after-snapshot start; no sample from the future relative to receipt. This ordering is an interval check, not atomicity.
3. Equal before/after source state and registry revisions; expected serial live in both complete registries; fixed relevant state fields agree. Matching revisions alone do not excuse changed fields.
4. Exact unchanged host use context at consumption; effective current trust, unpaused/unstopped owner, and no known source uncertainty, excluded state, armed fault, or unsupported coverage.

Wrong-run/window, stale/context-revoked, source-changed, retired, malformed, incomplete, and unsupported outcomes remain distinct fixed rejection codes. Their diagnostics retain original source attribution. They never become an eligible production observation.

There is **no default age policy**. Without an explicitly supplied laboratory policy, freshness is `unmeasured`; a consistent pair can be accepted as historical diagnostics only. A synthetic age policy can exercise parser/value tests but cannot calibrate control freshness.

If a diagnostic policy is later supplied, require finite positive maximum age and positive policy revision. Measure age from the **earliest before-snapshot start**, not after-snapshot completion. Validate finite advancing expiry arithmetic; `now >= expiresAt` is expired, including the exact boundary. Wrong policy revision, time regression/future samples, invalid intervals, overflow/nonadvancing expiry, and revocation reject current use. An unexpired sample is still a diagnostic sample, not a permit. Changing policy or returning from Pause cannot revive an old pair.

## Specified next implementation task

Implement schema-2 source revision/registry values and a Foundation-only pair/context/expiry reducer in `ITileFixtureDiagnostics`, with no production imports. Wire covered fixture intents and own observations to checked issuance; retain schema-1 behavior only as explicitly historical if needed. Make unsupported/missing coverage visible instead of inventing a safe branch.

Deterministic acceptance must exercise open/close reversal between samples; equal revisions with changed fields; retirement/recreation without serial reuse; inactive-tab omission from AX enumeration; stale/wrong-run/request/host context; Pause/resume and permission/environment revocation; newer incomplete replacement; unknown registry/coverage; exact expiry and invalid arithmetic; and exhaustion with cleanup retained. No wall-clock sleeps or AX objects belong in reducer tests.

Separate read-only fixture checks must capture source revisions around native tab/sheet changes, retire/recreate a peer with a new identity, and verify armed faults survive snapshots. Add controlled transitions inside a pair and require rejection even when final visible state returns to baseline. Workspace/process/permission tests remain separately scoped and need actual recorded events before claiming acceptance. Run `scripts/format` and `scripts/verify` after source edits.

This work precedes any fixture-only setter proposal. Such a proposal still needs exact supported scope, a measured freshness policy, synchronized per-call admission, residual-race analysis, readback/constraint handling, accessible pause/quit, and explicit consent for bounded disposable mutations. No contract here grants that consent or reopens production eligibility.

## Validation scope

Documentation/source review only. No source behavior, app bundle, permission, window, desktop/display, or keyboard action changed. Local Markdown links and whitespace checks validate the contract. Source tests were not rerun; latest source verification is M2.27's 202 tests plus the recovery parser check. No new manual platform result or calibrated timing claim is made.
