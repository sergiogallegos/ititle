# M2.38 — Schema-3 attribution review and diagnostic-policy scope

**Status: offline attribution/coverage review complete; the original M2.39 contract below is now implemented in [the offline comparison](m2-fixture-age-comparison.md).** Reviewed [M2.37's three retained artifacts](m2-fixture-setup-records.md) against the committed lab, collector and replayer. Collection completion, expected phase results and observed stopping conditions remain separate. This review itself performed no new native collection or numerical policy evaluation.

## Evidence and build identities

M2.36–M2.37 were committed and pushed as `2045923`. All three manifests identify macOS 27.0.1 (26A434), native lab SHA-256 `786996305f5c51a85ef42952750ea680e10a60146d80bf5bf347223cdc0bed3b` and fixture SHA-256 `f0c69ed08d1953c1459ae8ab4f2a5506ae868cc406df6381305b2230c4247ad5`. The final verified replayer has SHA-256 `2d0e23800babbf7949ca71e642ac109554414745ceb4da1570e05d216f55f5e7`. Its later partial-record/failure guards were source-tested, without repeating native acceptance. The packaged fixture and final replayer hashes still match at this review.

| Dataset | SHA-256 | Bytes / lines | Replay and coverage decision |
| --- | --- | --- | --- |
| [Ordinary](evidence/m2-37-timing.jsonl), UTC 2026-10-12T17:39:12Z | `8cf5fef8d2e480eff1859b981c8c967ad370d2bb7c11091cf055e056ebdd70b1` | 96,256 / 59 | 28 attempts, 27 assessments, 1 failed preflight, 12 setups; complete, unsuitable, no first stop |
| [Controlled exclusion](evidence/m2-37-exclusion.jsonl), UTC 2026-10-12T17:40:08Z | `ad10ad96d7e27dbbc729332b84ded469fb68b705dc610f7c11735c3cf69546ea` | 94,207 / 53 | 28 attempts, 27 assessments, 1 failed preflight, 14 setups; complete, unsuitable by declared mode, no first stop |
| [Controlled setup exit](evidence/m2-37-setup-exit.jsonl), UTC 2026-10-12T17:41:00Z | `605232f61e7f78ba665b81f7eddddf7d2cc85618ecd08a9b660bc37da7dbc1cc` | 2,598 / 8 | Zero attempts/assessments, 1 failed setup; incomplete, unsuitable, first stop childExited |

The checked-in replayer again matches every recorded assessment and available summary. Both complete files exit 0 despite suitability=false; the valid controlled incomplete report exits 1 with firstStop=childExited. All three replay reports have summaryPresent=true; their source terminals have orderly=true and occupied=false. No admitted pair record is absent in these files. The controlled exit has no pair admissions; its zero absent count does not mean the unattempted 28-pair schedule ran.

### Primary outcomes by cohort

| Cohort | Ordinary dataset | Exclusion dataset |
| --- | --- | --- |
| Ordinary, indices 1–4 | 4 historicalConsistent | 3 historicalConsistent, 1 unsupported |
| Dispatch, indices 5–8 | 2 historicalConsistent, 1 contextRevoked, 1 unsupported | 4 historicalConsistent |
| Assessment, indices 9–12 | 3 historicalConsistent, 1 contextRevoked | 4 historicalConsistent |
| Invalidation, indices 13–28 | 8 historicalConsistent, 4 contextRevoked, 3 sourceChanged, 1 failed preflight | Same counts |
| Total | 17 historicalConsistent, 6 contextRevoked, 3 sourceChanged, 1 unsupported, 1 failed preflight | 19 historicalConsistent, 4 contextRevoked, 3 sourceChanged, 1 unsupported, 1 failed preflight |

In both complete runs the four Pause episodes reject, the three sheet reversals reject, the invalid-PID reader preflight fails, and every fresh recovery at 14/16/18/20/22/24/26/28 accepts. The preflight fault has a worker terminal envelope but no after snapshot or assessment; it is not a real IPC timeout. Exclusion attempt 1 has synthetic=true and scenario=tree-ordinary in both snapshots; fresh attempt 2 accepts after reset. Replay's two frontmost exclusions in ordinary mode and two each of synthetic/scenario in exclusion mode count source fields in two snapshots, not additional rejected pairs.

## Ordinary attribution: snapshots do not clear later revocation

Attempt 7/request 14, with 200 ms requested dispatch delay, acquired both snapshots at source revision 11/registry revision 2. Both exported supported ordinary fields and frontmost=true; the AX identity matches the original. The two delivered activation callbacks follow after.end and after complete-line receipt, before line selection/parsing and inputs-ready. They therefore occurred after acquisition and reader completion, rather than during the requested dispatch wait.

| Attempt / delivered event | After source end | After complete-line receipt | Before assessment entry | Host revocation |
| --- | --- | --- | --- | --- |
| 7: activate / unrelated | 19.228 ms | 13.281 ms | 11.658 ms | 0→1 |
| 7: deactivate / owned | 19.613 ms | 13.666 ms | 11.273 ms | 1→2 |
| 12: activate / unrelated | 297.287 ms | 291.271 ms | 237.399 ms | 4→5 |
| 12: deactivate / owned | 297.677 ms | 291.661 ms | 237.009 ms | 5→6 |

Attempt 8/request 16, with 500 ms requested dispatch delay, begins in the newer revocation-2 context. Both snapshots instead report frontmost=false, key=false and main=false, at matching source revision 15/registry 2. Its exact AX identity still matches. There is no new pending-pair callback; the fixed frontmost guard explains unsupported. A newer host context alone cannot establish ordinary source support.

Setup 3 before attempt 9 successfully normalizes/activates/settles. It records revocation 2→4, with owned activation and unrelated deactivation delivered while no pair is pending. Subsequent attempts 9–11 accept. Attempt 12/request 24 has matching source revision 21/registry 2 and frontmost=true in both snapshots. Its callbacks occur about 273 ms after inputs-ready, inside the requested 500 ms assessment delay, and revoke the result. Setup 4 before attempt 13 records the next owned-activation/unrelated-deactivation callbacks and revocation 6→8; fresh later recoveries remain accepted.

Direction and owned/unrelated relationship now locate the observed transition more precisely than schema 2. They identify neither the other application nor the physical trigger, user intent or complete OS event history. Observation timestamps describe callback delivery to this host. Favorable snapshots, a short evidence age and later recovery cannot override either rejection. The ordinary unsuitable outcome remains a primary result.

## Setup and first-stop coverage

All 12 ordinary setups finish at settle with done=127, and all 14 exclusion setups finish with their purpose's complete mask: 127 for ordinary preparation/reset/recovery, 7 for the separate exclusion preparation. Issued and correlated request counters match in every record; they refer to the last prior snapshot, since setup issues no snapshot request. All record pair/reader occupancy observations are false. Ordinary setup 3 and 4 retain their delivered revocation changes; other completed setups have equal start/end revocation. Successful stage bits record existing operations and selected acknowledgments/confirmation, not an independent source sample or a freshness renewal.

The compact record stores start/end and the last stage observation, not individual timestamps for every completed stage. It supplies ordered progress, not per-stage latency attribution. Admission checks are performed after setup in the lab's separate admissionChecks stage; they are not a bit in a completed setup mask. In these runs each required setup is followed by its declared pair admission. A future admission failure needs its own first stop, and setup completion alone cannot prove admission passed.

Controlled exit sequence 1 targets next index 1 with issued/correlated request 1, revocation 3 before/after and done=1. Only the occupancy check completed. NormalizationWrite then observes that the deliberately quit owned child is no longer running. Its first stop childExited is at `294780.8195635417`, between the failed stage's entry `294780.819546875` and setup end `294780.8195704584`. It records setup 1, zero completed pairs, no pending request and false pair/reader occupancy. No normalization acknowledgment, activation stage or pair is invented.

The unrelated activation, owned deactivation and owned termination precede that setup and carry no pending pair. The native mode deliberately requested owned-child quit; childExited records the later send precondition, not an EOF, failed pipe write or activation refusal. The first stop survives orderly cleanup. This validates one controlled setup failure, without establishing the physical cause of M2.35's older unrecorded stop or testing first-stop preservation under a second native cleanup/output fault.

The final ordinary pair ends 8.033292 seconds after runStart, with 171.966708 seconds remaining to collectionDeadline. Exclusion ends at 8.199406 seconds, with 171.800594 remaining. Controlled first stop occurs at 0.413860 seconds, with 179.586140 remaining. These are actual recorded monotonic boundaries, excluding later cleanup/export; they rule out collection-deadline expiry at those boundaries. The 180-second resource limit is not an evidence-age policy.

| Boundary | Observed in these native artifacts | Remaining scope |
| --- | --- | --- |
| Setup success and recovery | Normalization, activation acknowledgment/positive confirmation, settling; exclusion preparation/reset; eight fresh recoveries per complete run | Universal focus/activation guarantees, per-stage timing, unrelated applications |
| Setup failure and first stop | Controlled childExited at normalizationWrite, zero admissions, orderly cleanup | Explicit negative activation confirmation; missing acknowledgment/confirmation; live pipe/EOF faults; occupied setup |
| Reader terminal and occupancy | Successful reads, invalid-PID preflight, no occupied reader at terminal | Real IPC timeout/watchdog, late physical drain, no replacement under a native stall |
| Resource and export failure | Files stay within type/total caps; complete summaries and terminal output | Native observer/record/output overflow, actual output write failure, deadline stop, forced/nonzero cleanup |
| Host delivery | Owned/unrelated activation, owned exit, explicit lab Pause/resume | Unavailable relationship delivery; exhaustive event coverage; sleep/wake, display and further-machine coverage |

Deterministic M2.37 tests cover partial stages, first-stop preservation, bounds, malformed clocks/protocol, diagnostic-only preflight and physical slot retention. Those are source checks, not native acceptance of the remaining rows. Earlier desktop/permission evidence keeps its separately recorded scope; none is newly exercised here.

## Proposed M2.39 — Offline diagnostic-age comparison

Proceed with a bounded Foundation-only evaluator over the exact three schema-3 inputs above, using the existing validated replay and pure `FixturePairAssessment`/`FixtureDiagnosticAgePolicy` values. Setup/stop attribution is sufficient to interpret these records. Additional rare-failure native coverage remains open, but need not be manufactured to compare already recorded, complete historical observations. There is no new GUI experiment in this next task.

### Predeclared candidates

| Evaluation-local policy revision | Maximum age | Rationale |
| --- | --- | --- |
| 1 | 0.05 seconds | Compare against the smallest nonzero injected-delay scale |
| 2 | 0.1 seconds | Intermediate sensitivity between the 50 and 200 ms requested delays |
| 3 | 0.25 seconds | Compare a budget above the 200 ms requested scale, allowing for additional acquisition/delivery time |
| 4 | 0.5 seconds | Compare with the largest requested-delay scale, without equating it to full age |
| 5 | 1.0 second | Wider diagnostic comparison, independent of any measured maximum or percentile |

These are a fixed sensitivity grid, not proposed safe ages or an automatic selection rule. Revisions identify independent offline comparisons, not a live policy sequence. Retain a no-policy baseline. Do not add candidates after seeing expiration counts or select the most favorable result. Policy arithmetic uses actual assessmentEntry and before.start, never requested delay, wall-clock UTC, AX completion, receipt or setup end. Equality `now >= before.start + maximumAge` expires; nonfinite, nonadvancing or overflowing expiry is malformed. A policy cannot extend existing evidence or revive it after invalidation/policy replacement.

### Inputs, cohorts and unchanged primary outcomes

- **Ordinary dataset:** inventory all 28 attempts and the unsuitable terminal. Evaluate its 17 historicalConsistent pairs, separating ordinary (4), dispatch (2), assessment (3) and fresh invalidation recovery (8). Preserve the other 10 primary rejections and the failed reader preflight. All four attempts in each delay cohort remain in the denominator/inventory, including the unexpected rejections; do not report a filtered cohort as an entirely accepted run.
- **Controlled exclusion dataset:** inventory all 28 attempts and label the mode separately. Its 19 historicalConsistent pairs may have diagnostic-age comparisons, separately grouped as ordinary/reset (3), dispatch (4), assessment (4) and recovery (8). The unsupported synthetic pair, four revocations, three source changes and failed preflight are negative controls. Never pool this run into ordinary calibration statistics or remove its exclusion/suitability flags.
- **Controlled setup exit:** inventory its failed setup/first stop and incomplete terminal with zero attempted pairs. It contributes no latency, expiration denominator or successful comparison. Unattempted schedule entries stay unattempted.
- **Historical schema 1/2:** exclude from this evaluation. Preserve existing replay compatibility and retained outcomes; do not substitute an older suitable run for the schema-3 ordinary outcome. Native setup/cleanup, failed or missing pair endpoints and intentionally revoked/source-changing records do not supply successful age samples.

Validate exact input SHA-256, schema/bounds, original assessments/summary and terminal before evaluating anything. Record the evaluator's own build hash separately from the manifests' collection hashes. Do not rewrite source evidence or historical replay output. Keep original outcome, phase, terminal suitability and completeness beside each candidate result. Only a validated historicalConsistent pair may become diagnosticUnexpired or expired; prior rejection/failure/absence stays its primary result, with age comparison not applicable. Timing-invalid input never becomes an acceptance.

Use the existing pure reducer for the accepted-pair comparison after full host replay validates context, request/sequence and event ordering. An age-only subtraction is not a replacement for replay. Require candidate results to agree with exact finite expiry arithmetic while preserving reducer rejection precedence. Summaries reconcile every original attempt per dataset/cohort/candidate as diagnosticUnexpired, expired, original rejection, failed or absent; zero-admission control stays explicit. Report per-record age only when both validated endpoints exist. Do not combine injected delays into an ordinary percentile or claim tail guarantees from four samples per cohort.

### Bounded implementation and acceptance

Add a separate offline CLI path before trust/AppKit setup; it must launch no child and make no AX call. Keep input count at three, each input within the existing 262,144-byte/174-line schema-3 limits, and candidate count at five. At most 420 pair/candidate results exist (3 × 28 × 5; the stopped control actually contributes none). Bound the complete comparison output at 524,288 bytes, with fixed fields/categories, explicit dataset identities and a reserved incomplete terminal on resource failure. No arbitrary input text, paths, process names or errors enter the report. A rejected input, output breach or export failure cannot yield a partial comparison labelled complete.

Acceptance requires deterministic checks for exact expiry, candidate validity and finite arithmetic; rejection precedence even when a rejected pair is also old; malformed/unknown/hash-mismatched inputs; missing endpoints/unattempted counts; no-policy compatibility; cohort/control separation; per-record/summary reconciliation; output bounds; and no revival after expiry, policy replacement or newer host context. Run formatting and `scripts/verify` after Swift edits. Then evaluate each named artifact exactly once and retain the bounded comparison with dataset/evaluator hashes and full original flags. An unsuitable input is a labelled comparison input, not a task failure to fix through recollection. The report answers diagnostic usability only; selecting an age, claiming freshness for production or enabling setters requires separate work.

## Verification — 2026-10-12

All three SHA-256 identities and native/final build distinctions were checked. Offline replay matched the two complete outcomes and the expected exit-1 controlled incomplete report. An independent temporary Foundation audit reconciled per-cohort outcomes, every setup sequence/mask/request/occupancy observation, recovery indices, callback placement and monotonic deadline arithmetic. Committed source review checked callback relationships, existing setup operations, admission ordering, stop classification and cleanup/export boundaries. The latest source verification remains M2.37's 250 passing tests; this task changes documentation only. No new native acceptance or policy result is claimed. Next: the explicitly scoped M2.39 evaluator above.

## M2.39 follow-up

[The bounded evaluator and retained comparison](m2-fixture-age-comparison.md) implement that contract. Its five candidates were evaluated offline on the three exact inputs, without a new native run or selected age. Original outcomes and suitability/completeness/control flags remain unchanged; the original predeclaration above remains historical.
