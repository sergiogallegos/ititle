# M2.27 — Explicit fixture-to-AX identity binding

Status: implemented with scoped read-only owned-fixture acceptance. Production eligibility remains unchanged. Completed after pushing the prior M2.14–M2.26 work as `1f1cf06` to `origin/main`; this task's new changes remain local.

## Binding and scope

With both `--identity-probe` and `--safety-probe`, the fixture assigns each newly created owned window an explicit identifier: `itile-fixture-v1:<run UUID>:<window serial>`. Original window serial 1 matches the snapshot's original serial. Peers, native tabs, and sheets receive increasing serials which are not reused after closure; exhaustion leaves new windows without a binding. Normal fixture launches do not assign these identifiers.

Apple exposes [accessibilityIdentifier](https://developer.apple.com/documentation/appkit/nsaccessibility-c.protocol/accessibilityidentifier) for an element's testing identity. The installed SDK declares the corresponding public `AXIdentifier` attribute. Our binding comes from **fixture-controlled assignment**, not an assumed identifier convention in another application. The UUID is correlation metadata, not authentication for arbitrary apps or IPC.

`FixtureWindowIdentity` in the laboratory-only Foundation module validates the exact version, canonical UUID, positive canonical serial, and 96-byte bound. It compares run/serial to a parsed snapshot. Geometry, window counts, CG IDs, and PID do not determine a match. Wrong-run/window identifiers cannot match even when geometry is identical. This type is not a production `WindowToken`, safety provider, or admission permit.

The optional lab identity mode reads only its owned child PID. A dedicated thread creates and retains the AX handles, sets the experimental 0.2-second per-handle timeout, reads the focused window and at most eight application windows, and parses their identifiers. It checks focused AX equality again after sampling. No titles, values, document paths, or raw unknown identifier text are exported. Only validated identifiers from the current fixture run produce serial diagnostics. The host waits at most five seconds for a result; it does not cancel a synchronous AX call. A timeout ends the run before another reader starts, so a stalled reader does not accumulate peers. No IPC runs under the result lock or on the main/cooperative executor.

Each read is bracketed by fresh correlated fixture snapshots. Their intervals must enclose the AX interval, the run must agree, the expected focused identity must match or differ from the original as declared, and the focused identity must appear in the sampled AX list. Equal-frame peer acceptance additionally requires another distinct fixture identity in that list. This establishes sampled own-fixture mapping; it does not prove continuity throughout the interval or after delivery.

## Run

```sh
scripts/package-ax-fixture
swift build --product iTileSafetySnapshotLab
.build/debug/iTileSafetySnapshotLab --identity-run
```

The default `--run` snapshot mode still makes no AX reads. `--identity-run` checks effective AX trust without requesting permission; an untrusted reader exits incomplete. It creates only one owned fixture and inherits the [snapshot lab's finite protocol/cleanup bounds](m2-fixture-safety-snapshot.md). Normal iTile can remain running. No permission grant, production app rebuild, native menu action, or user-window setter is performed by this mode.

Success is `lab-owned-identity-passed; no production eligibility claim` with orderly cleanup and exit status 0. Missing identifiers, unsupported AX reads, duplicates, wrong run/window, count overflow, changed sampled focus, unmatched intervals, or forced cleanup are incomplete. AX identifiers on arbitrary user apps are outside this protocol. No direct AX-to-CG bridge is added to the production reader.

## Observed results — 2026-10-09

Final `scripts/format` and `scripts/verify` passed **202 tests** (130 core, 65 platform, seven fixture diagnostics), plus the existing recovery parser check. Two added identity tests cover canonical/malformed identifiers and exact run/window rejection without geometry or eligibility. Release fixture packaging and strict ad-hoc signature verification passed.

Final artifacts:

- Fixture executable: `a270b17a9bb4617e96675ac1e49e0c22c8b8c0995d2cee3428e46d9c1bfe6df7`.
- Debug snapshot/identity lab: `9caa3b4353260ba20d70785cada7311c13eae934a3b2fb23e7b1b8f78f5f3898`.
- Normal iTile remained the M2.22 artifact `bd8f2a7da660befa0b54b72064dc737daa3d8e5640eac835fc35fefadfe6a08a`.

OS macOS 27.0.1 build 26A434; two scale-1 displays. AppKit bottom-origin frames were (0,0,1920,1080) and (-1920,0,1920,1080); usable rectangles were (0,60,1920,990) and (-1920,0,1920,1080). These are sampled topology, not hotplug/mixed-scale acceptance.

| Pair | Focused serial | AX window serials | Result |
| --- | --- | --- | --- |
| Baseline | 1 | [1] | Original matched |
| Equal-frame peer, source confirmed equal frames | 1 | [1,2] | Original matched; peer distinguished |
| Selected second native tab | 3 | [3] | Different owned window; original match rejected |
| Second tab closed | 1 | [1] | Original matched again |
| Native sheet opened then closed | 1 | [1] | Original matched after closure |

Five pairs and 24 correlated snapshot samples completed; the owned child exited normally. The baseline AX interval was 230614.92639970835–230614.96992587502; the remaining intervals were separately recorded in explicit stdout diagnostics. These are enclosing samples, not calibrated IPC latency or freshness policies. The run retained the existing snapshot checks, including armed-fault preservation after identity reads completed. No identity read was attempted while those one-shot faults were armed.

The initial second-tab pair failed because the lab incorrectly required the inactive original tab to remain in `AXWindows`. Diagnosis recorded focused serial 3 and list [3]. The final comparison requires the currently focused identity in the list and requires original-list membership only when testing original focus. It does not infer destruction from the inactive tab's absence. Earlier incomplete runs cleaned up normally. This finding applies to this fixture/OS; it is not a universal native-tab enumeration rule.

Open-sheet AX focus was not paired; own sheet state and post-closure recovery were observed separately. Wrong-run/window rejection has deterministic value tests, not a newly launched process-replacement race. No new cross-desktop transition, permission-loss cycle, or production token continuity test is claimed.

## Next task

Specify the fixture-only lifecycle, invalidation, and expiry contract needed for later paired safety evidence: source-state revisions, window retirement, tab/sheet transitions, wrong-run replacement, and conservative handling of uncertainty between samples. Exact mapping alone cannot clear visibility or lifecycle gates. Keep any disposable setter experiment separately scoped and explicitly opted in; this task does not authorize it.

## M2.28 follow-up

[The fixture lifecycle/expiry contract](m2-fixture-lifecycle-contract.md) is specified. Source revisions, live membership, host invalidation, and pair consistency remain proposed implementation work; schema 1 retains historical diagnostic scope.

## M2.29 follow-up

[Lifecycle assessment](m2-fixture-lifecycle-assessment.md) upgrades current fixture/lab exchange to schema 2, retaining schema 1 only for historical parsing. Recorded earlier schema-1 results above are unchanged. Source revisions and registry membership support diagnostic rejection; native host event delivery and production safety remain separate.
