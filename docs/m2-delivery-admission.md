# M2.10 — Bounded reply delivery and control admission

Status: accepted implementation contract. Its read-only receipt/delivery subset is now implemented and scoped in [M2.11](m2-read-only-delivery.md); semantic command buffering and live write admission remain unimplemented. This task specifies the next boundary after [M2.9](m2-registry-lifecycle.md). The app remains read-only, and production mutation scope remains empty. The following limits and transitions are requirements for future source, not claims about today's worker.

## Existing gap and decision

At the M2.10 review, `WindowProbe` limited each application to one outstanding backend request, but cleared `busy` before invoking its completion. App callbacks then scheduled main-actor tasks. Backend completion therefore does not prove owner consumption, and neither the pending request bound nor registry replacement bounds the lifetime of unconsumed replies. `ControlModel` tests simulate setter admission; they do not synchronize a real worker against pause or other revocations.

Retain one application operation slot through owner acknowledgment, carry result and registry in one immutable envelope, and use one shared scheduled owner drain. Keep a synchronous revocation gate separate from the owner's ordinary semantic queue. Implement and verify the read-only delivery portion first. Setter/action admission stays a proposed extension until eligibility and separate opt-in gates are met.

## Values and ownership

| Value | Required meaning |
| --- | --- |
| Operation ID | Current `AppToken` plus a monotonically increasing per-attachment request serial; distinguishes work even if target geometry repeats |
| Receipt ID | Operation ID plus a monotonically increasing per-operation reply serial; distinguishes intermediate setter replies from terminal replies |
| Reply envelope | Receipt ID, request environment/context, typed result, bounded registry replacement when applicable, and ordered monotonic timings |
| Revocation stamp | Global gate generation plus per-app generation; separate from environment epoch, layout revision, request ID, and registry revision |
| Admission record | Operation/step identity, token, target, environment epoch, layout/admission revisions, observation sequence, eligibility/capabilities, evidence deadline, and the expected revocation stamp |

Only immutable Swift values cross boundaries. AX handles, observer references, run-loop ownership, and handle correlation remain on the dedicated worker. Layout and lifecycle reduction remain pure core logic serialized by their owner. The synchronized transport owns slots and routing, not layout policy. It must not infer eligibility from role, bounds, or structural absence.

The owner runs bounded synchronous reductions without awaiting AX or leaving a partly committed model transaction. Gate/slot locks protect only bounded value updates; no AX call, callback, task submission, teardown, logging, or model reduction occurs under them. Use one consistent gate lock for admission and revocation ordering; avoid nested gate/owner/worker locks. A notification can close the gate without waiting for the worker run loop. Finite lock hold time is a design obligation to test, not a hard latency guarantee.

## Storage and overload bounds

| Storage | Initial bound and excess behavior |
| --- | --- |
| Attached application slots | 16 physical workers total, including retiring/quarantined workers; reject additional attachments visibly; never replace a stalled worker to make room |
| Operation slot per app | One, including an unread or owner-reserved reply; new read requests return busy until acknowledgment |
| Reply slot per app | One envelope; never overwrite a receipt that has not been acknowledged |
| Scheduled owner drain | One logical drain chain: at most one running pass and one queued successor; no task per callback |
| Semantic command queue | 128 ordered commands; reject excess commands explicitly, with hotkey admission passing excess input through |
| Coalesced invalidation state | Fixed reason flags and one dirty generation per attached app, plus global reasons; no notification-sized queue |
| Registry/model records | Existing 64 tokens per worker, 256 tracked tokens across the model, 16 apps |
| Pending absolute targets | At most one per tracked window; replacement only after ordered command reduction |
| Retained diagnostic report text | Proposed 64 KiB UTF-8 per reply, with bounded construction and a visible truncation marker |

The report text cap is a proposed transport limit, not an existing report guarantee. Structural evidence and registry sets are validated separately; never truncate a registry and call it complete. An oversize or malformed evidence payload produces a typed failure and suspends the affected app's control. The bounds limit retained transport values, not system AX/CG allocations or allocator overhead.

If a worker unexpectedly publishes a second reply into an occupied slot, retain the first receipt, latch a protocol failure, close that app's gate, and quarantine further work. Report the failure through fixed status flags, not another overflowing reply queue. Queue rejection never silently drops or coalesces a relative resize, swap, toggle, or focus command. Counter exhaustion is terminal for the affected transport scope: close admission and report failure; do not wrap IDs or restart a worker to bypass the condition.

## Read-only operation and acknowledgment

| Slot state | Permitted transition |
| --- | --- |
| Idle | Explicit request admission reserves its ID and moves to queued; otherwise return busy/stopped |
| Queued | Worker takes the matching request and moves to executing; revocation may cancel before backend entry |
| Executing | Backend produces exactly one bounded result, including failure, then publishes a receipt and moves to awaiting acknowledgment |
| Awaiting acknowledgment | Owner reserves the receipt, reduces or discards it, then acknowledges that exact ID; slot remains occupied throughout |
| Idle after acknowledgment | A subsequent explicit read may be admitted if inspection remains permitted; acknowledgment itself starts no read |
| Stopped/quarantined | Reject new work; late callbacks and duplicate acknowledgments cannot reopen the slot |

Reserving a reply for owner reduction does not free its slot. Retain its receipt identity until acknowledgment even if its payload has moved into a local owner value. Therefore at most 16 replies can be retained or under owner reduction across the transport, and no second request is admitted merely because one backend finished. A duplicate, unknown, older-process, or wrong-receipt acknowledgment is a no-op plus fixed diagnostic status; it must not release current work.

On owner consumption: first confirm attachment and receipt identity, validate the envelope, synchronize a current M2.9 registry replacement, then decide whether request context and evidence permit presentation/projection. Superseded UI results may still retire registry records if attachment, epoch, revision, and watermark checks pass. Malformed or obsolete registry values never revive tokens. Both accepted and discarded replies receive a terminal disposition and acknowledgment; rejection is not a reason to leak the application slot.

A queued request canceled before backend entry produces a typed canceled receipt on worker take, without performing AX work, and follows the same acknowledgment path. Terminal Stop instead records a stopped disposition without requiring owner progress. Pause, trust loss, environment changes, and request replacement may invalidate a reply while it waits. Do not cancel an executing synchronous call by pretending it finished. Once it returns, discard its obsolete presentation/control evidence and acknowledge its actual receipt. Registry retirement still follows current-epoch validation. Resume or re-enable requires a fresh explicit request, not replay of the retained envelope.

## Shared drain and lost-wakeup prevention

All passes execute on the same serialized owner without suspension during reduction, so a queued successor cannot overlap its predecessor. A producer deposits its envelope or latches dirty/safety state under the transport lock. If no drain is queued or running, it sets the scheduled flag there and posts one wakeup after releasing the lock. Other producers only update bounded slots/flags. Task creation is a wakeup mechanism, not the event buffer.

The owner prioritizes terminal/revocation flags, then consumes up to eight reply envelopes per pass using a rotating app cursor. It reduces bounded semantic commands in FIFO order only after reconciling the current safety generation. Use a maximum of eight semantic commands per pass; a command's input size must also be bounded. These batch limits are initial fairness choices, not performance results.

At pass completion, inspect pending state and update the scheduled flag under the same lock used by producers. Keep the flag set and post one continuation if work remains; otherwise clear it. A producer racing with this final check either contributes to that continuation or schedules the next drain. Never clear the flag before checking state, and never clear an acknowledged receipt by just app index: compare its full ID. A scheduled closure whose transport is stopped performs only terminal cleanup and cannot reopen admission.

## Safety controls and ordering

Pause, management Disable, Quit, effective trust loss, environment invalidation, observed identity destruction/uncertainty, and user ownership loss close the applicable gate synchronously at their ingress. They bypass the 128-command queue. Global changes advance the global stamp; app-specific uncertainty advances that app's stamp. Repeated signals can coalesce reasons, but must prevent an older owner publication from becoming current. Unknown routing closes the global gate rather than silently losing the signal.

Model delivery of these signals may happen later through fixed priority state. Before publishing any active admission records, the owner must consume that priority state and compare the publication's expected stamp against the gate under the lock. Publication fails if a newer revocation occurred. Neither reducing an old Tile command nor acknowledging a reply can erase a newer disable/pause latch. A delayed Enable/Resume command cannot reopen after a newer Disable/Pause; reject it as superseded. Quit is terminal.

Commands admitted before revocation keep their ordered semantic disposition, but older control intent is rejected rather than executed after recovery. Commands arriving while disabled must not create deferred writes. Re-enabling leaves management paused, clears obsolete intent, and requires fresh evidence plus explicit Tile. The requested running enable/disable management switch is planned; today's separate inspection Pause/Resume menu does not implement this control contract.

A gate closes only when a signal is observed. No transport lock proves that macOS, another app, or the user cannot change state between validation and a call. Idle observer coverage, permission detection, desktop/display membership, and mouse drag/resize coexistence require their own platform evidence.

## Future setter/action admission

No live setter or focus/raise handler is authorized by this design. For a later opted-in implementation, reserve one operation per application for its whole write sequence, including intermediate owner replies and final acknowledgment. The reply slot is reused only after each matching step receipt is acknowledged; it never permits an unrelated second operation.

For each step, the worker first resolves the current AX handle and performs any blocking platform validation on its dedicated thread. Then it enters the gate briefly, compares the full operation/step, current process and token registration, target revisions, permission/management state, revocation stamp, capability/eligibility values, and evidence deadline, and records the permit atomically. Release the lock before entering AX. This permit is the internal admission point. If revocation wins the lock first, no permit is issued. If admission wins first, that one call may still begin or complete after Pause; no cancellation, cross-process atomicity, or rollback is promised.

A permit cannot be copied to authorize another step. Size completion is a distinct receipt; the owner validates and reduces it before proposing position, and position must obtain a new permit. Final readback and terminal delivery retain the operation slot until owner acknowledgment. Revocation after size admission prevents position admission; a late result cannot restore an older desired tree. Geometry ordering, tolerance, and readback eligibility remain separate unimplemented policies.

A denied step still produces a typed terminal operation disposition so both worker and model release the matching sequence after owner consumption. The current reducer has no operation-ID-based event for every pre-permit denial; add and test that event before integrating this extension. Never invent a successful permit/result to free a slot. Executing unknown outcomes remain dirty and require fresh observation, with no automatic write retry. Registry retirement prevents later steps while preserving an already executing slot until actual acknowledgment.

Termination retires routing only after confirmed process-lifetime replacement or death; old callbacks cannot affect a newer attachment sharing its PID. A merely blocked thread remains quarantined and counts against worker bounds. Stop closes gates and removes queued work immediately, without waiting for IPC or teardown; retained replies get a stopped disposition, and any late worker publication is rejected. Stopped slots cannot be reused for the same attachment. Physical worker cleanup can finish later, and app Quit must not depend on it. A new confirmed process lifetime may attach only if physical worker capacity remains; retired callbacks retain their old immutable identities rather than growing a tombstone registry.

## Required verification before integration

The pure receipt/slot state machine and lock-protected **read-only** transport are implemented in [M2.11](m2-read-only-delivery.md), with scoped verification. The following requirements also cover remaining command/revocation and future setter stages; they are not all accepted by that implementation. Do not wire real writes or invent eligible observations to make the contract pass.

Required deterministic and barrier-controlled scenarios:

- Hold owner consumption after backend finish: thousands of subsequent request attempts return busy, one receipt remains, and unrelated apps progress.
- Acknowledge accepted, failed, stale, and rejected-registry replies; each releases only its matching slot. Duplicate/wrong IDs and PID-reused callbacks cannot release newer work.
- Interleave publish, owner reserve, acknowledgment, drain-finalization, and new producers at barriers: no overwritten reply, lost wakeup, overlapping owner drains, or leaked busy state.
- Saturate all reply slots and the semantic queue; verify exact limits, visible rejection, FIFO semantics, and rotating bounded drain fairness. Notification storms grow neither tasks nor reason storage.
- Pause/Disable/Quit/trust loss/environment invalidation before request take, during blocked backend work, and during owner reduction. Delayed activation publications and older Enable/Resume cannot reopen newer revocation; no fresh request starts automatically.
- Stop while the backend is blocked returns without waiting; callbacks after stop cannot reopen admission. Quarantined workers are not replaced, and confirmed new process lifetimes receive new identities.
- Reject oversized payloads, incomplete registry replacements, invalid timing, malformed IDs, and exhausted counters without partial control state or wrapped identity reuse.

A later fake setter stage must additionally force both admission/revocation lock orders, denial before any permit, revocation between setters, acknowledgment after unknown outcomes, and retirement while a call is executing. Then real read-only handler acceptance must check the changed completion lifecycle separately. Physical AX setters, mouse interaction, lock/wake, display/Space behavior, and representative-app eligibility require explicit separate acceptance. See M2.11 for the latest source verification and the exact subset accepted; no test count establishes the remaining live admission contract.
