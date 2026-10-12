# M2.35 — Attributed, replayable fixture timing

**Status: source implemented and verified; scoped native attribution/recovery observed, with final-run suitability and completion limits recorded below.** Implements [M2.34's next source task](m2-fixture-timing-review.md). The separate laboratory exports schema-2 timing evidence and replays it through the existing pure host/assessment. Freshness remains unmeasured and no numerical age policy is selected. Production targets, eligibility and mutation remain unchanged.

## Implemented evidence and replay

Each available before/after fixture snapshot is retained as its validated, bounded schema-2 protocol line. The timing envelope also retains the actual focused fixture identifier, successful AX interval, admitted/final host contexts including trust/Pause/stop, and phase. Expected identity is no longer substituted for the observed focused identity. Host events retain their resulting complete context and pending request. The manifest captures the initial context before attaching the timing sink; setup events after that point are exported, including events with no pending pair.

The envelope is **timing schema 2**, separate from the already-existing snapshot schema 2. Duplicate scalar revision/sequence/context metadata from the old envelope is replaced by complete values. Snapshot lines have a tighter 1,280-byte timing-export cap, while their underlying protocol retains its 4 KiB cap. Unknown snapshot fields and arbitrary identifiers cannot enter the exported evidence. Titles, keys, document paths and arbitrary errors are absent.

`FixtureTimingReplay` is Foundation-only. It bounds input bytes/lines and each record type, validates decoded values against canonical encoding to reject unknown fields, and rejects omitted required assessment evidence. It checks manifest/cohort/phase/delay identity, causal and cross-attempt timing, advancing snapshot request/sequence watermarks and nonregressing source revisions. It reconstructs host admission, events and completion in timestamp order, checks exact pending requests and captured/resulting contexts, and calls `FixtureDiagnosticHost`/`FixturePairAssessment`. Equal operation timestamps cannot prove ordering and are rejected. All assessed boundaries must exist. Failed-reader records cannot invent a successful AX sample, after snapshot or assessment.

Replay recomputes the complete timing summary and requires an exact match. Its output reconciles assessed, failed and absent attempts, primary assessment outcomes and fixed unmet snapshot requirements. Exclusion counts describe each available snapshot, so a field excluded in both before/after contributes two; these are not additional primary outcomes. Incomplete runs remain incomplete. The retained M2.33 timing schema-1 dataset returns `historicalNonReplayable`; no favorable inputs are synthesized for it.

## Parsing attribution

Complete-line receipt keeps its previous boundary at buffer splitting. Matching-line selection is now stamped when `wait(matching:)` removes that line. Parse/correlation entry is stamped immediately before `FixtureSnapshotConsumer.consume`; completion follows it. Failed parsing retains observed receipt/selection/entry without invented completion/source fields.

Schema 2 labels receipt-to-completion as `beforeReceiptToCompletion`/`afterReceiptToCompletion`, adds `beforeSelectionWait`/`afterSelectionWait`, and uses `beforeParsing`/`afterParsing` exclusively for parse-entry-to-completion. The schema change prevents confusing those last metrics with their schema-1 meanings. The host still sleeps and pumps events between receipt and selection; this task attributes that waiting without changing its scheduling behavior. Evidence age still starts at before.start and never resets at receipt or recovery.

## Declared bounds and experiments

The manifest declares **28 attempted pairs**: four ordinary, four dispatch, four assessment and sixteen invalidation/recovery. The two delayed cohorts each use 0/50/200/500 ms once. The sixteen invalidation attempts are four Pause/resume episodes, three sheet reversals and one deliberately failed PID-0 reader preflight, each followed by a separately admitted fresh recovery pair. Recovery requires historicalConsistent with new request/sequence values and current context.

Fixture activation/close-sheet normalization occurs only before each cohort and each recovery, before admission. Setup pumps events for a fixed 100 ms after activation confirmation, without retrying a measured pair until acceptance. The existing initial baseline check remains separate from the attempted-pair count. Only one pair and physical reader are admitted, with the existing five-second watchdog/drain and exact occupancy semantics. The overall collection deadline remains 180 seconds; owned cleanup/reader drain retains its existing separate bounded allowances.

Per-record byte caps, including newlines, reserve `28 × 6,144 + 128 × 512 + 16,384 + 1,024 + 512 = 255,488` bytes for pairs, events, summary, manifest and terminal. This fits the existing 262,144-byte output cap. Each cap is enforced during encoding; overflow stops collection, and terminal capacity remains reserved. No record is truncated to fit. Event count remains at most 128, cohort count at most 16, protocol buffering at most 8 KiB/512 lines, and artifact hashing at most 64 MiB per executable.

Terminal `complete` describes collection/cleanup. `calibrationSuitable` additionally requires all 28 declared phase outcomes, including all fresh recoveries. It means a dataset can proceed to a diagnostic-policy review, not that any age is safe or selected. Unexpected ordinary/recovery outcomes remain recorded; collection can complete with suitability=false. Native collection exits nonzero when expected phase acceptance fails. Offline replay exits zero for a complete, internally matching dataset even when suitability=false; callers must inspect that field.

The separately declared `--timing-exclusion-run` configures `tree-ordinary` before its first pair, deliberately producing fixed `synthetic=true`/`scenario=tree-ordinary` exclusion evidence. It clears that structure and activates the fixture before the second pair, then uses the same remaining episode/recovery schedule. Its manifest marks `controlledExclusion=true`, its first phase requires unsupported, and its dataset is always calibration-unsuitable. This is an attribution/recovery experiment, not a candidate calibration cohort.

## Run

With the existing packaged fixture and effective CLI trust:

```sh
swift build --product iTileSafetySnapshotLab
.build/debug/iTileSafetySnapshotLab --timing-run > /tmp/itile-timing.jsonl
.build/debug/iTileSafetySnapshotLab --timing-exclusion-run > /tmp/itile-exclusion.jsonl
```

The experiments launch only their own disposable fixture and refuse an existing fixture. They do not request/change trust, rebuild normal iTile, or relaunch the separate permission app. Repackage the fixture separately only when needed; the recorded checks reused M2.33's packaged fixture.

Offline replay requires neither trust nor a GUI/fixture session:

```sh
.build/debug/iTileSafetySnapshotLab --replay-timing docs/evidence/m2-35-timing-final.jsonl
.build/debug/iTileSafetySnapshotLab --replay-timing docs/evidence/m2-35-exclusion-final.jsonl
```

The incomplete second dataset prints a valid incomplete replay report and exits 1. Invalid inputs print only a fixed failure category; no raw file/error content is echoed.

## Verification and native records — 2026-10-12 UTC

Final `scripts/format` and `scripts/verify` passed **237 tests**: 130 core, 65 platform, 42 fixture diagnostics, plus parser/plist/shell checks. Ten new tests cover complete 28-attempt replay/eight recoveries, separate parsing attribution, validated Codable round trips, explicit unsupported/wrong-identity results, omitted/unknown/malformed/historical evidence, exact host event/context ordering and no revival, partial failed-reader stages, source/request/sequence watermarks, and richer-envelope/input bounds. Existing timeout occupancy and reserved closure tests also pass. SwiftPM initially hit the sandbox manifest restriction and passed on the approved retry; an initial formatting lint was corrected before verification.

All four actual datasets are retained; earlier complete results are not substituted for final-build outcomes. All runs used macOS 27.0.1 (26A434) and the unchanged packaged fixture hash `f0c69ed08d1953c1459ae8ab4f2a5506ae868cc406df6381305b2230c4247ad5`.

| Dataset | Manifest UTC | Bytes / events | Attempts and recorded primary results | Collection / suitability |
| --- | --- | --- | --- | --- |
| [First ordinary](evidence/m2-35-timing-first.jsonl) | 2026-10-12T01:09:41Z | 90,458 / 8 | 28: 20 historicalConsistent, 4 contextRevoked, 3 sourceChanged, 1 failed preflight | Complete / true |
| [First exclusion](evidence/m2-35-exclusion-first.jsonl) | 2026-10-12T01:10:33Z | 90,498 / 8 | 28: 19 historicalConsistent, 4 contextRevoked, 3 sourceChanged, 1 unsupported, 1 failed preflight | Complete / false by design |
| [Final ordinary](evidence/m2-35-timing-final.jsonl) | 2026-10-12T01:25:12Z | 91,498 / 12 | 28: 19 historicalConsistent, 5 contextRevoked, 3 sourceChanged, 1 failed preflight | Complete / false |
| [Final exclusion](evidence/m2-35-exclusion-final.jsonl) | 2026-10-12T03:20:25Z | 55,588 / 6 | 15: 12 historicalConsistent, 2 contextRevoked, 1 unsupported | Incomplete / false |

The first two used lab hash `32ce5da34b56f39a890d3e2468eb4279852a626835883c43a6a041a08ce12831`. After adding pure replay validation/tests, final verification produced lab hash `e1b30f586b6c104172228f21cf0aabc941c53525b1e28d14320a4cf141a4ded1`; the two separately declared final-build runs used that artifact. Native adapter/schedule behavior was unchanged between these builds. The final replayer validates all four artifacts and exactly reproduces every available primary outcome and summary; the final exclusion remains incomplete.

Final ordinary attempt 12/request 24, the 500 ms assessment delay, received two activation callbacks about 438.121/438.224 ms after inputs-ready and 72.525/72.422 ms before assessment. Its already-acquired pair was contextRevoked. Two additional activation callbacks with no pending request were delivered at the next cohort's setup. All four ordinary and dispatch observations and three remaining assessment observations were historicalConsistent. All eight final fresh recovery pairs, at indices 14/16/18/20/22/24/26/28, were accepted. Four Pause episodes and three sheet reversals rejected as intended; the preflight failure omitted successful/assessment stages. The extra assessment revocation correctly makes the complete final dataset unsuitable.

Final exclusion attempt 1 was unsupported with exported `synthetic` and `scenario` exclusions in both snapshots; attempt 2 freshly accepted after declared normalization. It also accepted the first Pause recovery at attempt 14. Two activation callbacks with no pending request followed attempt 15, and the run stopped before attempt 16 admission, with orderly cleanup and no occupied reader. Its export does not carry the exact setup stop category, so the failure's physical cause is unresolved. No full final-build exclusion-cohort completion or eight-recovery claim is made; the earlier exclusion run's completion remains separately identified.

In the final ordinary cohort, before-snapshot parse/correlation median was about **0.259 ms**, selection-wait median **18.037 ms**, and receipt-to-completion median **18.282 ms**. Ordinary evidence age was median **62.116 ms**, maximum **90.054 ms**. Dispatch/assessment maximum measured waits were about **505.166/510.646 ms**, respectively. These small, separately labelled cohorts describe this run only; each four-sample p95 is its maximum. They select no numerical age policy.

Dataset SHA-256 identities:

- First ordinary: `3bc1880856e4bbf1cd166a80afa3de2ef7cb7893b6e7df7ae62e97c89dc320b5`.
- First exclusion: `1c77f83f7aa88118b73291df803b27e345449f1a468f367f4c5af08c5a0b79df`.
- Final ordinary: `4e9ae23ddbc604887c7f2469ae5b948c94b61022769dbd73fc90efb377f5fc14`.
- Final exclusion: `12684183d1d1fbb85c7e8f833bfeff283d2ecb5ea2456beddec79687ab285511`.

Every recorded terminal reports orderly=true and occupied=false. No permission entry, physical desktop/display configuration, user-window setter or normal iTile artifact changed. Native IPC timeouts, permission episodes, sleep/wake, other machines and complete notification coverage remain outside these measurements.

## Next task — M2.36 dataset review and setup diagnostics scope

Review the schema-2 datasets' attribution/recovery and suitability, keeping their separate build identities and incomplete outcomes. Specify bounded, fixed setup/stop diagnostics for the final exclusion interruption before any new run; do not infer its cause from activation alone or rerun until acceptance. Any later diagnostic-age evaluation must declare candidate ages/revisions, exact included dataset/cohort hashes, exclusions and rationale, replay through the same guards, and retain unmeasured production freshness. No numerical policy or mutation proposal is selected here.

## M2.36 follow-up

[Schema-2 review and setup/stop diagnostic scope](m2-fixture-setup-diagnostics.md) completes that review and specifies the next M2.37 source task. It locates the missing recovery boundary without claiming a physical cause, proposes closed stage/stop records and reserves their bytes under the existing output cap. Those diagnostics remain proposed; the results above remain historical.
