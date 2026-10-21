# M2.42 — Acknowledgment-timeout evidence and failure-coverage review

**Status: offline evidence/source review complete; the original M2.43 proposal is retained below.** Reviews [M2.41's retained one-shot control](m2-fixture-ack-delay.md), committed as `671feb8`. The observed scheduling marker, live-child response timeout and orderly cleanup accept that scoped fixture transport check. The artifact remains incomplete and unsuitable for calibration. This review adds no native collection, selected age or production eligibility.

The source-only callback-attribution task is now implemented and verified in [M2.43](m2-environment-source.md), without native collection. The proposed contract below records its original scope; binary identities in this review describe the pre-M2.43 artifacts.

## Reviewed identities and replay

The retained files and currently available binaries match their recorded identities:

| Artifact | SHA-256 | Bytes / rows |
| --- | --- | --- |
| [Native control](evidence/m2-41-ack-delay.jsonl) | `31babdbc0030e5039dbdca72cc79ab105b4b67b9731fa8548ae6e9d16dd5e7c6` | 2,452 / 7 |
| [Prelaunch preflight](evidence/m2-41-ack-delay-preflight.jsonl) | `968ce11a17ebcc3e4a98ae179c8a2b55e0d708f0676d11d732ef68fbb346b713` | 669 / 1 |
| Final debug replayer | `40eb8bb4b3757a4baefe8fa8e4ab2da10d01ea14c837a9f7cfd66e940a30814e` | 2,063,072 / executable |
| Packaged owned fixture | `72062cc1dde8f16a636224fa5d4792993caef4ea568e41f8bd94492e8c0d094f` | 1,313,744 / executable |

The native manifest and preflight identify collection lab `6930f664a0fb482fe7c64b97024d59a58f07f4e9302b1d86f4227aaba4efab3c`, macOS 27.0.1 (26A434), and the same fixture hash. The later debug replayer is distinct from that collection binary; its successful replay does not establish another native run. Preflight trust=true is historical effective CLI trust at collection, not a current permission observation.

The existing offline CLI again returns a `replay` report with attempts=assessed=failed=absent=0, setups=1, firstStop=responseDeadline, summaryPresent=true, complete=false and calibrationSuitable=false. Exit 1 describes a valid incomplete source artifact; a parser rejection would instead return `replayFailure`. Zero failed pairs and zero absent records do not mean that the declared 28-pair schedule executed: all 28 entries remain unattempted.

All four schema-2 M2.35 archives and all three schema-3 M2.37 archives also replay with their original outcomes, completeness and suitability. The three M2.39 input hashes and retained comparison hash still match [the recorded comparison](m2-fixture-age-comparison.md). The schema-4 control remains outside its input set.

## Timeout, clocks and occupancy

An independent archive audit checks exact setup/fault/first-stop linkage, every row cap including newline, ordered clocks, context revisions and terminal accounting. Row sizes remain 961 manifest, 252 event, 295 setup, 362 fault, 249 summary, 172 stop and 161 terminal bytes. Each is within its declared reserve; the 262,144-byte / 175-row bound is unchanged.

| Derived interval | Observed value | Interpretation |
| --- | --- | --- |
| Fixture arming to host arming receipt | 5.275 ms | Delivery/host observation, separate from arm submission |
| Fixture scheduling to host deferred-marker receipt | 5.685 ms | The marker was observed before the timeout |
| Normalization wait entry to first stop | 5,010.458 ms | The unchanged five-second response bound elapsed |
| First stop to scheduled acknowledgment due | 989.626 ms | First stop preceded the declared six-second due time |
| Fixture scheduling to environment callback record | 521.679 ms | The callback was recorded during the wait |
| Environment callback record to first stop | 4,488.695 ms | Ordering alone does not establish a cause |
| First stop to setup finalization | 0.095 ms | Failure was latched before partial setup export |

These are differences of the retained monotonic timestamps, rounded for display. They include scheduling and host pumping where applicable and provide no latency bound beyond this observation. About 174.438 seconds remained before the collection deadline at first stop, so this is a responseDeadline rather than collectionDeadline.

Setup 1/next index 1 retains done=3, baseline issued=correlated=1 and last stage normalizationAck. The completed mask represents setupPrecondition and normalizationWrite. The subsequent setup activation stages were never completed; the separate initial activation and baseline had already succeeded before fault arming. The stop links that same setup, stage, category and fault-end clock. The fault result is deferred with running=true sampled at first stop. No pair or physical reader was admitted or occupied.

The terminal's orderly=true records the existing owned cleanup result. Source cleanup sends quit, closes input, pumps for up to three seconds, and uses the existing terminate/one-second/kill fallback if needed. This artifact records orderly completion without requiring that fallback. It does not record a child-exit timestamp or prove that the delayed acknowledgment was never emitted; it therefore cannot establish an exact exit-before-due interval. Late output cannot revive the finalized fault or admit pairs.

## What the environment event can establish

The one event at `496331.26121795835` has code=environment, no pending request, and environment=revocation=1 with activation=0. Setup revBefore=0/revAfter=1 preserves that invalidation. The callback occurred after observed delay scheduling and before the first stop.

The [laboratory monitor](../Sources/ITileSafetySnapshotLab/LabLifecycleMonitor.swift) maps native notifications as follows:

| Registered notification | Retained event code | Host reduction |
| --- | --- | --- |
| `NSWorkspace.activeSpaceDidChangeNotification` | nativeSpace | environment invalidation |
| `NSApplication.didChangeScreenParametersNotification` | environment | environment invalidation |
| `NSWorkspace.willSleepNotification` | environment | environment invalidation |
| `NSWorkspace.didWakeNotification` | environment | environment invalidation |

The retained code identifies the shared screen/sleep/wake branch, but it cannot distinguish its three registered notification names. No notification name, topology snapshot or physical cause was exported. It is not an observed nativeSpace callback. Neither statement rules out an unobserved physical event: callback delivery is incomplete evidence, and a screen-parameter callback would not itself prove a cable change, monitor count change or Space transition.

The monitor samples the clock on callback handling, reduces the event and exports the resulting context. This is a delivered callback observation, not the physical event's onset time. The response wait continues pumping after host invalidation; no pair exists to revoke in this control. Its stop still comes from the unmatched acknowledgment wait, with a scheduling marker establishing the deliberately delayed response. The record cannot show whether the callback affected scheduling or why it arrived. Repeating collection cannot recover the missing source of this historical event.

## Remaining failure coverage

| Boundary | Evidence available | Remaining limit |
| --- | --- | --- |
| Live child, missing normalization acknowledgment | M2.41 observed scheduled delay, responseDeadline, zero admission and orderly cleanup | Scoped transport/stage acceptance only |
| Owned child exit before normalization write | M2.37 setup-exit artifact, childExited, zero admission | Does not establish live-child EOF or a pipe read/write failure |
| Activation refusal | Stage/category source and deterministic setup/replay checks | No separately accepted native refusal control |
| Child EOF while alive, pipe read/write failure | Distinct adapter categories; synthetic replay cases include childEOF | No deliberately observed native transport failure |
| Real blocking AX request/watchdog and drain | Dedicated reader and timeout/drain source; separate earlier P3 scope | The fixture acknowledgment delay makes no AX call and accepts no new AX watchdog coverage |
| Observer/input/output exhaustion and forced cleanup | Bounded source and deterministic collector/replay checks | No separately accepted native exhaustion/forced-cleanup control |
| Sleep/wake and screen-change delivery | Registered callbacks; this artifact preserves only the shared environment code | No native sleep/wake sequence or physical-cause attribution |
| Production safety provider and admission | Existing empty supported mutation scope | No identity/visibility/lifecycle guarantee or live setter admission |

Deterministic replay can validate a supplied failure shape without exercising the adapter operation that would produce it. The native result closes only the first row's declared experiment. Historical Space/permission/display checks keep their separately recorded scope; this review does not expand them. Freshness remains unmeasured and the diagnostic-age grid still selects no policy.

## Proposed M2.43 — Preserve delivered environment callback identity

Choose a small source-only attribution task before declaring another native failure experiment. The present monitor knows which notification it receives and discards that distinction. Preserving that fact is useful for future failure reviews; it cannot explain this old event or establish complete event coverage. No new timeout collection is needed to check the mapping.

### Value and adapter boundary

Add a closed, content-free environment-source value in the Foundation-only diagnostics target: proposed cases nativeSpace, screenParameters, willSleep and didWake. Keep AppKit notification-name mapping at the laboratory adapter boundary. All four still reduce to the existing environment invalidation; callback identity does not change host authority, eligibility, admission or failure precedence.

Record the source on future environment event values alongside the existing callback-handling timestamp and resulting context. Require nativeSpace source with nativeSpace code, and one of the other three sources with environment code. Non-environment codes must not carry this field. Reject unknown or mismatched values instead of guessing from the current screen state. Preserve the existing activation direction/relation validation independently. Do not export arbitrary notification names, userInfo, application names, titles, paths or keyboard data.

### Versioning and bounded replay

Changed event rows require an explicitly versioned envelope. Scope a proposed schema 5 to a successor of the existing schema-4 diagnostic control, retaining its one-shot configuration, zero pair admission and incomplete/unsuitable result. Keep strict schema-2/3/4 readers and archives intact: historical environment rows have an unrecorded source, never a backfilled screenParameters or sleep/wake value. The new reader must require source on every schema-5 environment event, reject it on other event kinds, and preserve exact host context/revocation replay. Validate the source/code relationship before any internal normalization to historical replay.

Retain the schema-4 declaration's 128 events, 512-byte event cap, 175-row / 262,144-byte total and all other per-type reserves. Prove maximal source-bearing events with full identity/counters, pending request and finite clocks fit the existing cap, including newline. Keep manifest and terminal versioning consistent, embedded first-stop schema 3 and fixture snapshots schema 2. The manifest must identify the new event-source contract within its existing 1,280-byte cap. If maximal rows do not fit, revise the proposed budget before enabling any collection; never truncate or borrow closure reserve. M2.39's exact inputs/report and five candidates stay unchanged.

### Deterministic acceptance and stopping point

Test all four source/code mappings, unchanged invalidation/revocation and pending-work rejection, absent/unknown/mismatched sources, forbidden metadata on other events, activation metadata compatibility, nonfinite/regressing clocks, exact first-stop preservation and no late pair admission. Replay the retained schema-2/3/4 archives and test that historical rows cannot acquire source metadata. Synthetic schema-5 records must stay visibly synthetic and separate from native evidence.

Add an inert adapter self-check that maps the four actual registered notification names through the same mapping used by the callbacks and rejects an unknown name. It must run before trust/application setup, without posting native notifications, launching a fixture or changing the desktop. Pure value tests alone cannot verify the AppKit-name mapping. Run formatting and `scripts/verify` after Swift edits, then run that no-GUI adapter check. Confirm the bounds with maximal encoded values before considering a native mode.

The source task ends with deterministic value/replay acceptance and adapter mapping verification. Do not add or invoke a native schema-5 collection mode in that task. A later explicit experiment declaration must set its own purpose, build identities, output destination, invocation limit and acceptance conditions. An ambient run with no environment callback would leave native source delivery unobserved; it would not justify retries until a callback appears. Physical sleep/wake/display operations, pipe/EOF faults and real AX watchdog experiments each need their own declared check. This choice improves future evidence attribution without treating another GUI run as required to close M2.42.

## Verification — 2026-10-21

The tree was clean at `671feb8` before this review. Independent Python hashing/JSON arithmetic checked the retained control/preflight, final debug replayer, packaged fixture, three comparison inputs and comparison report. Exact causal/setup/stop/context linkage and every row cap passed. Offline CLI replay validated the schema-4 timeout plus seven historical schema-2/3 archives, preserving their expected exits and source flags. Source inspection covered callback registration/reduction, pumping, response/collection failure selection, first-stop latching, replay validation and cleanup.

Documentation only. Latest source verification remains M2.41's 267 passing tests; no new source test run or native collection is claimed. Local Markdown links and `git diff --check` passed. Next: implement the explicitly source-only M2.43 attribution scope above. Changes remain local; no commit or push was requested.
