# M2.40 — Diagnostic-age usability review and acknowledgment-failure scope

**Status: offline comparison/source review complete; M2.41 below is proposed.** Reviews [M2.39's retained comparison](m2-fixture-age-comparison.md) after M2.38–M2.39 were committed and pushed as `86fc92c`. No candidate is selected, input recollected or production eligibility changed. The useful result is a bounded expiration comparison with preserved rejection precedence, rather than a freshness guarantee.

## Reviewed identities and accounting

The [126,350-byte / 393-row report](evidence/m2-39-age-comparison.jsonl) has SHA-256 `6a0746f029e5802d0c3d7e56147beee05b34fcc2353c4ef31ec5a352d17b8036`. Its evaluator hash `85be6afbf026faeb0d025a19c6c3a2200c1cbf7875a333c1362872ebf165ae4d` still matches the final verified executable. The report identifies the three unchanged source inputs:

| Input | SHA-256 | Original accounting |
| --- | --- | --- |
| [Ordinary](evidence/m2-37-timing.jsonl) | `8cf5fef8d2e480eff1859b981c8c967ad370d2bb7c11091cf055e056ebdd70b1` | 28 attempts: 17 historicalConsistent, 10 rejected/revoked, 1 failed preflight; complete, unsuitable |
| [Controlled exclusion](evidence/m2-37-exclusion.jsonl) | `ad10ad96d7e27dbbc729332b84ded469fb68b705dc610f7c11735c3cf69546ea` | 28 attempts: 19 historicalConsistent, 8 rejected/revoked, 1 failed preflight; complete, unsuitable by mode |
| [Controlled setup exit](evidence/m2-37-setup-exit.jsonl) | `605232f61e7f78ba665b81f7eddddf7d2cc85618ecd08a9b660bc37da7dbc1cc` | Zero attempts; one failed setup/childExited first stop, 28 unattempted entries; incomplete, unsuitable |

All inventories retain native collection lab `786996305f5c51a85ef42952750ea680e10a60146d80bf5bf347223cdc0bed3b` and fixture `f0c69ed08d1953c1459ae8ab4f2a5506ae868cc406df6381305b2230c4247ad5`, on the originally recorded macOS 27.0.1 (26A434). Neither the changed evaluator binary nor successful report export reattributes or completes a native run.

An independent typed Swift audit again reconciles all 280 pair/candidate rows, 108 summaries, original fields/flags, exact ages/expiries and evaluator identity. The same five predeclared candidates and original no-policy baselines remain intact. The complete comparison terminal describes the offline task; source collection flags remain separate. The stopped control supplies neither an expiration denominator nor a zero-latency sample.

## Why 500 ms behaves differently

The ordinary candidate results of 17 unexpired / 0 expired at 500 ms apply only to its 17 historically consistent pairs. They exclude two original 500 ms delay observations from age assessment because those observations were already rejected. The exclusion dataset retains both corresponding observations as historically consistent, and their total ages exceed 500 ms.

| Dataset / index | Requested delay | Measured dispatch wait | Measured assessment wait | Evidence age | Original assessment | 500 ms comparison |
| --- | --- | --- | --- | --- | --- | --- |
| Ordinary / 7 | Dispatch 200 ms | 205.105 ms | 6.410 ms | 266.682 ms | contextRevoked | notApplicable |
| Ordinary / 8 | Dispatch 500 ms | 504.774 ms | 6.414 ms | 572.976 ms | unsupported | notApplicable |
| Ordinary / 12 | Assessment 500 ms | 0.070 ms | 510.392 ms | 566.073 ms | contextRevoked | notApplicable |
| Exclusion / 8 | Dispatch 500 ms | 500.621 ms | 5.604 ms | 564.957 ms | historicalConsistent | expired |
| Exclusion / 12 | Assessment 500 ms | 0.113 ms | 511.007 ms | 566.962 ms | historicalConsistent | expired |

Evidence age is assessmentEntry − before.start. Dispatch wait is reader entry − reader admission; assessment wait is assessmentEntry − inputsReady. Requested delay does not include snapshot acquisition/delivery, scheduling or other host work. These component intervals are explanatory; do not sum overlapping metrics into a new total.

Ordinary attempt 7 is an important counterexample to age-only acceptance: at 266.682 ms it fits 500 ms, yet delivered host activation revoked it after both acquisitions. Of ordinary's ten primary rejections, **eight have ages below 500 ms**; all ten remain original rejections. All eight exclusion rejections also have ages below 500 ms and remain rejected. The failed reader preflight in each run is separately notApplicable with no assessment age. Thus the 500 ms notApplicable rows number eleven ordinary and nine exclusion; these are not additional expired pairs.

The 1,000 ms candidate leaves all 17/19 historical pairs unexpired, but clears none of those rejections or the stopped setup. Comparing only accepted-pair expiration would hide the ordinary run's focus/context outcomes. Retain every attempt in the inventory and preserve every source suitability/control flag.

## What the grid does establish

| Historically consistent group | Ordinary observed ages / sample count | Exclusion observed ages / sample count |
| --- | --- | --- |
| Ordinary / reset | 62.857–97.900 ms / 4 | 61.046–63.964 ms / 3 |
| Dispatch | 61.581–116.039 ms / 2 | 63.143–564.957 ms / 4 |
| Assessment | 60.754–265.986 ms / 3 | 63.356–566.962 ms / 4 |
| Fresh recovery | 113.589–117.398 ms / 8 | 112.841–119.219 ms / 8 |

These are descriptive ranges for original historicalConsistent pairs, not full-cohort latency distributions. The ordinary dispatch/assessment ranges omit rejected observations while their attempt counts remain four each in the report. Controlled exclusion data stays separately labelled. The groups cannot be pooled into an ordinary performance percentile.

On these records, 50 ms expires every historical pair; 100 ms preserves all original ordinary/reset pairs while expiring every fresh recovery. The recovery observations include the existing delayed assessment in the invalidation schedule; their larger ages do not by themselves show a slow recovery setup. Setup happens before before.start and is not part of the pair age. At 250 ms both datasets retain every fresh recovery, while deliberate delay observations still expire. These statements describe the fixed experiment, not a recommended policy.

The evaluator usefully separates age arithmetic from host/source rejection and handles exact expiry without new AX sampling. It supplies no provider for uninterrupted current-desktop membership, tab/dialog safety or notification completeness. The [supported-scope decision](decisions/0004-supported-scope.md) and [provider review](m2-provider-feasibility.md) therefore remain in force. One machine, four samples per delay cohort and one sample at each requested delay provide no tail guarantee, causal explanation for every scheduling interval or eligibility lease. No age is chosen for live diagnostics or production.

## Follow-up decision

Close the scoped offline comparison review without adding ages or repeating collection to obtain a suitable flag. The next source task addresses one explicitly unaccepted native failure boundary from [M2.38](m2-fixture-diagnostic-policy-scope.md): a missing setup acknowledgment while the owned child remains alive. M2.37's childExited at normalizationWrite and invalid-PID preflight are different failures; neither accepts the responseDeadline path at normalizationAck.

Use a deliberate asynchronous acknowledgment delay in the owned fixture. The existing `stall` command is guarded by `--slow` and blocks for only 1.5 seconds, whereas the normal laboratory response wait is five seconds. The timing lab does not pass `--slow`. Reusing that command would not establish the declared timeout; repeatedly stalling or shortening the ordinary wait would change the experiment. A dedicated one-shot diagnostic fault with an observed scheduling marker gives a bounded, attributable check while keeping the ordinary five-second wait.

Generic safety-provider work remains separate. This fault experiment tests transport/stage diagnosis and cleanup, not the missing production provider. Additional activation refusal, pipe/EOF, IPC watchdog/drain, overflow, sleep/wake and further-machine checks remain open. No setter, hotkey or arbitrary-application enrollment is included.

## Proposed M2.41 — One-shot normalization acknowledgment delay

### Source and protocol scope

Add one explicitly invoked laboratory mode, proposed flag `--timing-setup-ack-delay-run`, and one fixture-only opt-in/arming command. After the existing successful activation/baseline snapshot, arm a **single 6-second delay** of the next `close-sheet-ready` acknowledgment. Keep the real close-sheet operation and fixture main loop responsive; defer only that acknowledgment with a main-queue timer. Do not delay quit, other replies or ordinary-mode commands. Consume the fault once, with no rearm, retry or replacement child.

Require a fixed arming acknowledgment and a fixed deferred-acknowledgment marker, recording the actual fixture monotonic scheduling time/due time and host receipt. A submitted arm request is not observed arming; a manifest declaration is not proof that the fixture scheduled the fault. Preserve absent markers explicitly. NormalizationWrite should complete, then the existing five-second wait at normalizationAck should expire while the child remains running. A scheduling marker validates the deliberate delay's observed application, not a generic explanation for every timeout.

Version this changed timing envelope to **schema 4** rather than adding unrecognized fields to retained schema-3 files. Declare the closed fault kind `normalizationAckDelayOnce`, its 6-second delay and the unchanged five-second response bound in the manifest. Add at most one bounded `setupFault` record for actual arming/deferred-marker observations, including absent partial fields and fixed result/category. Version the manifest and terminal as 4; retain the existing schema-3 first-stop value as an embedded diagnostic, existing schema-free compact setup/event shapes and schema-2 fixture snapshots. No pair admission belongs to this control: attempts/records stay zero, with one failed setup when preparation reaches normalizationAck. If the acknowledgment unexpectedly succeeds, record a fixed unexpected-fault/protocol stop before admission instead of continuing the pair schedule. A preparation failure before that boundary stays its actual observed stage/category.

Schema-3 replay remains a strict historical path; do not rewrite its native inputs, M2.39 report or hashes. Extend strict offline replay to the new envelope, validating fault kind/configuration, finite causal clocks, marker correlation, ordered setup mask and exact first-stop linkage. Delayed-ack evidence must never become host/reducer acceptance. The existing exact-input age evaluator continues to accept only its three schema-3 hashes; do not enroll the new controlled failure into its comparison cohorts.

### Bounds and expected result

Keep the 28-pair schedule declaration, 14-setup limit, 128-event limit, 180-second collection deadline, five-second stage wait/reader bound and existing owned cleanup bounds. Reserve another **512 bytes** for the single fault record by lowering the schema-4 summary cap from 15,104 to **14,592 bytes**, preserving the total **262,144-byte** cap and existing pair/manifest/setup/stop/terminal caps. The envelope then has at most 175 rows. Prove maximal fault/manifest values and every per-type/total cap before a native invocation; if they do not fit, revise the declaration before collecting rather than truncating or borrowing closure bytes.

When the declared fault is observed, expected setup sequence 1/next index 1 has done=3 (occupancy and normalizationWrite complete), last stage normalizationAck, issued/correlated baseline request retained and failure responseDeadline. Latch that first stop at observation before cleanup, with zero completed pairs, no pending pair/physical reader and actual setup linkage/time. Do not synthesize confirmation or later stages. If collection deadline, child exit, EOF, protocol/clock failure or another stop occurs instead, retain that outcome without relabelling it as the expected timeout.

Quit only the owned child using existing bounded cleanup. Its responsive main loop should permit orderly exit before the delayed acknowledgment is due; actual orderly/occupied outcomes remain observations. Missing or forced cleanup keeps the artifact incomplete and must not replace responseDeadline if that was the earlier stop. A late marker/acknowledgment cannot revive collection or cause a pair admission. This experiment is a fixture response timeout, not a real AX/IPC watchdog test or a native activation/permission failure.

### Acceptance and native declaration

Implement source and deterministic checks first, then run formatting and `scripts/verify`. Tests must cover opt-in/one-shot behavior; exact arming versus scheduling versus receipt; ordinary command/quit behavior; wrong/missing/late markers; finite/regressing clocks; timeout versus collection deadline/child failure; ordered partial masks; first stop surviving cleanup/export failure; byte/row reserves; no late admission/revival; and unchanged schema-2/3 replay and exact M2.39 evaluator inputs/results.

Before any GUI launch, build and record the exact lab and separately packaged owned fixture SHA-256 identities, effective existing CLI trust, OS/build and bounds. The existing fixture hash above is a historical baseline, not the future modified artifact's identity. This review cannot name an unbuilt binary's hash. Run **at most one** invocation of the new declared mode after those identities/checks are concrete. Retain its bounded output and hash, even if it fails preflight or stops at an unexpected boundary. Expected native exit is nonzero with complete=false and calibrationSuitable=false; the controlled timeout is an observed acceptance check, not a complete calibration run. Do not substitute a retry, rerun ordinary/exclusion cohorts, expand candidate ages or change permissions to obtain the desired outcome. No user-window setter, desktop/display operation or normal iTile rebuild belongs to this scope.

If trust is unavailable, export the actual diagnostic-only preflight and stop without launching a fixture. If arming/deferred-marker observation fails, keep that absence and first stop; do not claim deliberate-delay attribution from mode identity alone. Native acknowledgment-timeout acceptance requires the observed marker, normalizationAck responseDeadline and recorded cleanup. Wider failure/provider coverage is still separate after this check.

## Verification — 2026-10-12

M2.38–M2.39 were committed/pushed as `86fc92c` to `origin/main`; local and remote-tracking refs matched and the tree was clean before this review. Report, three input and evaluator hashes match. The independent typed audit reconciled all retained rows/summaries/flags; an additional typed review recomputed the delay/age examples, historical-only ranges and below-500-ms primary rejection counts above. Source inspection checked evaluation precedence, original wait/cleanup bounds and the existing stall command's actual guard/duration.

Documentation only. Latest source verification remains M2.39's 258 passing tests; no native collection, policy selection or new fixture behavior is accepted by this review. Local links and whitespace checks passed. Next: implement the explicitly scoped M2.41 source/fault experiment above. These review changes remain local after the requested push.
