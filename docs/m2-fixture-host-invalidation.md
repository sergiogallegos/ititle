# M2.30 — Laboratory host event invalidation

Status: read-only laboratory host wiring implemented, with scoped native activation/exit and fresh-run recovery checks. Production eligibility and mutation remain unchanged. This follows [M2.29 source/value assessment](m2-fixture-lifecycle-assessment.md).

## Implemented boundary

`FixtureDiagnosticHost` is a Foundation-only owner of one attached run, one pair assessment and one outstanding request. Delivered host events advance checked context authority and immediately invalidate current/pending assessment. Revoked work remains outstanding until its exact completion or failure is acknowledged; no replacement read is admitted in the meantime. A late completion returns `contextRevoked`. Wrong-request completions cannot release matching work or overwrite a newer result. A failed fresh read replaces prior favorable diagnostics with `incomplete`, retaining watermarks. Pause/resume and trust restoration require a fresh request. Stop, process exit, run replacement and counter exhaustion permanently close that attachment while still allowing matching cleanup.

The standalone `--host-run` mode attaches a main-thread `LabLifecycleMonitor` to the owned fixture's pipe-provided run and child PID. It registers public workspace activation/deactivation, owned-process termination, Space and sleep/wake notifications, plus AppKit screen-parameter changes. The host's own `NSApplication` uses prohibited activation policy and creates no window. Relevant delivered callbacks invalidate the owner directly. Trust and child liveness are independently sampled during host pumping; repeated unchanged samples do not revoke. Permission-loss detection is sampled, not a continuous notification or cancellation guarantee.

The AX identity reader is now explicitly one-shot: a dedicated thread owns all AX objects, a short lock publishes one bounded value/result, and the host polls completion while pumping its run loop. The host remains able to receive native callbacks during a blocking AX call. No lock spans AX IPC, no AX handle crosses to the host, and no cooperative executor is used. Each read retains the five-second watchdog and 0.2-second per-element messaging timeout. A timed-out read ends the workflow; it cannot overlap a replacement reader. An exit test drains the old physical reader before launching a replacement process.

The monitor retains at most 128 events per attachment and capped diagnostic counters. Overflow stops the attachment and makes the workflow incomplete, including cleanup. Reports contain fixed event codes, revocation numbers, timestamps and outstanding-status flags; no application names, window titles, keys or document paths are collected. Observers are removed on teardown.

All acceptance stays historical with unmeasured freshness. Equal source revisions and delivered callbacks still cannot prove complete event coverage, continuous visibility or future safety. This module is separate from production app/core/platform targets and grants no permit.

## Reproduce

```sh
scripts/package-ax-fixture
swift build --product iTileSafetySnapshotLab
.build/debug/iTileSafetySnapshotLab --host-run
```

Existing effective reader trust is required; the lab neither prompts nor changes permission. It refuses an existing ordinary fixture. Two disposable fixture processes run sequentially, with at most one owned child and one outstanding AX read at a time. Each attachment retains the snapshot lab's 30-second workflow deadline, five-second event wait, 512-line/8-KiB pipe bounds and 16-display bound. Replacement has a fresh watchdog, so the two-attachment workflow does not have a single 30-second overall bound. Cleanup sends Quit and uses the existing three-second exit/one-second termination fallback; forced cleanup is incomplete. Normal iTile is not rebuilt or restarted.

The workflow checks a stable pair, controller-driven Pause/resume rejection and fresh recovery, native focus-loss callbacks caused by the fixture's armed accessor, fresh focus recovery, owned exit with an outstanding request, reader drain, and a fresh replacement-run pair. The Pause check covers admitted outstanding work; it does not claim Pause occurred inside a synchronous AX call. One timestamped native-focus run recorded callbacks inside its AX interval; the final rerun recorded callbacks just afterward while the pair remained outstanding. Neither ordering is assumed by admission. Exit is an outstanding-request test, not proof that termination interrupted an AX call.

## Validation — 2026-10-09

`scripts/format` and `scripts/verify` passed **219 tests**: 130 core, 65 platform, 24 fixture diagnostics, plus the recovery parser self-check. Six new host-owner tests exercise immediate invalidation with matching completion, retained occupancy, stale completion isolation, current/pending event invalidation, restoration with fresh requests, terminal exit/stop/replacement, failed-read replacement, checked exhaustion cleanup and unchanged samples. These deterministic tests do not claim native event delivery.

The owned-host live run passed with orderly cleanup for both fixture processes. Recorded outcomes:

| Check | Outcome |
| --- | --- |
| Baseline | `historicalConsistent`, revocation 0 |
| Controller Pause/resume | Immediate pending invalidation; late identity pair `contextRevoked`, revocation 2 |
| Fresh Pause recovery | `historicalConsistent`, revocation 2 |
| Native focus loss | Workspace activation callbacks with pending=true; identity pair `contextRevoked`, revocation 4 |
| Fresh focus recovery | `historicalConsistent`, revocation 6 |
| Owned exit | Sampled exit plus one owned termination notification; pending result revoked and reader drained |
| Replacement | Different run UUID; fresh pair historical-consistent; old attachment remained stopped |

The timestamped run before the final cleanup-only overflow guard enclosed native-focus uptime 237419.51703083335–237419.62607525; host activation callbacks arrived at 237419.62487458336 and 237419.62490387502, inside that read interval (debug lab SHA-256 `757cab61c57d13d591e82ec3eabe72ffbb5834e0c605c48b198c138638162894`). The final verified rerun enclosed AX uptime 237573.96841833336–237574.07375795834; callbacks arrived at 237574.07702091668 and 237574.07720583334, after AX returned but before the pending pair was consumed. It also rejected the pair and recovered freshly. This does not prove synchronous-call cancellation or guaranteed callback latency. The controller Pause/resume callbacks preceded the worker's first sampled AX interval and are described as outstanding-work revocation only. All 15 snapshot replies in the two-attachment workflow were correlated by their respective run/request/sequence. No synthetic notification posting was used for native acceptance.

OS: macOS 27.0.1 build 26A434, two scale-1 displays. Initial AppKit bottom-origin frames were `(0,0,1920,1080)` and `(-1920,0,1920,1080)`, with usable rectangles `(0,63,1920,987)` and `(-1920,0,1920,1080)`. The replacement reported the second usable rectangle as `(-1920,0,1920,1050)`; these are non-atomic samples, not a display-transition acceptance claim. The fixture executable remained the M2.29 release artifact, SHA-256 `f0c69ed08d1953c1459ae8ab4f2a5506ae868cc406df6381305b2230c4247ad5`.

The final debug lab executable was SHA-256 `380eb8141ce4bfac72828f4b796b0b3caba8f10710222975ba4a4d4ddd8a195e`.

No permission toggle, Space switch, physical display change, sleep/wake action, user-window setter or production integration occurred. Native Space/display/sleep and permission-loss/recovery callbacks remain unvalidated here despite their adapter wiring and pure tests. Run replacement used orderly exit and a fresh process; crash/PID-reuse races remain unvalidated. Freshness is unmeasured.

## Next task

Record separately scoped native Space and effective-permission invalidation/recovery through this host owner, with bounded operator coordination where macOS requires it. Require actual event evidence, keep the fixture on its original desktop, preserve exact reader cleanup and require a new pair after recovery. Do not infer native acceptance from posted test notifications or pure context updates.

## M2.31 follow-up

[Native operator modes](m2-native-host-operator-checks.md) add explicit bounded AppKit event dispatch and scoped native Space acceptance. The separate permission app records effective loss/restoration and fresh recovery; its approved temporary grant was removed. M2.30 results above remain historical.
