# M2.39 — Bounded offline diagnostic-age comparison

**Status: implemented and verified; the scoped offline comparison is retained.** Implements [M2.38's predeclared scope](m2-fixture-diagnostic-policy-scope.md), with the existing pure assessment and the exact three schema-3 inputs. No policy was selected. Production freshness remains unmeasured and the mutation scope remains empty.

## Implemented boundary

`FixtureAgeComparison` is Foundation-only. Its file/crypto adapter is a separate laboratory CLI path, dispatched before trust checks or AppKit application setup. The adapter reads bounded files and computes SHA-256 with Apple's CryptoKit; the pure evaluator receives that digest operation. There is no child launch, AX call, activation, permission change or production dependency in this path.

The evaluator requires exactly one ordinary, exclusion and setupExit input, verifies their exact predeclared hashes, and runs full schema-3 no-policy replay on all three before constructing candidate results. Replay validates original assessments, contexts/events, timing, summary and terminal. Unknown/schema-2/hash-mismatched/malformed input cannot produce a successful comparison prefix. Collection build identities remain separate from the evaluator build identity.

Five fixed candidates retain the predeclared revisions/maximum ages: 1/50 ms, 2/100 ms, 3/250 ms, 4/500 ms and 5/1,000 ms. Each has an independent comparison; the report also retains a no-policy baseline. Only historicalConsistent pairs go through `FixturePairAssessment` with that candidate policy. Actual assessmentEntry and before.start supply `now` and the earliest acquisition origin. Expiry must be finite and advance the origin; `now >= expiry` expires, including equality. The pure result must agree with that exact arithmetic. No age origin is reset at receipt, AX completion or recovery.

Primary revocation, unsupported/source-change rejection, failed reads and absent inputs remain their original results, with ageResult=notApplicable and no invented expiry. A measured age may be reported for a rejected pair when both validated endpoints exist; it never changes that primary rejection. Missing endpoints remain absent. A missing encoded admission is accounted for separately from unattempted schedule entries.

Each candidate row retains original cohort, phase, requested delay, outcome/assessment and source completeness/suitability. A separate group separates invalidation episodes from fresh recovery. Inventories retain exact dataset/collection/fixture hashes, the original replay report, cleanup/occupancy, unattempted count and any failed setup/first stop. The stopped control has no pair/candidate rows or age samples. Every dataset/group has separate baseline and candidate summaries; no controlled data is pooled into ordinary measurements.

## Export bounds and failures

The report is buffered until all inputs/results/rows pass validation and caps. Every encoded row, including its newline, has a fixed cap. The worst-case reservation is:

| Type | Count × cap | Bytes |
| --- | --- | --- |
| Manifest | 1 × 1,024 | 1,024 |
| Inventory | 3 × 3,072 | 9,216 |
| Pair/candidate | 420 × 1,024 | 430,080 |
| Summary, including baseline | 108 × 768 | 82,944 |
| Terminal | 1 × 512 | 512 |
| Total | | **523,776** |

This fits the **524,288-byte** cap, at most 533 rows. Each of three inputs retains the existing 262,144-byte/174-line cap; five candidates and at most 28 admissions per dataset give at most 420 comparisons. Six groups (all, ordinary, dispatch, assessment, invalidation, recovery) × six policies (baseline plus five candidates) × three datasets give 108 summaries, including explicit zero control summaries. This is a capacity bound, not an assertion that the stopped control attempted 28 pairs.

The writer reserves 512 terminal bytes before appending ordinary rows. On validation, encoding or resource failure, the buffered prefix is discarded and only a bounded complete=false terminal with a closed category is returned. Arbitrary paths, raw protocol text, localized errors, process names, titles and keys are not exported. SIGPIPE is ignored in this offline mode; an actual stdout write failure exits 1 and is not claimed as a successful export. A complete comparison terminal describes evaluation/export preparation, not successful native collection in each source file.

## Run and retained identities

The input order is ordinary, exclusion, controlled setup exit:

```sh
scripts/format
scripts/verify
.build/debug/iTileSafetySnapshotLab --compare-diagnostic-ages \
  docs/evidence/m2-37-timing.jsonl \
  docs/evidence/m2-37-exclusion.jsonl \
  docs/evidence/m2-37-setup-exit.jsonl \
  > /tmp/itile-age-comparison.jsonl
```

The scoped CLI invocation was run once after verification, without a new native collection. It exited 0 and produced [the retained comparison](evidence/m2-39-age-comparison.jsonl): **126,350 bytes / 393 rows**, comprising one manifest, three inventories, 280 pair/candidate results, 108 summaries and one complete terminal. Tests exercise the pure evaluator separately; they are not additional native experiments.

- Evaluator executable SHA-256: `85be6afbf026faeb0d025a19c6c3a2200c1cbf7875a333c1362872ebf165ae4d`.
- Retained report SHA-256: `6a0746f029e5802d0c3d7e56147beee05b34fcc2353c4ef31ec5a352d17b8036`.
- Ordinary input: `8cf5fef8d2e480eff1859b981c8c967ad370d2bb7c11091cf055e056ebdd70b1`.
- Exclusion input: `ad10ad96d7e27dbbc729332b84ded469fb68b705dc610f7c11735c3cf69546ea`.
- Controlled exit input: `605232f61e7f78ba665b81f7eddddf7d2cc85618ecd08a9b660bc37da7dbc1cc`.

Every inventory still identifies native collection lab `786996305f5c51a85ef42952750ea680e10a60146d80bf5bf347223cdc0bed3b` and fixture `f0c69ed08d1953c1459ae8ab4f2a5506ae868cc406df6381305b2230c4247ad5`. The later M2.37 replayer identity remains historical; the evaluator's changed binary does not reattribute those native runs to a new build.

## Recorded results

Cells below are **diagnosticUnexpired / expired among original historicalConsistent pairs**. They are not accepted/attempted ratios or production safety results.

| Candidate | Ordinary, 17 original consistent pairs | Controlled exclusion, 19 original consistent pairs |
| --- | --- | --- |
| 50 ms | 0 / 17 | 0 / 19 |
| 100 ms | 6 / 11 | 5 / 14 |
| 250 ms | 16 / 1 | 15 / 4 |
| 500 ms | 17 / 0 | 17 / 2 |
| 1,000 ms | 17 / 0 | 19 / 0 |

Every ordinary candidate still accounts for **28 attempts: 17 comparisons, 10 original rejections and 1 failed preflight**. Every exclusion candidate still accounts for **28 attempts: 19 comparisons, 8 original rejections and 1 failed preflight**. Neither run becomes calibration-suitable. All candidates leave the controlled exit at zero attempts, incomplete source collection, one failed setup/childExited first stop and 28 unattempted schedule entries. Its zero expiration count is not a successful cohort.

### Ordinary dataset groups

The five result columns count diagnosticUnexpired only; remaining original consistent pairs expire at that candidate. Original rejected/failed attempts remain in each group inventory.

| Group | Attempts | Original consistent | 50 ms | 100 ms | 250 ms | 500 ms | 1,000 ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Ordinary | 4 | 4 | 0 | 4 | 4 | 4 | 4 |
| Dispatch | 4 | 2 | 0 | 1 | 2 | 2 | 2 |
| Assessment | 4 | 3 | 0 | 1 | 2 | 3 | 3 |
| Fresh recovery | 8 | 8 | 0 | 0 | 8 | 8 | 8 |
| Invalidation episodes | 8 | 0 | 0 | 0 | 0 | 0 | 0 |

Dispatch's two other attempts remain contextRevoked/unsupported; assessment's other attempt remains contextRevoked. Invalidation episodes retain four revocations, three source changes and the failed preflight. The ordinary 500 ms candidate has no expired historicalConsistent pair because the original 500 ms dispatch/assessment observations were already rejected. That does not establish that 500 ms accommodates the full delay schedule or is a safe age.

### Controlled exclusion groups

| Group | Attempts | Original consistent | 50 ms | 100 ms | 250 ms | 500 ms | 1,000 ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Ordinary/reset | 4 | 3 | 0 | 3 | 3 | 3 | 3 |
| Dispatch | 4 | 4 | 0 | 1 | 2 | 3 | 4 |
| Assessment | 4 | 4 | 0 | 1 | 2 | 3 | 4 |
| Fresh recovery | 8 | 8 | 0 | 0 | 8 | 8 | 8 |
| Invalidation episodes | 8 | 0 | 0 | 0 | 0 | 0 | 0 |

The deliberate synthetic/scenario unsupported pair remains excluded; fresh reset and all recoveries retain their original acceptance before the age comparison. The two historical pairs expired at 500 ms are the actual 500 ms dispatch/assessment observations, whose total evidence age includes other work as well. This is separately labelled controlled data, not additional ordinary calibration samples.

The candidate grid describes expiration sensitivity on these finite records. Four observations per delay cohort, one sample at each requested delay, deliberate invalidation/recovery, a single machine and remaining native failure/notification gaps provide no tail guarantee or evidence lease. An age cap cannot prove uninterrupted visibility, tab/dialog safety or complete invalidation delivery. No percentile or favorable count selected a policy.

## Verification — 2026-10-12

Final formatting and `scripts/verify` passed **258 tests** (130 core, 65 platform, 63 fixture diagnostics), plus parser/plist/shell checks. Eight new tests cover scoped hashes and unchanged baselines; exact expiry with adjacent representable times; primary rejection precedence; invalid policy/clocks, missing accepted inputs and nonadvancing/overflowing expiry; no revival after expiry/policy/context change; malformed/unknown/historical/hash-mismatched input; reserved all-or-nothing output; and incomplete/unwritten admissions versus unattempted counts. All 280 serialized comparison ages/expiries and summary counts are checked with typed floating-point decoding. SwiftPM required the approved unrestricted cache/manifest context.

An independent temporary Swift audit recomputed each retained age/expiry, checked original fields/flags, 280 unique comparisons, all 108 summary totals and the evaluator hash. Its initial numeric check used NSNumber bridging, which can change a final floating-point bit; direct typed decoding corrected that audit without changing the report. Separate offline CLI checks passed malformed arguments, input read failure, hash mismatch and closed stdout, all with exit 1 and fixed incomplete output where export succeeded. No new fixture, trust query, AX read, permission change or user-window action was exercised by these offline checks. The final executable hash still matches the retained manifest after the final report-precision test checks.

## Next task

M2.40 should review this comparison's diagnostic usability and limitations, including the different 500 ms results and primary rejections excluded from expiration counts. Keep every original unsuitable/incomplete/control flag and do not select a production age or repeat collection to favor a candidate. Explicitly scope any further fixture-only failure experiment or safety-provider work before implementation. Numerical selection and real mutation remain separate gates.
