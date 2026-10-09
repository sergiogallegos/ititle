# M2.15 — Fake workers through readback

Implemented an internal end-to-end harness over [M2.14 delivery](m2-shared-simulation-delivery.md), owner reduction, and gate admission. Dedicated threads execute fake size, position, and readback backends. No AX/AppKit handles, real setters, menu actions, permission requests, or production handler integration were added. Production mutation scope remains empty.

## Sequence and observed completion

The runtime opts into a new readback-required gate/owner mode. The older standalone simulation mode still ends after position and marks geometry unverified; its existing tests remain valid. In readback mode, an accepted Tile prepares at most one target per app. Size and position each obtain their own permit, execute off the main thread, publish an exact receipt, and wait for owner consumption before continuation.

Position success leaves the operation occupied and enables a separate readback permit. Readback runs on the same dedicated worker. Its receipt carries the target, process-scoped operation ID, first setter admission, actual fake readback finish time, outcome, and optional observation. The owner requires the observation to follow readback admission and finish no later than the result. The pure model additionally validates flight identity, target/revision/epoch, eligibility/capabilities, sequence, geometry, and ordered timing. Only matching accepted readback advances observed geometry. Successful setter outcomes alone do not update observations.

The gate retains the sequence through readback receipt reservation, owner reduction, and exact terminal acknowledgment. Successful model reduction removes its flight; terminal acknowledgment therefore validates the remaining gate stamp/state without requiring that completed flight to stay in the authorization mirror. Replay cannot dirty successful observed state or release newer work. Missing, mismatched, stale, unknown, or revoked readback leaves surviving windows dirty and requires fresh explicit recovery. No automatic write retry or rollback occurs.

Shared delivery routes readback in the same bounded reply slot as setter receipts. Continuation callbacks run after owner acknowledgment and outside locks. They queue only the next matching fake step. Terminal callbacks start no work. Absolute targets may reflect the final ordered Tile reduction in a batch; semantic command dispositions still reduce individually. Bootstrap uses explicit pure owner calls, with no dependency on Task ordering.

## Worker ownership and limits

Each `SimulatedSequenceWorker` owns one `Thread`, one condition-protected pending job, and one backend. Fake backend calls execute outside the condition/gate/transport locks and outside the main actor or Swift cooperative executor. The mailbox becomes available before receipt publication, while the occupied gate still prevents unrelated work; this allows an acknowledged continuation to arrive without a mailbox race.

The runtime caps physical workers at 16, including stopped or retired threads that have not reported exit. A stalled worker is not replaced. Retirement preserves delivery of its actual completion while removing old model routing. Quit closes admission immediately and signals workers to stop, without joining or pretending an executing call was canceled. Queued work obtains denial through the gate; already admitted work may finish and deliver matching cleanup. Missing worker availability terminalizes only unadmitted work, with no invented successful outcome.

Completed retired threads are collected on a later explicit attachment attempt. Gate and delivery capacity checks remain independent. A thread-exit callback supports deterministic tests; it is not a production teardown or OS lifecycle provider.

## Same-app plan review

The harness continues to reject more than one window per app in a Tile plan with an explicit unsupported disposition. Reusing a ticket for another target would bypass the current publication watermark and consume lifecycle evidence without a reviewed sequence identity. Supporting complete same-app plans needs a bounded ordered cursor, matching per-window completion/retirement, and a rule for newer revisions replacing pending targets while preserving admitted work. Do not silently split one command into independent re-tiles or relax the watermark to make a test pass.

## Verification

`scripts/format` and final `scripts/verify` pass 160 tests (103 core, 57 platform). Eight added tests cover exact external readback flight identity and replay; preservation of newer desired revisions/new operation slots; sampling after the actual readback permit; successful off-main size/position/readback and observed geometry; a barrier-held app while its healthy peer completes and Quit stays available; Pause during blocked readback; missing/mismatched/unknown/old-sequence/old-time readback; and the physical worker cap with a blocked retiring thread and confirmed replacement after actual exits. Threads are stopped and exit expectations are fulfilled in the runtime tests.

Tests use synthetic eligible values and a fixed logical time source. They prove internal ordering and isolation, not real window eligibility, wall-clock freshness, IPC timing, performance, monitor topology, or OS event coverage. No real window integration experiment was performed.

## Next task

Implement bounded same-app plan sequencing in simulation, with one app operation at a time, exact per-window readback/terminal identity, and cancellation of remaining targets on invalidation. Test newer revisions, retirement between windows, failures, and a stalled same-app sequence alongside a healthy peer. Keep all production mutation and automatic enrollment disabled pending the separate supported-eligibility and platform gates.

[M2.16](m2-same-app-plans.md) subsequently implements the reviewed bounded same-app cursor protocol in the fake runtime. Per-window operations still require exact observed completion before continuation; standalone owner mode retains its earlier unsupported multi-window disposition unless explicitly opted into that simulation mode.
