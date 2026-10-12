# M2.34 — Fixture timing dataset review

**Status: offline review complete; follow-up instrumentation specified, not implemented.** The final [M2.33](m2-fixture-timing-collector.md) dataset passes timing and summary checks. It supports bounded collection, injected-delay attribution and the recorded rejection paths. It does not establish accepted recovery after the unexpected activation, or support full assessment replay. No diagnostic age policy is selected. Production eligibility remains unchanged.

## Dataset and review method

The exact final dataset is retained as [bounded JSON lines](evidence/m2-33-timing-final.jsonl), rather than relying on the original `/tmp/itile-m233-timing-final.jsonl`. Its SHA-256 is `638703f093e716dec71958ced25e811ebcb0b78948de3ef01e233ecac136a9dd`. It contains 80,882 bytes and 85 lines: one manifest, 64 pairs, 18 events, one summary and one terminal. Manifest UTC is `2026-10-09T23:11:54Z`, macOS 27.0.1 build 26A434, run `5497ABD4-0249-474E-A361-3A61F01FF511`. Lab/fixture executable hashes remain those recorded in M2.33.

An offline Swift/Foundation/CryptoKit audit reconstructed each exported timing record using the checked-in `FixtureTimingRecord` value, checked its causal ordering and cross-attempt monotonicity, and recomputed `FixtureTimingSummary`. The reconstructed summary exactly matched the stored summary, including every metric's count, minimum, median, nearest-rank p95 and maximum. Additional checks verified contiguous attempt indices, cohort order, requested-delay cycling, run/serial identity, increasing request/sequence values, event ordering, consecutive revocations, matching pending requests and terminal counts/cleanup. This audits the exported values; it does not reproduce the native observation or verify omitted inputs.

All 63 assessed attempts contain all 20 host timing boundaries. Attempt 64 retains 11 boundaries: the six before-snapshot boundaries and five reader boundaries. Its after-snapshot, assessment and assessment-result fields are absent. The recorded terminal is complete=true, orderly=true, occupied=false. These are collection/cleanup results, not evidence that every cohort passed a stable-state or recovery check.

## Outcomes and event placement

| Attempts | Cohort | Assessment | Count |
| --- | --- | --- | --- |
| 1–16 | Ordinary | historicalConsistent | 16 |
| 17–22 | Dispatch | historicalConsistent | 6 |
| 23 | Dispatch | contextRevoked | 1 |
| 24–32 | Dispatch | unsupported | 9 |
| 33–48 | Assessment | unsupported | 16 |
| 49, 51, 53, 55, 57, 59, 61, 63 | Invalidation | contextRevoked | 8 |
| 50, 52, 54, 56, 58, 60, 62 | Invalidation | sourceChanged | 7 |
| 64 | Invalidation | No assessment; deliberate failed preflight | 1 |

Both activation callbacks belong to attempt 23, request 46. They advance host revocation 0→1→2 and activation 0→1→2, while source state changes 6→10. Their observation times precede worker inspection entry by about 131.699 ms and 131.655 ms. This attempt requested a 200 ms dispatch delay: the callbacks arrived **during dispatch wait, before inspection**, not inside an AX call. The native event's physical time, originating application and activation/deactivation direction are not exported.

Attempts 24–48 retain equal source revisions 10/10 and unchanged host context at revocation 2. Equal revisions show consistency of the recorded revision values, not restoration to a supported state. The 25 unsupported assessments cannot be attributed to the injected delay alone: each dispatch delay has both early accepted and later rejected observations, and all four assessment-delay levels reject, including zero delay. Foreground loss is a plausible explanation after an activation, but the omitted source fields prevent confirming it.

The remaining 16 host events are eight Pause/resume pairs, each attached to its intended outstanding request, after inputs-ready and before assessment. Each pair advances revocation twice; Resume does not revive the old request. Seven sheet reversals produce sourceChanged. Those checks prove their respective primary rejection paths within this run. The reducer checks host revocation and source changes before ordinary supported-state flags, so these results can mask an unsupported baseline. No subsequent attempt is historicalConsistent. Fresh requests after recovery were acquired, but **accepted recovery was not demonstrated**.

Attempt 64 measures the dedicated reader's failed PID-0 preflight. It is not a native IPC failure, IPC timeout or permission-loss episode. No timeout/sleep/wake/display/permission calibration coverage is added by this dataset.

## Timing attribution

All values below are milliseconds; metrics include valid rejected observations unless stated otherwise. Cohorts remain separate.

| Requested delay | Dispatch wait range, four attempts | Assessment wait range, four attempts |
| --- | --- | --- |
| 0 | 0.024–0.106 | 5.381–6.126 |
| 50 | 55.027–55.118 | 56.770–61.952 |
| 200 | 201.380–205.033 | 207.707–212.181 |
| 500 | 504.176–505.095 | 508.322–512.561 |

The delays are observable at the intended boundaries. Dispatch wait includes dedicated-thread scheduling and the deliberate thread sleep. Assessment wait includes the delay and active host event pumping, including an unconditional final pump even at zero requested delay. Neither is exclusively injected delay or exclusively OS scheduling overhead.

| Metric | Ordinary count | Minimum | Median | Maximum |
| --- | --- | --- | --- | --- |
| Evidence age at assessment | 16 | 59.222 | 62.276 | 81.214 |
| AX inspection, including trust and surrounding reads | 16 | 0.932 | 1.684 | 22.950 |
| AX publication-to-host receipt | 16 | 2.939 | 4.668 | 6.310 |
| Before receipt-to-parse completion | 16 | 17.601 | 18.666 | 19.202 |
| After receipt-to-parse completion | 16 | 16.926 | 18.996 | 19.666 |

The `beforeParsing`/`afterParsing` names overstate attribution. `wait(matching:)` timestamps a complete line when splitting it into the host buffer, then sleeps for 10 ms and enters another iteration's event pump before returning that line to `snapshot`. Only afterward does parsing/correlation complete. Thus these intervals include host waiting, event dispatch and parsing/correlation. They cannot establish that parsing alone costs about 19 ms, and subtracting a nominal sleep/pump duration cannot recover the missing parsing-entry timestamp. The full evidence-age measurements remain valid.

Maximum evidence age is 572.396 ms in dispatch and 577.300 ms in assessment. These include rejected observations and deliberate delays. The failed attempt supplies no evidence-age sample; invalidation has 15, not 16. With 16 metric samples, nearest-rank p95 is the maximum; with 15 samples it is also the maximum. These are descriptive measurements on one machine/run, without a tail guarantee. Overlapping intervals must not be summed into another total.

## Policy evaluation decision

Do not calibrate or select an age from this export. There are 22 reported historical acceptances and enough timing data to calculate age-only sensitivity, but the export omits the exact before/after source state, focused AX identity/interval and complete use contexts required to replay `FixturePairAssessment`. A comparison of age against a threshold would not be a full reducer evaluation. Unsupported/revoked/changed records must not become diagnostic acceptances merely because they are young.

Any numerical evaluation is deferred until a replayable dataset and accepted fresh recovery are available. A future evaluation record must name finite positive candidate ages and policy revisions **before its evaluation**, explain their diagnostic usability rationale, identify exact dataset hashes and included cohorts, and reconcile assessed, expired, rejected and absent-input counts. No candidate, default or production freshness limit is chosen here. The policy must retain earliest-before-start age, exact-boundary expiry, rejection precedence, replacement invalidation and no revival.

## Next source task — M2.35 attributed, replayable fixture timing

Extend the separate laboratory export, keeping production targets and mutation scope unchanged:

1. Version the timing envelope and retain each available validated schema-2 before/after snapshot using its existing bounded, content-free vocabulary. Retain the actual focused fixture identity and successful AX interval, captured/current host context including trust/Pause/stop, and enough ordered host events to replay the existing owner/reducer. The current constant `serial=1` is an expected identity, not a substitute for the observed focused identity. Failed stages remain absent. Reject malformed/unknown data without exporting arbitrary strings.
2. Add host timestamps for matching-line selection and parse/correlation entry. Keep complete-line receipt at its existing boundary. Report receipt-to-selection and parse-entry-to-completion separately, while preserving and accurately labelling the old receipt-to-completion interval. Validate the added boundaries, including partial failures, without reconstructing times by subtracting sleeps.
3. Add offline replay through the existing pure assessment/host values, with exact primary outcomes and context/sequence handling. Report fixed exclusion evidence from the exported snapshots; do not weaken guards or infer favorable missing fields to obtain a match. The original schema-1 dataset remains historical and is explicitly non-replayable.

Predeclare a new explicit run with the existing one-pair/one-physical-reader bounds, 64-attempt maximum, 16-attempt cohort maximum, 128-event maximum, 180-second deadline, five-second reader watchdog and 256 KiB output cap. Calculate the richer envelope's worst-case size before admission; if necessary, lower the declared ordinary/delayed cohort counts while reserving the 16 invalidation/recovery attempts below. Do not truncate evidence or silently raise the output cap. If the full episode schedule cannot fit, revise the declared schedule explicitly before running. Keep reserved terminal output and exact owned cleanup/drain behavior.

Use ordinary and delayed cohorts with rejection evidence retained. Replace the old 16-attempt invalidation schedule with a declared **eight episode/recovery pairs**: four Pause/resume episodes and three sheet reversals, each followed by one separately admitted fresh recovery pair; finish with the deliberate failed preflight and one fresh recovery pair. A recovery pair must be historicalConsistent with new request/sequence values and current context. Issue fixture activation/normalization only at declared setup/recovery boundaries, before admitting that new pair, and drain/pump callbacks there. Do not reactivate automatically inside a measured pair or repeat failed observations until acceptance. An unexpected activation or unsupported ordinary observation remains a recorded result; its missing acceptance makes that cohort unsuitable for calibration, even when collection itself completes.

Deterministic acceptance must cover outcome replay with omitted/malformed/wrong identity inputs, supported-state exclusion evidence, host invalidation ordering and recovery/no revival, independent line-selection/parsing timestamps, partial failures, and richer-envelope byte caps. Separately run native fixture acceptance showing delayed attribution, inspectable unsupported state, intended episode rejection and accepted fresh recovery. Record the first incomplete or unsuitable run as such; any separately declared rerun keeps its own hash and results. Numerical policy evaluation follows review of that dataset, not merely passing source tests.

## Verification and limits — 2026-10-11

The offline audit passed against the exact retained artifact and checked-in timing values. Compilation initially hit the sandbox's Swift module-cache restriction; the approved retry completed. This change retains the dataset and documents review/design only. No repository Swift behavior, GUI session, permission, fixture process or normal iTile artifact changed. Latest source/native verification remains M2.33's 227 passing tests and its recorded scoped run. No new platform acceptance or setter consent is claimed.

## M2.35 follow-up

[Attributed, replayable fixture timing](m2-fixture-timing-replay.md) implements the source task above with scoped native evidence. The original review and schema-1 dataset remain historical; new schema-2 records expose complete assessment inputs and separate parsing boundaries. Final-build suitability/incomplete results and earlier complete runs are retained separately. Numerical age evaluation is still deferred.
