# M2.37 — Bounded setup stages and first-stop diagnostics

**Status: source implemented and verified; scoped native setup, exclusion/recovery and controlled child-exit checks recorded.** Implements [M2.36's contract](m2-fixture-setup-diagnostics.md) in the separate laboratory. Timing schema 3 adds setup/stop diagnostics and preserves schema-2 replay. No diagnostic age policy or production eligibility/mutation scope is selected.

## Implemented values and adapters

`FixtureSetupRecord` retains one terminal value per declared setup boundary: checked sequence, next pair index/cohort/purpose, actual start/end/last-stage times, separate last-issued/correlated snapshot requests, start/end revocation, occupancy, last stage and fixed failure category. Its compact `done` mask records completion of the purpose's ordered stages. A submitted activation, a selected acknowledgment and a selected confirmation are distinct bits; an explicit negative confirmation retains its observed completion and activationRefused category. Unobserved later stages are absent from the mask. Setup records neither count as pairs nor release a reader slot.

Stages wrap the existing occupancy check, close-sheet or tree command write/acknowledgment, activation write/acknowledgment/confirmation and 100 ms event settling. The adapter does not add activation attempts, source requests or retries to obtain acceptance. Four cohort preparations and eight fresh-recovery preparations produce 12 records in ordinary mode. Exclusion preparation and reset add two, bounded at 14.

`FixtureFirstStop` latches the first fixed category/stage, observation time, optional setup/pending request, completed pair count and occupancy. It survives subsequent cleanup, drain, summary and record/output failures. Native adapters supply monotonic failure times; pure collector resource guards use an injected failure clock, with absent time retained when unavailable. Explicit activation refusal, stage/collection deadline, child/pipe/protocol/clock/counter failure, observer/resource cap, reader failure/watchdog and cleanup conditions remain distinct. Unknown cleanup does not imply forced termination. No arbitrary error text, paths, titles, keys, process names or PIDs enter these records.

The manifest captures the actual run initialization and collection deadline in the existing monotonic time base. These resource bounds do not provide a freshness policy. Delivered activation events now retain activate/deactivate direction and owned/unrelated/unavailable relationship. That relationship uses the existing owned child attachment/liveness and delivered public metadata; stopped/unavailable attachments remain unavailable. Neither direction nor relationship weakens host revocation.

The collector reserves first-stop plus terminal capacity before ordinary output. Schema-3 terminal counts distinguish admissions, written pair records and written setups. A pair lost to encoding/output is absent, never an invented successful record. A physical watchdog timeout keeps its slot until matching drain; collection cannot resume afterward. A diagnostic-only preflight before a successful manifest has zero pair attempts and no fabricated run/trust context. Failure to write the final output still returns failure; an in-memory stop is not proof of successful export.

## Replay and bounds

Schema-3 replay validates record types/caps, setup sequence/schedule/stage masks, request correlation and revocation against delivered events. It rejects missing setup prerequisites, unknown fields/categories, contradictory partial assessments and clock/order failures. It verifies the stored summary against every written pair. Fully observed pairs/events use a typed historical copy through the existing pure schema-2 host/reducer path. Typed copying preserves the original floating-point values; generic JSON numeric re-encoding is not used for that conversion.

An incomplete last pair and its later event tail remain diagnostics rather than claimed reducer acceptance. Replay processes the fully observed prefix and reconciles the remainder as absent. A missing exported summary stays explicitly labelled `summaryPresent=false`, even when available records can be summarized internally. Valid diagnostic-only preflight and controlled stop artifacts return incomplete reports, not favorable evidence. All four retained M2.35 schema-2 artifacts preserve their original outcomes, counts and completeness/suitability flags.

The implemented reservation, including newlines, is exactly **262,144 bytes**:

| Type | Count × per-record cap | Bytes |
| --- | --- | --- |
| Pair | 28 × 6,144 | 172,032 |
| Host event | 128 × 512 | 65,536 |
| Setup | 14 × 512 | 7,168 |
| Manifest | 1 × 1,280 | 1,280 |
| Summary | 1 × 15,104 | 15,104 |
| First stop | 1 × 512 | 512 |
| Terminal | 1 × 512 | 512 |
| Total | | **262,144** |

M2.36 proposed a 1,024-byte manifest and 15,360-byte summary. The richer manifest needs another 256 bytes of declared capacity, so implementation reserves 1,280/15,104 instead. This adjustment preceded native collection and preserves the total and pair evidence. Tested maximal counters/times/metadata fit the compact record caps. Every cap remains enforced; overflow stops collection without truncating fields. Schema 3 has a 174-line maximum. Existing 28-pair schedule, 128-event cap, five-second reader watchdog/drain, 180-second collection deadline and separate bounded owned cleanup remain unchanged.

## Run

Using the existing packaged fixture and effective CLI trust, explicitly run at most one of each declared mode:

```sh
swift build --product iTileSafetySnapshotLab
.build/debug/iTileSafetySnapshotLab --timing-run > /tmp/itile-timing.jsonl
.build/debug/iTileSafetySnapshotLab --timing-exclusion-run > /tmp/itile-exclusion.jsonl
.build/debug/iTileSafetySnapshotLab --timing-setup-exit-run > /tmp/itile-setup-exit.jsonl
```

The third mode declares `controlledSetupFailure=true`, quits only its owned child after baseline/manifest, waits at most three seconds with event pumping, then lets the first normal setup observe the stopped child. It launches no replacement and changes no permission. Its expected result is an incomplete artifact with childExited at normalizationWrite, zero pair admissions and orderly cleanup. This checks a controlled failure path, not native focus/permission failure.

Offline replay uses no trust/GUI session:

```sh
.build/debug/iTileSafetySnapshotLab --replay-timing docs/evidence/m2-37-timing.jsonl
.build/debug/iTileSafetySnapshotLab --replay-timing docs/evidence/m2-37-exclusion.jsonl
.build/debug/iTileSafetySnapshotLab --replay-timing docs/evidence/m2-37-setup-exit.jsonl
```

The last command prints the valid incomplete report and exits 1. Native collection also exits nonzero when expected phase acceptance fails, even if collection completes. Offline replay exits zero for complete internally matching artifacts; inspect `calibrationSuitable` separately. An unexpected observation remains its original primary result and does not invent a setup stop.

## Verification and recorded native scope — 2026-10-12

Final formatting and `scripts/verify` passed **250 tests**: 130 core, 65 platform, 55 fixture diagnostics, plus parser/plist/shell checks. Thirteen new tests cover each setup stage's success/partial failure, ordered masks, clocks and request correlation; first-stop preservation through cleanup/output failures; diagnostic-only preflight; maximal record and total reserves; exact physical drain/no revival; missing encoded pairs and contradictory partial results; unknown stage/sequence/deadline; both complete schema-3 schedules; unchanged schema-2 archives; injected failure clocks; and classification without invented causes. An initial test syntax error and a numeric conversion mismatch were corrected before passing verification. SwiftPM required the approved unrestricted cache/manifest context.

Exactly three native modes were run once each, all on macOS 27.0.1 (26A434) with the unchanged packaged fixture SHA-256 `f0c69ed08d1953c1459ae8ab4f2a5506ae868cc406df6381305b2230c4247ad5`. Their lab artifact was `786996305f5c51a85ef42952750ea680e10a60146d80bf5bf347223cdc0bed3b`, after 249-test verification. Final review then tightened contradictory-partial validation and failure/cleanup classification; 250-test verification produced `2d0e23800babbf7949ca71e642ac109554414745ceb4da1570e05d216f55f5e7`. The final replayer validates all seven retained schema-2/3 artifacts. No GUI experiment was repeated after that review, and no new native acceptance is claimed for the unexercised overflow/unknown-cleanup guards.

| Retained artifact | Manifest UTC | Bytes / setups / events | Observed results |
| --- | --- | --- | --- |
| [Ordinary](evidence/m2-37-timing.jsonl) | 2026-10-12T17:39:12Z | 96,256 / 12 / 16 | 28 attempts: 17 historicalConsistent, 6 contextRevoked, 3 sourceChanged, 1 unsupported, 1 failed preflight; complete, unsuitable, no first stop |
| [Exclusion](evidence/m2-37-exclusion.jsonl) | 2026-10-12T17:40:08Z | 94,207 / 14 / 8 | 28 attempts: 19 historicalConsistent, 4 contextRevoked, 3 sourceChanged, 1 unsupported, 1 failed preflight; complete, unsuitable by design, no first stop |
| [Controlled setup exit](evidence/m2-37-setup-exit.jsonl) | 2026-10-12T17:41:00Z | 2,598 / 1 / 3 | Zero pair attempts; incomplete, childExited at normalizationWrite; orderly, no occupied reader |

Ordinary dispatch attempt 7/request 14 and assessment attempt 12/request 24 were additionally contextRevoked. Dispatch attempt 8/request 16 exported frontmost=false in both snapshots and returned unsupported; its two source-field exclusions are preserved in replay. These observations correctly make suitability=false. All eight ordinary recovery pairs, indices 14/16/18/20/22/24/26/28, were accepted. There was no setup failure to latch in that run.

Exclusion attempt 1 retained the intended synthetic/scenario unsupported evidence; attempt 2 freshly accepted after reset. All four declared Pause episodes, three sheet reversals, deliberate failed reader preflight and eight fresh episode recoveries produced expected outcomes. All 14 setup records completed with correlated stage masks. This is separately labelled controlled exclusion, never a calibration cohort.

The controlled exit delivered an unrelated activation, owned deactivation and owned termination, all with no pending pair. Setup sequence 1 targeted next index 1, with issued/correlated request 1 and revocation 3 before/after. Its `done=1` records the successful occupancy check only. Normalization write then observed childExited; stop time `294780.8195635417` lies between last stage entry `294780.819546875` and setup end `294780.8195704584`. First stop retains setup 1, zero pairs and no physical/pair occupancy. Cleanup preserved that cause and ended normally. This supplies the exact failure-stage evidence missing from M2.35's incomplete setup; it does not retroactively establish that older failure's cause.

All three terminals report orderly=true and occupied=false. Every artifact replays its recorded results/summary with the final source, including the controlled incomplete outcome. No permission entry, user-window setter, desktop/display configuration or normal iTile artifact changed. Live refusal/acknowledgment timeout, pipe faults, real IPC timeout, sleep/wake and additional-machine coverage remain unaccepted by these runs; deterministic tests are not those native checks.

Dataset SHA-256 identities:

- Ordinary: `8cf5fef8d2e480eff1859b981c8c967ad370d2bb7c11091cf055e056ebdd70b1`.
- Exclusion: `ad10ad96d7e27dbbc729332b84ded469fb68b705dc610f7c11735c3cf69546ea`.
- Controlled setup exit: `605232f61e7f78ba665b81f7eddddf7d2cc85618ecd08a9b660bc37da7dbc1cc`.

## Next task

Review the schema-3 dataset attribution, observed setup/stop coverage and remaining native gaps. Keep the ordinary unsuitable outcome and the controlled incomplete result separate from passing expected checks. Explicitly scope any further fixture-only failure experiment or diagnostic-policy evaluation, naming exact artifact/build identities, included/excluded cohorts, candidate policies and rationale before evaluating them. No new run, numerical policy or setter consent follows automatically from these measurements.

## M2.38 follow-up

[The schema-3 attribution/coverage review](m2-fixture-diagnostic-policy-scope.md) now completes that task and specifies M2.39's bounded offline diagnostic-age comparison. The five candidates, exact dataset/build identities and included/excluded cohorts are predeclared; original unsuitable/incomplete and primary rejection results remain unchanged. No evaluation or new native run was performed by the review.
