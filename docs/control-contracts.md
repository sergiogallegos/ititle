# Control contracts

Accepted design after review. The M1 adapter implements a read-only subset (dedicated AX threads, bounded admission, process-scoped tokens, destruction invalidation, explicit handle timeouts). See [implemented limits](m1-probe.md). M2.1 now implements the [pure control model and simulated admission](m2-control-model.md). The live coordinator, synchronized worker admission, and real write path remain proposed and unvalidated; simulation does not establish platform eligibility or write safety.

## State and identity

Coordinator states: `permissionRequired`, `paused`, `active`, `suspended(reason)`, `stopping`. Read-only discovery can run while paused after permission is granted. Only `active` admits mutation, including focus/raise actions. Enrollment is read-only and available while paused. Explicit Tile validates the selected set and activates it; failure leaves the manager paused. Resume revalidates rather than replays an old plan. Per-app failures can degrade one app without changing healthy app state.

| Value | Contract |
| --- | --- |
| AppToken | PID plus coordinator-issued process-lifetime generation; validate against current process registry |
| WindowToken | AppToken plus monotonic session-local serial; never persist/reuse as an OS window ID |
| EnvironmentEpoch | Advances on desktop/display changes, sleep/wake invalidation, or global trust loss |
| LayoutRevision | Advances when policy state changes; never inferred from AX notifications |
| Observation | Token, frame, capability/eligibility status, monotonic timestamp, epoch, worker sequence |
| FrameTarget | Token, desired rectangle, epoch, revision, admission generation |
| ApplyResult | Same identifiers, requested/observed frame, timing, typed outcome |

AX objects stay in the originating worker. Equality is only a process-lifetime correlation hint, not a permanent identity. Unsupported/missing attributes are `unknown`, not false. Unknown eligibility blocks enrollment. Window titles never serve as an identity key. A process restart always produces fresh tokens, even when its PID is reused.

## Boundaries and worker lifecycle

The coordinator actor contains no blocking IPC and does not await platform work while holding a partially updated transaction. Reduce one input to a new snapshot and effects; dispatch effects afterward. Replies re-enter as new inputs and are validated against current identifiers. Actor reentrancy is not a substitute for these checks.

Use one dedicated Thread with a CFRunLoop per currently probed/managed app, owning AX objects and observer callbacks. A blocked AX call can delay that worker's observations; all its data becomes stale accordingly. Do not create a separate worker for every notification. Retire idle workers and reconcile on reattachment. If a worker is stuck, quarantine its app and do not replace it with more stuck threads. A helper-process design is deferred unless measurements demonstrate thread isolation is insufficient.

A small lock-protected mailbox holds cancellation/admission state and bounded pending work independently of the worker run loop. Its lock is never held across AX calls. Each setter/action checks admission immediately before entering; the admission point defines whether a call was already in flight when pause occurred. This narrows but cannot eliminate external races with apps or Spaces changing after validation.

Configure AX messaging timeouts deliberately. The installed SDK documents that setting a timeout on one AX object does not affect other equal objects; use a deliberate process-wide baseline or configure each actual handle. Zero is a reset/default value, not an immediate-cancel mechanism. Tune deadlines from the probe, and treat timeout as an uncertain outcome requiring later observation, not proof that nothing changed.

Quit revokes admission immediately and does not wait indefinitely for worker teardown. The app must not restart itself or silently regain permission.

## Bounded event processing

- Keep user commands in order. Relative resize, focus, swap, and toggle are semantic operations; do not discard them as if they were absolute frames.
- Coalesce repeated observation invalidations by app/window. Duplicate move events can request one fresh observation.
- After ordered reduction, replace obsolete pending absolute frame targets per window with the latest target. Never overlap write sequences in one app.
- Proposed initial limits: 128 queued semantic commands, 256 tracked windows, one queued frame target per tracked window. Reject excess work with visible status; these limits are hypotheses to tune.
- Use a bounded mailbox with one scheduled drain, not a new unbounded Swift Task for every AX callback.
- On event-buffer overflow, mark affected observations dirty, suspend their writes, and reconcile. Creation/destruction uncertainty requires registry reconciliation.
- Pause/quit bypass ordinary command backlogs. Key-repeat for commands that cannot safely repeat is disabled in the binding table.

## Apply and recovery

For each target: validate identity, epoch, admission, fresh eligibility, and capabilities; diff against the latest frame; apply the required size/position sequence; then observe. Validate admission again between setters. A plan is not a transaction across windows or apps.

Only fresh results for the current environment may update observed state. A completion for an obsolete layout revision may still describe a physical change: mark dirty and reconcile, but never roll desired state back to that revision. Results for dead tokens/old epochs cannot revive windows.

Start with one write sequence and at most one corrective sequence per explicit tiling operation. Budget expiry or repeated mismatch yields `constrained`, `unavailable`, or `unknownOutcome`, suspends that window, and stops retries. Another explicit user action can try again after revalidation. AX errors and readback decide whether to continue; never blindly repeat focus/raise actions after a timeout.

If one app fails after other apps moved, retain successful placements and show partial completion. No automatic rollback: it adds more writes against potentially changed user state. Reconcile before the next command. Original-frame restoration, if added, is explicitly best-effort.

A matching expected frame with a short expiry can classify our own notifications. A nonmatching observed change must yield ownership to the user rather than reassert layout indefinitely. Manual-movement detection is imperfect; automatic mode cannot ship until drag/resize experiments pass.

## Layout policy before UI control

The prototype calculates rectangles only. Before M2, specify and test these operations:

- Insert the newly enrolled window beside the selected leaf; otherwise use enrollment order. Choose initial split axis from the container's longer dimension; preserve existing orientation afterward.
- Remove a leaf and collapse its now-single-child parent. Floating windows are outside the tree, with their last observed frame retained for the session only.
- Directional focus chooses eligible leaf centers in the requested half-plane, prioritizing perpendicular overlap, then directional distance, then stable enrollment order. No wrap by default. Confirm actual focus before reporting success.
- Swap exchanges leaf identities without changing geometry. Ratio resize changes the nearest applicable ancestor, bounded to a documented range.
- Reject nonfinite/unrepresentable geometry, excessively deep trees (proposed depth 32), zero usable area, and impossible minimum-size constraints before issuing writes.
- Apply outer gaps once, inner gaps at splits; compute the trailing child's boundary from the parent endpoint. Snap boundaries at the platform boundary using display scale, without introducing overlap or cumulative drift.

Unknown minimum sizes require readback; impossible layouts suspend affected management rather than shrink windows endlessly. Constraint solving and rounding are not implemented in the existing solver.

## Keyboard and configuration

The proposed example declares `physical-us`: letter names refer to physical US-layout key positions, not Unicode characters. Display that choice to users; layout-aware text bindings are deferred. Normalize modifier order, reject unknown key names/commands and duplicate normalized chords. Control+Shift is an opt-in example, not a universally conflict-free default.

A callback consumes a chord only when its command is admitted. Track a consumed key-down through its repeat/key-up lifecycle to avoid delivering unmatched events to applications; reset carefully on tap loss or permission changes. Failed admission passes the chord through. Secure input and system-reserved shortcuts can defeat interception; keep menu access to all essential actions. Do not synthesize typing to bypass those restrictions.

Configuration reload is atomic: decode and validate first, then publish a new immutable binding/config snapshot. Malformed reload leaves the old configuration active. Startup is always paused. File size and array counts are bounded; object-member duplicate rejection is not assumed from JSONDecoder.
