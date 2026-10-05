# Foundation validation — 2026-10-02

Environment: Apple Silicon, macOS 27.0.1 (26A434), Apple Swift 6.4. Deployment target: macOS 14 (not tested on that OS).

- `scripts/verify`: passed debug build, all 4 XCTest cases (0 failures), and Info.plist lint.
- `scripts/package-app`: passed release build and local ad-hoc signing.
- `codesign --verify --strict --verbose=2 dist/iTile.app`: passed.
- Shell scripts passed `sh -n`.
- Swift package declares no external dependencies; repository has no remote.

SwiftPM initially could not start its nested sandbox inside the execution sandbox. Verification and packaging succeeded outside that restriction; no package dependencies were downloaded.

The menu-bar app was not launched or visually verified in this session. No Accessibility permission was requested, no keyboard interception was enabled, and no windows were moved. No real-window integration or latency benchmark has been performed.

# M1 implementation validation — 2026-10-04

- `scripts/verify`: passed debug build, all 10 XCTest cases (4 geometry, 6 probe identity/coordinate cases), and Info.plist lint.
- `scripts/package-app`: passed release build and local ad-hoc signing.
- `codesign --verify --strict --verbose=2 dist/iTile.app`: passed.
- `git diff --check`: passed.
- SwiftPM again required execution outside the outer sandbox. No external packages were added.

The packaged app was not launched in this session. No Accessibility grant was requested, no real-window experiments were executed, and no windows were moved. Thread isolation, timeout behavior, UI, native tab identity, and visibility still require the [M1 manual checks](m1-probe.md). Unit tests establish only pure identity retirement and coordinate transformations, not public-API feasibility. The prompt-key import uses `@preconcurrency` locally because the Apple C header exposes that constant as a mutable global; AX handles remain worker-owned.

# M1 worker fault checks — 2026-10-04

- Added a worker-thread-owned backend seam; the production adapter still creates and owns all AX objects on its dedicated thread. Tests substitute blocking reads without querying real applications or requesting permission.
- `scripts/verify`: passed 14 XCTest cases: 10 core cases and 4 platform worker cases; debug build and Info.plist lint passed.
- Platform tests exercised a blocked worker alongside a responsive worker, rejection of 1,000 requests while busy, stop during blocked reads with discarded completion, backend construction/read/teardown thread ownership, and reuse with a new environment epoch.
- Notification draining now has a 64-iteration cap with conservative identity invalidation at the cap. This prevents an unbounded drain loop; a real notification-storm experiment remains pending.
- `scripts/package-app`, strict signature verification, and `git diff --check`: passed.
- UI automation attempted to select the packaged app by path and then bundle identifier. Both attempts returned timeout errors. App launch and menu state could not be confirmed. No Accessibility grant or real-window results were verified.

This is fake-IPC concurrency evidence only. It does not satisfy P3's real AX delay/timeout measurements or P1/P2/P4's real-window gates. M2 mutation remains unimplemented. The next manual action is to open the packaged app and inspect Finder after explicit Accessibility onboarding, then follow the M1 experiment matrix.

## User-reported permission/discovery check — 2026-10-04 16:07:18 UTC

The user enabled Accessibility onboarding and supplied a report from the packaged UI on macOS 27.0.1 (26A434). The report displayed one screen with usable logical bounds `(0, 49, 2294, 1378)` at scale 1.0, then `Window enumeration unavailable: AX error -25211. Identity invalidated.`

The installed SDK defines -25211 as `kAXErrorAPIDisabled`. The app reached enumeration after its trust precheck, so this establishes a failed AX request despite a passing precheck, not successful discovery. The report UI and display-snapshot path have user-reported evidence; P1 discovery remains blocked. The precise cause (permission transition, running/rebuilt app identity, or another platform condition) is not established. Next diagnostic: quit iTile, verify its Accessibility entry is enabled, reopen the current `dist/iTile.app`, and repeat Finder inspection. Do not rebuild during this permission check.

## User-reported successful AX read — 2026-10-04 16:15:31 UTC

After quitting iTile, removing and re-adding its Accessibility entry, enabling it, and reopening the same build, the user supplied a successful Finder inspection on macOS 27.0.1 (26A434). The report contains one token (`app-1/window-1`), redacted `other-role` role/subrole, minimized false, no fullscreen value (`kAXErrorNoValue`, -25212), position `(0, 0)`, size `(2294, 1490)`, and position/size settable false. No matching-PID on-screen CG entries were returned. Reported duration: 0.034 seconds. Identity continuity was unsupported; tokens expire before the next snapshot.

This establishes user-observed successful AX enumeration and attribute reads following permission re-enrollment, not standard-window classification, stable identity, or desktop visibility. The element may represent Finder's desktop, but the redacted report cannot establish its identity. Next: open a normal Finder window and compare two explicit inspections without closing the window or restarting iTile. No source changes or rebuild were made during this check.

## Finder standard windows and identity fix — 2026-10-04

User-provided snapshot at 16:16:50 UTC enumerated two `AXWindow` / `AXStandardWindow` elements with minimized/fullscreen false and position/size settable true. Bounds `(821, 219, 1062, 704)` and `(792, 190, 1062, 704)` matched the two layer-zero CG entries for that PID. A third nonstandard element had screen-sized bounds and neither attribute settable. Duration was 0.055 seconds. This is evidence of standard-window classification and matching geometry in this one scenario, not an established AX-to-CG identity bridge or stable tokens.

The snapshot still reported unsupported identity continuity. Source inspection found that any timeout-setup or notification-registration failure permanently disabled continuity for the entire app attachment. The old report did not identify which call/element failed; attributing it to the nonstandard element remains a hypothesis.

The source now expires only affected element tokens and reports per-element destruction-notification registration errors, plus observer-creation failure when applicable. Destruction/environment invalidation still expires all tokens conservatively. A regression test checks repeated expiry of one unsupported identity while observable sibling tokens remain stable. `scripts/verify` passed all 15 tests (11 core, 4 platform), debug build, and plist lint; `git diff --check` passed. These changes have not replaced the running packaged app, preserving its current permission identity pending a coordinated quit/repackage. Real-window verification of this fix remains pending.

The user subsequently confirmed iTile was closed. The per-element identity fix was packaged with `scripts/package-app`; release build and ad-hoc signing passed. Strict signature verification and `git diff --check` passed. The updated `dist/iTile.app` is ready for repeated Finder inspection; real-window notification results remain pending. Because this replaces an ad-hoc signed build, Accessibility permission may need re-enrollment if macOS rejects it.

## User-reported per-element notification check — 2026-10-04 16:21:39 UTC

After the user again removed/re-added the updated app's Accessibility entry, the new report showed successful destruction-notification registration for two Finder standard windows (`app-1/window-1`, `app-1/window-2`). Both were non-minimized/non-fullscreen, with position and size settable. Their AX bounds matched the two reported layer-zero CG entries. The nonstandard screen-sized element (`app-1/window-4`) reported registration error -25207 and explicit token expiry. Snapshot duration: 0.065 seconds; environment epoch: 6.

This confirms that the new diagnostic distinguishes observable standard windows from the unsupported nonstandard element in the user's Finder scenario. It does not alone establish token stability across two snapshots; the next check is another inspection with the same windows and unchanged environment epoch. The app was not rebuilt after this successful permission grant.

## User-reported Finder close/reopen check — 2026-10-04

The 16:25:00 UTC baseline (environment epoch 0) showed three standard Finder windows with tokens `app-1/window-1`, `window-2`, and `window-3`, registered destruction notifications, and matching AX/CG bounds. The nonstandard element had token `window-5` and unsupported destruction notifications. Duration: 0.014 seconds.

The user then reported closing Finder and opening it three times. At 16:26:16 UTC, epoch 0, the report showed standard-window tokens `app-1/window-6`, `window-7`, and `window-8`, with registered destruction notifications and three matching AX/CG bounds. The nonstandard element had token `window-9`. Duration: 0.033 seconds.

Observed outcome: prior standard-window tokens were not reused after this user-reported close/reopen sequence, consistent with conservative destruction invalidation. These reports do not distinguish closing a Finder window from terminating its process, nor demonstrate PID reuse or exact event ordering. Do not mark process-restart coverage passed. Stable identity for unchanged, continuously open windows remains untested; the next check is another explicit Finder inspection without changing any windows or restarting iTile.

## User-reported Finder stable identity check — 2026-10-04 16:26:57 UTC

Compared with the 16:26:16 UTC report, the next explicit inspection retained standard-window tokens `app-1/window-6`, `window-7`, and `window-8` with unchanged bounds and registered destruction notifications. Environment epoch remained 0. The unsupported nonstandard element changed from token `window-9` to `window-10`, as intended. The three CG entries still matched standard-window geometry. Snapshot duration: 0.018 seconds.

Outcome: stable standard-window identity across these two successive Finder observations passed in the user-reported scenario; selective expiry of the unsupported element also passed. Together with the prior close/reopen observations, this supplies limited P1 evidence for Finder on this OS. It does not establish other-app coverage, title-change stability, process-restart/PID-reuse behavior, native tabs, or current-desktop visibility. Next proposed check: navigate one existing Finder window to a different folder without closing it, then repeat inspection to test identity across content/title changes. Do not record folder names or paths.

## Finder navigation follow-up — 2026-10-04 16:28:15 UTC

In response to the requested navigation within an existing Finder window, the user supplied another report retaining standard-window tokens `app-1/window-6`, `window-7`, and `window-8`, unchanged bounds, registered destruction notifications, and environment epoch 0. The unsupported element advanced from `window-10` to `window-11`. Duration: 0.019 seconds.

Observed outcome: standard-window identity remained stable in the follow-up snapshot. Navigation was the requested manual action; the report intentionally contains no folder paths or titles and cannot independently verify that the action occurred or a title changed. No private content was collected. Next manual check: minimize one existing Finder window and inspect whether it remains enumerated with `minimized=true`, while comparing CG entry count as evidence only.

## Finder minimization follow-up — 2026-10-04 16:29:03 UTC

The user supplied a report after the requested minimization. Two elements reported `AXStandardWindow`, minimized false; a third reported `AXWindow` / `AXDialog`, minimized true, at bounds `(601, 564, 1062, 704)` matching the prior middle standard window's geometry. Destruction notifications were registered for all three. The CG list contained only the two non-minimized windows' bounds. Snapshot duration: 0.009 seconds.

Environment epoch advanced from 0 to 1; display usable height changed from 1378 to 1379 logical points. Tokens changed from 6–8 to 12–14, consistent with the implementation's deliberate all-token invalidation on an environment change. The report does not identify the triggering notification; do not attribute it definitively to the Dock or minimization. Identity preservation across minimization cannot be concluded from this pair of snapshots because the epoch changed.

Observed outcome: minimized state was readable and the minimized element remained in AX enumeration while absent from this CG on-screen list. The `AXDialog` subrole is an observed classification change, not evidence that a user dialog opened. Next check: restore that window from the Dock and inspect its minimized flag, subrole, epoch, and CG entry count. No mutation by iTile occurred, and settable flags alone do not establish eligibility.

## Finder restoration follow-up — 2026-10-04 16:29:48 UTC

Following the requested restore from the Dock, the report contained three `AXWindow` / `AXStandardWindow` elements with minimized false and registered destruction notifications. The element at the previously minimized geometry `(601, 564, 1062, 704)` now had token `app-1/window-16`; the other standard elements had tokens 17 and 18. CG entries returned to three, matching the three AX geometries. Duration: 0.016 seconds.

Environment epoch advanced from 1 to 2 and usable display height returned from 1379 to 1378. Fresh tokens are consistent with conservative environment invalidation. The triggering notification remains unidentified. The observed minimized/subrole transition was `true / AXDialog` to `false / AXStandardWindow`; geometry links these observations as evidence, not a proven persistent identity across epochs.

Finder coverage now includes standard-window enumeration, same-epoch stable tokens, selective expiry of an unsupported element, token retirement after user-reported close/reopen, and minimize/restore state reporting. Other-application coverage, native tabs, fullscreen/Spaces, real delayed AX measurements, and physical multi-display checks remain open. Next: inspect the user's terminal application twice while keeping the same terminal windows and iTile session open.

## Terminal inspection baseline — 2026-10-04 16:30:35 UTC

In response to the requested terminal-app inspection, the user supplied a snapshot for `app-2`, environment epoch 2. One element (`app-2/window-1`) reported `AXWindow` / `AXStandardWindow`, registered destruction notifications, minimized/fullscreen false, and position/size settable true. Bounds `(0, 49, 2294, 1378)` matched the single layer-zero CG entry and the usable display area. Duration: 0.041 seconds.

This is a successful single-window observation. Stable identity awaits a second unchanged-window snapshot. The redacted report does not identify the application or version, so Ghostty attribution remains unconfirmed; exact app/version must be recorded before declaring version-specific coverage. Filling the usable display area does not imply native fullscreen; the reported fullscreen flag was false.

## Terminal repeat inspection — 2026-10-04 16:31:12 UTC

The second user-provided `app-2` snapshot retained `app-2/window-1`, environment epoch 2, identical AX/CG bounds `(0, 49, 2294, 1378)`, standard-window classification, registered destruction notifications, minimized/fullscreen false, and settable position/size. Duration: 0.035 seconds (baseline: 0.041 seconds).

Outcome: same-epoch token stability passed across these two supplied snapshots for the selected application. Its name and version have not yet been confirmed, so this remains unattributed app-2 evidence rather than Ghostty-specific coverage. No additional identical snapshots are needed for this narrow check. Next coverage target: two unchanged-window inspections of the user's browser, with app name/version supplied separately.

## Google Chrome baseline — 2026-10-04 16:31:57 UTC

The user explicitly identified Google Chrome as the inspected app. Snapshot `app-3`, environment epoch 2, contained `app-3/window-1`: `AXWindow` / `AXStandardWindow`, registered destruction notifications, minimized/fullscreen false, and settable position/size. AX bounds `(0, 49, 2294, 1378)` matched the single layer-zero CG entry. Duration: 0.012 seconds. Chrome version was not supplied.

Outcome: successful Chrome single-window classification and geometry observation. A second unchanged-window snapshot is required for this scenario's token-stability check. App-2's terminal identity/version remains unconfirmed.

## Google Chrome repeat inspection — 2026-10-04 16:32:39 UTC

The second Chrome snapshot retained `app-3/window-1`, environment epoch 2, bounds `(0, 49, 2294, 1378)`, standard-window classification, registered destruction notifications, minimized/fullscreen false, and settable position/size. The single CG entry still matched AX geometry. Duration: 0.013 seconds (baseline: 0.012 seconds).

Outcome: same-epoch token stability passed across these two Chrome snapshots. This narrow check does not establish tab-switch, native-tab, close/reopen, fullscreen, or other-Space behavior; Chrome version remains unrecorded. Next initial app-coverage check: two inspections of an unchanged editor window, identifying the editor separately from the redacted reports.

## Visual Studio Code baseline — 2026-10-04 16:34:31 UTC

The user identified VS Code as the inspected editor. Snapshot `app-4`, environment epoch 2, contained `app-4/window-1`, classified as `AXWindow` / `AXStandardWindow`, with registered destruction notifications, minimized/fullscreen false, and settable position/size. AX bounds `(403, 280, 1610, 1007)` matched the single layer-zero CG entry. Duration: 0.012 seconds. The editor version was not supplied.

Outcome: successful standard editor-window classification and geometry observation. Repeat-snapshot token stability remains pending for VS Code; no document names or paths were collected.

## Visual Studio Code repeat inspection — 2026-10-04 16:35:01 UTC

The second VS Code snapshot retained `app-4/window-1`, environment epoch 2, bounds `(403, 280, 1610, 1007)`, standard-window classification, registered destruction notifications, minimized/fullscreen false, and settable position/size. The single CG entry still matched AX geometry. Duration: 0.005 seconds (baseline: 0.012 seconds).

Outcome: same-epoch token stability passed across these two VS Code snapshots. The initial unchanged-window repeat checks now have user-reported evidence for Finder, the unnamed terminal application, Google Chrome, and VS Code on macOS 27.0.1. Exact application versions and the terminal's identity remain unrecorded. These few durations are observations, not latency distributions or benchmark claims.

M1 is not yet validated complete. Dialog/native-tab classification, wider identity lifecycle cases, P2 Spaces/fullscreen/occlusion evidence, P3 real delayed AX measurements, and P4 physical display coverage remain pending. The next narrow manual check is a disposable Finder native tab: add a tab in an existing Finder window, inspect; close only that new tab, inspect again. This checks whether AX window identities follow the tab or the containing window and does not exercise window mutation by iTile.

## Finder native-tab baseline — 2026-10-04 16:36:52 UTC

The user reported creating two tabs, giving one Finder window three tabs. The subsequent report contained three standard AX windows (`app-1/window-20`, `window-21`, `window-22`) with registered destruction notifications and three matching layer-zero CG entries. One nonstandard element (`window-24`) still had unsupported destruction notifications and selective expiry. Duration: 0.016 seconds.

Environment epoch was 4, compared with 2 in the earlier restored-window snapshot. The trigger is not identified, so the new tokens cannot establish identity behavior across tab creation. Observation: the supplied three-tab scenario did not yield extra standard-window entries in this snapshot; this does not prove all native tabs map to one stable AX window. Next check: switch to another of the three tabs without closing or creating anything, then inspect Finder again and compare epoch, tokens, and geometry against this baseline.

## Finder native-tab switch: identity discontinuity — 2026-10-04 16:37:43 UTC

Following the requested switch to a different tab in the existing three-tab Finder window, the report retained environment epoch 4 and the same three standard-window geometries. The element at `(684, 608, 1062, 704)` changed from `app-1/window-20` to `window-25`; the other two retained `window-21` and `window-22`. Destruction notifications registered for all three, and CG again contained the same three corresponding bounds. The unsupported element had token `window-27`. Duration: 0.014 seconds.

Outcome: stable containing-window identity across this Finder native-tab switch did not pass. The adapter assigned a new identity to the tabbed element while retaining sibling identities; this is consistent with AX element identity changing across tabs, but the report does not independently prove the underlying AX event sequence. Do not merge these tokens by bounds or infer that successful notification registration guarantees continuity through tab changes.

Decision: retain conservative token retirement. Native-tab transitions are a documented unsupported case for persistent containing-window identity; any future enrollment must expire/revalidate when the observed token disappears. This is not a completed mutation-safety design: M1 currently provides explicit snapshots, and automatic tab/focus reconciliation remains unimplemented. Next diagnostic: switch back to the original tab and inspect again to check whether the previously retired token stays retired. No window movement or geometry-based identity fallback is authorized or implemented.

## Finder return to original native tab — 2026-10-04 16:38:59 UTC

Following the requested return to the original tab, the tabbed element at `(684, 608, 1062, 704)` received `app-1/window-28`. Neither its baseline token 20 nor the intervening token 25 was reused. Sibling windows retained tokens 21 and 22, with unchanged geometry and environment epoch 4. The unsupported element advanced to token 30. All three standard elements registered destruction notifications and matched the three CG geometries. Duration: 0.021 seconds.

Outcome: conservative retirement passed for this observed native-tab round trip (`20 → 25 → 28`). Persistent containing-window identity across the tab switch remains unsupported. This is bounded evidence for retirement behavior, not proof of safe mutation or automatic tab-transition handling.

Next manual coverage target: open Chrome's file chooser with Command–O, leave it open without choosing a file, inspect Chrome, then cancel the chooser. This tests dialog visibility/classification through the current top-level AXWindows enumeration; attached sheets may not appear separately and must not be assumed absent or safe based on the parent window's standard role alone.

## Chrome file-chooser gap and new diagnostics — 2026-10-04 16:40:05 UTC

Following the requested Chrome Command–O chooser check, the user supplied an epoch-4 snapshot showing one standard AX window (`app-3/window-2`) at `(0, 49, 2294, 1378)`. CG listed that surface plus another at `(492, 389, 1310, 698)`. Duration: 0.003 seconds. The top-level AX report did not classify the extra surface; treating the main window's standard role and settable attributes as dialog-free would be unsupported. The changed main-window token is not a same-epoch comparison with the previous Chrome baseline (epoch 2).

Source changes add the public AXModal attribute and a bounded AXChildren role scan (up to 16 direct children) for AXSheet. No chooser descendants, file names, titles, or paths are read. Child handles remain worker-owned, get individual timeouts, and stop scanning at cancellation or the soft scan deadline. Incomplete/failed child scans cannot claim complete absence; even a complete direct scan excludes nested descendants.

`scripts/verify` passed 18 tests (11 core, 7 platform), debug build, and plist lint. Three new tests cover positive sheet evidence, unknown reads, and truncation. `git diff --check` passed. The installed app was not replaced; real Chrome chooser validation of the new diagnostics awaits a coordinated quit/repackage and fresh report.

The user confirmed the chooser was cancelled and iTile closed. `scripts/package-app` successfully built and ad-hoc signed the updated dialog diagnostics. Strict signature verification and `git diff --check` passed. The packaged app now includes `modal=` and `direct-child-sheets=` fields; Chrome chooser detection remains pending real-window confirmation. No Accessibility settings were changed by the packaging step.

## Chrome attached-sheet detection — 2026-10-04 16:44:43 UTC

After packaging the new diagnostics and repeating the requested Chrome file-chooser scenario, the user supplied a report with `direct-child-sheets=1 observed; child-role-scan=complete, 5/5`. The main element (`app-2/window-1` in this new session, epoch 2) remained `AXWindow` / `AXStandardWindow`, minimized/fullscreen false, modal false, with position/size settable true. CG listed both the main-window bounds and the extra chooser-sized surface. Duration: 0.015 seconds.

Outcome: the bounded direct-child role scan detected an attached AXSheet in this observed scenario. The parent's modal flag was false despite that sheet, confirming that modal=false plus standard role/settable attributes cannot establish absence of a blocking dialog. A complete direct-child scan does not cover nested sheets. Session-local app tokens have restarted and must not be compared with earlier session numbering.

Next check: cancel the chooser and re-inspect Chrome without restarting iTile. Compare sheet count, main-window token, epoch, and CG surface count. Positive detection is established for this sample; disappearance after cancellation remains pending.

## Chrome chooser cancellation — 2026-10-04 16:45:51 UTC

The follow-up report after the requested cancellation retained `app-2/window-1`, environment epoch 2, and unchanged main-window geometry. Direct-child sheets changed from 1 (5/5 child roles read) to 0 (4/4 read), both complete direct scans. CG entries fell from two to one, retaining only the main-window bounds. Modal remained false. Duration: 0.012 seconds.

Outcome: attached-sheet appearance/disappearance detection passed for this Chrome file-chooser sequence, with stable main-window identity at the same epoch. This does not establish absence of nested sheets or broad dialog coverage. No files were requested for collection and no chooser contents were inspected.

Next P2 visibility sample: hide Chrome via its normal Command–H action, leave it hidden, and explicitly inspect Chrome from iTile. Compare AX enumeration, token/epoch, and CG entries. AX existence and frame-settable flags alone must not imply on-screen eligibility.

## Chrome hidden-app visibility — 2026-10-04 16:47:04 UTC

After the requested Command–H hide action, the user supplied a Chrome report retaining `app-2/window-1`, environment epoch 2, unchanged geometry, standard role, registered destruction notifications, minimized/fullscreen/modal false, zero observed direct sheets with a complete 4/4 scan, and position/size settable true. The on-screen CG list for this PID was empty. Duration: 0.009 seconds.

Outcome: in this hidden-app sample, AX window existence, non-minimized state, and frame-settable attributes remained true while no on-screen CG entries were returned. These AX properties are insufficient to establish on-screen eligibility. This supplies one P2 hidden-app observation, not a general AX-to-CG correlation strategy. No automatic eligibility classifier or write admission is implemented.

Next contrast: restore Chrome, then fully cover it with an ordinary opaque window from another app without hiding or minimizing Chrome, and inspect Chrome again. Compare fully occluded versus hidden observations; do not treat CG on-screen membership as proof of unobscured pixels.

## Chrome covered by Ghostty — 2026-10-04 16:48:42 UTC

The user explicitly reported showing Chrome via its Dock icon, then returning to an opaque Ghostty window that covered Chrome. The resulting Chrome report retained `app-2/window-1`, environment epoch 2, unchanged geometry, standard role, registered destruction notifications, minimized/fullscreen/modal false, zero direct sheets with a complete 4/4 scan, and settable position/size. Unlike the hidden-app sample, the CG list contained one matching layer-zero entry. Duration: 0.015 seconds.

Outcome: for this user-reported fully covered Chrome window, CG on-screen membership persisted. Together with the hidden-app sample, this demonstrates that CG membership and unobscured pixels are distinct in these observations. Physical occlusion was described by the user, not independently measured. The user identified Ghostty as the covering terminal app; no version was supplied. This does not establish a general public AX-to-CG identity bridge or other-desktop eligibility.

Next P2 check: inspect Chrome while on a different native desktop, leaving Chrome on the original desktop. Record whether the diagnostic UI causes a return to the original desktop; if so, the observation cannot establish other-desktop behavior and the report-window presentation needs adjustment before repeating the test.

## Chrome other-desktop follow-up — 2026-10-04 16:51:59 UTC

After the requested switch to another native desktop, the user first reported the expected stale-observation message. A subsequent explicit Chrome report at environment epoch 11 contained no AX window rows and zero CG entries, with no enumeration error. In this implementation that output represents an empty successful AXWindows result. Duration: 0.003 seconds.

Outcome: Chrome supplied no window observations in this snapshot, consistent with the requested other-desktop scenario. The report itself does not identify the active native desktop, and the user has not separately confirmed whether the report UI changed desktops. Therefore this is conditional other-desktop evidence, not a proven general visibility guarantee. It also differs from the hidden-app observation, where AX enumeration still included the window. Do not extrapolate this behavior to other applications or all Chrome window configurations.

Next: return to the desktop containing Chrome, inspect it again, and check that discovery recovers with a fresh token after environment invalidation. Record any report-induced desktop switch before considering this P2 scenario validated.

## Report-window Space-switch interference and source fix — 2026-10-04

The user explicitly reported that requesting inspection on Chrome's original desktop caused iTile's report to appear on Desktop 2, followed by stale-observation invalidation. This establishes interference from report presentation. The earlier conditional other-desktop sample must not count as a completed P2 visibility check; both desktop directions need retesting with presentation that preserves the active desktop.

The report window now sets public AppKit `collectionBehavior = [.moveToActiveSpace]` at creation, intended to bring iTile's own report window to the active desktop rather than switch the user's desktop. Target application windows remain untouched. `scripts/verify` passed the build, 18 existing tests, and plist lint; `git diff --check` passed. No artificial unit test was added for this AppKit property: the actual cross-Space behavior requires manual confirmation. The installed app remains unchanged pending a coordinated quit/repackage.

The user confirmed iTile was quit before packaging the report-window Space fix. `scripts/package-app` passed the release build and ad-hoc signing; strict signature verification and `git diff --check` passed. The updated app is ready to retest report presentation on each native desktop. Successful cross-Space behavior and Chrome visibility results remain unverified until fresh observations. Accessibility permission may require re-enrollment for this changed ad-hoc signature.

## Report-window Space fix: user confirmation — 2026-10-04 17:33:09 UTC

After the updated package was supplied, the user reported “this time works” and provided a Chrome snapshot containing one standard AX window (`app-1/window-2`, environment epoch 5) and one matching layer-zero CG entry at `(0, 49, 2294, 1378)`. Destruction notifications registered; minimized/fullscreen/modal were false; the direct-child scan observed zero sheets with 4/4 roles read. Duration: 0.006 seconds.

This supplies user confirmation that the report-presentation fix works in their retest, plus a fresh Chrome-present observation. Only one report was supplied, without an explicit desktop label. Do not treat it as both sides of a visibility comparison. The next required observation is a labelled Desktop 2 inspection while Chrome remains on its original desktop and the report stays on Desktop 2. Earlier presentation-interfered observations remain excluded from a passed P2 comparison.

## Chrome other-desktop comparison after presentation fix — 2026-10-04 17:34:08 UTC

The user supplied the requested Desktop 2 report and explained they returned to paste it into the conversation. At inspection time the report showed environment epoch 6, no AX window rows, zero CG entries, and no enumeration error. Duration: 0.004 seconds. Returning after copying a completed snapshot does not invalidate that snapshot's reported observations.

Compared with the preceding Chrome-present snapshot at 17:33:09 UTC (epoch 5, one AX window and one CG entry), this supplies user-reported other-desktop evidence after the report-following fix. The earlier presentation-interfered attempts remain excluded. The result is limited to this Chrome/window/desktop configuration and does not establish universal current-desktop visibility or an AX-to-CG identity bridge. Next: inspect Chrome again after returning to its original desktop to confirm rediscovery following the environment transition.

## Chrome return-to-original-desktop recovery — 2026-10-04 17:34:52 UTC

After returning to Chrome's original desktop, the user supplied a snapshot at environment epoch 9 with one standard AX window (`app-1/window-3`) and one matching layer-zero CG entry at `(0, 49, 2294, 1378)`. Destruction notifications registered; minimized/fullscreen/modal were false; the complete 4/4 direct-child scan found zero sheets. Duration: 0.006 seconds.

Outcome: the observed desktop round trip completed: one AX/CG entry on Chrome's desktop, zero on the requested other desktop, and one again on return. The returned window received a fresh token rather than reusing window-2 after the environment transitions. The exact intermediate epoch increments are not explained by the report. This is a passed user-reported Chrome scenario, not broad native-Space support or bulk-enrollment validation.

Next P2 scenario: Chrome native fullscreen. Enter using its normal Control–Command–F command and inspect while still on the fullscreen desktop. Report presentation on fullscreen Spaces is not yet verified; any switch caused by the diagnostic UI must be recorded and must not be counted as a fullscreen observation.

## Chrome native-fullscreen observation — 2026-10-04 17:37:44 UTC

The user identified this as the Chrome fullscreen scenario and noted launching from Desktop 1. At environment epoch 10 the report contained three AX elements: two `AXWindow` / `AXUnknown` elements with heights 41 and 47 points (position settable, size not settable), and `app-1/window-6`, an `AXStandardWindow` reporting fullscreen true, minimized/modal false, position not settable, and size settable. The standard element's bounds were `(0, 137, 2294, 1353)`. Destruction notifications registered for all three. Direct-child scans were complete with zero observed sheets. CG listed four layer-zero surfaces, including the standard element's bounds and an additional surface without a corresponding reported AX frame. Duration: 0.034 seconds.

Outcome: the probe read a positive fullscreen flag for Chrome's main element in this user-reported fullscreen scenario. AX and CG cardinality differed (three vs four), reinforcing that PID, layer, and bounds alone do not establish a universal identity bridge. Do not classify the two AXUnknown elements as tileable or identify their UI purpose from geometry alone. Some frame attributes remained settable even though the main element was fullscreen; settable is not eligibility. Report presentation across the exact fullscreen/native-Space configuration was not independently observed.

Next: exit fullscreen using Chrome's normal Control–Command–F action and inspect again to confirm return to ordinary-window observations. This does not enable fullscreen management or mutation.

## Chrome exit from native fullscreen — 2026-10-04 17:38:54 UTC

After the requested fullscreen exit, the user supplied an epoch-23 snapshot containing one `AXWindow` / `AXStandardWindow` (`app-1/window-7`), fullscreen/minimized/modal false, registered destruction notifications, zero observed direct sheets (complete 4/4 scan), and settable position/size. Bounds returned to `(0, 49, 2294, 1378)` and matched the sole layer-zero CG entry. Duration: 0.031 seconds.

Outcome: ordinary-window classification and geometry observations recovered after the user-reported fullscreen round trip. The prior AXUnknown elements were absent from this snapshot. A fresh token is consistent with environment invalidation. The epoch advanced from 10 to 23; the report does not explain individual intervening events, and this is not evidence of a particular event count or timing guarantee.

## Manual validation checkpoint — 2026-10-04

User-supplied evidence now covers basic standard-window classification and repeat-token stability across Finder, a terminal app, Chrome, and VS Code; Finder close/reopen retirement, navigation follow-up, minimize/restore state reporting, and native-tab identity discontinuity with conservative retirement; Chrome attached-sheet appearance/cancellation; hidden versus user-reported fully covered windows; a native-desktop present/absent/return sequence after fixing report presentation; and native-fullscreen entry/exit observations. These are scenario-specific results, not full product coverage.

M1 remains incomplete. P3 real delayed-AX fixture and timeout/recovery measurements are still missing; the existing four worker tests use fake reads. P4 physical multi-display/mixed-scale/hotplug and sleep/wake observations remain pending. Exact app versions and original terminal-app attribution need completion. Mission Control, Stage Manager, lock, wider dialogs/tab lifecycles, and permission-revocation races remain untested. Bulk visibility correlation has not passed, native-tab identity continuity is unsupported in the observed Finder case, and window mutation remains disabled.

The next development task is a small public-API local delayed-AX fixture for P3 so IPC timeout/isolation can be measured against real AX requests, followed by the remaining available-hardware checks. No additional unchanged-window reports are needed for the completed narrow checks.

## P3 lab tooling implementation and preflight — 2026-10-04

Implemented a separate `iTile P3 Lab.app` plus embedded `iTileAXFixture` helper. The lab launches two owned fixture processes and uses one production AX worker per process. Five bounded trials pair a deliberately paused fixture with a healthy control and then measure recovery. Added exact AXWindows call timing, whole-request timing, nominal 50 ms main-loop heartbeat samples, and opt-in observer arrival timestamps. Reports include fixture pause intervals, AX result codes, overlap indicators, empirical latency summaries, and optional complete redacted observations. No automatic P3 pass is assigned.

The helper deliberately sleeps only its own event loop for 1.5 seconds after a parent command. Fixture control uses local parent-owned pipes, with no network service, injection, target-app mutation, title reads, or file-chooser content inspection. The diagnostic observer's retained handle set is capped at 64 and remains worker-owned. Stop/Quit revoke worker admission and terminate only owned fixture processes without joining blocked AX calls. A 60-second watchdog bounds lab orchestration, not the underlying AX call itself.

`scripts/verify` passed the debug build, all 21 tests (14 core, 7 platform), both Info.plist checks, and packaging-script syntax. Three new tests cover latency summary tail behavior, invalid measurements, and median overflow. `scripts/package-p3-lab` passed release builds, ad-hoc signing, and strict bundle/helper signature verification. `git diff --check` passed. The existing packaged iTile executable's SHA-256 was identical before and after packaging (`587fe1ec6c6739ee1bcb077aac565cdd2ed7122ee784b36c0a37c13900a1b208`); its permission identity was not replaced.

UI automation successfully opened the P3 Lab and observed its Start, Stop, Accessibility, Copy summary, and Copy full report controls. Pressing Start displayed the explicit permission-required message for this separate lab bundle. No fixture measurement run started and no permission was granted by the agent. Real IPC timings, fixture delay behavior, observer delivery, and process cleanup still await a permission-enabled run. The user-facing next step is enabling Accessibility for iTile P3 Lab, then Start and Copy summary. See [P3 lab instructions](p3-lab.md).

## P3 fixture-ready stall and transport fix — 2026-10-04

The user provided a run requested at 18:39:28 UTC that remained at launch/trial 0. Live UI inspection subsequently observed its 60-second watchdog finish with no AX samples and a responsive main-loop heartbeat. The agent reproduced the launch wait at 18:40:50 UTC. Both owned helper processes were running. A one-second sample of the lab showed both reader threads in Foundation `read(upToCount:)` / `readDataOfLength:`; sampling a fixture showed its main event loop running and its command thread waiting in readLine after the ready emission. No AX experiment worker had been started yet.

Replaced the event reader with a bounded POSIX streaming read on the same dedicated reader thread. Short pipe messages now return without waiting for a 1 KiB fill or EOF, with EINTR retry and explicit EOF/error handling. Added a regression that writes a short ready event, requires delivery while the writer remains open, and then confirms EOF shutdown; added an empty-EOF check. The launch UI now updates readiness/heartbeat and has a separate 10-second fixture-ready timeout.

The agent exercised Stop through the UI, quit the lab, and verified no lab/fixture processes remained before packaging. `scripts/verify` passed all 23 tests (14 core, 9 platform), debug build, plist lint, and script syntax. Release packaging and strict signatures passed; `git diff --check` passed. The main iTile app package was not replaced.

The updated lab opened successfully. Start displayed Accessibility permission required after the ad-hoc rebuild. No post-fix real fixture/AX measurement run has completed yet; the user must refresh the lab's permission entry before retesting. The successful pipe regression establishes transport behavior, not P3 timeout/isolation results.

## P3 measured isolation/recovery — 2026-10-04 19:06:45 UTC

Source: user-supplied complete five-trial P3 Lab summary, independently matched to the live lab UI. Environment: arm64, macOS 27.0.1 (26A434), P3 Lab v1, explicit 0.2-second per-handle timeout; two owned local fixture processes. All 22 baseline/stalled/recovery observations completed. Fixture pauses measured 1500.455–1501.382 ms.

| Measurement | Observed result |
| --- | --- |
| Delayed AXWindows IPC during pause | 201.060–206.172 ms; all five returned -25204 |
| Delayed whole request during pause | 401.995–409.664 ms; median 407.381 ms |
| Control whole request during pause | 1.180–4.662 ms; median 2.266 ms; all AXWindows results 0 |
| Delayed recovery whole request | 4.894–36.955 ms; all AXWindows results 0 |
| Control recovery whole request | 3.287–12.386 ms; all AXWindows results 0 |
| Candidate observer post-to-arrival | Five matches, 0.111–0.355 ms; median 0.218 ms |
| Lab heartbeat (nominal 50 ms) | 165 intervals; median 50.001 ms, empirical p95 51.881 ms, max 73.361 ms |

All five delayed and control AXWindows call start/end timestamps lie within their respective fixture pause intervals. All paired whole requests were also reported to start during the pause and finish before fixture resume. The delayed error -25204 is the public `kAXErrorCannotComplete` (busy/unresponsive/messaging failure), not a distinct guaranteed timeout code. Its consistent timing around the configured 200 ms during known 1.5-second pauses supports timeout behavior for this fixture/API/OS combination. It does not establish universal deadlines.

The roughly 400 ms whole-request duration must not be described as a 200 ms scan deadline. Source inspection shows observer-removal IPC in identity cleanup after failed enumeration; an additional timed wait there is a plausible explanation for the difference, but cleanup calls were not individually instrumented. Keep the per-call/whole-request distinction. No main-loop gap on the scale of the 1.5-second fixture pause was observed; heartbeat data includes scheduling and rendering and does not establish causality for smaller gaps.

## P3 active Stop/Quit checks — 2026-10-04

After preserving the complete run evidence, the agent started a separate UI-controlled run at 19:07:52 UTC, observed an active stalled phase, then pressed Stop. The UI reported `Stopped by user; partial observations only` at trial 4 with no fourth recovery/end event. Start was enabled and Stop disabled. A subsequent process check found no `iTileAXFixture` processes. This demonstrates responsive Stop and fixture cleanup during an active experiment; it is not an instruction-level proof of interruption inside an AX call.

A further run at 19:10:54 UTC showed stalled trial 1 with its control result complete and the delayed result still pending in the observed UI. The agent invoked Command–Q. A process check found neither `iTileP3Lab` nor `iTileAXFixture` remaining. The lab was left closed. No unrelated application process was terminated.

Decision: accept P3 isolation, bounded-time response, recovery, and active Stop/Quit for this scoped fixture scenario, alongside existing fake-worker admission/ownership tests. Retain 0.2 seconds as an experimental read timeout, not a validated general control default. Observer correlations remain candidates and describe notifications posted after the pause, not during it. Long-duration resource behavior and broader AX operations remain unmeasured. P4 physical-display/lifecycle coverage and the documented P1/P2 exclusions remain open; M1 and window mutation are not declared complete or enabled. No source changes or rebuild were needed to evaluate this run.

## P4 single-display baseline — 2026-10-04 19:35:23 UTC

The user explicitly confirmed only one display was connected. The main iTile report showed environment epoch 44, Display 0 usable bounds `(0, 49, 2294, 1379)` at scale 1.0, and one Chrome standard window (`app-1/window-8`) at `(0, 49, 2294, 1378)`. Its AX and sole CG bounds matched. Destruction notifications registered; minimized/fullscreen/modal were false; the complete 4/4 direct-child scan found no sheets. Duration: 0.009 seconds.

This is the before-connection baseline for P4. The one-point difference between usable display height and window height is recorded without treating it as a failure: iTile is read-only and does not promise to resize windows to current usable bounds. Next: connect a second display in extended-desktop mode, leave iTile running, and inspect Chrome again after the display arrangement settles. Compare display geometry/scales, environment epoch, and token invalidation; do not treat transient display indices as persistent identities.

## P4 second-display connection — 2026-10-04 19:37:14 UTC

The user confirmed two displays in extended mode, with Chrome and Ghostty remaining on the Mac's base display and no windows on the second display. The report advanced from epoch 44 to 48. Display 0 usable bounds were `(0, 33, 1512, 902)` at scale 2.0; Display 1 usable bounds were `(-515, -1410, 2560, 1410)` at scale 2.0. The reported second usable area has negative x/y, consistent with placement above and partly left of the primary coordinate origin. Display indices are snapshot-local, not stable identities.

Chrome received a fresh token (`app-1/window-9`, previously window-8), with AX bounds `(0, 33, 1512, 887)` matching the single CG entry. It remained standard, non-minimized/non-fullscreen/non-modal, with destruction notifications registered and no observed direct sheets. Duration: 0.005 seconds.

Outcome: extended-display discovery, preservation of negative usable origins, and environment/token invalidation were observed after connection. The primary usable geometry and scale also changed from the baseline; these changes were observed, not attributed to a particular system-setting action. Both current displays report scale 2.0, so this is not simultaneous mixed-scale evidence. Actual window-coordinate behavior on the second monitor, topology transformation ground truth, and disconnection recovery remain pending. Next: manually drag Chrome onto the second display and inspect it; iTile must remain read-only.

## P4 Chrome on negative-origin second display — 2026-10-04 19:38:58 UTC

Following the requested manual move to the second monitor, Chrome retained `app-1/window-9` and environment epoch 48. AX position/size became `(-515, -1410, 2560, 1410)`, matching both the second display's reported usable bounds and the sole CG entry. Both displays still reported scale 2.0. Standard role, destruction notification registration, non-minimized/non-fullscreen/non-modal state, and zero observed direct sheets were unchanged. Duration: 0.015 seconds.

Outcome: negative-origin window geometry was preserved consistently in AX and CG observations, and the window token survived this user-driven cross-display move without an environment epoch change. This is observed coordinate consistency, not a full transform/round-trip proof or mixed-scale result. iTile performed no frame writes. Next: disconnect the second display while Chrome is on it, leave iTile running, and inspect after macOS settles to observe environment invalidation and whatever window relocation macOS performs.

## P4 second-display disconnection — 2026-10-04 19:44:28 UTC

Following the requested disconnect while Chrome was on the second monitor, the user supplied a report with only Display 0, usable bounds `(0, 49, 2294, 1379)` at scale 1.0. Environment epoch advanced from 48 to 52. Chrome received a fresh token (`app-1/window-10`, previously window-9), with AX bounds `(0, 49, 2294, 1378)` matching its sole CG entry on the remaining display. It remained a standard, non-minimized/non-fullscreen/non-modal window, with registered destruction notifications and no direct sheets observed. Duration: 0.012 seconds.

Outcome: display removal, epoch/token invalidation, and rediscovery on the remaining display were observed. The resulting Chrome geometry is consistent with macOS relocation; iTile issued no frame writes. This completes the user-reported connection → manual move to a negative-origin display → disconnection sequence for this topology. Scale values changed between configurations (1.0 for the single display, 2.0/2.0 when two were connected); this is not simultaneous mixed-scale coverage.

Next P4 lifecycle check: leave iTile running, put the Mac to sleep using the Apple menu, wake/unlock it, and inspect Chrome again. Record whether an invalidation occurred and fresh discovery succeeds; screen lock alone is not a substitute for sleep/wake. Mixed-scale and other physical arrangements remain explicitly untested.

## P4 sleep/wake follow-up — 2026-10-04 19:45:59 UTC

In response to the requested Apple-menu Sleep, wake/unlock, and inspection sequence, the user supplied a Chrome report at environment epoch 56 (previously 52). The single display retained usable bounds `(0, 49, 2294, 1379)` at scale 1.0. Chrome received fresh token `app-1/window-11`, with AX bounds `(0, 49, 2294, 1378)` matching its single CG entry. It remained standard, non-minimized/non-fullscreen/non-modal, with registered destruction notifications and zero direct sheets in a complete 4/4 scan. Duration: 0.010 seconds.

Outcome: fresh discovery and environment/token invalidation were observed in the follow-up to the requested sleep/wake sequence. The snapshot does not independently distinguish which notifications caused the four epoch increments or prove an OS sleep transition; attribution relies on the user's requested manual workflow. No frame writes were issued.

P4 now has user-reported evidence for a single-display baseline, two-display connection, negative-origin window observation, a manual cross-display move preserving identity, disconnect recovery, and this sleep/wake follow-up. Simultaneous mixed scale factors (1x and 2x at once), further above/below/left topologies, and independent physical-coordinate round-trip verification remain outside the observed coverage. M1 remains a read-only probe with declared exclusions; these results do not enable broad bulk enrollment or window mutation.

## M1 readiness review — 2026-10-04

Consolidated the implementation boundary and accumulated P1–P4 evidence in [M1 readiness](m1-readiness.md). Decision: continue read-only diagnostics and begin M2.1 pure control-model/simulated-admission work; keep real mutation gated. M1 remains partially validated. P3's scoped result is accepted, while native-tab identity, eligibility/visibility, focused enrollment, wider lifecycle coverage, and mixed-scale geometry remain limited or open as detailed in the review.

Updated current status in README, architecture, roadmap, probe instructions, platform experiments, and testing. Replaced the obsolete main-UI “launch/state not confirmed” status with the later user-reported evidence while retaining untested pause/resume checks. Earlier log entries remain historical checkpoints. The next task now has explicit state/admission and fake-worker acceptance criteria; it is not a live Tile feature.

This checkpoint changes documentation only. No app was rebuilt, installed, or launched, and no permission setting was changed. The prior 23-test verification remains the latest recorded source run; it was not rerun for this review.

## M2.1 pure control model and simulated admission — 2026-10-04

Implemented `ControlModel` and immutable observation/target/permit/result records in ITileCore. Explicit events reduce to value state and effects without platform references or I/O. Environment epoch, layout revision, and admission generation are independent. Synthetic Tile requires fresh known eligibility and frame capabilities; each simulated setter independently checks admission. Pending absolute plans are bounded/coalesced, one in-flight sequence is retained per app, and stale/failed work requires reconciliation without desired-state rollback or automatic retries.

Added 26 deterministic control-model tests covering unknown evidence, invalid/stale samples, atomic plan validation, pause before dispatch/between setters/during an admitted call, resume, trust and environment changes, obsolete revisions, coalescing/capacity, overflow with a blocked app and healthy peer, destruction before/after first observation, PID reuse, duplicate callbacks, readback ordering/mismatch, and terminal quit. Review also added an invalidation-time barrier so delayed pre-pause/pre-overflow observations cannot clear dirty state. A retired-token serial high-water mark prevents late observations from recreating destroyed windows without unbounded tombstone storage.

Final `scripts/verify` passed the debug builds, all 49 tests (40 core including 26 new control scenarios, 9 platform), both plist checks, and packaging-script syntax. SwiftPM's nested sandbox initially blocked execution; verification ran with the authorized script outside that sandbox. Test compilation exposed a tuple type-inference issue and the final retirement change exposed an exclusive-access violation; both were corrected before the successful final run. No failing check remains.

The app UI and production AX worker are not connected to this model. Admission effects model a serialized admission point; they do not implement a concurrent worker mailbox or prove real write safety. The current app package was not replaced, no Accessibility grant was changed, and no real window integration test was claimed. See [M2.1 implementation limits](m2-control-model.md). Next: M2.2 focused read-only observations/revalidation; real mutation remains gated.

## Commit/push and M2.2 focused probe source — 2026-10-04

At the user's request, staged and committed the completed M1 probe, P3 tooling, M2.1 simulation, tests, and evidence as `f12fc97` (`Implement read-only probes, isolation lab, and simulated control model`). Fetched origin/main first; it matched the local base. The push to origin/main succeeded. M2.2 work below followed that push and is a separate local change.

Implemented explicit Inspect focused window and Revalidate last focused window menu actions. The worker reads public AXFocusedWindow before/after bounded structured window/sheet observations, records focus/destruction notification evidence, and compares session tokens. Focus requests share the existing per-app thread and single-request mailbox. The app refrains from activating the report during the read and rejects delivery after frontmost process, activation revision, environment, trust, or pause changes. Displayed results remain historical; activating the report is not live eligibility. The prior reference is only a comparison token and cannot admit mutation.

Added six pure evidence/delivery tests and two production-worker fake-backend tests. `scripts/verify` passed debug builds, all 57 tests (46 core, 11 platform), both plist checks, and packaging-script syntax. The focused result's control projection never reports eligible; nested-sheet, native-tab, and visibility uncertainties are retained. No title/path reads, private API, new package, or window setter was added.

The existing packaged app was not replaced or launched and its permission was not changed. Real focused-window/notification/UI acceptance has not been performed by this source task. Earlier M1 reports are not relabeled as M2.2 evidence. See the [focused-probe manual matrix](m2-focused-probe.md) for the next task and remaining scope decisions.

## M2.2 packaged launch/preflight — 2026-10-05 02:13 UTC (Oct 4 local)

Packaged the current source with `scripts/package-app`; release compilation and ad-hoc signing succeeded. `codesign --verify --strict --verbose=2 dist/iTile.app` passed. Packaged executable SHA-256: `9a882ea231da7fa48a0f6c4c2fe447fb20fa2d824dc516f38567b6b23e1ca9c1`. macOS 27.0.1 (26A434). Installed Chrome metadata: version 154.0.8037.97, bundle build 8037.97; this records the intended test application, not a successful inspection.

Window-level keyboard automation did not quit the old menu-bar app. A normal application Quit event succeeded and a subsequent process check confirmed it exited. The new app was launched. Window-based UI automation timed out with no report window, but targeted menu-bar UI inspection succeeded: the running app exposed both Inspect focused window (read-only) and Revalidate last focused window (read-only), along with Pause and Quit.

The same menu reported `Accessibility: required for inspection`. The agent opened the permission onboarding command and requested that the user refresh the grant for the exact packaged app. No permission setting was changed by the agent. No focused AX result, same-window revalidation, or wider manual acceptance was obtained in this preflight. The package and new menu commands are confirmed; focus acceptance remains blocked on the refreshed grant. The existing app bundle has now been replaced, unlike the earlier source-only checkpoint.

## M2.2 manual acceptance — 2026-10-05 02:15–02:29 UTC (Oct 4 local)

The user refreshed Accessibility and reopened iTile. The menu then reported Accessibility granted. All reports below came from the packaged executable with SHA-256 `9a882ea231da7fa48a0f6c4c2fe447fb20fa2d824dc516f38567b6b23e1ca9c1` on macOS 27.0.1 (26A434). That executable remained unchanged throughout these checks.

Initial automation mixed window-scoped CUA inspection with menu-bar automation. A focused report succeeded at 02:15:08, but subsequent attempts lost the historical token or returned AX -25212, and the report was not consistently visible to the other automation surface. These attempts do not establish a same-window round trip or a product regression. Controlled checks below used one menu-bar UI sequence and temporary known windows. Chrome version: 154.0.8037.97 (8037.97); Finder: 27.0 (1865); TextEdit: 1.21 (419).

| Check | Accepted observation |
| --- | --- |
| Chrome ordinary window, 02:18:01 / 02:18:03 | A new blank window retained `app-2/window-1`, epoch 4, sequences 1→2. Standard/non-minimized/non-fullscreen/non-modal; both frame capabilities true; zero direct sheets; destruction and focused-window checks true. Revalidation explicitly matched the token. Frame `(0,49,2294,1378)`. Durations 2.403 / 1.870 ms; eligibility unknown |
| Different Chrome windows, identical bounds, 02:19:09 / 02:19:12 | Two owned blank windows had the same `(0,30,2048,1187)` frame at epoch 9. Token changed `app-2/window-2`→`window-3`; revalidation returned expected-token-match=false and ineligible. UI setup changed only the second disposable window's bounds; iTile issued no setter |
| Chrome chooser, 02:19:52 / 02:19:55 | Baseline `app-2/window-4` was standard/unknown eligibility. Command–O on that test window made AXFocusedWindow an `AXSheet`, `window-5`, frame `(369,274,1310,698)`, with unsupported subrole/minimized/fullscreen/modal reads preserved as AX -25205. It was ineligible and did not match the expected token. This differs from M1 top-level enumeration of the parent with a direct child sheet. No chooser contents were inspected and no file was selected |
| Chooser cancellation | Escape canceled the chooser. Revalidate reported no historical token, consistent with clearing the reference after the mismatching sheet. A fresh inspection was required; no silent substitution of the parent occurred |
| Pause/resume | An initial combined automation script sampled text before the pause transition and is inconclusive. A separate action then confirmed the exact paused message and Resume inspections menu item. Attempting focused inspection left that paused message unchanged. Resume was subsequently invoked. The earlier resume/fresh-read sequence also showed the old comparison rejected and fresh ordinary-window inspection at epoch 11, `app-2/window-7` |
| Finder ordinary window, 02:23:26 / 02:23:28 | A new window retained `app-3/window-1`, epoch 13, sequences 1→2, frame `(94,435,920,436)`. Expected-token-match=true; eligibility unknown |
| Finder new native tab, 02:23:31 | Command–T in that owned window yielded `app-3/window-2` at the same epoch and identical frame. Expected-token-match=false; ineligible. This confirms rejection of the observed identity discontinuity, not stable tab-container identity |
| TextEdit blank document, 02:24:22 / 02:24:25 | Retained `app-4/window-1`, epoch 13, sequences 1→2, frame `(232,92,603,505)`. Standard, frame capabilities true, focused checks true; expected-token-match=true and eligibility unknown |

Chrome/Finder/TextEdit test windows/documents were closed using their owned references; the blank TextEdit document was not saved. TextEdit was quit only if launched by the test. Other existing documents/windows were not deliberately edited or closed. Display reports changed between sequences from `(0,49,2294,1378)` to `(0,30,2048,1187)` at scale 1; epoch changes were retained and no cause or multi-display guarantee is inferred from them.

### Focus-loss fixture attempt and remaining limit

Added an explicit `--focused-probe` mode to the existing disposable Swift fixture. It uses a regular activation policy and activates its own key window so M2.2 can select it; default P3 accessory behavior is unchanged. `--slow` still pauses only its own event loop for 1.5 seconds, controlled by its parent's stdin; EOF/quit exits. No real application was stalled. `scripts/verify` passed again after this fixture-only change: 57 tests, debug builds, both plists, and script syntax. The iTile app bundle was not rebuilt again, preserving the refreshed grant.

Two bounded focus-race attempts launched owned fixtures, requested a stall, invoked focused inspection, and activated Chrome. The second first established a normal fixture snapshot at 02:28:03 (`app-5/window-1`, epoch 14, standard, size-settable=false, ineligible), and independently checked its foreground PID before stalling. Its pause ran from monotonic 79634.55504958334 to 79636.05650979167. Both race attempts produced a focused failure AX -25212 while Chrome remained foreground; neither captured the pending-request discard message or demonstrated that the focus transition overlapped the request. **Do not count these as passing the real focus-loss race.** Menu action delivery and request-start ordering need explicit synchronization in the next test.

Both fixtures exited normally. A final process check found no iTileAXFixture process, and the probe displayed `An application exited. Inspect again for a fresh snapshot.` after cleanup. This confirms observed lifecycle invalidation, not a PID-reuse or mid-call termination guarantee.

Decision: accept the scoped ordinary-window/revalidation, identical-bounds rejection, focused-sheet exclusion, native-tab token rejection, confirmed paused-admission, and post-exit invalidation observations above. M2.2 has partial real-window validation. Real in-flight focus-loss, mid-scan permission revocation, and focused desktop/display-transition races remain open; fake tests are separate evidence. Mutation remains disabled. No source fix to the focused probe was justified by the inconclusive automation sequences.

## M2.2 synchronized focus loss — 2026-10-05 02:36–02:40 UTC (Oct 4 local)

Added an explicitly armed one-shot fault to the disposable fixture's public `accessibilityFocusedWindow()` accessor. In `--focused-probe` mode, the parent's `arm-focus-loss` command makes the next accessor call emit begin/hide/end monotonic events, hide only its own app, pause its own main loop for 0.1 seconds, and return the captured focused window. The separate `activate` command restores only the fixture's window. Arming is consumed before hiding; EOF/quit retains bounded child cleanup. Default P3 commands and accessory behavior are unchanged. No production probe setter, injected code, or private API was added.

Two preliminary runs at 02:37/02:38 did not select the fixture: the iTile baseline was Chrome even though the automation had set the fixture's foreground property. No accessor event occurred in the first attempt; the second aborted on a stricter fixture-geometry assertion. These are test-setup failures, not accepted race evidence. The successful run used the fixture's own stdin activation command and checked its known non-resizable window before arming. The debug fixture executable was wrapped in a temporary regular app bundle (`local.itile.focus-fixture`); the parent retained its input pipe and read only fixture events and iTile's diagnostic UI. No other client deliberately requested the fixture's focused AX attribute while armed. The accessor cannot identify the requesting client, so this is correlated test evidence rather than authenticated client tracing.

Successful sequence on macOS 27.0.1 (26A434), arm64, one reported display `(0,30,2048,1187)`, scale 1:

- 02:39:46 baseline: `app-6/window-1`, epoch 17, sequence 1, frame `(200,922,420,158)`, standard window, position-settable=true, size-settable=false, focused/destruction checks true, eligibility=ineligible. Worker interval `80335.15664183334`–`80335.17339275`.
- Fixture arm acknowledgment: `80337.91069191667`. Actual accessor begin: `80338.41710595833`; own hide: `80338.41739575`; accessor end: `80338.51845695834` (101.351 ms from begin to end).
- iTile displayed `Focus changed during inspection. Result discarded; inspect again.` Ghostty (`com.mitchellh.ghostty`) was foreground. The discard message remained after a subsequent delayed read; a late result did not replace it or raise iTile in these observations.
- After reactivating the fixture, Revalidate reported `No matching historical focused token for this app. Choose Inspect focused window first.`
- 02:39:57 fresh inspection recovered: `app-6/window-1`, epoch 17, sequence 3, same known frame and conservative ineligible result; worker interval `80345.76414808334`–`80345.76653345834`. The shared registry token survived, but the historical comparison reference had been cleared, as required.

The owned fixture exited with status 0. A final process check found no fixture. The installed iTile executable hash remained `9a882ea231da7fa48a0f6c4c2fe447fb20fa2d824dc516f38567b6b23e1ca9c1`; no repackaging or permission refresh was needed. Verification after fixture changes passed all 57 tests and existing build/plist/script checks.

Decision: accept this scoped real in-flight focus-loss rejection and recovery observation. It does not prove every activation race, uninterrupted foreground behavior between sampled checks, mid-scan permission loss, or desktop/display invalidation. Those remaining acceptance limits stay explicit; mutation remains disabled.

## Swift formatting convention — 2026-10-05 02:42 UTC (Oct 4 local)

At the user's request, adopted the official Swift toolchain's `swift-format` and Swift API Design Guidelines. Captured the installed formatter defaults in `.swift-format` (two-space indentation, 100-column target), added `scripts/format`, documented the convention in AGENTS/CONTRIBUTING/README, and made `scripts/verify` run strict formatting lint. Swift's formatter documentation explicitly does not prescribe one universal whitespace style; these captured defaults are the project's reproducible choice. No package or third-party formatter was installed.

Formatted all Swift package/source/test files. Strict lint additionally required converting one existing inline block comment to a line comment. Final `scripts/verify` passed formatting, all debug targets, all 57 tests (46 core, 11 platform), both plist checks, and script syntax. No app bundle was replaced. This source-formatting verification is separate from the packaged-executable manual evidence above.

## Commit/push and focused lifecycle checks — 2026-10-05 02:46–03:04 UTC (Oct 4 local)

At the user's request, fetched origin/main, confirmed no divergence, and committed the focused probe, manual evidence, and Swift formatting convention as `d490f62` (`Add focused read-only validation and enforce Swift formatting`). Push to origin/main succeeded. The working tree was clean immediately afterward. The fixture extension and evidence below are subsequent local work, separate from that push.

All checks used the unchanged installed iTile executable with SHA-256 `9a882ea231da7fa48a0f6c4c2fe447fb20fa2d824dc516f38567b6b23e1ca9c1`, macOS 27.0.1 (26A434), arm64, and one reported display `(0,30,2048,1187)`, scale 1. The owned fixture used a temporary regular-app wrapper and its parent-owned input pipe. Its known window frame was `(200,922,420,158)`, standard/non-minimized/non-fullscreen/non-modal, position-settable=true and size-settable=false; successful reports remained ineligible.

### Desktop round trip between requests

The initial 02:48 attempt switched right but could not read iTile's AX report window from the other desktop (AX automation invalid index). The original desktop was restored and the fixture exited. This was a test-setup limitation, not an accepted rejection check.

The corrected 02:49 run read the report only after switching right and returning left. Baseline at 02:49:10 was `app-8/window-1`, epoch 23, sequence 1. After the round trip, the report was `Desktop/display or sleep state changed. Previous observations are stale; inspect again.` Revalidation required a fresh inspection. Recovery at 02:49:20 was `app-8/window-2`, epoch 25, sequence 2, with unchanged geometry and ineligible evidence. Fixture exit status was 0. This is between-request environment invalidation, not a mid-read claim.

### Observed Accessibility loss and recovery

Two setup attempts at 02:51 stopped before changing permission because the settings page's loaded hierarchy differed from its transient hierarchy. The 02:53 attempt established `app-9/window-1`, epoch 28, then observed the iTile settings switch off, but an immediate inspection still produced an AX result: an unrelated focused sheet (`app-10/window-1`), not the fixture. The switch was restored and the fixture exited. No blocked-inspection or stale-token pass is claimed for that attempt, and no cause for the intervening sheet is asserted. Subsequent inspection of the settled off state did confirm iTile's menu reported missing permission. The successful retry explicitly waited for the app's effective trust status rather than treating the checkbox value as sufficient evidence.

- 02:57:54 baseline after confirmed granted status: `app-11/window-1`, epoch 30, sequence 1; worker interval `81423.25436695834`–`81423.27046479167`.
- Disabled only iTile's switch and confirmed **Accessibility: required for inspection** in its menu. Focused inspection then returned `Accessibility permission required. Use Enable Accessibility for inspection…`.
- Restored the switch and confirmed **Accessibility: granted**. The same running fixture's Revalidate action returned `No matching historical focused token for this app. Choose Inspect focused window first.`
- 02:58:16 fresh recovery: `app-11/window-2`, epoch 33, sequence 2; worker interval `81445.029765875`–`81445.03727895833`. Fixture exit status was 0.

The successful round trip did not restart iTile, replace its executable, or remove/re-add its permission entry. The final settings value and iTile's own menu both confirmed access restored. This verifies permission loss observed between requests and subsequent recovery. Effective mid-scan revocation, brief unobserved revoke/regrant cycles, and propagation timing guarantees remain unproven.

### Desktop notification during a delayed fixture accessor

Added the explicit `arm-window-stall` fixture command, accepted only in `--focused-probe` mode. It pauses the fixture's next public window-role accessor for 1.5 seconds and emits begin/end uptime events; the arm is consumed before sleeping. This affects only the disposable fixture and does not alter the production worker or its per-handle timeout. A separate temporary Swift/AppKit monitor emitted public Space-change notifications on the same host uptime clock. No AX access or private Space API was used by that monitor.

At 03:02:16, baseline was `app-12/window-1`, epoch 34, sequence 1. The arm acknowledgment was `81687.93338666667`. The fixture window accessor ran from `81688.44429366667` to `81689.94524966668`. After its begin event, the controller switched one desktop right; the monitor observed a Space notification at `81689.62803329166`, inside that accessor interval. After returning left, iTile reported the environment-stale message. Revalidate rejected the historical reference. At 03:02:29, a fresh read recovered as `app-12/window-2`, epoch 36, sequence 3; worker interval `81697.67868733333`–`81697.68164204167`.

Accepted scope: a real Space transition overlapped execution of an owned AX accessor, and the resulting historical reference remained invalid until a fresh inspection. Limits: the fixture cannot identify the AX caller; no other client deliberately read it while armed. Per-call timeouts can finish before the accessor returns. Production request-completion time was not traced, and simultaneous focus invalidation was not isolated from environment invalidation. Do not turn this into a hard client-IPC overlap or all-races guarantee. Physical display changes were not tested in this focused sequence.

Both disposable processes exited; a final process check found neither remaining. The original desktop was restored. Final `scripts/verify` after the fixture change passed strict formatting, all 57 tests (46 core, 11 platform), debug builds, both plists, and script syntax. No production source correction was justified by these observations. Next: effective mid-read permission-loss evidence and focused physical display changes; supported-scope exclusions continue to gate real mutation.
