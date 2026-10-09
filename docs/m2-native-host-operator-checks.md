# M2.31 — Native host operator checks

Status: bounded operator modes implemented, with scoped native Space and effective permission invalidation/recovery acceptance. The approved temporary permission entry was removed after recovery. Production mutation scope is unchanged.

## Implemented boundary

The standalone snapshot lab now supports `--space-run` and `--permission-run`. Each mode uses one owned fixture and a 180-second workflow watchdog, with at most 120 seconds for an operator phase and the remaining overall deadline for recovery. The physical five-second AX reader is drained before operator coordination. Its completed value remains outstanding diagnostic work; these modes do not claim the operator action overlaps synchronous AX IPC. Freshness remains unmeasured, so long waits never produce a current-use permit.

Space acceptance requires a delivered public `activeSpaceDidChangeNotification`, an own-fixture snapshot with `active=false`, rejection of the pending pair, a second native Space event and a snapshot with `active=true`, then a new historical-consistent pair. Focus changes alone cannot pass. The lab does not activate the fixture to force a return before original-desktop membership has been observed. With separate Spaces on multiple monitors, switch the monitor containing the fixture and leave its window in place.

Permission acceptance requires the running reader's own effective `AXIsProcessTrusted()` state to change true → false → true. Checkbox appearance or a user's “done” reply cannot substitute for that observation. The host records distinct sampled loss/restoration codes, revokes the outstanding pair, then requires fresh successful AX/snapshot pairing after restoration. No synthetic notification is posted and no permission is changed by the lab. Native permission checks require an identified app entry and operator authentication where macOS demands it.

The monitor now counts native Space and effective trust transitions separately from activation. It prepares its own prohibited-policy AppKit application once and dispatches up to 16 queued AppKit events per pump, in addition to run-loop callbacks. A manually pumped standalone application must dispatch those events rather than rely exclusively on `RunLoop.run`. Observers, event/pipe bounds, exact outstanding ownership and cleanup remain the [M2.30 host contract](m2-fixture-host-invalidation.md). A counter or timeout cannot turn an incomplete run into a pass.

## Separate permission app

`scripts/package-safety-permission-lab` packages `dist/iTile Safety Permission Lab.app`, bundle identifier `local.itile.safetypermissionlab`, with an ad-hoc signature. Production targets and normal iTile are unchanged. Opening this explicitly named test app selects permission mode. Its code performs AX identity reads only against its owned child PID, using the bounded dedicated reader. The standard macOS Accessibility grant itself is broader than those application-level restrictions and requires explicit approval for this new entry.

The app does not prompt for or programmatically grant access. A preflight without its own grant exits before creating a fixture. Do not toggle the coding app, terminal, or an unrelated entry to test the CLI's inherited access. Once approved, grant the named app, launch it, wait for `lab-operator-armed kind=permission`, temporarily disable **only that entry**, wait for recorded effective loss, and restore the same entry. macOS authentication is performed directly by the user.

Only this packaged mode replaces `dist/safety-permission-lab.log` on each launch. It opens that fixed generated-report path with no symlink following and mode 0600 for new files. Records are the bounded fixed laboratory vocabulary; no window titles, document paths or typed keys are captured. Ordinary CLI modes retain caller-owned stdout. The package is opt-in and local; nothing is installed or published by the packaging script.

## Reproduce

```sh
scripts/verify
scripts/package-ax-fixture
swift build --product iTileSafetySnapshotLab
.build/debug/iTileSafetySnapshotLab --space-run
scripts/package-safety-permission-lab
```

After the desktop marker, click the owned fixture, switch its monitor's native desktop, stay away about ten seconds, then return. Opening the permission app is a separate workflow requiring its own permission approval. The fixture release binary used here is still M2.29's; normal iTile was not rebuilt or restarted.

## Validation — 2026-10-09

Formatting and verification passed **219 tests** (130 core, 65 platform, 24 fixture diagnostics), plus the recovery parser self-check, all plist checks and packaging-script syntax checks. Existing host tests cover exact late completion, trust restoration without revival, environment revocation and cleanup. These adapter/operator changes add no synthetic native-event test claims. Release permission-lab build and strict signature verification passed.

The first desktop attempt recorded activation events but no native Space event, hit its 120-second operator deadline, and cleaned up normally. It is incomplete. The retry added explicit AppKit event dispatch and clarified which monitor to switch; that combination prevents attributing the first failure solely to either the event pump or operator action.

Accepted retry, run `8BF4043B-A5C0-440A-A416-14D62BAAE90A`:

| Check | Recorded evidence |
| --- | --- |
| Baseline | Historical-consistent pair; request/sequence 2–3 |
| Outstanding pre-switch sample | Request/sequence 4, active=true; physical AX reader drained |
| Native departure | Host `nativeSpace` at uptime 238277.57585354167, pending=true, revocation 13 |
| Off-desktop fixture | Request/sequence 5, active=false, visible=true, original serial 1 still live |
| Old pair | `contextRevoked`, no retained favorable fallback |
| Native return | Host `nativeSpace` at uptime 238289.8937840417, revocation 16; request/sequence 6 active=true |
| Fresh recovery | Requests/sequences 7–8, source revision 39/39, historical-consistent |
| Cleanup | Owned fixture exited normally |

The native departure/return events were about 12.3 seconds apart. All eight snapshots were correlated within this run. Both sampled intervals and window visibility remain historical, non-atomic evidence. The check does not establish arbitrary AX current-desktop visibility or numbered-desktop support.

Debug CLI SHA-256: `c3ce455b9973aabe8feeb95b162009b0fa74997910817cab12fb2565624b0853`. Separate permission-app executable SHA-256: `f64d860df0284f58e5d60f0aa2a221c7e307e601516f7a74ab18dddd1b0cea49`. Its native launch preflight reported `identity-reader-not-trusted` and exited before fixture creation; the UI tool timed out because this headless untrusted preflight leaves no window. This is no permission-loss/recovery acceptance result.

## Native permission acceptance

The user explicitly approved temporary standard Accessibility access for the separate lab app, authenticated directly in System Settings, and approved temporary switch-off/restoration followed by removal. The newly created entry was enabled; native LaunchServices launch then produced a successful baseline under run `82765C40-D911-4E66-9513-352BA3917374`. The UI tool returned a timeout for the headless app, while its fixed report confirmed the running test was armed.

| Check | Recorded evidence |
| --- | --- |
| Baseline | Effective trust true; historical-consistent pair, requests/sequences 2–3 |
| Outstanding work | Request/sequence 4; physical reader drained before permission operation |
| Effective loss | `sampledTrustLost` at uptime 238568.85734608336; revocation 1, pending=true |
| Old pair | Request/sequence 5; source state unchanged at revision 8, active=true; result contextRevoked |
| Effective restoration | `sampledTrustRestored` at uptime 238575.11011487502; revocation 2; old assessment remained revoked |
| Fresh recovery | Requests/sequences 6–7, source revision 10/10; successful AX identity sample and historical-consistent pair |
| Cleanup | Owned fixture and lab exited normally; temporary grant entry subsequently removed |

Only the named lab switch was changed. Loss/restoration were observed by the running app's public trust query, rather than inferred from checkbox state. No activation event preceded the loss in this run: the old pair's rejection followed effective trust loss with matching source state. Seven snapshots were correlated in this run. Trust loss lasted about 6.25 seconds between sampled transitions; this is observation timing, not guaranteed revocation latency.

Removal required a second user authentication and manual selection because row-selection automation repeatedly selected other entries. No automated Remove action was sent. After the user's removal, a fresh settings snapshot verified the lab entry absent and the existing iTile/coding-app/terminal grants unchanged. The app was not relaunched after removal, avoiding recreating its entry.

The native permission report is the explicitly generated, ignored local artifact `dist/safety-permission-lab.log`; app launches replace it. The desktop transcript was captured at `/tmp/itile-m231-space-retry.log`. Fixed results and artifact hashes above are retained here for durable validation. Both workflows used macOS 27.0.1 build 26A434 and two scale-1 monitors.

The operator switched native desktops; no user window was moved or resized. Display/sleep acceptance, continuous safety and permission-loss-in-IPC remain separate. Source/host revisions and unexpired synthetic policies cannot grant production eligibility.

## Next task

[M2.32](m2-fixture-timing-calibration.md) specifies fixture-only acquisition/delivery/assessment measurements and a diagnostic freshness-policy calibration experiment. The next source task implements its bounded collector. Freshness remains unmeasured until a reviewed policy is selected; these results do not support a production lease or authorize any setter.
