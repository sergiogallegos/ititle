# Read-only feasibility experiments

Status: partial user-reported P1/P2 observations are recorded in [validation](validation.md); full gates remain open. P3 has [lab tooling](p3-lab.md) and a scoped five-trial real-AX isolation/recovery result plus active Stop/Quit checks recorded in validation; broader guarantees remain unproven. The [M1 probe](m1-probe.md) now provides read-only observations for these experiments; implementation and unit tests do not constitute experimental evidence. Do these before implementing frame mutation. Use Apple public APIs and no screenshots or Screen Recording permission. Store only explicitly exported, redacted metadata.

## P1 — Window identity and eligibility

For the consolidated P1–P4 decision, including partial P4 physical-display evidence and the next simulation-only task, see the [M1 readiness review](m1-readiness.md). The timestamped log retains earlier checkpoints as history.

Enumerate AX windows with each app's worker, correlate live elements by equality within process lifetime, and assign internal tokens. Observe close/reopen, title changes, native tabs, multiple identical windows, app restart, and minimized/fullscreen windows.

Pass: live windows retain tokens where correlation is supported; destroyed/restarted windows cannot receive old tokens; unsupported/ambiguous cases are reported and excluded. Do not require all apps to pass in order to describe a limited supported set. Test Terminal, Finder, one browser, and the user's editor, recording exact versions.

## P2 — Current-desktop visibility (critical gate)

[M2.6](m2-desktop-visibility.md) now implements content-free focused on-screen bounds candidate diagnostics. Scoped owned overlap/hide/recovery and equal-frame cross-desktop observations are recorded; candidate counts establish no AX identity mapping and do not complete this gate.

Compare AX observations with public on-screen CGWindowList metadata using available PID/layer/bounds evidence. Do not assume a CG window number is directly available from an AX element, use a title match, or call a private bridge. Bounds/PID matching is evidence only, especially when windows overlap or have identical geometry.

Scenarios: two native desktops with same-app/same-size windows; a fully occluded window; minimized and hidden apps; native fullscreen; Stage Manager; Mission Control; screen lock; missing metadata without capture permission. Confirm what 'on screen' means for enrollment rather than interpreting it as unobscured pixels.

Pass for bulk enrollment: an unambiguous correlation strategy across the declared supported cases with no wrong-desktop enrollment in the matrix. No finite test proves universal correctness; expose exclusions and disable bulk mode where evidence is absent. If this fails, keep focused-window enrollment only. If even focused-window revalidation is unreliable, stop at a read-only probe or explicitly narrow supported environments; do not silently adopt private APIs or request capture permission.

Focused enrollment itself must verify the frontmost app/focused standard window through public APIs, validate subsequent epoch and focus/visibility evidence, and expire enrollment on observed transitions. There is no atomic snapshot spanning desktop changes and AX writes. Document this residual race and suspend when detected.

## P3 — IPC isolation and timeouts

Use a small local test fixture app to delay AX responses while another app remains responsive. Observe IPC durations and observer lag. Verify configured timeout behavior on the actual handles. Confirm that menu interactions and other workers remain responsive, buffers remain bounded, and no replacement-thread loop occurs. Read-only calls only at this stage.

Pass: isolated delay and recovery with measured distributions and no coordinator/main-thread stalls attributable to AX. Pick timeout/backoff defaults from results rather than claiming a fixed hard deadline.

## P4 — Coordinates and lifecycle

Read frames and usable monitor bounds across displays above/below/left of the primary, mixed Retina scale, Dock placements, display reconnection, and sleep/wake. Compare transformation round trips without moving windows. A single physical monitor can validate only a subset; mark others untested, not passed.

Pass: reversible coordinate transforms within proposed tolerance; topology events invalidate stale plans in a fake adapter; no persisted display-index assumptions.

## P5 — Input feasibility (before M3)

After explicit enablement, test only configured chords: balanced down/up behavior, repeat, non-US layout, VoiceOver coexistence, secure input, tap disablement, and permission loss. No raw event logging. Test fake event streams before attaching a real tap. Preserve menu controls if input interception is unavailable.

## Report format

Date, exact OS/toolchain/hardware/app versions, scenario, observation, redacted event trace, supported/unsupported/ambiguous outcome, and resulting decision. Link records here after execution. P1–P4 gate real writes; P5 gates global input. No additional package dependencies may be introduced by fixtures.
