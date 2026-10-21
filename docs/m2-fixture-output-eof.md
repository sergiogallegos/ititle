# M2.45 — One-shot owned-fixture output EOF

**Status: source implemented and verified; the single declared native EOF control is recorded below.** Implements [M2.44's bounded live-child EOF scope](m2-environment-source-review.md) in the separate owned-fixture laboratory. This tests transport/stage diagnosis and owned cleanup. Production safety, numerical freshness and window mutation remain gated.

## Implemented boundary

`--timing-setup-output-eof-run` selects timing schema 6. After the existing successful initial activation/baseline, it submits one arm command and starts setup 1. The fixture requires `--setup-output-eof-probe`, safety/nested prerequisites and no acknowledgment-delay opt-in. Both fault sources are disabled if both opt-ins are supplied. Pure `FixtureOutputEOFOnce` arms once and consumes only after the next actual close-sheet operation; other commands cannot consume it or rearm it.

Fixed arming and selection markers carry actual fixture monotonic clocks, with host submission/receipt recorded separately. The selection marker precedes descriptor replacement and records intent only. The new Darwin-only `ITileFixtureTransport` adapter checks and replaces the owned fixture's stdout with `/dev/null`, closes the temporary descriptor and suppresses that close-sheet acknowledgment. Later output can still be written to the redirected descriptor. Input and quit/EOF dispatch remain available. A failed replacement emits a fixed failure marker when possible, which stops as protocolFailure rather than claiming EOF.

The same descriptor helper is used by the fixture and an inert private-pipe check. It rejects invalid descriptors, stdin and stderr as targets. The check observes initial retry, bytes, actual read=0 after replacing a private writer, successful redirected writes and continued command-input exchange. It never replaces the verifier's standard streams or launches an application. The Foundation-only diagnostic target owns no descriptor or AppKit objects.

The host records EOF only from an actual zero-byte read, sampling child liveness there and latching childEOF at that observation before cleanup. EOF at or beyond the selected response boundary instead takes the deadline path. EAGAIN/EINTR retain retry semantics; other read errors retain pipeRead, and early child exit/write/deadline/marker failures retain their actual category. Liveness remains null unless a zero-byte read was captured; EOF with running=false is retained but cannot establish the declared live-child acceptance.

## Schema and replay

The schema-6 manifest declares normalizationOutputEOFOnce, environmentCallbacks and the unchanged five-second response bound; it carries no injected six-second delay. A separate `FixtureOutputEOFRecord` occupies the single setupFault row. Its explicit nullable fields distinguish submission, observed arming, arm receipt, normalization submission, actual wait entry/deadline, observed selection/receipt, EOF/liveness and terminal failure. The closed result progression is notSubmitted/submitted/armed/selected/eof. A selection marker alone never supplies EOF or liveness.

Manifest and terminal use schema 6, the embedded first stop remains schema 3, and fixture snapshots remain schema 2. Strict source/code and activation metadata validation precedes historical host normalization. This native mode exports source-bearing environment callbacks if any arrive; none is required for EOF acceptance. Schema 5 remains the acknowledgment-delay contract without a native collection mode. Historical schema-2/3/4/5 inputs cannot acquire the new fault or source metadata outside their original contracts.

Replay requires exact causal clocks, ordered partial setup masks, baseline request correlation, source/host context replay and setup/fault/first-stop linkage. An EOF fault can have no more than one setup and cannot advance past normalizationAck. Expected selected live-child EOF has setup=next=issued=correlated=1, done=3, normalizationAck/childEOF, zero pair/reader occupancy, and EOF before the recorded response/collection deadlines. Earlier failures and missing markers remain partial diagnostics. Late callbacks cannot revive collection or replace its first stop.

Schema-6 admission is disabled independently of the adapter and replayer. Attempts/records remain zero; complete and calibrationSuitable remain false even after orderly cleanup or an optimistic passed flag. Unexpected acknowledgment stops before subsequent activation/pair admission. Cleanup/export failures preserve the first observed stop.

## Bounds and verification

The reservation remains **262,144 bytes / at most 175 rows**, including newline bytes:

| Type | Count × cap | Bytes |
| --- | --- | --- |
| Declared pair capacity; zero admission | 28 × 6,144 | 172,032 |
| Host event | 128 × 512 | 65,536 |
| Setup | 14 × 512 | 7,168 |
| Manifest | 1 × 1,280 | 1,280 |
| EOF fault | 1 × 512 | 512 |
| Summary | 1 × 14,592 | 14,592 |
| First stop | 1 × 512 | 512 |
| Terminal | 1 × 512 | 512 |
| Total | | **262,144** |

Tests encode maximal manifest/source-event values, a conservative fault upper bound with quoted 25-character numeric placeholders and longest fixed result/category values, each synthetic row, and a completely filled non-closure reservation before adding the terminal reserve. The conservative fault bound is 501 bytes, within its 512-byte cap. Overflow rejects export without truncating or borrowing another reserve. Collection remains bounded to 180 seconds, five-second response/reader/drain bounds, 128 host events, 512 input events and 8,192 pending-line bytes. Owned cleanup retains three seconds plus one second before the existing final kill fallback.

Ten new deterministic tests cover opt-in/prerequisites/mutual exclusion; one-shot and ordinary-command selection; intent versus EOF/liveness; canonical/missing/wrong/late/regressing markers and failed replacement; real descriptor/read-result behavior; EOF versus child/read/write/protocol/response/collection/unexpected-ack outcomes; exact schema/source/clock/setup/stop linkage; explicit-null partial/preflight results; first-stop/cleanup/export/no-revival guards; and maximal per-row/total bounds. Existing historical archive, schema-5 synthetic and exact-input age-comparison tests remain intact.

`scripts/format` and `scripts/verify` pass **285 tests** (130 core, 65 platform, 90 fixture diagnostics), both inert adapter checks and existing parser/plist/shell checks. SwiftPM used the approved unrestricted manifest/cache context after macOS blocked its nested sandbox. An initial official lint finding in the new descriptor cleanup loops was corrected before the passing verification. No native invocation preceded source acceptance.

The new inert command, included in verification, is:

```sh
.build/debug/iTileSafetySnapshotLab --self-check-output-eof
```

It reports passed=true, synthetic=true and nativeCollection=false before trust/application setup. Its private-descriptor result is not live-child native acceptance.

## Native declaration

Reserved destinations are `docs/evidence/m2-45-output-eof-preflight.jsonl` and `docs/evidence/m2-45-output-eof.jsonl`; neither existed before preparation. The release build, packaged fixture signature verification and diagnostic-only [preflight](evidence/m2-45-output-eof-preflight.jsonl) completed before GUI launch. The preflight is 738 bytes / one row, SHA-256 `835662342f30e22c98b8415a917d8edfa0f633dea8281af20edd0d3f2b2df48c`, and records:

- Release lab SHA-256 `75c69ead3dffa255d77342312d379afc88beafc19cb9c107e67d88326d97a4fe`.
- Separately packaged fixture SHA-256 `686a858b1d9cc0d794c489fb8f97d3df4a7c8d6338088d28d2153dc5d6004218`.
- macOS Version 27.0.1 (Build 26A434), effective existing CLI trust=true at `2026-10-21T23:14:17Z`.
- Schema 6, normalizationOutputEOFOnce, environmentCallbacks, every fixed bound above, and invocationLimit=1.

A separate process check found no existing iTileAXFixture. Exactly one invocation of the new native mode is declared after this successful preflight. A controller exclusively creates the destination and a one-shot invocation marker, checks the preflight hashes/trust against the binaries and this declaration, and retains the actual output. Unexpected/preparation failures are retained without retry, replacement child, permission changes or ordinary/exclusion recollection. If trust had been unavailable, only diagnostic preflight would be retained, without a fixture.

Expected native exit is 1, with observed arming/selection, actual read=0 and running=true, setup 1/next 1/done=3 at normalizationAck/childEOF, zero admissions and recorded orderly owned cleanup. Cleanup uses existing quit/input closure; it does not demand a reply from the redirected channel or prove which exit path the child took. No physical display/sleep operation, user-window setter, normal iTile bundle rebuild or production provider belongs to this check.

## Native result

The single invocation exited **1**, as expected for a controlled incomplete run. Its [retained artifact](evidence/m2-45-output-eof.jsonl) is **2,218 bytes / six rows**, SHA-256 `2e4112f209997511b0f05f9cfcee2b868aec98c1f0fed5c5dc603343cd7b2fb1`. Manifest lab/fixture identities match the prelaunch declaration. Newline-inclusive row sizes are 983 manifest, 285 setup, 375 EOF fault, 249 summary, 165 stop and 161 terminal bytes; all fit their declared caps. The controller recorded no stderr output and performed no retry or replacement.

| Observed boundary | Monotonic seconds |
| --- | --- |
| Host arm submission | 715192.4648790833 |
| Fixture armed | 715192.4649304583 |
| Host arming receipt | 715192.4703319167 |
| Normalization submission | 715192.4881745834 |
| Actual wait entry | 715192.4881793751 |
| Fixture output-redirection selection | 715192.4882499584 |
| Host selection receipt | 715192.4933772084 |
| Actual read=0 / first stop | 715192.5112765834 |
| Actual response deadline | 715197.4881793751 |

The EOF fault has result=eof and running=true sampled at the zero-byte read. Wait entry to EOF is **23.097 ms**, leaving **4,976.903 ms** before its unchanged five-second response deadline and about **179.253 seconds** before collection deadline. Selection to host receipt is 5.127 ms; selection to EOF is 23.027 ms. These are rounded differences of observed monotonic clocks, including scheduling and host pumping; the selection marker supplies no exact redirection-completion time or transport latency guarantee.

Setup sequence/next index 1 retains done=3, issued=correlated=1, normalizationAck/childEOF, and revBefore=revAfter=0. The exact EOF clock links fault end and first stop, which precedes setup finalization by 0.021 ms. The initial activation/baseline had succeeded, but subsequent setup activation and all pair stages were unattempted. No pair or physical reader was admitted or occupied. All 28 declared pair entries remain unattempted; zero failed/absent pair records are not a completed schedule.

No host event rows were recorded; initial environment/revocation remained zero through setup. This run therefore adds no native callback-source delivery acceptance or explanation for M2.41's historical environment event. No ambient callback was required or forced.

Terminal records attempts=records=0, setups=1, occupied=false, orderly=true, complete=false and calibrationSuitable=false. The existing owned quit/input-closure cleanup returned orderly. The artifact does not identify which exit path the fixture took or timestamp child exit; no exact cleanup duration or post-redirection command acknowledgment is inferred. A separate process check found no remaining iTileAXFixture.

Both the exercised release replayer and verified debug replayer validate the retained incomplete childEOF report, summaryPresent=true, with exit 1. This is distinct from a replay parse failure. Final debug lab/replayer SHA-256 is `f16f96f2e909b7275bc356ae12cd6d565b848f13a19357ccf9464af82e2ea4ee`. No source changes followed the passing precollection verification; subsequent edits record results only.

The normal iTile bundle executable remains SHA-256 `bd8f2a7da660befa0b54b72064dc737daa3d8e5640eac835fc35fefadfe6a08a`. Retained M2.41 control and M2.39 inputs/report hashes are unchanged. An independent JSON/hash audit verifies exact causal clocks, deadline selection, setup/fault/stop/context linkage, zero occupancy, flags and every row cap.

This accepts only the scoped live-child fixture output-EOF/stage diagnosis and orderly owned cleanup. Activation refusal, actual pipe read/write errors, real AX watchdog/drain, exhaustion, forced cleanup and sleep/wake remain separately unaccepted by this check. No policy or production provider is selected. Next: review this retained EOF result and remaining failure coverage before declaring another bounded experiment. Changes remain local; no commit or push was requested.
