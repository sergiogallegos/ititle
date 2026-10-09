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

## Commit/push and physical display round trip — 2026-10-05 03:10–03:15 UTC (Oct 4 local)

At the user's request, fetched main, confirmed no divergence, and committed the previous fixture/evidence checkpoint as `24fafc7` (`Validate focused permission recovery and desktop invalidation`). Push to origin/main succeeded. Subsequent changes below are separate local work.

The user confirmed the second monitor was available and disconnected. A parent-controlled fixture stayed alive through the entire physical connection/disconnection sequence; iTile was not rebuilt or restarted during it. These observations used the prior installed executable hash `9a882ea231da7fa48a0f6c4c2fe447fb20fa2d824dc516f38567b6b23e1ca9c1`, macOS 27.0.1 (26A434), arm64.

| Checkpoint | Observation |
| --- | --- |
| 03:12:29 single-display baseline | `app-13/window-1`, epoch 37, sequence 1; display usable `(0,30,2048,1187)`, scale 1; fixture frame `(200,922,420,158)` |
| User connected second display and confirmed settled | Report changed to environment-stale message; Revalidate rejected the historical token |
| 03:14:11 two-display recovery | `app-13/window-2`, epoch 41, sequence 2; display 0 usable `(0,33,1512,891)`, scale 2; display 1 usable `(-515,-1410,2560,1410)`, scale 2; fixture frame `(236,470,420,158)` |
| User disconnected second display and confirmed settled | Report again changed to environment-stale message; Revalidate again rejected the historical token |
| 03:15:11 single-display recovery | `app-13/window-3`, epoch 44, sequence 3; display usable `(0,30,2048,1187)`, scale 1; fixture frame `(200,922,420,158)` |

Every successful fixture report was standard/non-minimized/non-fullscreen/non-modal, position-settable=true, size-settable=false, focused/destruction checks true, and ineligible. The fixture exited normally with status 0. iTile issued no setters; no cause beyond the observed display transition is assigned to the changed fixture frame. This covers focused reference invalidation and recovery across physical hotplug between requests. It does not establish mixed-scale simultaneous displays, mutation geometry, or hotplug during an admitted AX call.

## Opt-in client request trace — 2026-10-05 03:13–03:16 UTC (Oct 4 local)

Added an optional metadata-only trace callback around the focused backend on its dedicated worker, plus `--trace-focused-probe` application logging through OSLog. The visible menu indicator identifies trace mode. Events correlate worker start/return, main-thread completion/disposition, trust samples, and environment/focus invalidation using host uptime and session-local counters. Defaults remain off; no window content, titles, paths, or process IDs are included in the payload. Unified-log retention is controlled by macOS and documented separately from the memory-only report.

Extended the existing blocked-worker test to require trace start before backend entry, trace finish even when stop suppresses delivery, and no execution trace for rejected mailbox requests. An initial closure type-inference compiler failure was fixed by replacing a conditional closure expression with explicit branches. Final `scripts/verify` passed all 57 tests, strict formatting, debug builds, plist checks, and script syntax. Trace finish intentionally excludes autorelease cleanup/main delivery; documentation distinguishes this from whole-request duration and permits the main-thread admission log to follow worker start.

After the physical display test completed, quit the old iTile, packaged the new release, and verified its ad-hoc signature. New executable SHA-256: `8a485458f5bf8e1e5e7a21554ec029a6292863fcab8d9804cc0a4cc150d42710`. Launched with the trace flag and captured only the `local.itile.app` / `FocusedProbeTrace` log category. The menu indicator and `traceEnabled` event were observed. The rebuilt app reported missing Accessibility permission; `menuTrust trust=0` and invalidation were logged. Requested the user's refresh of the exact bundle entry before continuing live timing acceptance. No effective mid-read permission-loss pass is claimed by this preflight.

## Traced permission loss inside a backend request — 2026-10-05 03:18–03:28 UTC (Oct 4 local)

After the user initially reported the entry refreshed, the settings list did not contain iTile; the first prepared run stopped before changing permissions and cleaned up its fixture. The agent opened Add, macOS requested authentication, and the user authenticated directly through the system prompt. The agent then selected the exact `dist/iTile.app` bundle in the app picker and reopened it with the trace flag. Both the enabled settings entry and iTile's granted status were confirmed before the successful experiment. No password was requested in chat or entered by the agent. The executable remained the trace-build hash above.

The test used the owned 1.5-second window-role fixture fault. An AppleScript helper located only iTile's checkbox in advance, acknowledged readiness, and waited on its parent's input pipe. After the fixture's `window-read-begin` event, the parent released that helper to click the cached checkbox. This removed the slow settings-navigation step from the measured interval. The controller checked iTile's own menu for effective trust loss and captured only the opt-in trace category. The helper did not explicitly activate System Settings while the request was running.

At 03:26:18, baseline was `app-1/window-1`, environment 0, sequence 1, known fixture frame `(200,922,420,158)`, standard/non-minimized/non-fullscreen/non-modal, size-settable=false, and ineligible. The delayed request's correlated evidence follows; all times are host monotonic uptime:

| Event | Uptime | Evidence |
| --- | --- | --- |
| Worker started, request 2, app generation 1 | 83130.332997 | Captured environment 0 |
| Fixture window-role accessor began | 83130.33402516667 | Owned one-shot pause |
| Menu trust sample, request 2 | 83130.549053 | `trust=0`, followed by invalidation at 83130.549149 |
| Fixture accessor ended | 83131.83511933334 | Server-side pause completed |
| Worker finished, request 2, app generation 1 | 83131.843043 | Backend returned; excludes subsequent cleanup/delivery |
| Main-thread completion, request 2 | 83131.843178 | Current environment 1, `trust=0` |
| Discarded, request 2 | 83131.843193 | No presentation event for this request |

The permission-loss sample lies strictly inside the 1.510046-second backend interval, 0.216056 seconds after start. No focus-invalidation or environment-change event occurred for this request in the captured trace. The displayed report remained `Accessibility permission is missing. Previous observations are stale.` This establishes permission-driven invalidation of the in-flight backend result at the sampled menu boundary; it does not prove that an individual synchronous IPC was interrupted or that every transient permission cycle is detectable.

Restored only iTile's switch and waited for the app to report granted. Revalidate rejected the old comparison reference. Fresh recovery at 03:26:36 was `app-1/window-2`, environment 1, sequence 2, with the same fixture geometry and ineligible evidence. Request 4's backend interval was `83144.828359`–`83144.833782`, and completion observed trust=1 before presentation. Generic disposition events in this initial trace schema leave environment at a default zero; environment conclusions above use the worker and completion events that explicitly capture it.

The fixture exited with status 0, the cached helper exited, and both filtered log streams stopped. Restarted iTile without the trace flag. A final menu check confirmed Accessibility granted and no trace-mode indicator; no fixture remained. The second monitor remained disconnected after the completed physical test. No source edits followed the already-passing 57-test verification; subsequent edits recorded evidence and limits only.

Decision: accept the scoped observed mid-request permission-loss rejection/recovery and physical hotplug between-request checks. M2.2 now has the planned scoped lifecycle evidence, while universal compatibility, transient unobserved changes, supported eligibility, and live mutation safety are not established. Next task: consolidate the supported-scope/eligibility decision for focused enrollment before integrating any live control.


## M2.3 focused eligibility policy — 2026-10-04 local (Oct 5 UTC)

Consolidated the M2.2 evidence into [ADR 0003](decisions/0003-focused-eligibility.md). The intended initial ordinary-window scope is distinct from the currently enforceable production mutation scope, which remains empty. Added a pure `WindowEligibilityAssessment`: positive exclusions yield ineligible, otherwise unknown; missing evidence remains explicit alongside exclusions. The generic probe always retains desktop-visibility, native-tab, and nested-dialog requirements. Fixed report reason codes contain no application content; no eligible override or live enrollment path was added.

Control projection now rejects missing/non-finite/non-positive geometry and overflowing edges, non-finite/backward/negative observation intervals, and zero worker sequences. Valid negative origins and zero-duration intervals remain supported. Five new tests cover these cases, retained scope requirements, positive exclusion precedence, and unsupported/malformed attribute evidence.

Ran `scripts/format` and `scripts/verify`: 62 tests passed (51 core, 11 platform), debug targets built, strict formatting passed, and plist/script checks passed. These tests exercise values and fake workers; no new real-window acceptance, visibility proof, performance bound, or mutation safety is claimed. The installed trace-build bundle was not repackaged or relaunched, so this source report extension has not received a new manual UI check. Existing Accessibility permission and the trace-off running app were left in place.

Next task: bounded nested-dialog evidence on the existing dedicated worker, preserving unknown results for incomplete/unsupported scans. Tab and visibility proof, eligible scope, coordinator integration, and live setters remain gated.

## M2.4 structural scan: scoped fixture and native acceptance — 2026-10-05 UTC (Oct 4 local)

Environment: macOS 27.0.1 (26A434), arm64, single display. The owned fixture was extended using public `NSAccessibilityElement` objects and explicit stdin scenarios. `scripts/package-ax-fixture` packages separate fixture/control bundles so two actual per-application workers can be exercised. Synthetic trees deliberately replace the fixture window's child graph; they are not models of every native application's hierarchy. Native sheets use `NSWindow.beginSheet` instead.

Added an opt-in `--manual-probe` local stdin driver and `--show-probe-report` startup window to iTile. Fixed test commands can target the two owned bundle identifiers or TextEdit and use the existing production `WindowProbe.inspectFocused` backend. These backend samples explicitly bypass the app's foreground delivery coordinator, clear historical references, retain trust/pause/environment/process checks, and label that limit in their reports. Ordinary `inspect`/`revalidate` commands call the existing menu handlers. Reports are exported only on the driver's explicit `report` command. No listener, periodic inspection, arbitrary PID input, AX setter, focus action on another app, or eligible projection was added. Normal launches have no stdin driver or stdout report export.

Initial requests selected the terminal rather than the owned fixture. The UI service could attach to the visible diagnostic window but could not reliably reach iTile's status menu or establish the desired foreground application. Those attempts do not count as fixture or TextEdit passes. A delayed foreground attempt also selected the terminal. Targeted backend samples were used to isolate the actual structural reader from this UI-control limitation.

### Observed structural samples

The parent controller retained each child's stdin/stdout, waited for scenario readiness and backend completion, then requested the redacted report. Root frame for the synthetic cases was `(200,922,420,158)`; its size capability is deliberately unsupported, so `sizeNotSettable` remains alongside structural exclusions.

| Scenario | Observed nested summary | Eligibility consequence |
| --- | --- | --- |
| Explicit ordinary synthetic tree | 0 sheets, 0 dialogs, 2 nodes, complete | Ineligible for size capability; all three generic scope requirements remain |
| Direct synthetic sheet | 1 sheet, 0 dialogs, 2 nodes, complete; direct sheet count 1 | `sheetPresent`, once |
| Sheet beneath a group | 1 sheet, 0 dialogs, 3 nodes, complete; direct sheet count 0 | `sheetPresent` |
| Window with dialog subrole | 0 sheets, 1 dialog, 3 nodes, complete | `dialogPresent` |
| Window with system-dialog subrole | 0 sheets, 1 dialog, 3 nodes, complete | `dialogPresent` |
| Group with 80 child links | 1 sheet, 0 dialogs, 64 nodes, `nodeLimit` | Positive sheet exclusion retained despite truncation |
| Deep chain with sheet beyond the depth boundary | 0 sheets, 0 dialogs, 7 nodes, `depthLimit` | No absence proof or scope clearance |
| Self-repeated group link | 0 sheets, 0 dialogs, 2 nodes, `cycle` | No absence proof or scope clearance |
| Child accessors delayed by 0.08 seconds | 1 sheet, 0 dialogs, 16 nodes, `budget` | Positive sheet exclusion retained; observed request approximately 1.06–1.09 seconds, not a hard deadline |
| Owned native AppKit sheet | Focused element became `AXSheet`; 2 nodes, complete | `nonWindowRole`; missing sheet state attributes remain explicit |
| Cancel owned native sheet | Ordinary window returned, new token; 7 nodes, complete | Ineligible for size capability; generic scope remains unproven |

A first budget report was requested before completion and still displayed the preceding cycle sample. It is not counted. A completion-synchronized repetition produced the budget result above. A synthetic hide-on-child-read attempt ran while the fixture was not foreground; the sampled focused handle remained equal. It does not establish foreground focus-loss rejection and illustrates why sampled AX equality alone cannot prove lifecycle safety.

### Synchronized pause and two-worker isolation

A temporary local parent controller waited for the fixture's `nested-stall-begin` event before sending further commands; it did not enumerate the armed fixture with a second AX client. Times below are host monotonic uptime. The server accessor deliberately paused only the owned fixture for 1.5 seconds; individual production client calls retained their 0.2-second timeout.

| Pause event | Uptime |
| --- | --- |
| Nested accessor began | 86250.17962808334 |
| App processed Pause | 86250.18011929168 |
| Backend sample discarded at app delivery | 86250.58990450001 |
| Nested accessor ended | 86251.68068241667 |

Pause arrived inside the accessor interval, and the completion was discarded while the accessor was still running. The report retained the paused message. Resume followed by a new ordinary sample recovered with a new token and complete structural summary. This proves the scoped manual-driver pause gate, not direct status-menu interaction or cancellation of an in-flight IPC.

For isolation, the delayed fixture accessor ran from `86251.71876220834` to `86253.21969241668`. A separately packaged control fixture's production worker completed at `86251.74545833335`, with a healthy 7-node structural scan. The delayed sample was superseded and discarded at `86252.12796891667`. The control worker responded before server recovery; no generic scheduler or latency guarantee follows from this single pair.

An earlier isolation attempt tried the normal foreground handler while iTile itself was foreground; it rejected source selection and is not counted. A later attempt to repeat cases after unsynchronized native commands consumed stale events in the disposable parent controller and stopped with a queue timeout; both owned children and iTile exited normally. That controller bookkeeping failure is not a platform pass or an AX failure. Successful samples above used completion-synchronized requests without that mixed command sequence.

### Native TextEdit sheet

Created a disposable blank TextEdit document through the UI and opened its native Print panel. No printing, saving, or text entry occurred. A targeted backend sample reported `AXSheet`, unknown subrole/minimized/fullscreen/modal attributes (AX -25205), frame `(135,160,780,637)`, 64 examined nodes, and `nodeLimit`. Eligibility was ineligible with `nonWindowRole`, and all missing state/scope reasons remained. The scanner requested structural metadata only, not print settings or document contents.

After cancelling the panel through the UI, the ordinary document window returned with a new token, frame `(232,92,586,488)`, 47 nodes, and a complete sample. Eligibility stayed unknown with `currentDesktopVisibility`, `nativeTabSafety`, and `nestedDialogSafety`. The blank document was closed, returning TextEdit to its initial Open panel. This is one representative native sheet observation, not proof of all sheets/dialogs or parent-window relationships.

### Verification and remaining scope

Source verification passes 71 tests (60 core, 11 platform), strict Swift formatting, debug builds, three plist checks, and shell syntax including the new fixture packaging script. Release app/fixture packaging and strict ad-hoc signature verification succeeded. Intermediate AppKit actor-isolation warnings were corrected by keeping fault state in a main-actor value object, accessed only on a main-thread callback. No unchecked AX handle sendability was introduced.

Accept the scoped positive detection, explicit limits/budget/cycle outcomes, native-sheet exclusion, synchronized pause recovery, and separate-worker response observations. Direct foreground/menu acceptance with the new scanner, sheet-tree mutation during a scan, and nested-read-specific mid-request permission/focus rejection remain pending. Earlier M2.2 lifecycle evidence remains scoped to its earlier reader and is not silently promoted to new nested-scan coverage. Structural completeness does not close lifecycle, native-tab, or visibility proof requirements. Production mutation scope remains empty.

## M2.4 foreground and nested-read lifecycle acceptance — 2026-10-05 05:05–05:29 UTC

Added `scripts/nested-lifecycle-lab.swift`, a Swift/Apple-framework-only local controller with private FIFOs, LaunchServices launches, bounded fresh-event correlation, and an explicit redacted report/trace transcript. It launches only iTile and the two owned fixture bundles. Fixture commands now support synthetic sheet-link removal, native AppKit sheet opening, and activation of the owned control fixture from within a structural children accessor. None changes production AX budgets, admission, or mutation behavior. The installed iTile executable remained unchanged (SHA-256 `e83729432ef8b642b8617797002b8813798889081cbfdcccfee15bd4f20e0fd9`), preserving the refreshed bundle grant.

The normal foreground handler, rather than the targeted backend bypass, presented the nested-sheet fixture as sheets=1, dialogs=0, nodes=3, complete, direct sheets=0, with `sheetPresent` exclusion. Repetitions after permission and focus recovery confirmed the same positive result. On macOS 27.0.1 (26A434), the final transcript established:

| Scenario | Correlated uptime evidence | Observed result |
| --- | --- | --- |
| Sheet-link removal, request 16 | worker 90284.244354–90284.246468; removal 90284.246294–90284.246350 | Historical positive retained: sheets=1, nodes=3, complete, `sheetPresent`; removal does not erase evidence already observed |
| Native sheet opening, request 17 | worker 90284.453325–90284.486287; opening 90284.454791–90284.479907 | Parent structural sample had no nested sheet, but final focused-window equality was false and `focusChanged` excluded the observation |
| Focus switch, request 18 | worker 90294.059577–90294.228574; switch began 90294.061320; focus invalidated 90294.065682; owned control confirmed foreground 90294.221307 | Completion discarded at 90294.228784; fresh nested-sheet inspection presented at 90294.393555 |
| Effective permission loss, request 7 | worker 90252.898460–90253.882012; nested budget began 90252.901082; trust=false 90253.820457 | Invalidation at 90253.820518 and discarded completion at 90253.882063; permission-missing report, no stale observation retained |
| Permission recovery, request 15 | restored settings switch on; app trust=true 90283.891907; fresh worker 90284.045200–90284.050074 | New epoch 8/token window-3, nested-sheet finding and exclusion; no replay of the prior observation |

The permission race used at most three successive ordinary-handler requests with bounded status sampling. Earlier requests still saw trust=true and are not counted as revocation evidence. Only iTile's existing settings switch was toggled; it was restored to on, with effective trust=true verified through the same LaunchServices app. Repeated missing-trust status refreshes advanced the invalidation epoch; this is diagnostic behavior, not enrollment recovery.

The user performed the actual **Inspect focused window** menu action and replied done. Trace request 2 in the earlier session ran at uptime 90035.057196–90035.085618 and presented at 90035.087970. Its report selected a different foreground application, with a standard window, nodes=31, complete, and unknown eligibility. This establishes actual menu delivery through the new scanner, not a second nested-sheet fixture result. No application content was recorded.

Two self-hide attempts failed to demonstrate focus loss. The instrumented attempt explicitly reported `nested-hide-rejected` and `nested-still-frontmost`; its presented result is not counted as rejection evidence. Switching between owned fixture applications subsequently established actual mid-read focus invalidation and discard, twice. A queued activation/revalidate attempt lacked activation-completion synchronization and is also not counted as historical-token acceptance.

Accept these scoped foreground/menu, sheet-transition, observed nested-read focus/permission discard, and fresh recovery results. They do not prove uninterrupted lifecycle continuity, generic tree coverage, native-tab safety, current-desktop visibility, or eligible mutation scope. Next: read-only native-tab evidence and an enforceable conservative focused-window exclusion policy. Window mutation remains disabled.

Verification passed strict formatting, all 71 tests (60 core, 11 platform), debug builds, plist/script checks, and Swift 6 typechecking of the controller. Owned lab processes were stopped and iTile relaunched in normal mode after the checks.

### Permission-context preflight and final recovery

The user authenticated directly in macOS when changing only iTile's existing access; no credentials were entered or collected by the agent. The settings switch became off. However, an iTile executable launched directly as a terminal child still reported trusted=true. This launch context did not establish effective revocation; inherited responsible-process access is a plausible explanation, not a separately traced TCC conclusion. Do not use terminal-child trust to validate iTile's own bundle grant.

Launched the final app through public LaunchServices (`open -W --stdin` / `--stdout`) with a private local FIFO and redacted output file. It reported `manual-ready trusted=false`; a `status` sample at uptime `87166.31004745833` confirmed false and the explicit fixture request was blocked. This was an untrusted-start check, not loss during an outstanding request or invalidation of a previously stored token in the same process.

Toggling the old settings entry back on did not restore effective trust. Refreshed only the same exact `dist/iTile.app` entry by removing its stale entry and selecting the rebuilt bundle in the native picker; no other app permission changed. The still-running LaunchServices-launched app reported trusted=true at `87308.58233141668`. A fresh nested-sheet sample ran at `87312.056740625`–`87312.07991558334`: `app-1/window-1`, environment 4, sequence 1, three nodes, one sheet, complete, and `sizeNotSettable, sheetPresent` exclusions. This accepts scoped blocked-start/recovery with the final bundle's own permission context. Nested-read-specific in-flight revocation remains pending.

Final executable hashes: iTile `e83729432ef8b642b8617797002b8813798889081cbfdcccfee15bd4f20e0fd9`; fixture `93a2a356c7f51787f74582943322dc9118e2c72041c4e1b00a2909ad43f69e7c`. The earlier synthetic/native and synchronized race samples used intermediate verified manual-driver builds with the same structural backend; the final bundle additionally carries the visible manual-mode indicator and clears historical comparison references for targeted samples. Its actual LaunchServices nested-sheet recovery was checked after those edits. Final `scripts/verify` passed without compiler warnings; no source edits followed it.

The LaunchServices bridge and owned fixture exited with status 0. Other disposable controller runs also stopped both fixture processes and iTile. Relaunched iTile normally without manual, startup-report, or trace flags. Its existing permission is restored. TextEdit's disposable blank document/Print panel was closed without saving or printing. No production window mutation or keyboard capture was enabled.


## 2026-10-05 — M2.5 tab-group exclusion source and live preflight

Extended the existing bounded structural traversal with `AXTabGroup` recognition and content-free group counts. Positive groups produce `tabGroupPresent` even with incomplete scans; absence never clears `nativeTabSafety`. No additional AX IPC, title/value reads, mutation, or input interception was added. The owned fixture now supports explicit synthetic groups/cycles and native AppKit tab creation, selection, and closure under `--tab-probe`. See [M2.5](m2-native-tabs.md) for the policy and separate acceptance checklist.

`scripts/format` and `scripts/verify` passed all 74 tests (63 core, 11 platform; count corrected from the separate suite summaries during the M2.6 review), debug builds, plist validation, and script syntax checks. Three new tests cover tab counts/radio-button non-detection, incomplete/bounded findings, and simulated admission rejection. Local release packaging and owned-fixture ad-hoc signature verification also succeeded.

The user described the current environment as a closed-lid laptop with two external monitors. This is test context, not a display validation pass. Host OS is macOS 27.0.1 (26A434), arm64. Packaged iTile executable SHA-256: `40746ecbe07158f928782c79cf758ae764d04a29b4ac480ed1fdb3aa6c628644`; fixture: `af46327b1777f9f5831ef03cf05799b3083dd40671b293e553700c370c7caeb8`.

LaunchServices preflight of the rebuilt iTile bundle reported `manual-ready trusted=false`. The controller stopped before launching the fixture or requesting AX reads and quit its iTile instance normally (LaunchServices exit 0). Requested refresh of only the existing iTile Accessibility entry. This is an effective-untrusted-start observation, not accepted native-tab coverage or a revocation race. Native-tab and foreground-handler acceptance remain pending; mutation remains disabled.


## 2026-10-05 15:55–15:56 UTC — M2.5 owned native tabs and focused-handler acceptance

The user refreshed only the existing iTile Accessibility entry by toggling it off/on. LaunchServices startup of the same packaged hash reported `manual-ready trusted=true`; no rebuild or source change intervened. Native runs used the same macOS/build and hashes recorded in the preceding preflight. Disposable iTile and fixture instances exited through their own `quit` commands, with LaunchServices exit 0 for both after each run.

The first sequence used explicit `fixture` backend samples (foreground delivery deliberately bypassed). The owned AppKit `NSWindowTabGroup` emitted count 2 after opening/selecting tabs and count 1 after closing the second tab. At environment epoch 0:

| Sample | Token / sequence | Structural result | Eligibility |
| --- | --- | --- | --- |
| Ordinary native baseline | app-1/window-1 / 1 | 0 groups, 7 nodes, complete | unknown |
| Second native tab opened, first selected | app-1/window-1 / 2 | 1 group, 13 nodes, complete | ineligible: tabGroupPresent |
| Second native tab selected | app-1/window-2 / 3 | 1 group, 11 nodes, complete | ineligible: tabGroupPresent |
| First native tab selected again | app-1/window-1 / 4 | 1 group, 13 nodes, complete | ineligible: tabGroupPresent |
| Second tab closed | app-1/window-3 / 5 | 0 groups, 8 nodes, complete | unknown |
| Synthetic group | app-1/window-3 / 6 | 1 group, 3 nodes, complete | ineligible: tabGroupPresent |
| Synthetic cyclic group | app-1/window-3 / 7 | 1 group, 3 nodes, cycle | ineligible: tabGroupPresent |

The second sequence, requested at 15:56:27–15:56:29 UTC, called ordinary `inspect`/`revalidate` handlers through the explicit stdin driver. Fixture activation acknowledgment preceded each request; commands selected tabs only inside the owned app. Reports recorded `focused-window-unchanged-at-checks=true`. Baseline was `app-1/window-1`, sequence 1. Opening the second tab retained that token, sequence 2, with expected-token-match=true and positive tab exclusion. Switching to the second tab returned `app-1/window-2`, sequence 3, with expected-token-match=false and `tokenChanged, tabGroupPresent`. Returning to the first and revalidating rejected the absent historical reference. Fresh inspection recovered `app-1/window-1`, sequence 4, still excluded for its group.

Closing the second tab returned `app-1/window-3`, sequence 5, with expected-token-match=false and `tokenChanged`. Fresh inspection recovered the same new token at sequence 6 with zero groups and unknown eligibility. These observations show that closing another tab can retire the original token; no stable container identity is claimed. Normal handler reports observed usable display areas `(0, 30, 1920, 987)` and `(-1920, 30, 1920, 1050)`, both scale 1.0. This matches the user's two-external-monitor context but does not independently verify lid state, physical coordinate accuracy, or display/lid transition handling.

Accepted scope: owned native AppKit tab detection, conservative exclusion, historical mismatch/rejection, and fresh recovery through the ordinary focused handlers; synthetic positive findings retained with a cycle. This is not actual-menu delivery, mid-read tab switching, Finder/TextEdit native-tab coverage, generic native-tab absence, visibility proof, or live mutation safety. All observations retain `currentDesktopVisibility, nativeTabSafety, nestedDialogSafety`. No production source edits followed the passing M2.5 verification (74 tests across its separate core/platform runners). Next: representative application native-tab coverage, then current-desktop visibility and enforceable supported scope before live coordinator/setter integration.


## 2026-10-06 17:03–17:09 UTC — Finder/TextEdit native-tab reader acceptance

Used the existing M2.5 release without rebuilding. Packaged iTile SHA-256 remained `40746ecbe07158f928782c79cf758ae764d04a29b4ac480ed1fdb3aa6c628644`. Host: macOS 27.0.1 (26A434), arm64. TextEdit: version 1.21, build 419. Finder: version 27.0, build 1865. Earlier normal-handler reports observed the same two scale-1.0 displays and negative-x external origin as the prior run; no physical display/lid transitions were performed or independently validated.

### Setup failure excluded from acceptance

An initial attempt used CUA to manipulate blank TextEdit tabs and a LaunchServices `--manual-probe` instance to invoke ordinary focused handlers. CUA acted on TextEdit in the background; a later content-free public `NSWorkspace.frontmostApplication` query reported another foreground application. Those reports cannot establish TextEdit token behavior. The temporary Python report poller also compared text outside the report delimiters, which could accept an old report while waiting for a new backend result. All reports from that initial attempt are excluded from native-app acceptance. The separate iTile test instance exited normally. The earlier apparent unchanged-token claim is not a TextEdit result.

### Accepted reader method

A temporary Swift CLI helper linked the existing release `ITileCore.o` and `ITilePlatform.o` and called public `WindowProbe.inspectFocused` on the production dedicated worker. It resolved only the fixed Finder/TextEdit bundle identifiers, maintained separate workers and historical tokens, and passed the expected token on revalidation. A semaphore waited up to eight seconds for the exact completion before printing each sample. No AX handles crossed the worker boundary. The helper printed content-free reports and fixed lane/sample names; no window titles, text, document paths, actions, or setters were requested by the reader. Only CUA manipulated the temporary native UI.

The helper reported effective trust from its launch context. This is not a new test of iTile's own bundle permission, frontend admission, current-desktop visibility, or normal menu delivery. Reference clearing after mismatch was helper bookkeeping; the worker's observed mismatch and eligibility are production results. Environment epoch was fixed at zero, so these samples do not validate environment invalidation. No production source was changed.

TextEdit used blank unsaved documents. A visible one-tab bar was the accepted baseline; UI snapshots verified both tab selections. Finder used one explicitly created window and two empty temporary folders, with UI snapshots verifying the selected tab. Existing application documents/windows were not merged or closed by a global command.

| Application/sample | Token / sequence | Tab groups / nodes / outcome | Expected comparison | Eligibility exclusions |
| --- | --- | --- | --- | --- |
| TextEdit visible one-tab baseline | app-1/window-1 / 1 | 1 / 50 / complete | not requested | tabGroupPresent |
| TextEdit second tab selected | app-1/window-2 / 2 | 1 / 53 / complete | false | tokenChanged, tabGroupPresent |
| TextEdit first tab, fresh read | app-1/window-1 / 3 | 1 / 53 / complete | not requested | tabGroupPresent |
| TextEdit second tab closed | app-1/window-1 / 4 | 1 / 51 / complete | true | tabGroupPresent |
| TextEdit fresh after closure | app-1/window-1 / 5 | 1 / 51 / complete | not requested | tabGroupPresent |
| TextEdit tab bar hidden | app-1/window-1 / 6 | 0 / 47 / complete | not requested | none; unknown eligibility |
| Finder ordinary empty-folder baseline | app-2/window-1 / 1 | 0 / 64 / nodeLimit | not requested | none; unknown eligibility |
| Finder second tab selected | app-2/window-2 / 2 | 1 / 64 / nodeLimit | false | tokenChanged, tabGroupPresent |
| Finder first tab, fresh read | app-2/window-1 / 3 | 1 / 64 / nodeLimit | not requested | tabGroupPresent |
| Finder second tab closed | app-2/window-1 / 4 | 0 / 64 / nodeLimit | true | none; unknown eligibility |
| Finder fresh after closure | app-2/window-1 / 5 | 0 / 64 / nodeLimit | not requested | none; unknown eligibility |

All accepted observations reported standard, non-minimized/non-fullscreen/non-modal windows, writable geometry attributes, successful destruction notification registration, and sampled focused equality. After each second-tab mismatch, a revalidation attempt without a reference was rejected by the helper, then fresh inspection recovered the first token. In both applications, closing the second tab preserved the first token, unlike the owned fixture's earlier retirement observation. No general closure/identity rule is inferred. The TextEdit hidden-bar sample and Finder incomplete zero-group samples retained unknown eligibility and all three unproven requirements. Finder's positive finding survived its node limit, as required.

Temporary blank TextEdit documents and the temporary Finder window were closed through their own controls/menu. No document contents were typed or saved. The reader stopped its workers and exited normally; the LaunchServices test instance also exited normally. No production behavior correction was justified, and no new automated verification run is claimed for these documentation-only changes.

Accepted scope: production-reader native-tab detection, historical-token mismatch, and fresh recovery for these Finder/TextEdit versions and UI sequences, including retained positive Finder evidence under node limits. Not accepted: generic tab absence, native frontend/menu delivery, mid-read tab transitions, lifecycle continuity, visibility proof, or mutation safety. Next task: current-desktop visibility evidence and an enforceable supported scope; real enrollment/coordinator/setter integration remains gated.


## 2026-10-06 — M2.6 on-screen bounds candidate source

Added pure `OnScreenBoundsEvidence` and worker-side sampling to explicit focused inspection. Only owner/layer/bounds fields are decoded; no titles, CG window numbers, capture APIs, actions, or setters were added. Finite positive bounds use one logical point per-component tolerance, preserve negative origins, and remain candidates with explicit ambiguity/incomplete outcomes. Retention is limited to 128 inspected-app entries, with deadline/cancellation checks and conservative malformed-owner handling. The synchronous system metadata call/allocation is not interrupted or globally allocation-bounded. Final focused worker return now rejects a request exceeding the existing five-second request limit after revalidation as well.

Added six deterministic tests for candidate matching/collision/absence, malformed/overflowing geometry, limits, negative coordinates/tolerance, and retained visibility requirements plus simulated Tile rejection. `scripts/format` and `scripts/verify` passed, including strict lint, debug builds, 80 tests (69 core, 11 platform), three plist checks, shell syntax, and the existing lab-driver Swift typecheck. Verification was repeated after adding the owned visibility fixture commands, with the same 80 tests passing. Source and test behavior is distinct from the live observations below.

The current generic production mutation scope remains empty. A complete single bounds candidate does not correlate CG to AX or clear `currentDesktopVisibility`; empty or malformed lists do not infer off-desktop state. See [M2.6](m2-desktop-visibility.md).

## 2026-10-07 02:45 UTC (October 6 local) — Owned overlap/hide/recovery reader acceptance

A temporary Swift reader linked the production debug core/platform objects and targeted only the owned fixture by its fixed bundle identifier. The fixture ran with `--focused-probe --visibility-probe` inside a separate temporary ad-hoc app bundle. It used public AppKit APIs to create one un-tabbed same-frame peer, close it, hide itself, and restore its original window. The installed iTile bundle was not rebuilt/replaced and its existing normal instance was not stopped by the controller.

Host: macOS 27.0.1 (26A434), arm64. Debug core object SHA-256: `c1a75064e762b67c7c5cf706556778c805569a051ff756fa1846eb6cce4cc14c`; platform: `42a66d182f2bec0df8cd00e2bdaab583d426f2a37a21d996a8efe7de71fe56de`; owned fixture executable: `3fbdcb5c0a9344fed4a9dbfc48ca814279e80d9ac147cc3d89f52e6321a01e64`. The reader's effective-trust=true startup describes its launch context, not the updated iTile bundle's grant. No Screen Recording permission was requested.

Setup limits/failures are not passes: the unbundled debug fixture was not discoverable by bundle identifier, so the first attempt stopped before a sample. A subsequent controller incorrectly compared a timestamped equality event against an untimestamped exact string; it stopped after a one-candidate baseline. An immediate unsynchronized peer sample still showed one CG entry despite the owned equal-frame acknowledgment. That sequence failed its expected-two assertion and does not establish settled overlap coverage. Both processes exited normally after every attempt. The corrected sequence allowed 0.2 seconds after owned UI change acknowledgments and recorded actual sample results; this delay is lab scheduling, not a production timing guarantee.

At host uptime `153725.11692104168`, the fixture emitted `visibility-peer-equal`, establishing equality of its own two AppKit frames. The reader waited for each exact production-worker completion before advancing. Environment epoch was fixed at zero; AX frame was `(200, 922, 420, 158)` throughout the accepted sequence. Display count/scale and physical lid state were not queried in this late run, so the user's earlier two-monitor context is not relabeled as a new display validation pass.

| Reader sample / UTC | Token / sequence | Layer-zero entries / bounds candidates | Outcome |
| --- | --- | --- | --- |
| Baseline / 02:45:31 | app-3/window-1 / 1 | 1 / 1 | singleBoundsCandidate, complete |
| Equal overlapping peer / 02:45:31 | app-3/window-1 / 2 | 2 / 2 | ambiguousBoundsCandidates, complete |
| Peer closed / 02:45:32 | app-3/window-1 / 3 | 1 / 1 | singleBoundsCandidate, complete |
| Fixture hidden / 02:45:32 | app-3/window-1 / 4 | 0 / 0 | noBoundsCandidate, complete |
| Restored / 02:45:32 | app-3/window-1 / 5 | 1 / 1 | singleBoundsCandidate, complete |

The peer geometry was intended to cover the original window, but no pixel visibility or CG/AX identity was inferred. The hidden sample reported `AXDialog` subrole despite stable token/frame, while other samples reported `AXStandardWindow`; no cause or general hidden-window classification rule is assigned. All samples had size-settable=false and remained ineligible. Every sample retained `currentDesktopVisibility, nativeTabSafety, nestedDialogSafety`. Reader intervals were 69.658, 11.464, 6.769, 2.305, and 5.395 ms respectively; these include the complete focused backend and are not CG-call-only benchmarks.

Accepted scope: real worker-side candidate counts, equal-bounds ambiguity, absent metadata while the owned app was hidden, and fresh read recovery on restoration. The controller stopped the reader and fixture through their own `quit` commands; both exit statuses were zero. No source edits followed final passing verification; subsequent edits record these observations only.

Not accepted: current-desktop identity proof, pixel occlusion proof, independent-display Space membership, environment invalidation, frontend/menu delivery, rebuilt-bundle trust lifecycle, generic performance, or any real mutation. Next task: same-app/same-size windows across native desktops, followed by an enforceable supported-scope decision. Public bounds evidence alone must continue to block control.


## 2026-10-07 03:29–03:31 UTC (October 6 local) — Owned equal-frame cross-desktop reader acceptance

Added fixture-only `--desktop-probe` instrumentation using public `NSWorkspace.activeSpaceDidChangeNotification`, owned `NSWindow.isOnActiveSpace`, own-process focused-window status, and display count. The new peer alone uses `.moveToActiveSpace`; the original retains its collection behavior. No private Space identifiers, user application mutation, synthetic keys, or additional production visibility inference were introduced. `scripts/format` and final `scripts/verify` passed all 80 tests (69 core, 11 platform) after these source changes.

The CUA connection timed out while inspecting desktop controls. The operator switched native desktops instead. An initial round trip produced owned active/inactive events, but the operator had returned before a peer sample could be taken; that run is not cross-desktop collision acceptance. Both helpers exited normally. A subsequently armed controller reacted to the native event, created the owned peer, waited 0.2 seconds, checked owned status around the exact reader completion, and sampled before the operator returned. The user then confirmed completion.

Host: macOS 27.0.1 (26A434), arm64. Fixture executable SHA-256: `0b707549606dd2fc337c7ad716d7e196fc20c445152a0b9f2478de4d87709018`. Debug core and platform objects retained the hashes from the M2.6 overlap run. The fixture reported one display throughout; neither the earlier two-monitor setup nor physical lid state is validated by this run. Reader effective trust describes its terminal launch context, not the installed iTile bundle's grant. The existing normal iTile instance was not replaced or stopped.

| Sample / UTC | Owned active-Space status | Own focused source | AX token / sequence | Bounds candidates |
| --- | --- | --- | --- | --- |
| Baseline / 03:29:27 | Original active; peer absent | original | app-3/window-1 / 1 | 1, complete |
| Other desktop with equal-frame peer / 03:31:04 | Original inactive; peer active | original | app-3/window-1 / 2 | 1, complete |
| Returned / 03:31:18 | Original active; peer inactive | original | app-3/window-1 / 3 | 1, complete |
| Peer closed / 03:31:18 | Peer closed after return | not resampled separately | app-3/window-1 / 4 | 1, complete |

The away event occurred at host uptime `156339.77157275`. Immediately before/after the cross-desktop read, owned status at `156340.19489058334` and `156340.2120127917` reported original inactive, peer active, equal frames, focused source original, and fixture not frontmost. The reader interval was `156340.19733675002`–`156340.208732125`, with AX frame `(790, 420, 420, 158)`, one ordinary CG entry, one candidate, and unchanged focused-window equality at its checks. On return, the event at `156353.9625345` reversed the owned active-Space states; status around sequence 3 retained equal frames and focused source original. The baseline frame had been `(200, 922, 420, 158)`; its later position differed, and this run does not identify the cause or claim geometry stability over the operator interval.

Accepted scope: a complete single same-PID bounds candidate coexisting with the sampled original AX window off the active Space, with an equal-frame owned peer active there; returned and peer-closed reader recovery. This is a scoped counterexample to unique geometry proving current-desktop AX identity. Own AppKit status is fixture ground truth, not an available provider for arbitrary applications, and no CG window identity was decoded. Every sample retained `currentDesktopVisibility, nativeTabSafety, nestedDialogSafety` and the `sizeNotSettable` exclusion. No window became eligible.

The reader's environment epoch was fixed at zero and requests targeted the fixture even while another application was frontmost. This does not accept native frontend/menu delivery, transition invalidation, atomic sampling, independent-display Spaces, Stage Manager/fullscreen, arbitrary-app membership, pixel visibility, or real mutation safety. The controller quit the reader and fixture through their own commands; both exited zero. No source changes followed the passing verification; subsequent changes document results only. Next: assess an enforceable supported scope, retaining the empty production mutation scope unless identity-correlated evidence and lifecycle gates are established.


## 2026-10-06 local — M2.7 supported-scope review

Reviewed the current eligibility assessment, focused evidence projection, app request/delivery guards, pure control model, control contracts, and the recorded structural/visibility experiments. Cross-checked the reviewed API semantics against Apple's documentation for `AXFocusedWindow`, `CGWindowListCopyWindowInfo`, and `NSWindow.isOnActiveSpace`; references are in [ADR 0004](decisions/0004-supported-scope.md).

Decision: no reviewed provider establishes all current production eligibility requirements, so the supported mutation scope remains empty. The background cross-desktop counterexample rejects geometry-only correlation but does not disprove every future foreground-only strategy. Owned AppKit ground truth and user consent are not generic production providers. The review specifies acquisition, coverage, expiry, invalidation, per-call admission, residual race disclosure, and separate manual acceptance requirements for any later scope proposal.

Next implementation task is read-only integration of accepted production observations with the pure control model and explicit blocked-preview reporting. That integration is proposed, not implemented or manually accepted. No source or permission changes, user-window actions, new tests, or new live experiment occurred during this review. Documentation link checks and `git diff --check` passed; the previous 80-test source verification remains the latest automated source result, not a newly run test suite.


## 2026-10-07 03:39–03:40 UTC (October 6 local) — M2.8 preview source and foreground-handler acceptance

Implemented pure `ReadOnlyPreview` with persistent bounded `ControlModel` state, focused evidence projection, fixed block outcomes, validated single-window targets, and a local effect-consumption boundary with no platform control handlers. Added **Preview focused tiling (read-only)** and a fixed `preview` command to the existing explicit manual driver. App lifecycle reductions remain on the main actor; blocking AX stays on its dedicated worker. The wrapper's environment epoch is authoritative for both app requests and model observations; request counters and activation revisions remain independent.

Twelve new core tests exercise unknown/ineligible production projection into blocked plans, old sequences and expired delivery, pause/resume freshness, permission epochs/recovery, desktop and activation context, request replacement, process replacement, malformed/future evidence, terminal Quit, ordered serial introduction, negative-origin/offscreen display targeting, and bounded 256-window storage. Final `scripts/format` and `scripts/verify` passed 92 tests (81 core, 11 platform), strict formatting, debug build, plist checks, shell syntax, and lab-driver typecheck. The first verification passed 90 tests before the final target-selection and capacity tests were added. A later sandboxed invocation could not start SwiftPM's manifest sandbox; the final 92-test run succeeded outside that restriction. No external dependencies were downloaded.

Host: macOS 27.0.1 (26A434), arm64. Debug iTile SHA-256: `1114a2fb5d4b9320f37568009682b72bd3057f111033b41bfe44a892a4efa9ad`; fixture: `fb1d1a1bde1092241058757bae7d84b3369c2e291b078d362226d3f6fceba211`; core object: `e031bf0ab19f18a62c4e73fa642174ecf80a59e3e3fd05b1a04c38467cef4d18`; platform object retained `42a66d182f2bec0df8cd00e2bdaab583d426f2a37a21d996a8efe7de71fe56de`. Both disposable app bundles were ad-hoc signed. The controller launched their executables as terminal children, so effective-trust=true is not a test of iTile's own rebuilt bundle grant. The installed iTile app was not replaced or stopped by the controller.

Each accepted sample used the ordinary foreground handler registered by the menu through the explicit stdin driver. The owned fixture's public `activation-confirmed` acknowledgment preceded requests, and the app independently checked source process lifetime, frontmost state, activation revision, epoch, trust, and pause at delivery. The controller waited for a new delimited report before advancing; fresh recovery reports had to differ from the preceding accepted sample.

| Check | Result |
| --- | --- |
| Baseline preview | app-1/window-1, epoch 0, sequence 1; complete single bounds candidate; ineligible with sizeNotSettable; model invalidPlan |
| Pause then request preview | Existing paused report retained; no new focused sample admitted |
| Resume then fresh preview | app-1/window-2, epoch 2, sequence 2; model invalidPlan; new token after environment invalidation |
| Fixture hides itself during focused AX read | Focus-change report: pending result discarded; no preview projected |
| Fresh recovery after focus loss | app-1/window-2, epoch 2, sequence 4; model invalidPlan |

All accepted preview reports retained `currentDesktopVisibility, nativeTabSafety, nestedDialogSafety` and stated no window was enrolled or moved. Proposed frame was `(0, 30, 2048, 1187)`, from the single scale-1.0 usable area captured at request start. Fixture AX frame remained `(200, 922, 420, 158)` in baseline and accepted recoveries. These reads do not establish physical coordinate accuracy, the earlier two-monitor setup, or geometry writes. Both disposable processes exited zero through their own Quit commands.

Accepted scope: real foreground-handler/report delivery into blocked model plans, pause between reads, fresh resume, observed focus-loss discard and recovery, plus deterministic lifecycle/bounds tests. Not accepted by this sequence: physical menu clicking, representative native applications, preview-specific in-flight permission/Space/display/pause races, live registry completeness, frontend performance, or any production mutation. The complete registry/lifecycle and eligibility gates remain open. See [M2.8](m2-read-only-preview.md).

### Native menu check setup

A subsequent disposable app used the same verified binary and showed its initial report. An initial noninteractive controller immediately reached stdin EOF and quit normally; no menu coverage is claimed for that attempt. The corrected interactive controller kept the app open. CUA inspected its report and created one blank unsaved TextEdit window, with no text entered. Connecting CUA to SystemUIServer to inspect menu extras timed out. A CUA-driven source selection plus ordinary driver preview produced a blocked report, but the sampled source application was not independently identified; that report is excluded from TextEdit or actual-menu acceptance. An operator menu check was requested with the ready, concrete test app. Its accepted result is recorded below.


### 2026-10-07 03:51:15 UTC — Operator-driven TextEdit menu acceptance

Following the explicit request to activate the disposable blank TextEdit window and choose **Preview focused tiling (read-only)**, the user supplied a new report. The interactive controller independently retrieved the identical report from the still-running test app. Its request timestamp advanced from the excluded 03:46:36 setup report to 03:51:15, with a different app token and window geometry matching the 603-by-505 blank TextEdit window inspected through CUA. This is operator-driven menu acceptance, not automated SystemUIServer interaction or a new bundle-permission test. Source identity is supported by the operator action and matching owned test-window context; no additional production application-name logging was added.

The fresh sample was `app-2/window-1`, epoch 0, sequence 2, with AX frame `(714, 326, 603, 505)`, writable position and size, standard/non-minimized/non-fullscreen/non-modal flags, no direct sheets, and a complete 46-node structural scan with zero sheets/dialogs/tab groups. It returned one complete bounds candidate and unknown eligibility with no positive exclusions. All three requirements remained unproven. Its worker interval was `157551.53272308334`–`157551.55454895835` (21.826 ms for the complete focused read, not a platform performance guarantee).

The report proposed `(0, 30, 2048, 1187)`, then displayed `planRejected` / `invalidPlan` and **No window was enrolled or moved**. This confirms actual menu/report delivery into a blocked plan for a real unknown-eligibility sample; zero groups and one candidate did not grant eligibility. No source correction was required. The latest source verification remains the 92-test run above; only documentation changed afterward.

CUA closed only the disposable blank TextEdit document, without a save dialog or writing content, and verified return to the preexisting Open panel. The interactive controller quit its temporary iTile app normally (exit 0). This completes the scoped menu check. Preview-specific in-flight pause/environment/permission races, complete bounded registry/lifecycle integration, and all production mutation gates remain separate tasks.


## 2026-10-07 03:59 UTC (October 6 local) — Preview-specific in-flight Pause acceptance

Used the verified M2.8 debug app without source changes, an owned fixture with a one-shot delayed window-role accessor, and opt-in `FocusedProbeTrace` collection limited to iTile's trace category. The app/fixture ran in disposable ad-hoc bundles as terminal children; this is not bundle-permission acceptance. A baseline blocked preview was followed by a fresh preview through the normal foreground handler. The controller waited for the owned `window-read-begin` acknowledgment before sending Pause, then correlated the same request's backend and main-thread delivery events. Debug app and fixture hashes remained those recorded for M2.8.

For request 2, worker start was `158041.722693`, owned delayed accessor begin `158041.72312083334`, Pause command completion `158041.72576420836`, backend finish `158043.251054`, and discarded main-thread completion `158043.251196`. Pause is strictly inside the observed backend interval. The report remained **Inspections paused. In-flight reads may finish; their results are discarded.** No late focused evidence or preview replaced it. The 1.528-second backend interval is one deliberately delayed observation, not an interruptibility or timeout guarantee.

After the fixture's delayed accessor ended, Resume and a new foreground preview recovered `app-1/window-2`, epoch 2, sequence 3, with the expected `planRejected` / `invalidPlan` and all three unproven requirements retained. No control effect performed platform work. Both app and fixture exited normally with status zero; the owned log-stream helper was terminated and reaped (status -15). No source correction was required and no new automated source verification is claimed.

### LaunchServices permission-test preparation

Packaged the verified read-only preview source into `dist/iTile.app` with `scripts/package-app`; release build and strict ad-hoc signature verification passed. SwiftPM's sandboxed manifest launch initially failed, so packaging was repeated outside that restriction. A private FIFO controller launched this exact bundle through public LaunchServices, with manual driver, initial report, and content-free request tracing. Startup reported `manual-ready trusted=false`. This is an effective-untrusted-start preflight, not permission-loss acceptance.

System Settings showed only the existing iTile access entry enabled, while the rebuilt LaunchServices instance remained untrusted. Requested refresh of that existing entry. macOS required direct operator authentication; no credentials were entered or collected by the agent. Release executable SHA-256: `0094e345595dea5956df6fc8178d4bde361724bb4b227dda9fbc0619ac40f1c7`. After the user authenticated directly, the existing iTile switch was observed off and restored to on, but the LaunchServices instance still reported effective trust=false. CUA then timed out while selecting the iTile row and returned an unrelated row selected; no removal or permission change was performed on that row. Requested an operator-driven refresh of only the same exact iTile bundle entry because native row selection was unreliable. Desktop and permission-loss checks remain pending this preflight. The live test retains its own bounded controller and owned fixture; no unrelated application permissions are being changed.


### LaunchServices permission refresh and fresh preview — October 6 local

The user removed and re-added only the exact rebuilt `dist/iTile.app` entry. The same still-running LaunchServices instance then reported effective trust=true. Its fresh normal-handler preview returned `app-1/window-1`, epoch 7, sequence 1, with AX frame `(226, 447, 420, 158)` and `planRejected` / `invalidPlan`. All three unproven requirements and `sizeNotSettable` remained. The release executable hash was unchanged. This accepts scoped untrusted-start/recovery for the rebuilt bundle in its own LaunchServices context; it does not accept in-flight revocation.

The first bounded permission-cycle attempt completed 12 previews while effective trust stayed true. CUA first required a refreshed app state, then macOS presented a direct-authentication sheet for switching off iTile's access. None of those 12 previews observed revocation inside its backend interval; this attempt is excluded from permission-loss acceptance. The operator was asked to authenticate directly, without exposing credentials, before another synchronized attempt. No other app switch was toggled.


## 2026-10-08 02:47 UTC (October 7 local) — Preview-specific desktop-change acceptance

The daemon restart interrupted the preceding run before an accepted permission-loss test. Recovery inspection found no accepted revocation interval in the saved transcript; the old controller/fixture were no longer running. A normal iTile instance remained, and the resumed lab launched a separate instance of the unchanged release bundle through LaunchServices without stopping it. The resumed test reported effective trust=true. No source or permission-grant expansion was performed during recovery.

An operator-driven native desktop test used bounded ordinary-handler preview requests against the owned fixture's delayed structural tree and content-free production request traces. The fixture reported one display and remained on its original desktop. The controller checked owned active-Space status before reactivation and stopped once the original was off the active Space, rather than pulling it onto the operator's desktop. Only the production request with a correlated environment event inside the backend interval is accepted; other completed or focus-discarded attempts are not desktop-race passes.

For request 15, worker start was `182997.940413`, app environment-change handling `182998.858086`, owned Space-change event `182998.9247167917`, owned status original-active=false `182998.92513791667`, backend finish `182999.008755`, and discarded delivery `182999.008915`. Both the app event and owned off-active-Space observation occur strictly inside the backend interval. Focus loss also occurred, so this establishes combined observed Space/focus invalidation and stale-result discard; it does not isolate a single causal guard or prove transition detection before every external change.

After the user returned, a fresh normal-handler preview at 02:48:50 UTC recovered `app-1/window-2`, epoch 14, sequence 14, with `planRejected` / `invalidPlan`, `sizeNotSettable`, and all three unproven requirements retained. The fixture's baseline frame `(200, 922, 420, 158)` and recovery frame `(124, 428, 420, 158)` differed; no cause or geometry stability across the operator interval is inferred. Multiple public environment notifications advanced the opaque epoch; it is not a count of physical desktop changes.

The resumed app and fixture exited normally with zero statuses; the owned log-stream helper was terminated and reaped. Accepted scope: this one-display owned-fixture native desktop sequence through the real preview handler, observed in-flight environment invalidation, discarded completion, and fresh recovery. Independent-display Spaces, fullscreen, Stage Manager, lock/wake, generic visibility proof, and mutation safety remain unvalidated. Source hashes and the latest 92-test verification remain unchanged.

## 2026-10-08 02:55–02:57 UTC (October 7 local) — Preview-specific permission-loss acceptance and recovery

Launched a separate instance of the unchanged release `dist/iTile.app` through LaunchServices, with an owned fixture, bounded manual-driver requests, and opt-in content-free production request tracing. Startup effective trust was true; the baseline normal-handler preview returned `app-1/window-1`, epoch 0, sequence 1. A one-shot 1.5-second owned window-role accessor provided the delayed backend interval. Only iTile's existing Device Control and Data Access switch was turned off. macOS required direct operator authentication; no credentials were entered or collected by the agent. Earlier attempts without effective trust loss inside the backend interval are excluded from acceptance.

For request 8, worker start was `183482.623350`, owned accessor begin `183482.62359045833`, last sampled trust=true `183482.713451`, first sampled trust=false `183482.791106`, model/report invalidation `183482.791181`, and untrusted status acknowledgment `183482.80544570833`. Owned accessor end was `183484.12464129168`, backend finish `183484.134821`, completion with trust=false `183484.145213`, and discarded delivery `183484.145301`. Observed effective permission loss and invalidation are strictly inside the backend interval. No late preview was installed. This accepts sampled trust loss and stale-result discard in the bundle's own LaunchServices permission context; it does not prove instantaneous revocation detection, isolate every causal guard, or guarantee interruptibility of AX calls.

Restored only the same iTile switch and confirmed it enabled in System Settings. The same running test app then reported effective trust=true. A fresh normal-handler preview at 02:57:44 UTC recovered `app-1/window-2`, epoch 27, sequence 7, with `planRejected` / `invalidPlan`, `sizeNotSettable`, and all three unproven requirements retained. Its frame `(182, 454, 420, 158)` matched this run's baseline; proposed area was `(0, 30, 2048, 1187)`, one display at scale 1. Repeated explicit untrusted status checks advanced opaque generations; epoch 27 is not a count of physical permission changes.

The test app and owned fixture exited normally with status zero; the owned log-stream helper was terminated and reaped (status -15). The preexisting normal iTile instance was not stopped. Strict ad-hoc signature verification passed after cleanup, and release executable SHA-256 remained `0094e345595dea5956df6fc8178d4bde361724bb4b227dda9fbc0619ac40f1c7`. No source correction was required. Documentation synchronization and local link/diff checks are separate from the latest 92-test source verification, which was not rerun for this documentation-only update.

The scoped preview-specific in-flight Pause, native desktop, and real permission-loss checks now have discarded-completion and fresh-recovery evidence. The next source task is a complete bounded registry/lifecycle protocol before live coordinator/admission integration. Preview-specific in-flight physical display changes and broader platform coverage remain unvalidated; production mutation scope remains empty.


## 2026-10-08 03:09–03:10 UTC (October 7 local) — M2.9 registry/lifecycle source and owned-handler acceptance

Implemented [bounded explicit-read registry/lifecycle synchronization](m2-registry-lifecycle.md). Worker replies now carry complete tracked-set replacements, revision and serial watermarks, including read failures. The app reduces those values before reply guards, with current attachment/epoch/revision checks; production previews require an accepted registry. Missing tokens retire model records, retained older tokens can be observed in either order, and watermark checks reject resurrection without accumulated tombstones. No live enrollment, setter dispatch, automatic polling, per-notification owner task queue, or permission-grant change was added.

`scripts/format` and final `scripts/verify` passed 99 tests (87 core, 12 platform) at October 7 21:13 local. The last sandboxed verification attempt failed at SwiftPM's nested manifest sandbox before building/tests; rerunning outside that restriction passed all checks. Seven added tests cover registry-required previews, retirement/resurrection, malformed/stale epoch/process state, per-worker/global bounds and recovery, snapshot delivery with failures on the worker thread, watermark persistence, and executing-slot retention until acknowledgment. Existing tests now accept retained older-window observations and verify bounded replacement churn over 256 fresh observations.

The separate real-window lab used disposable ad-hoc debug bundles as terminal children, an owned native-AppKit tab fixture, and the ordinary foreground preview handler through the explicit manual driver. Effective startup trust was true in that inherited context; this is not acceptance of the debug bundle's own grant. OS was Version 27.0.1 (Build 26A434), with one reported display at scale 1 and usable area `(0, 30, 2048, 1187)`. Debug app SHA-256: `32508bcb116839df64daccf98ca5d75462792d1969d19d208338a65729b5dca8`; fixture SHA-256: `fb1d1a1bde1092241058757bae7d84b3369c2e291b078d362226d3f6fceba211`.

The first lab attempt incorrectly accepted an unchanged previous report as its next sample and then lost the activation race. That sequence is excluded from acceptance; both test processes exited zero. The corrected controller required a strictly newer worker sequence before advancing, without changing production source. The accepted run recorded fourteen fresh reports from 03:09:21 to 03:09:27 UTC, all at environment epoch 0. Baseline/first-tab reports retained `app-1/window-1` (sequences 1–2), second-tab was window 2 (sequence 3), and return to the retained first tab accepted window 1 again (sequence 4). Closing the peer conservatively expired tracked identities and recovered window 3 (sequence 5). Three additional open/select-second/close cycles advanced tokens through window 9 (sequence 14). Each preview remained `planRejected` / `invalidPlan`; native groups retained `tabGroupPresent`, and all samples retained the three unproven safety requirements. The fixture frame remained `(200, 922, 420, 158)` in these reports, with no iTile window mutation.

Accepted scope: owned native-AppKit retained-window ordering, conservative destruction/rekeying, repeated peer close/recreation, and fresh registry-backed blocked-preview delivery. The model record-retirement/capacity claims additionally have deterministic tests; live reports alone do not measure every internal record. Both accepted-run test apps quit normally (exit 0). The normal installed app and release bundle were left unchanged. Final review also wired registry reduction into the separate backend-only manual sample driver; the normal foreground handler exercised above was unchanged, and that driver-specific change has automated verification rather than fresh live acceptance. Prior permission/Pause/Space acceptance remains historical evidence for its recorded source; those races, idle immediate destruction delivery, generic coverage, continuous enrollment, and mutation safety are not newly accepted here.

Next task: specify bounded worker-to-owner delivery acknowledgment and admission/overload ordering before a live coordinator. Recorded the user's requested running enable/disable management switch, mouse drag/resize coexistence, and native desktop-number feasibility in [product design](design.md); these remain planned, not implemented features.


## 2026-10-08 03:24 UTC (October 7 local) — M2.10 delivery/admission contract

Reviewed the existing worker mailbox, main-actor completion routing, registry replacement path, pure reducer, and prior control contracts. The worker currently clears its busy flag before invoking a completion; completion schedules owner work without an acknowledgment back to the worker. This task therefore specified [M2.10](m2-delivery-admission.md) rather than claiming that backend admission already bounds owner delivery.

The accepted implementation contract defines exact operation/receipt identities, one operation and retained reply per app through acknowledgment, one shared serialized drain chain, fixed queue/payload/worker bounds, explicit overload/quarantine behavior, and synchronous safety revocation independent of semantic command backlogs. A queued successor cannot overlap the current owner pass. The future setter extension requires per-step atomic admission, matching terminal denial dispositions, and actual completion acknowledgment; it preserves the possibility that an already admitted call finishes after pause. Observed signals do not establish uninterrupted external lifecycle safety.

Recorded required pure-state and barrier-controlled fake-backend checks, including delayed consumption, duplicate/wrong receipts, lost-wakeup races, stale process callbacks, saturation, blocked stop, superseded re-enable, and counter/payload failures. Next source task is the pure receipt state machine and read-only transport; live setters and eligible enrollment remain gated. Synced roadmap, architecture, preview/registry boundaries, testing, and README links. Corrected testing's stale latest-test count to the already recorded 99-test source result, not a new run.

This was a documentation-only task. No source, running app, permission grant, window, or package changed; no new automated source or real-window verification is claimed. Local Markdown link checks and `git diff --check` passed. The latest source verification remains 99 tests (87 core, 12 platform).


## 2026-10-08 03:37 UTC (October 7 local) — M2.11 acknowledged reply source and owned-handler acceptance

Implemented the [read-only receipt/transport subset](m2-read-only-delivery.md) of M2.10. Pure receipt state now holds an app read through exact terminal acknowledgment. Production workers expose acknowledged report/focused methods; all three app reply paths use a shared bounded main-actor drain rather than a separate task per callback. Occupied/duplicate/replayed receipts cannot replace current work, and Stop cannot be undone by acknowledgment. Stopped-but-retiring threads count toward the app's physical worker cap. Invalidated queued reads skip backend entry; read invalidation preserves the occupied slot. Delivered report text is capped at 64 KiB, and malformed/oversize registry sets are excluded without partial identity claims.

`scripts/format` and final `scripts/verify` passed 116 tests (91 core, 25 platform) at October 7 21:37 local. Seventeen new tests cover receipt identity/occupancy/stop/cancellation/exhaustion; held owner consumption through the actual dedicated worker; exact and late acknowledgments; queued and blocked cancellation; registry/report payload exclusion; full reply-slot limits and rotating batches; concurrent producers around a held scheduler wakeup; publication during owner consumption and after drain finalization; stale process/receipt routing; and terminal transport Stop. A test initially failed Swift's isolation check for a captured mutable flag; replacing it with a main-actor-owned helper fixed test compilation. A teardown expectation is not treated as proof that all final thread cleanup has already run. Final source checks passed without source changes during the accepted live sequence.

The live lab used disposable ad-hoc debug bundles as terminal children, the ordinary foreground preview handler through the explicit manual driver, an owned native-AppKit tab fixture, and opt-in content-free production tracing. OS was Version 27.0.1 (Build 26A434); effective startup trust was true in the inherited context, not proof of the debug bundle's own grant. Debug app SHA-256: `1e6107affbee522258a967bcc7267b320f5f3040353ecc4ade5256b9a05e17a1`; fixture SHA-256: `fb1d1a1bde1092241058757bae7d84b3369c2e291b078d362226d3f6fceba211`. The installed release bundle and permission grant were not changed.

The first controller attempt stopped after an overly strict baseline-token equality assertion: an observed environment notification advanced epoch 0 to 1 and the sampled usable-area height changed from 1187 to 1188 logical points. The worker conservatively rekeyed the original tracked window. Its fresh previews remained blocked, but this incomplete attempt is excluded from complete acceptance. Both test apps exited zero and its trace helper was reaped. The corrected controller compared retained tokens only within matching epochs; no production code correction was required.

The accepted run began at 03:37:08 UTC. Baseline was `app-1/window-1`, epoch 0, sequence 1. An environment event again advanced to epoch 1 before the first tab sample. First tab/window 2 (sequence 2), second tab/window 3 (sequence 3), and retained first tab/window 2 (sequence 4) accepted in that matching epoch. Peer closure and three additional open/select/close cycles recovered fresh tokens through window 10 (sequence 14). All previews remained `planRejected` / `invalidPlan`; native groups retained `tabGroupPresent`, and all samples retained the three unproven safety requirements. One display at scale 1 was reported; proposed areas were `(0, 30, 2048, 1187)` initially and `(0, 30, 2048, 1188)` afterward. No physical hotplug, desktop-number, or multi-monitor coverage is inferred from this notification.

For delayed preview request 16, production worker start was `185989.389846`, owned accessor begin `185989.39005520835`, Pause command completion `185989.39093416667`, backend finish `185990.893529`, and discarded owner delivery `185990.893963`. Pause is strictly within the backend interval. The paused report stayed installed. Resume followed by a fresh preview at 03:37:15 UTC recovered `app-1/window-11`, epoch 3, sequence 15, with the same blocked model result and unproven requirements. Fixture frame remained `(200, 922, 420, 158)` in accepted reports; no iTile window mutation occurred. This establishes scoped ordinary-handler delivery, observed in-flight Pause rejection, and fresh recovery. Deterministic tests additionally establish held-consumption capacity and receipt identity; live reports alone do not measure every transport slot.

The accepted test app and fixture exited normally with status zero, and the owned trace helper was terminated/reaped (status -15). The preexisting normal app was not stopped. Historical permission/Space experiments remain tied to their recorded source and were not repeated for this changed completion path. No live write gate, semantic command buffer, management enable/disable UI, or eligible production scope was added. Next source task: bounded semantic commands and synchronized revocation using fake-worker admission, keeping real mutation gated.


## 2026-10-08 09:26 MDT — M2.12 command/revocation simulation

Before this task, staged, committed, and pushed the accumulated source/documentation to `origin/main` as `53c8643` (`Add conservative previews and acknowledged read-only delivery`), as requested. The subsequent M2.12 work is a new local change set.

Implemented [the isolated semantic FIFO and synchronized fake-operation gate](m2-command-revocation.md). No production app/worker integration, management UI, global keyboard input, AX setter, or permission request was added. The simulation admits only owner-supplied synthetic eligible targets; production eligibility remains unknown/ineligible and mutation scope remains empty.

`scripts/format` and final `scripts/verify` passed 132 tests (98 core, 34 platform), including strict formatting, debug build, metadata lint, shell syntax, and lab script typechecking. Seven new core tests cover 128-command saturation/FIFO, bounded payloads/attachments, app/global revocation, stale activation intents, permission recovery, terminal Quit, and generation exhaustion. Nine new platform tests cover safety denial before a permit; a barrier-held fake call admitted before Pause; exact step/terminal acknowledgments and replay rejection; failure/expiry; fresh Resume evidence; app isolation/process replacement; retained retiring capacity; saturated-buffer Disable; and invalid/unknown evidence. Backend barriers execute outside the gate lock. No latency or real IPC ordering claim follows from these tests.

Initial verification caught a Swift parser/formatter ambiguity between adjacent comparison expressions in a guard; splitting the guard resolved it. The test compile also required a testable core import for synthetic token construction. The final run passed after both fixes. No new real-window acceptance was needed or claimed for this isolated simulation. The installed release app, permissions, and monitor configuration were not changed by this task.

Next: a simulation owner adapter that synchronizes registry/revision state and maps exact operation denials/late completions to reducer cleanup before shared delivery integration or live worker wiring. The current gate does not release separate model slots or execute multi-window plans; its trusted-owner and one-target-per-app prototype limits are documented.


## 2026-10-08 14:05 MDT — M2.13 simulation owner and model cleanup

Implemented [the manually driven simulation owner adapter](m2-simulation-owner.md). Added exact operation binding, step receipt reduction, terminal cleanup, and unpublished-target discard events to the pure reducer. Owner-managed gate mode mirrors current target/revision snapshots and requires exact receipt reservation before acknowledgment. The owner closes safety ingress before model reduction, preserves externally bound slots through Pause/Quit until terminal consumption, and retains retired gate operations without allowing old callbacks to release replacement process work. No production app handler, worker, grant, window, or release bundle was changed.

`scripts/format` and final `scripts/verify` passed 143 tests (101 core, 42 platform), including build, strict formatting, metadata lint, shell syntax, and lab script typecheck. Eleven added tests cover core exact identity/order/timing/replay/discard/Quit cleanup and adapter pre-permit denial, reserved step processing, new layout revisions, registry retirement, PID reuse, permission/environment epoch recovery, and unsupported policy reporting. A barrier-controlled fake size call continued after Quit while owner reduction remained available; terminal consumption released the matching retained model/gate slots without starting position or reopening control. Successful fake sequences retain desired geometry but do not overwrite observations, and mark windows dirty for fresh explicit recovery.

The initial sandboxed check was blocked by SwiftPM's nested manifest sandbox; verification outside that restriction proceeded. Adapter tests then exposed missing acknowledgment support for reserved step receipts. The gate now accepts the reserved transition and requires reservation in owner-managed mode; final verification passed. A daemon restart interrupted the turn after source edits; the preserved workspace was inspected before continuing. No new real-window or performance acceptance is claimed.

Next: bounded shared simulation command/reply delivery and priority safety ingress, including wakeup/finalization races and publication during owner consumption. Real readback, multi-window same-app sequences, live setters, mouse interaction, desktop numbering, and supported eligibility remain unimplemented. M2.12 and M2.13 changes are local and uncommitted; the previously pushed commit remains `53c8643`.


## 2026-10-09 09:22 MDT — Commit/push and M2.14 shared simulation delivery

As requested, verified the completed M2.12/M2.13 work (143 tests), staged it, committed as `d9fc97a` (`Add bounded simulation commands and matching operation cleanup`), and pushed successfully to `origin/main` before continuing. The subsequent M2.14 change set is new local work and remains uncommitted.

Implemented [bounded shared simulation delivery](m2-shared-simulation-delivery.md): one serialized drain chain, at most eight replies and eight commands per pass, rotating reply selection, fixed priority safety flags, exact reply routing/removal before acknowledgment, persistent app quarantine, and retained retiring process routes. Safety closes the gate at ingress, independently of owner progress or FIFO saturation. Repeated pending epoch-bearing signals coalesce while every signal still revokes admission. Owner application avoids double gate epoch advancement. Gate actual-phase checks reject premature/mismatched replies; an exact later completion from a quarantined executing call remains consumable for cleanup.

`scripts/format` and final `scripts/verify` passed 152 tests (101 core, 51 platform), with strict formatting, debug build, metadata lint, shell syntax, and lab script typechecking. Nine added tests cover resource saturation and FIFO dispositions; immediate Disable with a full queue; reply/safety publication during owner consumption and after finalization; duplicate/replay quarantine; quarantined late cleanup; safety between command reduction and publication; 1,000 paired permission/environment signals with one wakeup and fresh epoch recovery; retired routing/PID replacement; and a barrier-held scheduler post concurrent with command/Quit ingress. All prior tests remain passing. Local Markdown link validation and `git diff --check` passed.

No installed release app, permission grant, real window, keyboard interception, display configuration, or production read-only reply path changed. No real-window acceptance or latency result is claimed. Next task: complete fake-worker/readback sequencing and an end-to-end stalled-peer check, including review of same-app multi-window plans before complete plan execution. Production eligibility and mutation remain blocked.


## 2026-10-09 09:33 MDT — M2.15 fake worker/readback sequencing

Implemented [the internal dedicated fake-worker runtime](m2-fake-worker-readback.md), readback-required gate/owner mode, shared readback delivery, and exact external model readback events. The existing standalone position-terminal simulation mode remains available. Matching readback can establish synthetic observed geometry; setter success alone cannot. Readback observation time must follow the actual readback permit. The gate remains occupied through exact receipt reservation, model reduction, and terminal acknowledgment.

`scripts/format` and final `scripts/verify` passed 160 tests (103 core, 57 platform), including strict formatting, debug build, metadata lint, shell syntax, and lab script typecheck. Eight added tests cover core flight/revision/replay identity, actual readback-admission timing, successful off-main sequencing, a blocked app alongside healthy peer readback and responsive Quit, Pause during blocked readback, five invalid/unknown readback variants, and physical worker capacity while retirement is blocked. Runtime tests signal Stop and wait for actual worker-exit callbacks. A pure explicit bootstrap replaced an initial Task-order assumption; no timed sleeps are used to establish sequencing. Initial compilation found a missing readback envelope declaration, which was added before final verification.

Reviewed same-app multi-window behavior: it stays explicitly unsupported until a bounded cursor and per-window retirement/revision protocol exist. No watermark relaxation or implicit per-window re-tile was introduced. Next task is bounded same-app sequence simulation, including failure/new revision/retirement and stalled-peer checks.

No production app handler, AX setter, permission grant, installed release bundle, real window, desktop, or monitor configuration changed. Fixed logical test time is not evidence of real elapsed freshness or latency. No manual real-window acceptance is claimed. M2.14 and M2.15 changes remain local and uncommitted; `origin/main` remains at the requested prior push `d9fc97a`.


## 2026-10-09 09:46 MDT — M2.16 bounded same-app simulation plans

Implemented [bounded same-app plan sequencing](m2-same-app-plans.md) in readback-required runtime mode. Pure cursors bind ordered windows to one command/revision; gate publication under a reused ticket requires its exact cursor token, and only accepted readback plus exact terminal acknowledgment advances it. At most 64 windows per app and 256 per installed complete plan are retained. No per-window re-tile command or general watermark relaxation was introduced. The standalone owner mode remains unchanged unless multi-window simulation is explicitly enabled.

`scripts/format` and final `scripts/verify` passed 170 tests (106 core, 64 platform), including build, strict formatting, metadata lint, shell syntax, and lab script typecheck. Ten added tests cover pure cursor order/bounds/malformed identity, command/execution stamp scope, two-window completion in one revision, failed-app/healthy-peer behavior, barrier-held app uncertainty with shared-ticket peer continuation, new revision during an admitted call, 64-window execution and rejection of a 65th window, registry removal before continuation, and destruction between windows. The maximum test executes 192 fake backend calls. The existing retired-route test now also rejects an occupied duplicate old receipt while proving replacement admission remains available.

Initial shared-ticket tests exposed that activation still validated every affected app after an atomic command reduction. Added per-app execution activation/checks while preserving whole-command validation. Barrier control was strengthened so the healthy peer cannot finish before uncertainty ingress. Final tests passed after this correction. Registry/destruction and unpublished preparation now cancel unusable app cursors and pending targets. Retired duplicate routing no longer latches unknown global uncertainty for a replacement process. Source edits were followed by final formatting/verification; local Markdown links and `git diff --check` passed.

All work remains simulation-only with fixed logical timestamps and synthetic eligible observations. No production handler, AX setter, permission grant, release bundle, real window, desktop, or monitor changed. No real-window or performance acceptance is claimed. M2.14–M2.16 changes are local and uncommitted; the previous requested push remains `d9fc97a`.

Next: consolidate complete-plan simulation acceptance and review production adapter/eligibility requirements against the still-empty supported scope before live wiring. Requested management enable/disable UI, mouse coexistence, and desktop numbering remain planned product tasks.


## 2026-10-09 09:53 MDT — M2.17 production boundary audit

Completed [the production readiness review](m2-production-readiness.md), consolidating M2.12–M2.16 simulation acceptance and comparing it with the production eligibility assessment, preview wrapper, app composition, dedicated reader, and observer processing. The supported mutation scope remains empty. Desktop visibility, native-tab safety, and nested-dialog safety remain unproven; no synthetic eligibility or fake runtime was wired to production.

Recorded proposed adapter obligations for evidence provenance/expiry, dedicated handle ownership, synchronous safety ingress, exact readback acknowledgment, bounded retirement, and explicit user control. The audit found existing unchecked lifecycle issuers despite checked simulation counters. The next source task is conservative exhaustion handling across the read-only path and pure model, with value-level boundary tests.

Documentation-only changes; no source tests were rerun. The last source verification remains the M2.16 run of 170 passing tests. Local Markdown links and whitespace were checked after this review. No GUI, permission, installed app, real window, or monitor change was made; no new manual or performance acceptance is claimed. M2.14–M2.17 remain local and uncommitted; the last requested push remains `d9fc97a`.


## 2026-10-09 10:02 MDT — M2.18 lifecycle issuer exhaustion

Implemented [checked lifecycle-counter exhaustion](m2-counter-exhaustion.md) across app requests/activation/process generations, dedicated reader identities/focus/observation/registry revisions, token-registry batches, and pure model epochs/revisions/admission. Exhaustion stops new work without resetting identity. Exact admitted-operation cleanup remains possible after model stopping. Production preview exposes terminal model exhaustion; worker exhaustion during registry publication discards the earlier result and permanently closes new mailbox admission while preserving receipt acknowledgment.

Final `scripts/format` and `scripts/verify` passed 177 tests (112 core, 65 platform), including build, formatting, metadata lint, shell syntax, and lab script typecheck. Added six core boundary tests and one dedicated-worker test exercising both report and focused paths through exhaustion, acknowledgment, rejection, and teardown. Initial test compilation rejected an equality comparison on a non-Equatable event; explicit event/time pairs fixed it. A sandboxed manifest compilation was also blocked; final verification outside that restriction passed. Local Markdown links and `git diff --check` passed.

No real-window, permission, release-bundle, display, or keyboard action was performed. Production eligibility remains unknown/ineligible. No manual UI/AX acceptance or performance result is claimed. Next: read-only evidence provenance/expiry contract and unsupported coverage, before any provider eligibility proposal. M2.14–M2.18 remain local and uncommitted; last requested push remains `d9fc97a`.


## 2026-10-09 10:12 MDT — M2.19 evidence provenance/expiry contract

Specified [read-only evidence provenance and expiry](m2-evidence-provenance.md) after reviewing the focused value projection, eligibility assessment, structural summaries, and recorded visibility/tab/dialog limits. The proposed envelope has fixed source/requirement pairings and coverage codes, enclosing-request intervals, owner-use context, and diagnostic freshness assessment. No initial source/coverage code can establish safety or clear the three retained requirements.

The contract specifies malformed/future/expired rejection, an exact expiry boundary, unmeasured freshness without an approved age policy, newer incomplete evidence superseding older evidence, revocation preventing revival after resume, bounded retention, and historical diagnostics retaining original attribution. Next source acceptance is pure values and deterministic diagnostic projection/rejection tests; reader/UI wiring and provider acceptance follow separately.

Documentation-only work. Local Markdown link validation and `git diff --check` passed. Source tests were not rerun; latest source verification remains 177 passing tests from M2.18. No real-window, permission, bundle, monitor, or keyboard action was performed, and no manual or performance acceptance is claimed. M2.14–M2.19 remain local and uncommitted; the last requested push remains `d9fc97a`.


## 2026-10-09 10:19 MDT — M2.20 pure provenance values

Implemented [the pure diagnostic evidence envelope and assessment](m2-evidence-values.md) with canonical source/requirement mapping, enclosing-request attribution, deduplicated fixed issue codes, owner-use context, explicit age-policy assessment, and conservative current observation projection. No public source override or eligible branch exists. Original historical exclusions and all three unsupported scope requirements remain available even on rejection. No cache, issuer, automatic action, system clock, or platform objects were added.

`scripts/format` and `scripts/verify` passed 188 tests (123 core, 65 platform), including build, formatting, metadata lint, shell syntax, and lab script typecheck. Eleven added tests cover source/coverage preservation, positive incomplete findings, CG candidates, malformed values/counts, invalid identity/interval/policy/expiry, sequence/context/registry rejection, exact expiry, revival rejection, and geometry/capability projection. Build emitted three existing captured-variable warnings in `SimulatedDeliveryTests`; no new evidence-value warning was emitted. Local Markdown links and `git diff --check` passed.

Only pure core source/tests and documentation changed. No reader/UI wiring, production policy age, real AX read, permission, bundle, window, display, or keyboard action was performed. Next is historical provenance in focused read-only reply/report delivery with unmeasured freshness, retaining existing preview and eligibility boundaries. M2.14–M2.20 remain local and uncommitted; last requested push remains `d9fc97a`.


## 2026-10-09 10:30 MDT — M2.21 focused historical provenance delivery

Wired [historical provenance reports](m2-focused-provenance-report.md) into focused inspection/revalidation/preview replies. Owner-use context is captured after the existing preview revocation and before enqueueing; the value comes from the model's admission generation. Each bounded app attachment retains one scalar watermark for accepted worker sequences, without issuing another sequence or caching envelopes. Metadata/context rejection prevents candidate/preview use; existing early stale-delivery checks remain. Freshness is unmeasured with no policy, or invalid for malformed time, and all scope requirements remain unproven.

Final `scripts/format` and `scripts/verify` passed 195 tests (130 core, 65 platform), including build, formatting, metadata lint, shell syntax, and lab script typecheck. Seven new pure integration/report tests cover formatting, duplicate/newer-incomplete evidence, context failure/recovery, process replacement, shared model revocation with blocked preview, malformed samples, and content/time preservation. The three existing captured-variable warnings in `SimulatedDeliveryTests` were emitted; no new provenance/report warning was emitted. Local Markdown links and `git diff --check` passed.

No real AX call, installed bundle replacement, permission, real window, desktop/display, or keyboard action was performed. Native rebuilt menu/report acceptance remains pending and is the next task; compilation/value tests are not that acceptance. Production mutation scope remains empty. M2.14–M2.21 remain local and uncommitted; the last requested push remains `d9fc97a`.


## 2026-10-09 17:35 UTC — M2.22 native provenance audit and partial lifecycle acceptance

Packaged the current source and verified its ad-hoc release signature. [The acceptance audit](m2-native-provenance-acceptance.md) records exact build hash, OS, two reported scale-1 displays (including negative origin), native operator-driven inspection and blocked preview, and separate fixed-driver foreground-handler results. Native source app/version remains unconfirmed; it is not labeled as owned-fixture coverage. Native intermediate revalidation capture was missed; the final blocked preview was captured before further invalidation.

Owned-fixture same-handler checks captured a matching token at sequences 1/2 with unchanged (200,722,420,158) frame; Pause rejected inspection; fresh Resume used a new token at epoch 2/sequence 3 and new provenance context; controlled focused-accessor hiding produced focus-loss rejection. Post-focus recovery is unaccepted because fixture reactivation confirmation missed its deadline. Earlier capture/environment invalidation failures are recorded without a production recovery claim. Test children were stopped. No source behavior or permission scope changed; source verification remains M2.21's 195 passing tests. Documentation links and whitespace checks passed after recording results.

Next: bounded tracing of the owned-fixture post-focus activation failure and a separately captured fresh recovery. M2.14–M2.22 remain local and uncommitted; last requested push remains `d9fc97a`.


## 2026-10-09 17:44 UTC — M2.23 bounded focus recovery

[Bounded parent/fixture event tracing](m2-focus-recovery.md) did not reproduce M2.22’s reactivation timeout. Both the existing fixture and a fixture rebuilt from current source confirmed reactivation after focused-accessor hiding; iTile discarded the fault result and a fresh explicit foreground-handler inspection produced accepted historical provenance. The current fixture also confirmed its original window active/focused/frontmost on two displays. Recovery advanced from epoch 0/sequence 1 to epoch 1/sequence 3 with a new token and retained unknown eligibility. Geometry was unchanged in the sampled pair. Both owned children exited normally; the normal app was restored.

Fixture release packaging/signature verification passed. No Swift source behavior changed; latest source verification remains 195 passing tests. The earlier timeout cause remains unresolved; no native-menu recovery, client IPC timing, or broad repeatability claim is made. Next: a checked-in bounded recovery lab. Changes remain local and uncommitted.


## 2026-10-09 17:52 UTC — M2.24 checked-in recovery lab

Implemented [the bounded Swift foreground recovery lab](focus-recovery-lab.md), using only Apple frameworks and fixed parent-child protocols. Formatting, standalone compilation, and final `scripts/verify` passed 195 existing tests plus the lab’s parser self-check. Verification initially encountered a sandboxed manifest-cache restriction; the final unrestricted verification passed. Existing-instance refusal was also observed without launching children.

Final real acceptance is **environment-invalidation recovery**, not focus-specific discard capture: the fixture produced its focused-read begin/hide/end events, the app reported desktop/display/sleep invalidation, and a fresh inspection advanced epoch 0/sequence 1 to epoch 1/sequence 2 with accepted historical provenance and unchanged fixture geometry. Both owned children exited normally; normal read-only iTile was restored. Earlier incomplete runs exposed and corrected fixture fault-arming order and an invalid two-sequence-gap assumption. No production behavior changed, and the earlier activation timeout cause remains unresolved.

Next: supported-window evidence-provider review for the remaining safety gates. Changes remain local and uncommitted.


## 2026-10-09 — M2.25 safety-provider feasibility review

Reviewed the current eligibility/provenance boundary, previous collision/tab/dialog evidence, installed macOS 27.0 SDK public declarations, and Apple documentation. [The review](m2-provider-feasibility.md) finds AppKit active-Space window-number enumeration useful for known identities but insufficient to bind arbitrary AX tokens. Own AppKit tab/sheet state is suitable for controlled fixture instrumentation; no reviewed strategy clears all production requirements. ADR 0004 remains unchanged.

Specified the next source task: an explicitly enabled, versioned, bounded owned-fixture safety snapshot and lab consumer, separate from production evidence sources and eligibility. It must not invoke the fixture’s faulting focused AX accessor. Exact identity binding, transition coverage, freshness, and admission remain future gates. Documentation-only work; no GUI, permission, fixture, mutation, or new platform acceptance occurred. Latest verification remains M2.24’s 195 tests plus the lab parser self-check. Local links and whitespace checks passed. Changes remain local and uncommitted.


## 2026-10-09 18:03 UTC — M2.26 owned-fixture safety snapshots

Implemented [the separate fixture snapshot protocol, producer, consumer, and owned-process lab](m2-fixture-safety-snapshot.md). Fixed versioned metadata retains explicit unavailable states and conservative own-fixture coverage. One outstanding request is correlated by run/request/sequence and enclosing time; malformed/replayed/wrong-run records are rejected. Checked issuance closes on exhaustion. Snapshot reads avoid faulting AX accessors. No production target depends on the new protocol module or clears eligibility requirements.

Final formatting and `scripts/verify` passed 200 tests (130 core, 65 platform, five new protocol tests) plus the recovery-lab parser check. Release fixture packaging/signature verification passed. The final two-display owned-process run accepted 14 scenario samples covering baseline, hide/recovery, native tabs/selection/closure, one-tab visible/hidden bar, native sheet open/close, and retained structural/focused faults across repeated snapshots. An initial two-tab hidden-bar expectation was not met; it remained an incomplete run with normal cleanup. The final lab uses one-tab bar transitions and does not claim the unsupported case. Artifact hashes, timings, and bottom-origin display rectangles are recorded in the task document.

The fixture exited normally; normal iTile was left running. No AX client read, permission change, user-window mutation, desktop/display configuration action, or new production scope occurred. Next: explicit fixture-local AX identity binding and paired observations. Changes remain local and uncommitted.


## 2026-10-09 — M2.27 fixture-to-AX identity binding

Committed and pushed completed M2.14–M2.26 work as `1f1cf06` to `origin/main`, then implemented [fixture-controlled identifiers and paired AX/snapshot observations](m2-fixture-ax-identity.md). Final formatting and verification passed 202 tests plus the recovery parser check. Fixture release packaging/signature verification passed. The owned-process live run accepted five pairs and 24 snapshot samples: baseline, equal-frame peer, selected second native tab, tab closure, and post-sheet-closure recovery. The native tab’s focused/list identity was serial 3/[3]; inactive original-list membership was not assumed. Earlier rejected comparisons exposed and corrected that laboratory assumption, with normal cleanup.

The owned fixture exited normally. Normal iTile was neither rebuilt nor restarted; no permissions or user-window setters changed. This is cooperative fixture identity mapping, not production safety coverage. Open-sheet AX focus, process-replacement races, and new desktop transitions were not accepted in this run. Next: fixture-only lifecycle/invalidation/expiry contract. M2.27 changes remain local and uncommitted after the requested prior push.


## 2026-10-09 — M2.28 fixture lifecycle and expiry contract

Specified [schema-2 source authority and read-only pair assessment](m2-fixture-lifecycle-contract.md): checked state/registry revisions, bounded live serials, conservative pre-intent invalidation, distinct controlled/observed coverage, exact host use context, and unmeasured freshness without a diagnostic age policy. Tab/sheet open-close reversal cannot revive a sample; inactive-tab omission from AX enumeration does not imply retirement. Missing notifications and post-sample races remain explicit uncertainty, with no lease or production eligibility.

Next: source revision/registry values and a pure diagnostic pair/context/expiry reducer, followed by separate controlled transition checks. Documentation-only work; no source, bundle, permission, window, display, or keyboard action changed. Latest source verification remains 202 tests plus the recovery parser check. Local Markdown links and whitespace checks passed. M2.27–M2.28 changes remain local and uncommitted; last requested push is `1f1cf06`.

## 2026-10-09 — M2.29 fixture lifecycle source/value assessment

Implemented [schema-2 source revisions/live registry and pure context/pair/expiry assessment](m2-fixture-lifecycle-assessment.md), isolated from production. Formatting and verification passed 213 tests plus the recovery parser self-check. Release fixture packaging/signature verification passed. The scoped two-display lab accepted 36 snapshots, six identity comparisons and three lifecycle pairs. Stable revision 32/32 was historical-consistent; tab reversal 33/39 and sheet reversal 40/51 returned matching fixed fields but rejected as sourceChanged. Peer recreation changed serial 2 to 3; inactive original membership survived AX omission; repeated armed fault snapshots preserved flags and revisions. Cleanup was normal.

No permission, desktop/display configuration, user-window setter, or normal iTile rebuild/restart occurred. Freshness remains unmeasured. Host authority/revocation is implemented as pure values; complete native host callback delivery and in-flight Pause/trust/environment/process acceptance remain the next task. M2.27–M2.29 changes remain local and uncommitted; last requested push remains `1f1cf06`.

## 2026-10-09 — M2.30 laboratory host event invalidation

Implemented [the Foundation-only host owner, native monitor and pumped dedicated-reader wait](m2-fixture-host-invalidation.md). Formatting and verification passed 219 tests plus the recovery parser self-check. The scoped two-display live run recorded immediate outstanding Pause/resume rejection, fresh recovery, native activation callbacks with an outstanding pair (inside AX in one timestamped run and just after AX in the final rerun), fresh focus recovery, owned exit with a pending request/reader drain, one native termination notification and fresh replacement-run acceptance while the old attachment stayed stopped. Both fixture processes exited normally.

No permission, Space/display configuration, sleep/wake, user-window setter or normal iTile rebuild/restart occurred. Host Space/display/sleep and effective-permission paths are wired but not natively accepted by this run. The next task is separately scoped native Space/permission invalidation and fresh recovery. Freshness remains unmeasured. Changes remain local and uncommitted; last requested push remains `1f1cf06`.

## 2026-10-09 — M2.31 native desktop operator check and permission preparation

Implemented [bounded operator modes, explicit AppKit event dispatch and separate permission-app packaging](m2-native-host-operator-checks.md). Formatting and verification passed 219 tests plus the parser/plist/shell checks. The first desktop attempt recorded only focus events and timed out with orderly cleanup. The retry recorded two native Space callbacks about 12.3 seconds apart, original active=false while away, old pair contextRevoked, original active=true after return, and a fresh historical-consistent pair (eight correlated snapshots). Cleanup was normal. Event pumping and monitor-specific operator clarification changed together, so neither alone is credited as the initial failure's cause.

The separate permission app packaged/signature-verified successfully. Native untrusted preflight exited before fixture creation; the user then approved its temporary Accessibility grant and authenticated directly. The running app recorded effective trust loss (revocation 1), old-pair rejection with unchanged source state, trust restoration (revocation 2) and a fresh historical-consistent pair across seven correlated snapshots. Cleanup was normal. The user removed the temporary entry after automation could not select it reliably; a fresh settings snapshot verified absence and unchanged existing grants. Only the approved temporary permission entry changed and was removed afterward. Physical display configuration, sleep state, user-window geometry and the normal iTile artifact were unchanged. Production mutation stays disabled; changes remain local and uncommitted.

M2.31 source/native acceptance is complete within its recorded scope. Next: fixture-only timing/freshness calibration design; no new age policy or setter consent exists. Changes remain local and uncommitted.


## 2026-10-09 — M2.32 fixture timing and freshness calibration design

Specified [the laboratory measurement envelope and bounded calibration experiment](m2-fixture-timing-calibration.md). The contract distinguishes source acquisition, worker dispatch, result publication/delivery and host assessment; age begins at the earliest source acquisition. It retains failures, missing/censored intervals, exact expiry boundaries, context revocation and post-sample races. Predeclared cohort/resource/output limits and dataset review precede any explicit experimental diagnostic policy. No real age policy is selected.

Documentation-only work; no source, permission, fixture, window, display or normal iTile artifact changed. Latest source verification remains M2.31's 219 tests plus parser/plist/shell checks; its scoped native acceptance is unchanged. Local Markdown links and whitespace checks passed. Next: implement the bounded laboratory timing envelope and collector, then separately accept read-only measurements before calibration review. Changes remain local and uncommitted; last requested push remains `1f1cf06`.


## 2026-10-09 — M2.33 bounded fixture timing collector

Implemented [pure timing values, bounded structured collection and native timestamp adapters](m2-fixture-timing-collector.md) in separate laboratory targets. Source acquisition, dispatch, publication/delivery and assessment intervals retain partial failure endpoints; causal and cross-attempt clock regression stop collection. Exact matching completion/drain, physical timeout occupancy, fixed event/record/output caps and reserved terminal output are tested. No diagnostic age policy or production integration was added.

Final formatting and `scripts/verify` passed 227 tests (130 core, 65 platform, 32 fixture diagnostics), plus parser/plist/shell checks. Final native collection completed 64 attempts and 18 events within 80,882 bytes, with orderly fixture cleanup and no occupied reader. Ordinary pairs all completed; an activation during dispatch attempt 23 revoked that pair, and subsequent dispatch/assessment unsupported results were retained. Invalidation recorded eight Pause revocations, seven sourceChanged reversals and one deliberate invalid-PID preflight failure with partial timestamps. The task document records exact counts, artifact/dataset hashes, measurement ranges and attribution limits. Earlier exploratory runs are not substituted for final-build results.

No permission, physical desktop/display configuration, user-window setter or normal iTile artifact changed. The temporary permission app remained removed. Freshness stays unmeasured; no latency percentile authorizes mutation. Next: review this dataset's attribution/rejection coverage and explicitly scope any additional fixture-only diagnostic policy evaluation. Local Markdown targets and whitespace checks passed. Changes remain local and uncommitted; last requested push remains `1f1cf06`.
