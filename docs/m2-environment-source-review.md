# M2.44 — Callback-attribution review and live-child EOF scope

**Status: offline source/bounds review complete; the original M2.45 proposal is retained below.** Reviews [M2.43's source-only attribution](m2-environment-source.md). Callback identity is preserved in laboratory values and checked by schema-5 replay, with no native schema-5 collection mode. The selected boundary is an owned fixture's output-pipe EOF while the child remains alive. No new fault source or native run is implemented by this review.

The follow-up is now implemented and recorded in [M2.45](m2-fixture-output-eof.md). Binary identities in this review describe pre-M2.45 artifacts; the proposed declaration below records its original scope.

## Attribution and bounds result

The reviewed debug lab/replayer SHA-256 remains `47d2b8f5bb4b5489f38104eee715f1b3c85819fceec07dffc6d02426f6f0a8c1`. The inert `--self-check-environment-sources` again exits 0 with passed=true, synthetic=true and nativeCollection=false. Its early branch precedes trust sampling, application/monitor setup and fixture creation. Registration and callback dispatch use the same AppKit-name mapping checked by that command.

Source inspection confirms that all four closed sources reduce to the existing environment invalidation. Source/code and activation metadata are validated before normalization into historical replay; exact context/revocation/pending-work replay remains authoritative. Unknown/absent/null/mismatched source fields cannot substitute for an observed callback. Schema-5 events after the first stop are rejected, pair admission is disabled, and the control cannot claim complete or calibrationSuitable. Existing native modes deliberately omit source in schema-3/4 exports. Native source delivery therefore remains unaccepted; the inert mapping check does not post or receive notifications.

An independent compact-JSON audit recomputes conservative encoded bounds, including newline bytes. Environment event contexts use the full fixed identity, maximal counters and pending request, all-false booleans for the longest spelling, and a quoted 32-character clock placeholder. The manifest uses maximal counters, its required initial booleans, 128-byte unescaped OS metadata and two quoted clock placeholders.

| Reviewed upper bound | Bytes | Existing cap |
| --- | --- | --- |
| nativeSpace event | 399 | 512 |
| screenParameters event | 404 | 512 |
| willSleep event | 397 | 512 |
| didWake event | 395 | 512 |
| Schema-5 manifest | 1,189 | 1,280 |

These are conservative serialization bounds for the fixed fields, not measured native rows or valid clock samples. M2.43's Swift tests separately encode the actual values and check each cap. The existing reservation still sums to 262,144 bytes / at most 175 rows; no budget change is needed for source attribution.

All eight retained schema-2/3/4 archives replay with their original outcomes and expected exit codes. The M2.41 native control/preflight, separately packaged fixture, three M2.39 inputs and comparison report hashes remain unchanged. M2.35's first ordinary run alone retains its original suitable flag; later unsuitable/incomplete observations are not replaced. No native schema-5 artifact exists to review. M2.41's old environment callback remains unattributed, and no age or production safety provider is selected.

## Next failure boundary

Select **live-child output EOF during normalizationAck**. The adapter already maps a zero-byte `Darwin.read` to childEOF, independently of its childExited, pipeRead, pipeWrite and responseDeadline categories. M2.37's childExited occurred before normalizationWrite; M2.41's delayed acknowledgment instead exercised responseDeadline with a live child. Neither observes EOF from an otherwise living fixture.

This fault can be confined to the owned child's reply transport without manipulating user applications, permissions, displays or sleep state. It also exercises cleanup after the reply channel becomes unusable. Activation refusal, actual pipe read/write errors, a real AX watchdog, exhaustion, forced cleanup and sleep/wake remain separate checks. Another delayed-ack run solely to wait for an ambient environment callback would not close those boundaries or explain the historical event.

## Proposed M2.45 — One-shot owned-fixture output EOF

### Fault selection and observable facts

Add one explicitly invoked laboratory mode, proposed `--timing-setup-output-eof-run`, and a mutually exclusive fixture opt-in, proposed `--setup-output-eof-probe`. Require the existing safety/nested probe prerequisites. After successful initial activation and the baseline snapshot, submit one arm command. The fixture must arm at most once and consume the fault only after the next actual close-sheet operation. Ordinary commands must not consume it. Do not enable the acknowledgment-delay fault in this mode or rearm after consumption.

Use a fixed arming marker with actual fixture monotonic time and host receipt. Immediately before replacing the fixture's standard-output descriptor with `/dev/null`, emit one fixed selection marker with fixture time. Then redirect that descriptor using public Darwin APIs, release any temporary descriptor and suppress the normal close-sheet acknowledgment. Leave stdin and the main loop running so existing owned quit/input-EOF cleanup remains available. Redirecting subsequent fixture output avoids exceptions from later writes to an explicitly closed `FileHandle`. No additional reporting pipe or restored output channel is part of this experiment.

The selection marker is **intent before redirection**, not confirmation that redirection succeeded. Actual host read=0 plus a live-child sample establishes the observed EOF boundary. Do not invent a fixture completion marker or exact syscall-completion clock on a channel that has just closed. Check redirection failures and, when output is still available, report a fixed failure marker; preserve protocol/fault failure rather than claiming EOF from selection alone. Confirm descriptor ownership and cleanup against the installed SDK before implementing the adapter.

Distinguish host arm submission, observed fixture arming, host arming receipt, normalization submission, wait entry/actual response deadline, observed selection/receipt, actual read=0 and child liveness. Absent observations remain explicit nulls. A read error, EOF with a dead child, deadline, unexpected acknowledgment, malformed marker or earlier preparation failure must retain its actual category and evidence. EOF alone must never imply running=true.

### Versioned record and replay

Declare the new fault kind, proposed normalizationOutputEOFOnce, in a **schema-6** envelope. Schema 5 remains the existing acknowledgment-delay contract; adding an enum case must not make it accept the new fault. Reuse the reviewed environmentCallbacks contract and require closed source/code attribution on every schema-6 environment event. Do not require an ambient event to occur for the EOF control to be accepted. Validate metadata before historical host normalization as in M2.43.

Add a separate bounded EOF fault value under the single setupFault row, selected by the schema/manifest fault kind. Do not reinterpret the delay record's scheduled/due clocks as EOF clocks. Schema 6 has no injected delay; declare the unchanged five-second response bound without a six-second delay claim. The new manifest/terminal identify schema 6; embedded first stop stays schema 3 and fixture snapshots stay schema 2. Historical schemas 2/3/4/5 and their vocabularies remain strict. M2.39's exact input set and comparison stay intact.

The expected setup is sequence 1/next index 1, done=3, issued=correlated=1, failed at normalizationAck with childEOF. Capture the EOF observation and running sample at the failed read, before cleanup, and latch the first stop at that observation. Require exact fault/setup/stop linkage; expected live-child acceptance also requires the arming and selection markers and a first-stop clock before the recorded response/collection deadlines. A marker alone, a manifest declaration or a later process sample is insufficient. Preserve actual partial records if an earlier stage fails.

No pair or physical reader is admitted. Enforce zero attempts/records/occupancy independently in collector admission and replay. The terminal remains complete=false and calibrationSuitable=false even after successful cleanup or an unexpected acknowledgment. A successful acknowledgment must stop before activation/pair admission; it cannot turn this fault control into an ordinary run. Late callbacks, terminal export and cleanup failures must not replace the latched first stop or revive collection.

### Bounds and source acceptance

Keep the existing 180-second collection deadline, five-second response/reader/drain bounds, 28-entry declared schedule, 14-setup and 128-event limits, 512 input-event and 8,192 pending-line-byte bounds, and owned cleanup bounds of three seconds plus one second before the existing final kill fallback. Only the new explicitly invoked mode changes the fixture's stdout.

Reuse the 512-byte single fault-row reserve and 14,592-byte summary reserve, retaining 512-byte event/setup/stop/terminal caps, 1,280-byte manifest cap and the 262,144-byte / 175-row total. This is a proposed budget, not a proof for the unimplemented EOF value. Before any GUI launch, encode maximal new fault/manifest values, all source-bearing events and a worst-case envelope with newline bytes. If any cap fails, revise the declaration before native collection; never truncate or borrow closure reserve.

Deterministic checks must cover opt-in/prerequisites/mutual exclusion, one-shot arm/consumption, ordinary command and quit dispatch, canonical marker grammar, submission versus observed arming/selection, missing/duplicate/wrong/late markers, redirection failure, partial/null observations, finite/causal clocks, actual EOF versus EAGAIN/EINTR/read error/child exit/deadline, response/collection deadline precedence, exact setup masks/context/first-stop linkage, and no late admission/revival. Add an inert descriptor/pipe adapter check that observes real read=0 after writer replacement while a separate command input remains usable, without changing the verifier process's own stdout. Synthetic replay does not exercise that descriptor operation. Test caps, cleanup/export failure preservation and strict schema-2/3/4/5/comparison compatibility. Run formatting, `scripts/verify` and the inert adapter check first.

### Native declaration and stopping rule

Before any native invocation, build/hash the modified lab and separately packaged fixture and record effective existing CLI trust, exact OS/build, fixed bounds and output destinations. The M2.43 debug hash and current packaged fixture hash are review baselines, not identities for an unbuilt EOF experiment. Reserve proposed artifacts `docs/evidence/m2-45-output-eof-preflight.jsonl` and `docs/evidence/m2-45-output-eof.jsonl` before launch; do not overwrite older evidence.

Invoke the new mode **at most once** after its source checks and preflight. If trust is unavailable, retain the actual diagnostic-only preflight and stop without a fixture or permission change. If another boundary fails, retain that actual result and stop without retry, replacement child or ordinary/exclusion recollection. Expected exit is 1 with normalizationAck/childEOF, observed arming/selection, a live child at read=0, zero admissions and recorded orderly cleanup. Cleanup uses existing owned quit/input closure; an exit afterward does not prove which command or EOF path caused it, and no acknowledgment can be demanded from the redirected channel. Forced/nonzero cleanup remains an observed failure and cannot replace an earlier EOF.

This accepts only the scoped live-child fixture output-EOF/stage diagnosis and owned cleanup. No user-window setter, normal iTile rebuild, desktop/display action, sleep/wake operation, new Accessibility grant, real AX watchdog or generic production provider belongs to the experiment. Native callback identity is reported if callbacks arrive, with no retry to force coverage.

## Verification — 2026-10-21

Source review covered the source enum/name mapping, monitor callback/legacy sink, strict version/source/fault replay, reader failure mapping, fixture command/output dispatch and owned cleanup. Independent hashing checked eight artifact identities; compact-JSON arithmetic checked maximal event/manifest and total reserves. The inert mapping CLI passed, and all eight retained archives replayed with their expected incomplete/unsuitable flags and exits.

Documentation only in this step. Latest source verification remains M2.43's 275 passing tests; no source change, native run or failure acceptance is claimed. Local Markdown links and `git diff --check` passed. M2.42–M2.44 changes remain local; no commit or push was requested. Next: implement M2.45's one-shot EOF source/adapter checks and its single declared native control, retaining any unexpected result.
