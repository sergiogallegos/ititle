# M2.12 — Semantic commands and simulated revocation

Implemented as an isolated pure command boundary and an internal, lock-protected fake-operation gate. This is the simulation subset of [M2.10](m2-delivery-admission.md), following [M2.11](m2-read-only-delivery.md). The app remains read-only. No production worker, menu, hotkey, AX setter, focus action, or permission request uses the new gate.

## Implemented boundary

`CommandBoundary` retains at most 128 semantic intents and drains at most eight in FIFO order. Tile payloads contain at most 256 valid frames. Relative resize, swap, focus, and floating toggle retain their individual ordered dispositions; their layout policies are not implemented. Overflow rejects the incoming intent explicitly. This is a value API, not yet a visible UI rejection or hotkey pass-through implementation.

Pause, Disable, Quit, permission loss, environment change, and app uncertainty bypass the FIFO. Global and per-attachment stamps reject older commands and publications. Unknown app routing closes globally. Older Enable/Resume cannot reopen a newer revocation. A fresh Enable/Resume advances the global stamp and leaves management paused; fresh evidence and an explicit Tile are required. Permission recovery does not replay commands. Quit and exhausted revocation generations stop admission. Attachments are capped at 16, use positive monotonically issued process generations, and do not accumulate retirement tombstones.

`SimulatedCommandGate` serializes this small boundary with one `NSLock`. It checks synthetic eligibility/capabilities, matching observation sequence and epoch, finite geometry/timing, a 0.5-second evidence deadline, and the current command stamp before publishing a Tile operation. It retains one operation per app, up to 16. The initial control-model admission generation of zero is valid. Targets in tests come from the real pure `ControlModel`; eligibility is synthetic test input, never inferred from live AX evidence.

Each size or position step obtains a distinct permit under the lock. Revocation and admission use that same lock. Revocation before admission produces a terminal denial without a permit. Admission first allows that one fake call to finish after Pause; its late acknowledgment cannot admit position. Fake backend work, barriers, and callbacks run outside the lock. Invalid timestamps cannot suppress safety ingress.

An operation stays occupied through each exact step acknowledgment and its terminal acknowledgment. Duplicate, mismatched, older-process, or older-operation receipts cannot release newer work. Failure, unknown outcome, expiry, and revocation end the sequence without retry. Retired executing or undelivered work still occupies capacity until its terminal acknowledgment; replacement attachment cannot bypass the 16-slot resource bound.

## Verification

The source suite includes pure FIFO saturation/order, payload and attachment bounds, app/global revocation, permission recovery, stale Enable/Resume, and terminal generation exhaustion. Gate tests cover each safety reason before admission, a barrier-held admitted fake call across Pause, acknowledgment between setters, terminal identity/replay, failure/expiry, stale publication/evidence after Resume, app isolation, process replacement, retained retiring capacity, and Disable with a saturated command buffer. No real windows or permission grants are involved. See [validation](validation.md) for the final run.

## Remaining integration and next task

This gate trusts its serialized simulation owner to supply tickets emitted by that boundary and current owner-approved targets. It does not mirror `ControlModel` desired revisions or window registry retirement, execute multi-window plans, schedule a shared command/reply drain, perform readback/reconciliation, or deliver denial events to the reducer. One Tile ticket can publish one target per app in this prototype; additional same-app targets need a reviewed sequence protocol. The terminal receipt releases only the simulation gate slot, not a separate model slot. It is internal to the platform module and has no platform-call capability.

Next: implement and test a simulation owner adapter that consumes ordered command dispositions, synchronizes registry/revision invalidation, and reduces operation-ID-based pre-permit denials and late completions into matching model cleanup. Keep all fake work outside owner reduction and locks. Integrate bounded wakeup/priority delivery before any live worker wiring. Management UI, mouse drag/resize coexistence, native desktop numbering, supported eligibility, and real setter acceptance remain separate gates.

[M2.13](m2-simulation-owner.md) subsequently implements the manually driven owner adapter, target authorization mirror, reserved consumption, and matching reducer cleanup. The isolated M2.12 mode described above remains available for its tests; neither mode has live platform-call capability or a shared scheduler.
