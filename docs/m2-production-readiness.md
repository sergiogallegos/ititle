# M2.17 — Production boundary review

Status: documentation/source audit complete; production integration remains proposed. Reviewed 2026-10-09 against the local M2.14–M2.16 source and the last recorded 170-test verification. No real setter experiment was performed.

## Decision

Accept the internal complete-plan simulation as evidence for its bounded protocol, not as production window-control acceptance. Retain [ADR 0004's empty mutation scope](decisions/0004-supported-scope.md). No eligible production branch, live setter dispatcher, or enrollment UI is authorized by this review.

The follow-up source task, now implemented in [M2.18](m2-counter-exhaustion.md), is lifecycle-counter exhaustion hardening in the existing read-only path and pure control model. Audit token, request, registry, observation, activation, epoch, revision, and admission issuers; use checked advancement with conservative terminal rejection rather than wrapping or resetting identity. Exercise exhaustion through value-level tests without long loops or AX calls. This is useful independently of an eligibility provider and does not change supported scope.

## Accepted evidence and remaining work

| Boundary | Implemented evidence | Required before production control |
| --- | --- | --- |
| Ordered commands and bounded plans | FIFO 128; complete plan 256 windows; same-app cursor 64; whole-command validation followed by per-app execution isolation | Production semantic input, visible capacity rejection, explicit management opt-in |
| Admission and cancellation | Synchronized fake gate; separate size/position permits; priority safety ingress bypasses FIFO | Production safety ingress and handle resolution wired to the same admission authority |
| Owner/reply protocol | Exact operation binding, reserve/reduce/mirror/ack, shared bounded drain, quarantine, retained retiring routes | Production composition and teardown review; preserve read-only reply behavior |
| Physical isolation | Dedicated fake threads; stalled-peer checks; active plus unfinished-retired worker cap 16 | AX integration, measured timeouts, observed teardown/resource acceptance |
| Completion | Actual fake readback; exact cursor advancement only after accepted completion | Fresh identity-bound AX readback and constrained-geometry policy |
| Eligibility | Production exclusions and explicit unknown reasons | Reviewed provider covering desktop visibility, native tabs, and nested dialogs |
| Timing and geometry | Deterministic logical-time interleavings and synthetic geometry | Measured freshness policy, tolerance, ordering, minimum-size failures, mixed-display checks |

See [delivery](m2-shared-simulation-delivery.md), [fake workers/readback](m2-fake-worker-readback.md), and [same-app plans](m2-same-app-plans.md) for precise test scope. The 0.5-second model age limit and fake size-first sequence are simulation assumptions. Passing tests do not calibrate live freshness, IPC latency, or geometry constraints.

## Production source findings

- [WindowEligibilityAssessment](../Sources/ITileCore/WindowEligibility.swift) returns only unknown or ineligible. It always retains current-desktop visibility, native-tab safety, and nested-dialog safety as unproven. A complete negative structural scan and a single CG bounds candidate cannot clear these requirements.
- [ReadOnlyPreview](../Sources/ITileCore/ReadOnlyPreview.swift) rejects unexpected preparation, perform, or readback effects. [The app](../Sources/ITileApp/main.swift) supplies request/context checks and explicit registry replacements; it does not instantiate the internal simulated gate, delivery, or worker runtime.
- [WindowProbe](../Sources/ITilePlatform/WindowProbe.swift) owns AX objects and observer processing on dedicated threads. Bounded run-loop draining and identity retirement protect explicit read results; delayed notifications during blocked IPC remain a separate live-admission concern. The current reader is not a continuous mutation safety ingress.
- At review time, issuers still included unchecked increments, including app activation revision, worker registry revision and focus notifications, and model layout revision. Checked simulation ticket/operation counters alone did not establish end-to-end exhaustion handling; M2.18 subsequently hardens these production issuers.
- No AX setter/action implementation is present in the production source. Reusing a fake backend protocol or injecting synthetic eligible observations would bypass the reviewed boundary.

These are repository findings, not a claim that all public-API provider strategies are impossible. The [supported-scope decision](decisions/0004-supported-scope.md) records the reviewed candidates and requirements for a narrower proposal.

## Proposed adapter contract

A future adapter proposal must satisfy these requirements before live wiring:

1. **Evidence provenance:** immutable value evidence must identify its provider, supported coverage, process-lifetime app token, window token, environment epoch, acquisition interval, sequence, and expiry policy. Positive exclusions and unsupported/incomplete outcomes survive projection. No user assertion, app name, or externally supplied eligibility Boolean replaces missing proof.
2. **Single ownership:** the serialized owner reduces complete commands and publishes immutable authorization. Dedicated workers alone resolve and use AX objects. Evidence and receipts cross the boundary as values; no IPC occurs under a transport/gate lock or on the main/cooperative executor.
3. **Revocation:** observed Pause, Disable, Quit, trust loss, environment changes, process retirement, destruction, and uncertainty close admission before owner scheduling. Define handling for delayed/missing notifications and the residual race after the last sampled check. Already admitted IPC may finish; no subsequent setter inherits its permit.
4. **Exact completion:** one operation per app remains occupied through readback and exact owner acknowledgment. Validate identity, epoch, revision, timing, and registry membership. Obsolete or uncertain results cannot advance a cursor or revive a retired token. Successful peers retain their placements; no implicit rollback or retry.
5. **Finite resources and identity:** count unfinished retired physical workers, retain bounded cleanup routes, reject overload visibly, and check every issuer for exhaustion. Document the lock order and scheduler requirement to enqueue rather than invoke inline. Retained payload limits do not bound all transient backend/system allocations.
6. **User control:** startup/enablement must require explicit management opt-in with accessible Disable/Pause/Quit. Manual dragging or resizing yields ownership until explicit re-tile. Production control must not silently resume from read-only inspection permission or stale evidence.

This specifies review obligations, not an implemented provider schema or live adapter. Keyboard input, management UI, mouse coexistence, and native desktop-number discovery remain [planned product work](design.md). A desktop-change count is not a native desktop identifier.

## Acceptance before widening scope

First review a concrete public-API provider proposal against ADR 0004; implement read-only provenance and rejection checks for that provider before considering an eligible projection. Require deterministic stale/unsupported/expiry and transition tests, then separate scoped real observations. A provider must cover all retained requirements together for the declared scope.

Any later disposable real-setter experiment needs its own explicit opt-in, named fixture/application, bounded actions, and stop conditions. Record OS build, app versions, signing/permission state, actual display topology and scale, timing, requested/observed geometry, and residual uncertainty. Include equal-frame cross-desktop peers, tabs/sheets, permission loss, Pause between setters, blocked calls, process replacement, and constrained readback. Historical checks reporting one display do not validate the user's closed-laptop/two-monitor setup.

M2.17 changes documentation only. The last source verification remains 170 passing tests; this review adds no manual acceptance or performance result.
