# M2.33 — Bounded fixture timing collector

**Status: source implemented in the separate read-only laboratory.** The [M2.32 design](m2-fixture-timing-calibration.md) now has pure timing values, bounded collection and native adapters. No production target depends on these values, and no diagnostic age policy is selected. Pair assessment still receives no policy and reports historical consistency or rejection.

## Run and output

Build the existing packaged AX fixture and the standalone lab, then explicitly run:

```sh
scripts/package-ax-fixture
swift build --product iTileSafetySnapshotLab
.build/debug/iTileSafetySnapshotLab --timing-run > /tmp/itile-fixture-timing.jsonl
```

The lab requires effective AX trust under its existing CLI launch context and refuses an existing fixture. It does not grant permissions, relaunch the separate permission app, or rebuild normal iTile. It launches one owned fixture, reads its fixed identifiers, opens/closes only its own sheet and exercises laboratory Pause. Those fixture commands are separate from user-window setters.

`--timing-run` produces JSON lines only: manifest, fixed host events, terminal pair records, per-cohort summary and final cleanup/completion status. The manifest records OS/build, UTC, SHA-256 hashes of the actual lab and fixture executables, fixed bounds, unmeasured freshness and the deliberate failure probe. Titles, keys, document paths and arbitrary error text are absent. Ordinary lab text is suppressed in this mode. A failed preflight still emits an incomplete terminal report without creating a fixture.

There are exactly 16 attempted pairs per cohort in a complete run, at most 64 overall:

- Ordinary acquisition, with no injected delay.
- Dispatch delays cycling 0/50/200/500 ms on the dedicated thread before inspection entry.
- Assessment delays cycling those same values while the host continues pumping events.
- Invalidation: eight Pause/resume pairs during a pending assessment and seven sheet reversals between acquisitions. The last attempt uses invalid PID 0 for a fixed reader-preflight failure; it targets no process and makes no AX IPC call. It verifies that a failed inspection has an entry/exit/publication/receipt envelope without invented after-snapshot or assessment timestamps.

A sheet reversal can also deliver a host activation event; either contextRevoked or sourceChanged is accepted as rejection for that cohort and reported distinctly. Pause/resume does not revive the old pair. Subsequent attempts acquire new evidence. A transition after both snapshots remains a residual race; old source revisions do not reveal it.

## Timestamp placement and validation

`FixtureTimingRecord` and `FixtureTimingCollector` are Foundation-only values. Snapshot submission precedes the pipe write; write completion is captured immediately afterward. Complete-line receipt is captured when the bounded line is split from the buffer, before logging/parsing. Consumer correlation uses that receipt time. Source times come from the validated schema-2 record; parse completion follows consumption. Failed acquisitions retain whichever host boundaries were actually observed.

`OwnedAXIdentityReader` captures admission under its start lock. Inspection entry precedes the trust query and all AX work; exit follows the successful or failed inspection. Publication is stamped under the result lock before publishing the immutable result. The host captures matching receipt immediately after polling completion. The older successful sample's AX interval remains the pair reducer's input; the enclosing worker interval measures trust checks and other inspection overhead as well.

Inputs-ready follows both snapshot correlations and AX receipt. Assessment entry supplies the reducer's `now`, and assessment exit measures computation cost. Host invalidation events retain observation time, revocation and pending request. Pair records retain admitted and final context counters, opaque run/request/sequence/serial identity and both source/registry revisions.

All available causal boundaries are checked together, including partial failed records and monotonic progress between attempts. Source acquisition may begin before write completion; that valid ordering is explicitly tested. Nonfinite, negative, regressing or wrongly ordered times produce malformedTiming and stop the run. Missing intervals stay absent. Evidence age begins at before.start; receipt, recovery and assessment do not reset it.

Summaries contain counts by a single primary terminal outcome, plus each available metric's count/minimum/median/nearest-rank p95/maximum. Missing failure/timeout endpoints never become zero samples. Cohorts remain separate. With 16 attempts, p95 is the cohort maximum and provides no tail guarantee. Overlapping metrics must not be summed as an alternative total.

## Bounds and cleanup

The overall deadline is 180 seconds including startup; each reader has a five-second observation watchdog. Existing snapshot limits remain: five-second reply deadline, 8 KiB buffered bytes and 512 total protocol lines. Timing collection allows 64 pair records, 16 per cohort, 128 fixed host events and 256 KiB total structured output. Artifact hashing reads bounded chunks with a 64 MiB per-artifact cap. Output reserves 512 bytes for a final incomplete/cleanup record; terminal closure is idempotent and rejects subsequent output.

Only one pair and physical reader are admitted. Wrong terminal/drain identities cannot release the slot. A watchdog timeout records absent completion boundaries, stops collection and retains occupancy. Owned-child cleanup then precedes one bounded final drain attempt; no replacement reader is launched. Output exhaustion, invalid timing, observer overflow, protocol failure, deadline breach or forced cleanup produces an incomplete run. A complete exit requires orderly child cleanup, no stopped collector and no occupied reader slot. The existing monitor's callback coverage is still observed rather than complete.

## Verification and native acceptance

The deterministic timing tests cover independent attribution, acquisition before write completion, partial/nonfinite/regressing timestamps, cross-attempt clock regression, exact terminal/drain matching, retained timeout occupancy, attempt/cohort/event/output caps, reserved idempotent closure and missing-metric statistics. Existing lifecycle tests retain exact expiry, policy-change and revocation/no-revival checks. Native AX IPC timeouts, sleep/wake and scheduling across different machines remain separate acceptance.

Final `scripts/format` and `scripts/verify` passed **227 tests** (130 core, 65 platform, 32 fixture diagnostics), plus parser/plist/shell checks. An initial test compile error and a synthetic incomplete-record setup were corrected before final verification.

The final native dataset `/tmp/itile-m233-timing-final.jsonl` was collected on macOS 27.0.1 (26A434), manifest UTC `2026-10-09T23:11:54Z`, run `5497ABD4-0249-474E-A361-3A61F01FF511`. It contains 64 pair records, 18 host events, manifest, summary and terminal: **80,882 bytes**, below the output bound. The terminal reports complete=true, orderly=true and occupied=false.

| Cohort | Final recorded outcomes |
| --- | --- |
| Ordinary | 16 historical-consistent completions |
| Dispatch | 6 completions, 1 contextRevoked, 9 unsupported rejections |
| Assessment | 16 unsupported rejections |
| Invalidation | 8 contextRevoked, 7 sourceChanged, 1 deliberate failed preflight |

Two activation callbacks were observed during dispatch attempt 23, with the matching pair pending. Source revision changed 6 to 10 and the pair was revoked. Later unsupported results were retained; timing records do not identify the exact source flag behind that result or prove the physical cause of activation. The final dataset therefore does not demonstrate stable historical acceptance throughout the dispatch/assessment cohorts. Earlier exploratory builds collected stable completions, but they are not substituted for this final artifact's results.

All final timing envelopes passed causal and cross-attempt validation. Ordinary evidence age ranged about 59.222–81.214 ms. Maximum measured dispatch wait was about 505.095 ms; maximum assessment wait was about 512.561 ms. These maxima include injected delays and rejected observations, and select no age policy. The failed preflight retained admission/entry/exit/publication/receipt and omitted after acquisition and assessment boundaries. Pause and source reversal rejected all 15 intended invalidation pairs. There was no native IPC timeout or permission episode in this run.

SHA-256 identities:

- Dataset: `638703f093e716dec71958ced25e811ebcb0b78948de3ef01e233ecac136a9dd`.
- Final debug lab: `3130df82def468e98af5decb1a88d43c322588687a13f8181c7ce73f08e8f14f`.
- Reused packaged fixture: `f0c69ed08d1953c1459ae8ab4f2a5506ae868cc406df6381305b2230c4247ad5`.

The owned fixture exited normally. No permission entry, display configuration, user-window setter, normal iTile artifact or production eligibility changed. The separate temporary permission app was not relaunched.

## Next task

Review the bounded dataset and its attribution/rejection coverage. Define any additional fixture-only diagnostic policy evaluation explicitly, with dataset identity and rationale. No percentile automatically selects an age policy, and these measurements do not establish a production lease, generic supported-window safety or setter consent.
