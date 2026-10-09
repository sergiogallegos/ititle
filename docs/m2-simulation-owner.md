# M2.13 — Simulation owner and matching model cleanup

Implemented as an internal synchronous test harness on the main actor, using the [M2.12 gate](m2-command-revocation.md) and pure `ControlModel`. No production menu, worker, AX action, permission request, or keyboard handler uses this adapter. Production mutation scope remains empty.

## Implemented protocol

`ControlOperationID` identifies a sequence by app attachment and serial. After gate publication, the owner binds that ID to the exact prepared model target before exposing it to a fake worker. A per-attachment operation watermark rejects reused IDs without an accumulated tombstone set. Externally bound flights use separate phases from the reducer's original simulated `perform` effects; binding and receipt consumption emit no setter permits.

The owner consumes at most eight ordered command dispositions per explicit drain. Enable/Resume leaves the model paused and invalidates its evidence. Valid explicit Tile commands reduce into model plans. Relative resize/focus/swap/toggle policies and multiple same-app windows are explicitly reported as unsupported by this harness; they are not silently executed or coalesced. At most one target per app is supported in a Tile plan.

After each model change, an immutable snapshot of current flight targets and the layout revision is copied to the gate under its lock. Publication and each setter admission must match that snapshot, the ticket stamp, evidence, and gate state. Revisions cannot regress. A newer Tile removes old revision authorization; registry retirement removes authorization for the missing token. The mirror is an internal admission boundary, not a claim of atomic external window state. A permit that wins before the mirror update may still finish later.

For a step reply, the owner reserves the exact receipt, reduces its outcome, updates the mirror, then acknowledges it. Reservation leaves the slot occupied. Owner-managed gate acknowledgment requires reservation; the next setter cannot start while reduction is pending. Model reduction, fake backend work, and callbacks never run under the gate lock. The harness performs no suspension during reduction.

An actual terminal denial or completion reduces `operationTerminated` before gate acknowledgment. It releases only the flight bound to that ID and marks surviving app windows dirty. No successful result is invented to free pre-permit denied work. Terminal cleanup works after Quit and with invalid reducer timestamps, without reopening control. Unpublished prepared work has a separate exact-target discard event. Process retirement removes old model records while the gate and owner routing retain occupied old operations through their actual terminal acknowledgment; late old receipts cannot release a replacement process's flight.

Successful size/position receipts do not establish observed geometry. The harness ends at terminal position completion, retains desired frames, and requires fresh observation plus explicit Tile rather than automatically dispatching pending work. Receipt processing time is used as the simulation completion upper bound; it is not a measured backend finish timestamp. The original pure model readback path remains separate.

## Verification

`scripts/format` and final `scripts/verify` passed 143 tests (101 core, 42 platform). Three added core tests cover exact operation binding/terminal identity, Pause retention, wrong step order/timing/replay, operation-ID reuse, exact unpublished-target discard, and terminal cleanup after Quit. Eight adapter tests cover pre-permit denial cleanup; reserved acknowledgment and successful sequence cleanup without observed geometry changes; newer desired revisions; registry retirement; a barrier-held fake call across Quit; PID replacement; permission/environment epoch recovery; and explicit unsupported policies. The blocked fake call runs on a dedicated test queue outside all owner/gate locks. No real window integration or latency result is claimed.

## Remaining boundary and next task

The adapter is manually driven in tests. It has no shared command/reply scheduler, worker wakeups, priority signal mailbox, continuous observation, real readback, or live enrollment. Its actor owns simulation records only; it introduces no production layout policy in the platform module. Callers must use the owner for model events and the gate for fake admission/finish, and consume exact receipts through the owner. The isolated gate mode used by M2.12 tests still permits direct acknowledgment; the owner-managed mode requires reservation.

Next: add bounded shared simulation delivery and priority safety ingress, with one drain chain, exact receipt routing, and barrier tests for publication during owner reduction, invalidation before publication, and drain-finalization races. Keep fake worker execution outside reduction and locks. Live setters, supported eligibility, management UI, mouse coexistence, native desktop numbering, and multi-monitor acceptance remain separate tasks.

The subsequent [M2.14 delivery layer](m2-shared-simulation-delivery.md) now schedules this owner through a bounded shared drain in simulation. Owner acknowledgment exposes a synchronous pre-acknowledgment callback for exact transport removal. Standalone M2.13 tests still manually drive the adapter; no production worker or handler is connected.

[M2.15](m2-fake-worker-readback.md) adds an opt-in readback-required owner mode used by the dedicated fake runtime. Matching observed readback can now complete its externally bound model flight; the original standalone position-terminal mode above still treats setter geometry as unverified.
