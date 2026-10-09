# M2.14 — Bounded shared simulation delivery

Implemented internally around [M2.13's simulation owner](m2-simulation-owner.md). Commands, fake step/terminal replies, and priority safety signals now share one serialized drain chain. This does not replace the production read-only transport, enroll real windows, install hotkeys, or execute AX actions. Production mutation scope remains empty.

## Implemented bounds and ordering

`SimulatedDelivery` retains one exact reply per app and at most 16 routing attachments, including retired operations awaiting their actual terminal consumption. Commands use the existing 128-intent gate FIFO. Each main-actor pass applies priority state, consumes at most eight replies with a rotating app cursor, reapplies priority state, then reduces at most eight commands. It stores no disposition history; an optional serialized sink receives each bounded command batch.

All ingress shares a short transport lock. The scheduled flag stays set throughout owner consumption. Final pending-state inspection and flag update use that same lock, so a producer either contributes to the queued continuation or arms the next drain. Scheduling occurs outside the lock. The scheduler must queue closures serially on the main actor, rather than executing them inline. There is no task per reply or notification; the tests use a held scheduler to inspect the chain.

Safety ingress closes the gate synchronously before scheduling owner delivery. Fixed global flags and a bounded per-app uncertainty set bypass the semantic FIFO. Unknown routing closes globally. Repeated pending permission/environment signals coalesce their epoch transition; every repeated ingress still revokes global admission using Pause. Owner application does not revoke the gate a second time. A 1,000-iteration paired storm therefore retains two epoch-bearing flags, one wakeup, and aligned gate/model epochs. This is conservative invalidation, not a count of macOS transitions.

Gate and owner clocks provide a nonregressing floor for the injected simulation time source, including invalid source values. Safety cannot be suppressed by invalid timestamps, and matching receipt cleanup is not deferred by a clock regression. No real IPC timing or latency measurement follows from this policy.

## Exact receipt consumption and retirement

Reply submission checks the gate's actual finished/terminal phase and exact receipt value. Occupied slots are never overwritten. The owner reserves the receipt and reduces it without holding either lock. Immediately before gate acknowledgment, an owner callback removes only that exact transport entry; the worker still holds its gate slot through this gap. After acknowledgment, a next step can publish into the now-empty routing slot. Test hooks and scheduling callbacks run outside both locks.

Duplicate, malformed, or replayed receipts quarantine a known app route and close new gate publication/admission. The original occupied reply is preserved. Quarantine still accepts an exact actual completion from an already executing call so model/gate cleanup does not leak. Quarantine persists until attachment retirement; fresh observations and Tile do not bypass it. Unknown old process callbacks cannot quarantine a replacement attachment.

Retirement removes owner model records immediately but keeps routing for an occupied old operation. The old route is removed only after terminal acknowledgment leaves both transport and gate empty. Confirmed replacement processes use new generations and available capacity. Quit stops command admission immediately while retaining delivery of matching already-admitted completions for cleanup; neither acknowledgment nor a queued drain can reopen control. No new fake work starts automatically.

Lock order is transport then gate. The gate has no callbacks into the transport. Model reduction, fake backend work, reply hooks, and scheduling all occur outside these locks. Bootstrap/recovery observation and trust remain explicit owner calls; runtime simulation commands, safety signals, and receipts must use delivery ingress, while fake workers use gate admission/finish.

## Verification

`scripts/format` and final `scripts/verify` pass 152 tests (101 core, 51 platform). Nine added tests cover 16 reply slots, 128 FIFO commands, eight-item batches and one chain; full-queue Disable and stale Enable rejection; reply/safety publication during owner consumption and after finalization; duplicate/replay quarantine; late cleanup from a quarantined executing call; safety after command reduction before publication; epoch storms and fresh recovery; retired-process routing with a replacement flight; and a barrier-held producer wakeup concurrent with command/Quit ingress. Existing model, blocked fake-call, and production read-only transport tests remain passing. No live window or permission experiment was performed for this isolated source task.

## Remaining boundary and next task

The delivery layer is driven by tests and an injected scheduler. It does not instantiate fake worker loops, automatically prepare operations after Tile, perform readback, execute multiple same-app windows, or connect to production app handlers. Disposition sinks and test hooks must not perform blocking platform work. Its bounds describe retained routing/queue state, not total system allocations or arbitrary scheduler implementations.

Next: complete the fake-worker sequence through observed readback and terminal acknowledgment, with bounded per-app sequencing and an end-to-end stalled-peer test. Review same-app multi-window behavior before supporting complete plans. Real eligibility, live control opt-in, mouse drag/resize coexistence, desktop numbering, physical display topology, and representative-app acceptance remain separate gates.

The subsequent [M2.15 runtime](m2-fake-worker-readback.md) now drives dedicated fake workers through readback-required mode. This delivery layer also routes readback receipts and invokes serialized continuation callbacks after owner acknowledgment. Standalone M2.14 tests retain their earlier position-terminal mode; neither mode controls real windows.
