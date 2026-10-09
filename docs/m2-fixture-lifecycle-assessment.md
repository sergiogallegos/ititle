# M2.29 — Owned-fixture lifecycle assessment

Status: schema-2 source authority and pure read-only assessment implemented, with scoped owned-process transition acceptance. This implements the source/value subset of [M2.28](m2-fixture-lifecycle-contract.md). Production mutation scope remains empty.

## Implemented boundary

The Foundation-only `ITileFixtureDiagnostics` module now owns checked source revisions, a maximum-eight live serial registry, host context/revocation values, and a bounded pair reducer. Production targets do not depend on this module. There is no setter, enrollment, eligibility projection, or lease.

The fixture and lab now exchange schema 2 by default under `--safety-probe`. The parser also retains schema 1 for historical diagnostics; the lifecycle reducer rejects it. Schema 2 adds positive state/registry revisions, sorted unique live serials (`none` for empty, `unavailable` for uncertainty), original membership, closed coverage and uncertainty codes. Exact field sets and canonical bounded lists are enforced.

Every recognized state-changing command conservatively advances state before intent, including safe no-ops. Owned creation allocates a monotonically increasing serial; retirement removes membership before explicit close/end-sheet, and delivered close also retires it. Removed window observations are unregistered. The bounded registry is independent of AX enumeration. State advances before fault consumption, relevant delivered own-window/application/Space/display/sleep callbacks, or differences in sampled fixed state and private frame signature. Repeated stable snapshots do not themselves advance it. Exhaustion/registry uncertainty closes publication to favorable assessment; cleanup still removes owned membership. No unbounded tombstones are retained.

Coverage is always `observedEventsOnly` in the adapter. Controlled commands are covered, but equal revisions cannot prove every external event was delivered or detect an unobserved reversal. The main-thread snapshot does not freeze WindowServer or provide continuous safety.

The reducer retains one pending pair and one current result. New work immediately replaces the old result with `incomplete`. Before/after requests bind to the pending before request and its exact successor; sequences must advance above the retained watermark. It checks exact run/focused identity, bracketing finite intervals, receipt time, source/registry revisions, complete live membership, fixed state equality, known flags, source uncertainty, faults and declared coverage. Snapshot state describes **original serial 1 only**; peer/tab identities are membership diagnostics and cannot receive original-window state assessment.

Results distinguish wrong run/window/request, stale, revoked context, changed source, retired, malformed, incomplete and unsupported evidence. Stable accepted pairs are `historicalConsistent`, with unmeasured freshness. No age policy is selected. Optional synthetic policies are value-test inputs: finite positive maximum age and positive revision, earliest-before-start expiry, advancing finite arithmetic, exact-boundary expiry, wrong-policy and clock-regression rejection. Rejected current assessments cannot revive.

`FixtureHostAuthority` advances checked host revocation on observed updates, with separate environment/activation revisions, trust, Pause and terminal stop. Pause/resume or trust restoration changes generation. Host counter exhaustion closes the authority. The reducer compares exact captured/current contexts; callers can immediately clear pending/current work through `invalidate()`. These are pure laboratory values, **not a wired native host notification coordinator**. The standalone pair checks current child liveness/trust at receipt, while the fixture records source callbacks. Full host-side in-flight Space/display, permission, Pause and process replacement delivery remains the next task; value tests are not acceptance of those native events.

## Reproduce

```sh
scripts/package-ax-fixture
swift build --product iTileSafetySnapshotLab
.build/debug/iTileSafetySnapshotLab --lifecycle-run
```

This mode uses the existing dedicated-thread, bounded AX identifier reader against its own child only. It requires existing effective reader trust and never prompts for or changes permission. It includes the prior snapshot/identity scenarios, then checks registry recreation and stable/tab-reversal/sheet-reversal pairs. Only the disposable fixture opens/closes its own windows/tabs/sheets. Existing bounds and exact owned-child cleanup remain those of [the snapshot lab](m2-fixture-safety-snapshot.md); no timing constant becomes an evidence age policy.

## Validation — 2026-10-09

Formatting and `scripts/verify` passed **213 tests**: 130 core, 65 platform, 18 fixture diagnostics, plus the recovery parser self-check. Eleven new lifecycle tests cover registry reversal/recreation, stable sampling, inactive-tab membership independence, canonical lists, capacity/counter exhaustion with cleanup, source changes despite equal fields/revisions, exact identity/context/request, newer incomplete replacement, Pause/resume/trust/environment invalidation, terminal stop, original-only/schema-1 rejection, expiry boundary/no revival and invalid arithmetic/clock/intervals. No AX objects or sleeps occur in those tests.

Release fixture packaging and strict signature verification passed. Scoped live results on macOS 27.0.1 build 26A434, two scale-1 displays:

| Check | Recorded outcome |
| --- | --- |
| Peer close/recreate | Serial 2 retired; recreated peer serial 3 |
| Inactive original tab | Registry retained original 1 and selected tab; AX list contained only selected identity |
| Stable pair | `historicalConsistent`, revision 32 → 32; freshness unmeasured |
| Tab open/close inside pair | `sourceChanged`, revision 33 → 39; final fixed snapshot fields matched baseline |
| Sheet open/close inside pair | `sourceChanged`, revision 40 → 51; final fixed snapshot fields matched baseline |
| Repeated structural fault snapshots | Armed flag retained; revision 102 → 102 |
| Repeated focused fault snapshots | Armed flag retained, hidden=false; revision 105 → 105 |
| Cleanup | Owned child exited normally |

The run accepted 36 snapshots and six existing identity comparisons, plus three lifecycle pairs. Display rectangles use AppKit bottom-origin coordinates: display 0 frame `(0,0,1920,1080)`, usable `(0,59,1920,991)`; display 1 frame/usable `(-1920,0,1920,1080)`. No desktop/display configuration or permission change was performed. Normal iTile was not rebuilt or restarted. The fixture executable used in this run was SHA-256 `f0c69ed08d1953c1459ae8ab4f2a5506ae868cc406df6381305b2230c4247ad5`.

A final rerun against the verified original-only reducer reproduced all three lifecycle outcomes and orderly cleanup. Its debug lab executable was SHA-256 `df3436a2ceb72b410d616743ba0a09cc70e6a9b39c173c0d0efa58a1070db984`.

These checks cover cooperative fixture transitions and sampled identity. They do not validate global safety, native host revocation delivery, process replacement races, user-window control, or measured freshness.

## Next task

Wire the standalone laboratory host's observed lifecycle/trust/process events to checked context revocation and immediate pending/current invalidation. Add bounded in-flight invalidation/recovery checks, separating deterministic tests from actual native events. Keep the same read-only scope and require a fresh pair after recovery. Any setter proposal still needs separate scope, timing, admission and consent review.

## M2.30 follow-up

[Laboratory host event invalidation](m2-fixture-host-invalidation.md) now wires the host owner and native callbacks, with scoped activation/exit and fresh-run recovery. Native Space/display/sleep and permission acceptance remain separate. The earlier M2.29 results above remain historical.
