# M2.2 — Focused read-only observation and revalidation

Implemented in source on 2026-10-04. Automated verification passes; real-window acceptance is **partial**, with scoped Chrome, Finder, TextEdit, sheet/tab, and pause observations recorded in [validation](validation.md). This is a diagnostic path, not enrollment or live tiling. The M2.1 reducer is still disconnected from the app's platform observations and never receives eligible evidence from this path.

The updated app has been packaged, signature-verified, launched, and granted Accessibility by the user. Ordinary-window revalidation, conservative rejection cases, and synchronized in-flight focus-loss rejection have been observed. Permission/desktop-transition races remain open. Earlier unsynchronized fixture attempts were inconclusive and are retained in the validation history.

## Use after packaging

Run `scripts/verify` and `scripts/package-app`, quit the previous iTile instance, and open the new `dist/iTile.app`. As with M1, replacing an ad-hoc signed app may require refreshing its Accessibility grant. The source-only checkpoint did not replace the bundle; the later manual-validation task did. See the latest validation checkpoint before rebuilding unnecessarily.

1. Activate the ordinary application window you want to inspect.
2. Open the iTile menu and choose **Inspect focused window (read-only)**. iTile captures the frontmost application at this explicit action. It does not raise or focus another app and does not activate its report while the worker reads. Waiting status is in the menu-bar item's tooltip.
3. The worker reads the application's public AXFocusedWindow, collects structured evidence, processes a bounded set of queued notifications, and rereads AXFocusedWindow. The main thread checks the frontmost process and activation/environment revisions again before displaying the report. A stale result is discarded without activating the report.
4. The displayed report is historical. Showing it can activate iTile and change focus. Return to the original application/window, then choose **Revalidate last focused window (read-only)** to compare a fresh sample with the previous token. The comparison uses session identity, not matching titles or bounds.
5. A different token reports `expected-token-match=false`; unsupported continuity can prevent retaining a comparison token at all. Select **Inspect focused window** again to start a new comparison. Pause/resume, environment invalidation, permission loss observed by the app, or application termination clears the comparison reference.

The existing **Inspect application**, Copy, Pause inspections, and Quit commands remain. All reports stay in memory unless copied explicitly. There is no keyboard interception, title/path collection, focus action, or frame setter.

## Evidence and limits

`FocusedWindowEvidence` contains the process-scoped window token, environment epoch, focused-worker sequence, start/end monotonic times, role/subrole, minimized/fullscreen/modal flags, frame, frame capabilities, direct-sheet count/completeness, destruction-notification status, focused-window check result, and optional expected-token comparison. Unavailable AX attributes preserve their error codes; invalid types stay unknown. Failed geometry cannot become a `WindowObservation`.

The structured sheet reader is shared with M1: it reads at most 16 direct child roles, never sheet contents. A positive sheet count excludes the window even if the scan is incomplete. Zero direct sheets, modal=false, and a standard role do not prove absence of nested dialogs or safe tab/desktop identity. The derived control observation is therefore always **unknown or ineligible**, never eligible.

Focused requests share the existing single-admission mailbox and dedicated per-app thread with full reports. There is no second worker or periodic scan. Each actual AX handle gets the existing experimental 0.2-second timeout; the five-second budget remains soft. Window references are bounded to the existing 64-element limit. New focused windows join the attachment's registry; a later full inspection can retire absent entries. Unsupported destruction observation expires that element's token before the next request.

Focus-change observation is registered on the inspected application only when explicitly using focused inspection. The observer increments a worker-owned counter; it reads no title or focused UI contents. Successful notification registration plus equal focused handles at both reads is evidence at those checks, not a guarantee against every intervening focus/tab transition. Missing notification support leaves continuity unknown. Destruction, notification-drain overflow, environment changes, and focus differences prevent a positive continuity result.

AppKit application-activation notifications advance a separate revision. Source app → iTile/another app → source app while a request is pending still rejects that result. Current process identity includes the attachment generation and a main-thread launch-date/termination check. These checks are non-atomic and do not solve focus changes between the final check and report presentation or any future setter.

Public APIs were checked against the installed SDK's `AXAttributeConstants.h` and `AXNotificationConstants.h`. No private AX-to-CG bridge or additional permission was introduced.

## Verification

Six new pure tests cover unknown evidence and the control-model gate, positive exclusions including sheets, incomplete/missing attributes, token mismatch despite equal geometry, inspector/away-and-back activation, and process/epoch/permission/pause delivery checks. Two new production-worker tests verify focused/full requests share the bounded mailbox, stopped focused reads do not deliver, typed results and expected tokens survive dispatch, and backend operations remain on the same dedicated thread. Existing sheet and worker tests continue to pass.

`scripts/verify` passed all 57 tests (46 core, 11 platform), debug builds, plist lint, and script syntax. These are fake-backend and value-model tests; they do not establish real focus-notification support, UI behavior, or AX eligibility.

## Remaining manual focused-probe acceptance

Exact tested versions and timestamps are in the validation log. Scoped normal/rejection checks have been observed; the remaining race checks are separate from earlier M1 evidence:

| Scenario | Required observation |
| --- | --- |
| Ordinary Chrome/Finder/editor window | Source app remains frontmost during the read; report appears afterward with structured evidence; eligibility stays unknown or ineligible |
| Same window after returning from report | Revalidation either matches its token or explicitly reports unsupported/changed identity; report activation must not validate an old pending request |
| Another same-app window with identical bounds | Revalidation must not substitute geometry for identity |
| Sheet open/cancel and Finder native-tab switch | Positive sheets exclude; tab identity changes remain explicit; no eligible result |
| Focus loss during an outstanding read | Result is discarded without forcing focus back to iTile; a controlled delayed fixture may be needed to exercise the race |
| Pause, permission loss, Space/display change, app close/restart | Pending stale results cannot revive the historical comparison reference |

### Synchronized focus-loss fixture

The owned fixture accepts `--focused-probe` to become a regular foreground app. Its parent's stdin supports `activate` (unhide/activate only its own window) and `arm-focus-loss` (one-shot). The latter emits `focus-loss-armed`. The next invocation of its public [`accessibilityFocusedWindow()`](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/accessibilityfocusedwindow%28%29) accessor captures the ordinary result, emits `focused-read-begin`, hides only the fixture, emits `focused-read-hide`, pauses its own main thread for 0.1 seconds, emits `focused-read-end`, and returns the captured result. Event timestamps use host monotonic uptime. The arm is consumed before hiding to avoid repeated/reentrant faults. These commands have no effect without the explicit focused-probe flag.

For the manual check, retain the child stdin pipe, activate via its own command, and first verify a fresh iTile report identifies the fixture's known 420-point-wide, non-resizable window. A foreground property alone did not establish that iTile would select this app. Return to the fixture, open the iTile menu, arm and await acknowledgment, then invoke focused inspection. Do not read the fixture's AX focused attribute with another client while armed: the accessor cannot identify its caller. Require the begin/hide/end events and iTile's focus-loss discard message; verify a late completion does not replace it or activate iTile. Return to the fixture and require Revalidate to reject the historical reference, then run a fresh inspection to check recovery. Close stdin or send `quit` and verify child exit.

The 2026-10-05 02:39 UTC check followed that sequence using a temporary regular-app wrapper for the fixture. iTile discarded the pending result, Ghostty remained foreground, revalidation required a fresh inspection, and recovery succeeded. This is one scoped real integration observation, not a timing guarantee or proof of every activation race. The prior unsynchronized attempts are not counted as passes.

Default P3 behavior is unchanged; `--slow` still enables its separate stdin-triggered 1.5-second pause. No user application is stalled, no private API is used, and the installed iTile executable did not need to be replaced for this fixture test.

No extra unchanged-window samples are needed for the completed scoped M1/M2.2 checks. Focused-platform acceptance remains a gate before any live control integration; nested-dialog, tab, and visibility exclusions still need enforceable supported-scope decisions.
