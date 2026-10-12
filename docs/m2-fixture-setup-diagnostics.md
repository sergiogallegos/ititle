# M2.36 — Schema-2 dataset review and setup/stop diagnostics scope

**Status: offline review complete; the M2.37 implementation contract below is proposed.** Reviewed the four retained [M2.35 datasets](m2-fixture-timing-replay.md) and the committed laboratory control flow. No additional native run, numerical policy or production behavior is introduced. Full pair replay is implemented; setup failure attribution is the remaining gap.

## Reviewed evidence

The dataset SHA-256 identities match M2.35. The checked-in offline replayer again matches every available primary assessment and timing summary. Its complete/incomplete and suitability results remain separate:

| Dataset | Assessed / failed preflight | Fresh episode recoveries | Review decision |
| --- | --- | --- | --- |
| [First ordinary](evidence/m2-35-timing-first.jsonl) | 27 / 1 | 8 accepted | Complete, marked suitable; earlier build, four observations per ordinary/delayed cohort |
| [First exclusion](evidence/m2-35-exclusion-first.jsonl) | 27 / 1 | 8 accepted | Complete; deliberate exclusion, never calibration-suitable |
| [Final ordinary](evidence/m2-35-timing-final.jsonl) | 27 / 1 | 8 accepted | Complete, unsuitable after an additional assessment revocation |
| [Final exclusion](evidence/m2-35-exclusion-final.jsonl) | 15 / 0 | 1 accepted | Incomplete; 13 declared attempts were not collected |

The two earlier datasets use lab hash `32ce5da34b56f39a890d3e2468eb4279852a626835883c43a6a041a08ce12831`. The final datasets use `e1b30f586b6c104172228f21cf0aabc941c53525b1e28d14320a4cf141a4ded1`, matching the verified binary and committed source. The packaged fixture is unchanged, hash `f0c69ed08d1953c1459ae8ab4f2a5506ae868cc406df6381305b2230c4247ad5`. The earlier successes do not replace either final outcome. Missing attempts are absent, not failures with manufactured timestamps or zero latency.

### Final ordinary: post-acquisition revocation

Attempt 12/request 24 had matching source revision 13, registry revision 2 and original live membership in both snapshots. Both samples reported supported ordinary state, including active/visible/frontmost and no dialog, tab-count, hidden/fullscreen or armed-fault exclusion. Its recorded AX identity matched the expected original. The exported source fields themselves are not the reason for rejection.

Two activation callbacks arrived after both acquisitions, about 463.429/463.532 ms after after.end, during the requested 500 ms assessment delay. They changed host activation/revocation 0→1→2. Assessment followed about 72.525/72.422 ms later and returned contextRevoked. This demonstrates that favorable historical source fields do not override a newer host revocation; it does not identify the activating application, notification direction or physical cause. An age-only comparison must not turn this pair into an acceptance.

Two further callbacks with no pending pair were recorded at subsequent cohort setup. Fresh recovery at indices 14/16/18/20/22/24/26/28 was accepted under current contexts and new requests. These are scoped recovery results; they do not imply uninterrupted source state or complete notification coverage.

### Final exclusion: failure outside pair accounting

Attempt 1 explicitly exported `synthetic=true` and `scenario=tree-ordinary` in both snapshots and returned unsupported. Attempt 2 was freshly accepted after the declared structure reset/activation. The source evidence now explains this controlled exclusion; the old M2.33 unsupported results remain unexplainable from their omitted fields.

Attempt 14/request 28 was an accepted Pause recovery. Attempt 15/request 30 was the next Pause episode: its source revision remained 21 and its fixed fields were ordinary; host revocation advanced 2→4 through Pause/resume and it returned contextRevoked. The pair ended at uptime `286664.222502375`, with no physical reader or pair left occupied. Its after snapshot/request/sequence was 31.

Two activation callbacks with no pending request followed approximately **87.623 ms and 89.246 ms** after that pair's terminal boundary. They advanced activation 0→1→2 and revocation 4→5→6. No before snapshot, host admission or pair record exists for attempt 16. The terminal reports incomplete, orderly cleanup and no occupied reader. Neither event identifies the subsequent stopping condition.

Code review locates the next work in recovery setup before attempt 16 admission: occupancy precondition, close-sheet write/acknowledgment, activation write/acknowledgment/confirmation, bounded event settling, then the collection admission checks. The export lacks these stage boundaries and the caught error category. It cannot distinguish an explicit not-frontmost confirmation, acknowledgment timeout, pipe/child failure, deadline/resource stop or failed setup precondition. The callbacks may relate to setup or cleanup; their direction/relationship is absent. Do not label them as the proven cause of stopping.

The currently exported monotonic times also omit run initialization/deadline and setup/cleanup boundaries. A short interval between measured pairs is not proof of remaining collection budget. Wall-clock manifest UTC cannot substitute for those missing monotonic values.

## Policy evaluation decision

Keep numerical policy evaluation deferred. The earlier suitable flag permits a separately justified diagnostic review; it selects no age and proves no production freshness. The final ordinary data remains useful for attribution/rejection and its accepted ordinary/dispatch observations, while its extra revocation stays a primary outcome. The final exclusion provides explicit exclusion/fresh recovery evidence and a stopping gap; do not pool it with complete runs or treat its missing episodes as passed.

A future evaluator must name exact dataset/build identities, candidate ages/revisions and included/excluded cohorts, preserve primary rejection precedence, and reconcile absent attempts. Four observations per ordinary/delayed cohort, one sample per requested delay, one machine and deliberately delayed/rejected intervals supply no tail guarantee. Setup diagnostics should precede a new collection, rather than repeating the existing experiment until a suitable terminal appears.

## Proposed M2.37: bounded setup records and first stop

Implement separate Foundation-only diagnostic values and adapters in the existing lab. Version the timing envelope to **schema 3** because the manifest, record kinds, reserves and terminal interpretation change. Preserve schema-2 replay as a separate historical path; do not rewrite retained evidence or reinterpret its absent setup data.

### Setup record

Record one bounded terminal value for each existing setup boundary, including partial failure. Do not add requests, waits, activation attempts or observation retries to obtain a favorable result. Boundaries are the four cohort preparations, eight recovery preparations, and in exclusion mode the separate tree preparation and second-observation reset: at most **14** records. They do not count as pair attempts or acquire a physical reader slot.

Each record needs a checked diagnostic sequence, next attempted-pair index/cohort, fixed purpose, actual start/end times, separate last-issued and last-correlated snapshot requests, start/end revocation counters, occupancy observations, last reached stage, and fixed result/stop category. Issuing a request does not prove its reply was consumed. Run identity is bound by the manifest; do not repeat full snapshots/contexts here. Optional boundaries remain absent when not observed. Validate sequence, finite causal times, allowed stage progression and linkage to the declared schedule. A setup failure does not invent attempt 16 or consume an attempt slot.

Use a closed stage vocabulary covering:

| Stage | Boundary or observed result |
| --- | --- |
| setupPrecondition | Pair and physical-reader occupancy check |
| normalizationWrite / normalizationAck | Existing close-sheet command write and matching acknowledgment |
| exclusionWrite / exclusionAck | Existing tree-ordinary preparation and matching acknowledgment |
| activationWrite / activationAck | Existing activation command and activation-requested acknowledgment |
| activationConfirmation | Received activation-confirmed or activation-not-frontmost; absence stays absence |
| settle | Existing bounded event pump after confirmation |
| admissionChecks | Collection deadline, observer/output state and host admission checks before the next pair |

Capture a stage before its operation, and completion/result only when observed. Distinguish complete-line receipt, matching acknowledgment selection and source confirmation; a submitted activation request is not confirmation. A compact terminal setup record may retain completed-stage flags and the last stage instead of an unbounded event stream. Existing host events still carry actual revocation context. Setup values never clear host revocation, renew evidence or authorize a setter.

### Stop record and terminal

Latch **one first stopping condition** at its observation, before best-effort record export or cleanup. Later cleanup, drain, summary or output errors must not replace it. The record needs fixed stage/category, monotonic observation time, optional active setup sequence and pending request, last completed pair index, and pair/physical occupancy facts. Add monotonic run start and collection deadline to the schema-3 manifest, capturing the existing values rather than reconstructing them. Bound and validate their arithmetic; they are resource limits, not evidence age limits.

Closed categories must distinguish observed activation refusal; stage response deadline; collection deadline; child exit/EOF; pipe read/write failure; protocol/clock/counter failure; occupied setup; observer/record/output cap; reader failure/watchdog; forced/nonzero child cleanup; and unclassified failure. Map internal errors to these categories before formatting. Do not export localized descriptions, arbitrary error text, paths, process names, PIDs or unknown protocol lines. A timeout describes the host's expired wait, not the fixture's physical cause.

For activation events, retain a closed activate/deactivate direction and owned-fixture/unrelated/unavailable relationship derived from the delivered notification and the existing attachment. If attachment liveness/metadata is unavailable or stopped, keep the relationship unavailable rather than assuming PID continuity. Export no application identity beyond that relationship. This improves attribution without claiming exhaustive delivery or changing the revocation rule.

Reserve stop plus terminal bytes so an earlier output cap cannot erase the first stop. A valid preflight stop before fixture/manifest creation must have a bounded diagnostic result with absent run/context, zero pair attempts and incomplete/unsuitable status; it must not fabricate a trusted context or successful manifest. Replay must distinguish this diagnostic-only prefix from malformed data. Actual write failure can prevent export; never claim successful export merely because a stop was latched in memory.

Collection completion, expected phase acceptance, and cleanup remain distinct. If collection completes but a phase is unexpected, keep complete=true and suitability=false with the real assessment; this is not an invented setup failure. A forced cleanup, missing summary or diagnostic/output failure keeps the run incomplete. Physical timeout occupancy still survives until exact drain; cleanup and a later drain cannot revive the collection or launch a replacement reader.

### Proposed output reserve

Keep the 28-pair schedule, 128 host events and **262,144-byte** total cap. The new worst-case reservation, including newlines, is:

| Type | Count × per-record cap | Bytes |
| --- | --- | --- |
| Pair | 28 × 6,144 | 172,032 |
| Host event | 128 × 512 | 65,536 |
| Setup | 14 × 512 | 7,168 |
| Manifest | 1 × 1,024 | 1,024 |
| Summary | 1 × 15,360 | 15,360 |
| First stop | 1 × 512 | 512 |
| Terminal | 1 × 512 | 512 |
| Total | | **262,144** |

This lowers the summary cap by 1 KiB rather than increasing output or discarding pair evidence. The retained final ordinary summary uses 12,322 bytes including its newline; that observed size is not a future worst-case proof. Enforce every cap before appending and separately prove reserved first-stop/terminal closure. Compact encodings must fit their declared caps under tested maximal values; if the richer manifest/setup encoding cannot fit, revise the declaration before a native run. Never truncate fields, silently borrow reserved bytes or use an observed normal size as the bound. Update the line-count bound for the extra record types.

### Acceptance and next source task

M2.37 should implement these values, bounded collection, native stage adapters, schema-3 replay and tests before another GUI experiment. Deterministic acceptance must cover every stage's success/partial failure, wrong sequence/schedule linkage, simultaneous/regressing clocks, unknown categories, first-stop preservation across cleanup/output failures, deadline/confirmation distinction, stage and total byte caps, preflight without a manifest, and physical occupancy/no revival. Schema-2 replay of all four committed datasets must remain unchanged.

Separately declare at most one ordinary run, one exclusion run and one controlled owned-child exit/refusal check for native acceptance. Name each mode, artifact hashes, bounds and fault before running. The controlled check must establish the observed stopping stage and distinguish its deliberate fixture fault from a native focus/permission claim. Stop on the first incomplete run in each declared mode, retain its artifact, and review it rather than substituting a retry. Existing trust is required; no permission change, normal iTile rebuild, user-window setter or desktop/display operation belongs to this scope.

## Verification — 2026-10-12

M2.34–M2.35 source, tests, documentation and evidence were committed/pushed as `d483de5` to `origin/main` before this review. Retained artifact hashes and all four replay results were checked; the final exclusion's exit 1 is its expected incomplete result. Independent inspection correlated the final callbacks with exact pair boundaries and source/host fields. This is documentation/design work only. Latest source verification remains M2.35's 237 passing tests; no new native acceptance is claimed. The proposed diagnostics are not implemented. Next: the explicitly scoped M2.37 source task above.

## M2.37 follow-up

[Bounded setup-stage and first-stop diagnostics](m2-fixture-setup-records.md) now implement the contract with schema-3 replay and scoped native checks. The richer manifest reserves 1,280 bytes and the summary 15,104, preserving the total output cap; this revises the proposed split above. The original review remains historical. Numerical age policy and production eligibility remain unchanged.
