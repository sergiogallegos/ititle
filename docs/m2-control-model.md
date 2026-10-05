# M2.1 — Pure control model and simulated admission

Implemented in `Sources/ITileCore/ControlModel.swift`; exercised by `Tests/ITileCoreTests/ControlModelTests.swift`. The diagnostic app is still read-only. No app UI, AX worker, or event callback is connected to this model, and no effect performs an actual window operation.

## Implemented behavior

`ControlModel.reduce(event, at:)` synchronously changes value state and returns explicit effects. It owns no AppKit/AX objects, threads, locks, tasks, or clock source. The caller supplies monotonic time and serializes events. A future coordinator may host this reducer, but the actor and atomic worker admission mailbox are not implemented here.

| Record | Meaning |
| --- | --- |
| `WindowObservation` | Session token, frame, eligible/ineligible/unknown status, independent supported/unsupported/unknown frame capabilities, environment epoch, worker sequence, sample time |
| `FrameTarget` | Desired frame, token, environment epoch, layout revision, admission generation, source observation sequence, plan time |
| `SetterPermit` | Target, simulated size/position step, admission time |
| `ApplyResult` | Target, optional readback observation, whole-operation start/end times, succeeded/unavailable/unknown outcome |

Environment epoch, layout revision, and admission generation are independent. Environment changes and trust loss invalidate observations and enrollment intent; an accepted explicit plan advances layout revision. Pause, resume, quit, failed plan validation, and global invalidation revoke admission and clear pending targets. Desired geometry is never rolled backward by a completion.

The model starts permission-required; granting permission leaves it paused. A complete explicit `tile` plan activates only when every selected window has fresh, current, eligible evidence and both frame capabilities are known supported. An invalid plan leaves control paused without partially replacing desired geometry. `resume` leaves it paused, invalidates old evidence, and requests reconciliation; fresh observations and another explicit Tile are required. The current M1 app's Pause inspections menu remains a separate feature.

Dispatch selects the lowest pending window serial for an app and returns `prepare`. A simulated worker requests admission independently for size and position. Each request validates state, token, epoch, revision, admission generation, source observation sequence, freshness, and eligibility. A permit is the simulation's admission point. Tests can hold it indefinitely, deliver a pause or overflow, then finish the already-admitted call. No subsequent setter is admitted after invalidation.

One sequence may occupy each app's slot. Executing calls and readbacks retain that slot across pause/environment invalidation until acknowledged; the model does not pretend to cancel IPC or create replacement workers. Other apps have independent slots. Quit is terminal and returns without waiting for an occupied slot. Pause, quit, and trust loss bypass timestamp validation as well as ordinary work. Invalid timing cannot prevent these safety controls.

Readback must follow the last simulated setter, carry newer worker evidence, match the current target exactly, and have ordered timestamps. Unknown outcome, unavailable result, mismatching geometry, or obsolete work marks the app's windows dirty, drops its pending targets, and requests reconciliation. It never retries automatically or rolls back successful geometry. An obsolete-revision result is not installed as a current observation; its possible physical effect is represented by dirty state. Exact equality and the fixed size-then-position order are simulation choices, not the future platform's tolerance or ordering policy.

## Bounds and input contracts

- Defaults are 256 live window records and 16 attached apps, configurable at initialization. There is at most one pending absolute target per live window and one in-flight sequence per attached app. Repeated complete plans replace pending absolute targets. There is no semantic command queue in this task.
- Overflow is an explicit event from a future bounded event adapter. It invalidates the affected app's observations and pending work without stopping healthy apps. Excess window observations are rejected without growing storage; excess plans pause and revoke admission.
- Process generations come from one monotonically increasing issuer. New attachments must arrive in generation order; stale attachment and termination callbacks cannot replace/remove a newer registered process. A higher generation for the same PID represents confirmed process replacement, not permission to replace a merely stalled worker.
- New window tokens must be introduced in increasing serial order per attachment. Existing windows can be observed in any order. A per-app serial high-water mark prevents retired tokens from returning without retaining an unbounded tombstone set. Destruction before first observation also retires the serial. A future adapter must register/introduce tokens in this order or supply a revised bounded registry protocol; it must not feed arbitrary AX enumeration order directly into this interface.
- Worker sequence increases per accepted observation record, including readback, within the attachment lifetime. Samples use the same monotonic time domain as events. Times cannot regress or precede attachment/invalidation, exceed delivery time, or exceed the configurable freshness age (default 0.5 seconds, a simulation assumption only). Observations arriving while that app has an occupied sequence are rejected; reconcile after it acknowledges completion.
- Eligibility is asserted by synthetic inputs, not inferred from role/settable/modal flags. A future adapter must establish the focused-window, identity, visibility, and dialog contract before supplying `eligible`. Unknown evidence blocks plans and admission. The M1 probe does not currently produce that proof or these records.

## Verification and remaining work

The deterministic fake-worker scenarios cover startup, unknown evidence, stale/invalid observations, atomic plan rejection, pause before dispatch and between setters, already-admitted call completion, resume revalidation, environment/trust loss, obsolete revisions, pending-target coalescing, overflow with a stalled/healthy app pair, bounded storage, window destruction, PID reuse, duplicate callbacks, readback timing/mismatch, and terminal quit.

These tests verify state transitions and simulated linearization. They do not verify thread synchronization, AX setters, real application constraints, focus capture, physical geometry, or the impossibility of external races. The real worker must eventually check a lock-protected admission mailbox immediately before each call; delivering a reducer effect alone is insufficient for live control.

Follow-up: **[M2.2 focused read-only observation and revalidation](m2-focused-probe.md) is implemented with partial manual acceptance, including focus-loss rejection, permission recovery, and desktop invalidation; mid-read permission loss and focused physical display changes remain open.** The original platform task was: Add structured platform evidence for an explicitly selected frontmost/focused standard window; test focus changes caused by iTile UI, loss of focus, sheets, token invalidation, and environment changes. Preserve unknown eligibility where proof is missing. Keep mutation disabled. Real write integration additionally requires the geometry, bounded-application, and supported-scope gates in the [M1 readiness review](m1-readiness.md).
