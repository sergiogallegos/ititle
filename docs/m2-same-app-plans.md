# M2.16 — Bounded same-app plan sequencing

Implemented in the internal readback-required runtime over [M2.15](m2-fake-worker-readback.md). One explicit Tile can now contain several windows from the same app, processed in ascending token-serial order. No production handler, real setter, permission request, or live eligibility provider changed. Production mutation scope remains empty.

## Command and cursor identity

Pure `PlanCursor` records the app, command serial, layout revision, and ordered window tokens. Construction requires 1–64 distinct positive window serials from the same issued app identity. It advances only for its exact next token. Current installed plans retain at most 256 target tokens across at most 16 app cursors, matching the existing model/command bounds. Completed tokens can remain in the bounded cursor array until that cursor is removed; the exposed remaining count is not a memory measurement.

The owner still reduces each semantic command in FIFO order and creates one layout revision for the complete Tile. It validates the per-app cap before accepting the model plan. An oversized app group yields a typed capacity rejection and pauses rather than partially installing a plan. Relative focus/resize/swap/toggle policies remain unsupported in this harness.

The gate installs the complete owner-approved cursor set once for a fresh command serial. Publication of another window under that same ticket requires the exact current cursor token and layout revision. It does not relax the publication watermark generally or create per-window re-tile commands. Each published window receives a fresh process-scoped operation ID. The cursor advances only after accepted observed readback and exact terminal acknowledgment; slots remain occupied through that boundary. Duplicate, out-of-order, or exhausted cursor advancement cannot authorize work.

The runtime queues the next same-app window only as continuation of that still-current explicit plan. At most one app operation and one worker job remain admitted at a time. Readback uses monotonically increasing app-wide observation sequences even when different windows have older retained observations. The original standalone owner mode continues to reject multi-window app plans unless explicitly enabled with readback-required mode.

## Isolation and cancellation

Command admission/reduction checks every affected app stamp atomically. After reduction, execution checks the global stamp and the individual app stamp. This distinction lets a healthy app continue its portion of a shared plan after another app becomes uncertain; relative commands or unprocessed complete plans cannot partially bypass stale stamps. Global Pause, Disable, Quit, permission/environment invalidation, and unknown routing still close all relevant admission.

Failure or rejected readback cancels the app's remaining cursor and pending targets, with no retry or rollback. Positive destruction and an accepted registry replacement missing a remaining cursor token cancel the whole app sequence. Completed observed geometry is retained, while surviving app records may become dirty for explicit recovery. Retirement retains actual occupied cleanup through acknowledgment; stale duplicate callbacks on retired routing cannot become global uncertainty for a replacement process.

A newer Tile replaces pending cursor records and desired frames without pretending an admitted old operation was canceled. Old completion cannot restore old desired geometry or advance the new cursor. If that old completion requires app reconciliation, it also cancels the app's replacement pending targets; fresh evidence and another explicit Tile are required. Healthy other apps can continue. Failed/unpublished preparation clears the corresponding cursor rather than leaving an unusable ticket retained.

## Verification

`scripts/format` and final `scripts/verify` pass 170 tests (106 core, 64 platform). Ten new tests cover cursor ordering/exact advancement/malformed identities/bounds; whole-command versus per-app execution stamps; two same-app windows with exact observed readback and one revision; failure with a healthy peer; barrier-held app uncertainty while a peer continues two windows from the shared ticket; new revision during an admitted call; the 64-window maximum and typed 65th-window rejection; registry removal before the next dispatch; and destruction between windows. The existing retired-route test additionally rejects a duplicate old receipt while proving replacement work still admits.

The maximum-plan runtime test executes 192 fake size/position/readback calls, retaining one active app operation while its cursor initially contains 64 targets. Dedicated fake backends remain off the main thread. Tests use fixed logical time and synthetic eligibility. They do not establish actual elapsed freshness, throughput, AX behavior, monitor topology, or real application support.

## Next task and production boundary

Consolidate the end-to-end simulation acceptance and review the production adapter contract against the remaining eligibility/lifecycle evidence. Identify concrete provider and acceptance requirements for identity, desktop visibility, native tabs, nested dialogs, owner/worker routing, and revocation before any live control wiring. Keep the [empty supported-scope decision](decisions/0004-supported-scope.md) authoritative until new evidence supports a reviewed narrower scope.

Management UI, mouse drag/resize coexistence, native desktop numbering, configuration/hotkeys, and representative real-window acceptance remain separate product/platform tasks. A complete fake plan does not make iTile a working window manager.
