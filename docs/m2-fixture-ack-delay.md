# M2.41 — One-shot fixture normalization acknowledgment delay

**Status: source implemented and verified; the single declared native acknowledgment-timeout check is recorded.** Implements [M2.40’s scoped fault experiment](m2-fixture-age-review.md) in the separate owned-fixture laboratory. The experiment tests setup transport diagnosis and cleanup. Production eligibility, numerical freshness policy and window mutation remain gated.

The retained timeout, environment attribution limits and remaining failure coverage are now reviewed in [M2.42](m2-fixture-ack-review.md). Its source-only callback-attribution follow-up is implemented in [M2.43](m2-environment-source.md), without new native collection.

## Implemented boundary

The lab’s `--timing-setup-ack-delay-run` uses timing envelope schema 4. After the existing successful activation and baseline snapshot it submits exactly one `arm-setup-ack-delay` command. The fixture requires `--setup-ack-delay-probe`, `--safety-probe` and `--nested-probe`; the fault is otherwise disabled. `FixtureAckDelayOnce` accepts one arm and consumes it only after the next actual close-sheet operation. It cannot rearm, even after consumption. Other commands, snapshots and quit keep their ordinary dispatch. A main-queue timer defers only `close-sheet-ready` by six seconds; it does not block the fixture’s main loop or delay the real sheet operation.

Fixed `setup-ack-delay-armed` and `setup-ack-delay-deferred` markers carry the fixture’s actual monotonic arming/scheduling clocks and scheduled due time. The lab records host submission and receipt separately. Canonical marker grammar, finite causal clocks, one-shot correlation and exact six-second due arithmetic are required. Mode identity and a submitted arm do not establish observed arming or scheduling. Missing values are explicit JSON nulls in the single bounded `setupFault` record. Its result is the closed progression notSubmitted/submitted/armed/deferred, paired with the actual first-stop category and sampled child liveness at that stop.

Normalization retains the ordinary five-second response wait. A selected acknowledgment in this mode stops with unexpectedAcknowledgment at normalizationAck before completing that stage or entering activation. A missing response retains its actual responseDeadline, collectionDeadline, child/pipe/protocol/clock or other first failure. The adapter records that failure before cleanup and finalizes the partial setup; late markers cannot change the finalized fault or admit pairs. Schema-4 collector admission is disabled independently of the adapter. No retry, replacement child or additional pair schedule follows this control.

The manifest and terminal are schema 4; the embedded first stop remains schema 3, setup/event shapes remain schema-free and fixture snapshots remain schema 2. Strict replay checks version/configuration, explicit partial marker absence, causal clocks, one setup at sequence/next index 1, ordered partial masks, baseline request correlation, no pair/reader occupancy and exact setup/first-stop/fault linkage. A responseDeadline at normalizationAck requires a live child and at least the unchanged five-second wait, before the collection deadline. Observed scheduling is separate from a valid timeout diagnostic: a missing deferred marker does not become delay attribution. Schema 4 can never claim complete or calibrationSuitable, including if cleanup succeeds.

Schema-2/3 histories and M2.39’s exact three input hashes/results remain unchanged. The new controlled failure is not an age-comparison input. The normal iTile app has no dependency on the fixture diagnostics target and no production provider/admission integration is added.

## Bounds and verification

The reservation includes newline bytes and remains exactly **262,144 bytes**, at most **175 rows**:

| Type | Count × cap | Bytes |
| --- | --- | --- |
| Pair schedule declaration | 28 × 6,144 | 172,032 |
| Host event | 128 × 512 | 65,536 |
| Setup | 14 × 512 | 7,168 |
| Manifest | 1 × 1,280 | 1,280 |
| Setup fault | 1 × 512 | 512 |
| Summary | 1 × 14,592 | 14,592 |
| First stop | 1 × 512 | 512 |
| Terminal | 1 × 512 | 512 |
| Total | | **262,144** |

Pair capacity is retained in the declaration; this control must admit zero pairs. Schema 3 keeps its original 15,104-byte summary cap and 174-row bound. Schema-4 OS metadata is bounded to 128 printable ASCII bytes without JSON-escaped quote, slash or backslash; UTC is canonical 20-byte ISO 8601. Maximal counters, metadata and conservative quoted numeric placeholders prove the manifest/fault caps before native invocation. Existing pair/event/setup/stop caps remain tested. Overflow stops export without truncation or borrowing closure bytes.

Nine new deterministic tests cover opt-in/one-shot consumption, ordinary command/quit selection, submission/arming/scheduling/receipt distinctions, malformed/missing/duplicate/late markers, finite/regressing clocks, timeout versus collection/child/EOF/protocol outcomes, unexpected acknowledgment, ordered masks/linkage, zero admission/no revival, first-stop preservation through export/cleanup failure, diagnostic-only preflight and byte/row reserves. Historical archive replay and exact-input age-comparison tests also pass. `scripts/format` and `scripts/verify` pass **267 tests** (130 core, 65 platform, 72 fixture diagnostics), plus parser/plist/shell checks. SwiftPM requires the approved unrestricted manifest/cache context.

## Native declaration — 2026-10-17

Before any GUI launch, release build/package and the no-fixture `--timing-setup-ack-delay-preflight` recorded [the exact environment](evidence/m2-41-ack-delay-preflight.jsonl):

- Lab SHA-256: `6930f664a0fb482fe7c64b97024d59a58f07f4e9302b1d86f4227aaba4efab3c`.
- Separately packaged fixture executable SHA-256: `72062cc1dde8f16a636224fa5d4792993caef4ea568e41f8bd94492e8c0d094f`.
- macOS Version 27.0.1 (Build 26A434); effective existing CLI trust=true at `2026-10-17T16:49:39Z`. No permission changes are part of this experiment.
- Exactly one invocation of `--timing-setup-ack-delay-run`; ordinary/exclusion cohorts are not repeated.
- Six-second one-shot acknowledgment delay, unchanged five-second response/reader/drain bounds, 180-second collection deadline, owned cleanup of three seconds plus one second before existing forced termination fallback.
- All row/byte reserves above; 512 input events and 8,192 pending line bytes remain the existing pipe bounds.

The single declared invocation was assigned `docs/evidence/m2-41-ack-delay.jsonl` before launch. Expected observation is setup 1/next index 1 with done=3, normalizationAck/responseDeadline, issued/correlated baseline request retained, live child and zero admitted pairs/occupied readers. Expected exit is 1 with complete=false and calibrationSuitable=false. If preflight or another boundary fails, retain that actual result and stop without retry. Native acknowledgment-delay acceptance requires the observed scheduling marker, that exact timeout and recorded cleanup; mode identity alone is insufficient.

## Native result

The single invocation exited **1**, as expected for a controlled incomplete run. Its [retained artifact](evidence/m2-41-ack-delay.jsonl) has **2,452 bytes / seven rows**, SHA-256 `31babdbc0030e5039dbdca72cc79ab105b4b67b9731fa8548ae6e9d16dd5e7c6`. The separate preflight SHA-256 is `968ce11a17ebcc3e4a98ae179c8a2b55e0d708f0676d11d732ef68fbb346b713`. Manifest lab/fixture identities match the prelaunch declaration. Per-row bytes including newline are 961 manifest, 252 event, 295 setup, 362 fault, 249 summary, 172 first stop and 161 terminal; all fit their declared caps.

| Observed boundary | Monotonic seconds |
| --- | --- |
| Host arm submission | 496330.71629970835 |
| Fixture armed | 496330.716333375 |
| Host arming receipt | 496330.72160800005 |
| Normalization submission | 496330.73945050006 |
| Normalization wait entry | 496330.73945445835 |
| Fixture acknowledgment scheduling | 496330.7395390834 |
| Host deferred-marker receipt | 496330.74522425 |
| First stop | 496335.749912875 |
| Scheduled acknowledgment due | 496336.7395390834 |

The fault result is **deferred**, with running=true sampled at the first stop. Wait-entry to first stop is **5,010.458 ms**, with the scheduled due time still **989.626 ms** later. This is the observed bounded host wait, including loop scheduling, not a precise five-second real-time guarantee. The setup is sequence 1/next index 1, done=3, issued=correlated=1, last stage normalizationAck, failure=responseDeadline; activation and later stages were not completed. First stop links setup 1 at that exact stage/category/time with pairs=0, pairOccupied=false and readerOccupied=false.

One no-pending `environment` event at 496331.26121795835 advances environment/revocation from zero to one during the wait; setup revBefore=0/revAfter=1 preserves it. The existing monitor groups screen-parameter and sleep/wake notifications under this code. The artifact does not identify its physical cause, and it is not evidence that the experiment performed a display/desktop action. It neither replaces the transport timeout nor supplies an accepted pair.

Terminal records attempts=records=0, setups=1, occupied=false, orderly=true, complete=false and calibrationSuitable=false. The existing owned cleanup returned orderly; no forced-cleanup result is inferred or needed. The artifact does not timestamp child exit, so it does not claim an exact exit-before-due interval. Offline replay returns the same incomplete zero-attempt responseDeadline report, with summaryPresent=true and exit 1; that exit is distinct from a replay parse failure. No native retry or ordinary/exclusion recollection occurred.

After collection, final source review restricted the new unexpectedAcknowledgment category to schema 4 so schema-3 replay keeps its historical vocabulary. A ninth deterministic test replays this retained control and rejects that category in schema-3 history. Final formatting/verification passes 267 tests. These final pure replay/test guards were not followed by another native invocation; the collection identities above name the artifacts actually exercised. The final verified debug replayer SHA-256 is `40eb8bb4b3757a4baefe8fa8e4ab2da10d01ea14c837a9f7cfd66e940a30814e`; its CLI also validates this retained incomplete result. A separate process check found no remaining iTileAXFixture process.

This accepts only the scoped fixture transport/stage diagnosis and orderly owned cleanup. It does not test a real AX/IPC watchdog, native activation refusal, pipe/EOF failure, overflow, sleep/wake behavior or a production safety provider. M2.39’s report and its three input hashes remain unchanged; no age is selected. Next: review this retained timeout, environment attribution limits and remaining failure coverage before declaring another bounded experiment. Changes remain local; no commit or push was requested.
