# M2.32 — Fixture timing and diagnostic freshness calibration

**Status: measurement contract; its collector is now implemented in [M2.33](m2-fixture-timing-collector.md). No calibrated age policy is implemented.** This completes the design task following [M2.31](m2-native-host-operator-checks.md). The separate fixture lab remains read-only, and accepted pairs remain historical with unmeasured freshness. Production eligibility and ADR 0004 are unchanged.

## Question and boundary

Measure how much a paired observation ages during acquisition, worker scheduling, reply delivery and host assessment. Use those measurements to evaluate the usability of explicitly labelled experimental diagnostic age policies. Latency measurements cannot prove uninterrupted visibility, tab/dialog safety or complete native notification delivery. A diagnostic deadline does not grant a lease or permission to call a setter.

The existing schema-2 fixture supplies source acquisition start/end times. Successful owned AX reads supply an inspection start/end interval. The consumer validates enclosing host request/receipt times but does not retain them in returned snapshots. The reader does not expose worker admission/start/publication timing, and failures have no timing envelope. Existing transcripts therefore cannot separate these stages or serve as a calibration dataset. The five-second reader watchdog, AX messaging timeout and operator deadlines are resource bounds, not freshness limits.

## Proposed measurement envelope

Keep schema-2 fixture records unchanged. Add a versioned, Foundation-only host timing value in `ITileFixtureDiagnostics`, used only by the lab. Native adapters capture timestamps and pass immutable values; AX objects remain on the dedicated thread. Store one terminal record per attempted pair, including rejected, timed-out and revoked attempts. Do not manufacture missing timestamps or substitute a timeout deadline for observed completion.

Use `ProcessInfo.systemUptime` seconds consistently with the existing source and AX intervals. It is a shared system monotonic time base on this local machine, not a process-relative stopwatch. Validate finite, nonnegative values and causal ordering before computing durations. Wall-clock UTC belongs only in the run manifest and must never enter duration/expiry arithmetic. Sleep/wake invalidates the host context; do not pool measurements across it as one stable cohort.

Capture the following boundaries at the operation, rather than reconstructing them from printed lines:

| Stage | Timestamp boundaries | Meaning |
| --- | --- | --- |
| Each before/after snapshot | host request submission; completed pipe write; source start/end; host complete-line receipt; completed parse/correlation | Submission starts before writing. Receipt is when the complete bounded line is available, before parsing or printing. These distinguish source acquisition from transport and host processing. |
| Dedicated AX reader | host admission; worker inspection entry; inspection exit; publication under result lock; host matching-result receipt | Entry precedes the trust query and AX calls. Exit applies to successful and failed inspections. Publication follows exit; receipt is when the host consumes the matching value. |
| Pair assessment | host inputs-ready; assessment entry; assessment exit | Inputs-ready requires both correlated snapshots and the matching terminal AX value. The entry timestamp supplies the reducer's `now`; exit describes computation cost, not an extended deadline. |
| Host invalidation | callback/sample observation time; updated revocation counter; pending request | Records when this host observed invalidation, not the time the OS event physically occurred. It retains the existing fixed event codes. |

Receipt for an immediately available value still needs its own timestamp. Lock publication timing must be captured as part of the same publication, not by a later worker log. The implementation must document placement precisely and retain absent stages for failed writes, parse rejection, reader failure or timeout. A physically unfinished reader keeps its slot occupied even if the attempt has a terminal timeout record; do not launch a replacement to improve the sample count.

Snapshot source start may precede host completed-write time because the child can read before the write returns. Do not impose the false ordering `writeComplete <= sourceStart`. Required bounds are submission <= sourceStart <= sourceEnd <= complete-line receipt <= parseComplete, and submission <= writeComplete <= complete-line receipt for successful writes. Paired acceptance additionally retains before.end <= AX.entry <= AX.exit <= after.start. Reader admission <= entry <= exit <= publication <= receipt; inputs-ready is at least both parse completions and AX receipt; inputs-ready <= assessment entry <= exit. Validate each available subset without inferring absent endpoints. Any invalid ordering yields a fixed malformed-timing outcome and cannot receive a freshness label.

The existing pair reducer continues to validate identity, request/sequence, source/registry revisions and exact host context. Timing envelopes cannot bypass those checks. A context change while assessment is delayed is evaluated before acceptance; discarded or revoked values cannot revive after recovery.

## Derived measurements

Only compute a metric when both endpoints exist and pass validation:

| Metric | Definition |
| --- | --- |
| Source acquisition | snapshot.end - snapshot.start, separately for before and after |
| Snapshot end-to-end | parseComplete - submission, separately for before and after |
| Snapshot delivery | complete-line receipt - source.end; includes scheduling/transport, without attributing each component |
| Snapshot parse/correlation | parseComplete - complete-line receipt |
| Worker dispatch wait | AX.entry - reader admission |
| AX inspection duration | AX.exit - AX.entry; includes trust checks and surrounding inspection work, not just IPC |
| Result publication | publication - AX.exit |
| AX reply wait | host AX receipt - publication |
| Assessment wait / cost | assessment entry - inputs-ready / assessment exit - entry |
| Conservative evidence age | assessment entry - before.start |
| Complete pair latency | assessment exit - before submission |

The earliest source acquisition, `before.start`, remains the age origin. Do not reset age at AX completion, receipt, recovery or assessment. End-to-end intervals overlap their component intervals: do not sum all metrics into a second purported total. Report individual records alongside aggregate counts so delivery delay and source change remain distinguishable.

## Bounded experiment

The next implementation task adds the collector and deterministic timing tests; it leaves native age policy absent. A later explicitly run calibration uses one owned fixture, one outstanding pair, one physical AX reader and one host assessment slot. No overlapping requests, parallel readers, user-window enumeration or setter is introduced.

For a reproducible first experiment, predeclare these limits in the manifest: at most 64 attempted pairs per invocation, at most 16 attempts in each cohort, a 180-second overall deadline, existing five-second reader drain/watchdog and bounded existing protocol buffers. Stop on the first resource-bound breach, clock/order failure, observer overflow or incomplete owned-child cleanup. A stopped run stays incomplete; do not silently repeat until it passes. Request/sequence/revision exhaustion retains existing checked-stop behavior. Bound timing/event records and total output (at most 256 KiB); hitting either bound stops collection and records incomplete using reserved terminal capacity.

| Cohort | Purpose and proposed procedure |
| --- | --- |
| Ordinary | Stable original fixture, no injected delay; collect at most 16 attempts. State/context rejection remains an outcome rather than a discarded sample. |
| Worker dispatch delay | At most 16 attempts, cycling requested delays 0, 50, 200 and 500 ms before inspection entry. Use a lab-only dedicated-thread delay; keep host event pumping active. Measure actual delay separately from its requested value. |
| Assessment delay | At most 16 attempts, cycling the same requested delays after inputs-ready and before assessment. Schedule a due time and continue bounded event pumping; do not block the main thread to simulate delivery. |
| Invalidation | At most 16 attempts alternating explicit laboratory Pause during scheduled assessment delay and a controlled owned-fixture tab/sheet reversal between before/after acquisition. Require contextRevoked or sourceChanged respectively, then obtain new evidence after recovery. Never reuse the rejected pair. A source transition after both snapshots cannot be detected by comparing their old revisions; retain that residual race. |

These cohorts test attribution and rejection behavior. They do not emulate every OS scheduling/load condition. Native desktop and effective-permission observations remain the separately accepted M2.31 scope; this experiment requires no new temporary permission grant. A future grant or physical operator episode must have its own scope and recorded cleanup.

Record fixed metadata only: format version, cohort/index, requested delay, opaque run/request/sequence/serial identities, source/registry revisions, host context counters, optional timestamps, fixed terminal outcome, observed invalidation codes and cleanup status. The manifest records OS/build, lab/fixture artifact hashes, fixed configuration, counts and bounds; omit titles, typed keys, document paths and arbitrary error strings. Export bounded structured records rather than unbounded log text. Timing fields need enough precision to preserve ordering; formatting must not round a passing timestamp into an apparent boundary violation.

Summaries show attempted, completed, rejected, revoked, failed, timed-out and incomplete counts per cohort. Preserve overlapping rejection categories or use a documented single primary terminal outcome; counts must reconcile to attempts. Show minimum, median, nearest-rank p95 and maximum for each metric with its available-record count. Timeouts and missing endpoints are explicitly censored/absent, never zero-duration successes. With at most 16 attempts per cohort, p95 is a coarse descriptive statistic, not a tail-latency guarantee. Do not combine intentionally delayed cohorts into a normal-operation percentile.

## Policy evaluation and review

Collection initially passes no `FixtureDiagnosticAgePolicy`; historical consistency and timing availability remain separate. After collection, a reviewer may name a finite positive experimental age and positive policy revision in a separate evaluation record. Replay measured valid pairs through the pure assessment with that exact policy; report rejection at `now >= before.start + maximumAge`, including pairs already expired on arrival. Reject nonfinite, nonadvancing or overflowing expiry and regressing clocks. Policy replacement invalidates prior acceptance; age cannot extend an already accepted record.

Selection is explicit and fixture-only. Record the candidate age, rationale, dataset hashes, included cohorts, excluded/absent records and resulting expiration counts. A percentile or the longest successful observation does not automatically choose a limit. The experiment evaluates latency versus diagnostic expiration frequency; it establishes no safe age for mutation. No reviewed real policy is selected by this document, and production freshness remains unmeasured.

## Implementation and acceptance gates

The collector must have deterministic pure tests for causal ordering (including source start before write completion), absent failure timestamps, finite arithmetic, exact expiry, clock regression, policy change and no revival after invalidation. Test admission-to-entry and publication-to-receipt attribution with independent fake times. Exercise every record/output cap and retain unfinished-worker occupancy. Native adapters need separate real fixture checks showing success/failure terminal envelopes, injected versus measured delays, timely pumped revocation and normal cleanup; unit tests alone cannot accept those paths.

The collector implementation and its scoped source/native acceptance are recorded in [M2.33](m2-fixture-timing-collector.md). The next task reviews the dataset and attribution/rejection coverage. Numerical calibration and policy selection follow only after a valid dataset and review. Production admission, supported-window safety, enable/disable management, mouse coexistence and native desktop numbering remain separate work.
