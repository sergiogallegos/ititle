# M2.6: Focused on-screen bounds evidence

Source implemented with scoped owned overlap/hide/recovery and equal-frame cross-desktop reader acceptance. **Current-desktop visibility is still unproven; the enforceable production mutation scope remains empty.** No enrollment, bulk discovery, frame writes, capture permission, or screenshots are added by the probe.

## Public API boundary and decision

Apple's [on-screen list option](https://developer.apple.com/documentation/coregraphics/cgwindowlistoption/optiononscreenonly) selects on-screen windows, while [CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)) returns window-server metadata. This does not establish a correlation to the inspected AX element. The existing AX token registry uses element equality, not CG window numbers. No private bridge, title match, or image capture is used.

A same-PID, ordinary-layer bounds match is only a candidate. Even one candidate can be a different same-app window with matching geometry while the AX window is elsewhere. Zero candidates can reflect missing/incomplete metadata, geometry changes between reads, hidden/minimized state, or desktop state; it must not imply a proved off-desktop identity. Multiple candidates explicitly expose geometric ambiguity. The distinction between on-screen metadata and unobscured pixels also remains experimental.

Decision: keep `currentDesktopVisibility` unproven for every diagnostic outcome. No result produces eligible status or grants admission. The pure assessment has no production eligibility override. Single, absent, duplicate, malformed, and incomplete samples all retain the existing visibility gate, alongside native-tab and nested-dialog safety requirements. Synthetic tests cannot establish a real identity mapping.

## Implemented sampling

Each explicit focused request samples `CGWindowListCopyWindowInfo` once, on its existing dedicated worker, after AX geometry and structural reads and before final AX identity/focus revalidation. The adapter examines only ownership, layer, and bounds fields; it never reads names, titles, CG window numbers, document paths, or pixels. Missing/malformed owner fields make the sample incomplete rather than silently implying absence. Boolean, fractional, or overflowing numeric ownership/layer values cannot become valid identifiers/layers.

Only metadata for the inspected PID is retained, capped at 128 entries including nonordinary layers. The pure `OnScreenBoundsEvidence` counts layer-zero entries whose finite, positive rectangles match the sampled AX frame within one logical point per x/y/width/height component. Negative origins are preserved. Missing/malformed layer-zero geometry is incomplete. Fixed report outcomes distinguish `singleBoundsCandidate`, `noBoundsCandidate`, `ambiguousBoundsCandidates`, and `incomplete`, alongside issues: `notSampled`, `metadataUnavailable`, `frameUnavailable`, `invalidGeometry`, `invalidMetadata`, `entryLimit`, `budget`, and `cancelled`. Partial counts survive later issues; a single partial candidate remains incomplete.

The CG call occurs only on an explicit request and adds no polling. Scheduling/cancellation checks precede the call and bound subsequent parsing; the sample deadline is 4.5 seconds after request start. System allocation of the initial whole-session metadata list is outside the 128-entry retention bound. CG's synchronous call has no configured per-call timeout here; deadline checks do not interrupt it. Final worker return now also rejects requests exceeding the existing five-second request limit after the final focused AX read. The existing app environment/activation/trust/pause guards still reject stale delivery. The initial AX frame and later CG snapshot are non-atomic, and no stable geometry/identity interval is claimed.

## Owned fixture and acceptance

Run the fixture with `--focused-probe --visibility-probe` and retain stdin. These fixed commands affect only the disposable fixture:

- `visibility-peer-open`: create and show an un-tabbed peer with the same frame/style as the original; emit whether the owned AppKit frames are equal.
- `visibility-peer-close`: close only that peer.
- `visibility-hide`: hide the owned fixture application.
- `activate`: restore/activate the fixture's original window.
- `desktop-status` under `--desktop-probe`: report owned original/peer `isOnActiveSpace`, equal-frame status, the own-process focused source, frontmost status, and display count. A public Space-change observer emits metadata-only transition/status events in this mode.
- `quit` or stdin EOF: exit.

In `--desktop-probe` mode, only the new peer uses public `.moveToActiveSpace` collection behavior so it can be created on the operator's current desktop while the original stays elsewhere. This flag changes only the owned fixture; no production window movement is enabled. Acknowledged peer creation must be followed by status checks proving the original and peer occupy different active-Space states before counting a cross-desktop sample.

Ground-truth frame equality is not a production CG/AX identity bridge. Window-server changes are asynchronous, so the command acknowledgment alone does not establish that subsequent CG metadata has settled.

Unit tests cover matching/duplicate/nonmatching/empty snapshots, negative origins, the fixed tolerance boundary, nonordinary layers, missing/malformed/overflowing rectangles, bounded partial samples, and simulated admission rejection for every candidate outcome. `scripts/verify` passed 80 tests: 69 core and 11 platform.

The scoped 2026-10-07 02:45 UTC reader sequence (October 6 local time) observed one candidate, then two equal-overlap candidates, then one after peer closure, zero while hidden, and one after restoration. The AX token remained unchanged. All samples retained unproven visibility and ineligible fixture state. Exact events, the immediate unsynchronized attempt, and test-context limits are in [validation](validation.md).

This acceptance uses a temporary helper linked to the production debug worker, not the app's frontend. It does not validate the rebuilt bundle's permission, frontend delivery, current desktop membership, environment invalidation, or mutation safety. The installed iTile app was not rebuilt/replaced during these checks.

## Next task and remaining gates

The owned equal-frame cross-desktop case is now recorded: a complete single candidate coexisted with an AX observation of the off-desktop original. Continue to reject both unknown and ambiguous evidence. The [supported-scope review](decisions/0004-supported-scope.md) retains an empty mutation scope and rejects geometry-only correlation for production eligibility. The follow-up [M2.8 read-only preview](m2-read-only-preview.md) now explains blocked control-model plans without admitting setters. Its remaining menu/lifecycle acceptance and registry integration gates precede live control. Native Spaces with independent displays, Stage Manager, Mission Control, fullscreen, minimize, lock, missing metadata, and mid-request transitions remain separate checks in the P2 matrix.

Before proposing eligible scope, document an enforceable provider tied to process/window token and environment with acquisition, expiry, transitions, and exact app/OS coverage. If public APIs cannot establish such a provider, retain a read-only product or explicitly narrow the design; do not treat geometry matching or consent as proof. Live coordinator/admission integration, bounded frame application policy, and separately opted-in setter acceptance remain later gates.


## Cross-desktop reader acceptance — 2026-10-06 local

The owned fixture's `--desktop-probe` controls and public Space notification instrumentation are implemented and passed `scripts/verify` (80 tests: 69 core, 11 platform). The UI control connection timed out while trying to inspect desktop controls, so native desktop changes are operator-driven and must be confirmed by fixture events. No AppleScript, private Space IDs, or synthetic key injection is substituted.

At 2026-10-07 03:31:04 UTC, public owned-window status before and after the exact production-reader completion reported `original-active=false`, `peer-active=true`, equal frames, and focused source `original`. The original AX token remained `app-3/window-1`; the reader nevertheless found one complete same-PID bounds candidate. Returning to the original desktop reversed the owned active-Space states and still yielded one candidate. Closing the peer retained one candidate. All samples retained unproven visibility and ineligible state. Both helper processes quit normally.

Accepted scope is this owned fixture on macOS 27.0.1, with one reported display and operator-driven native desktop changes. The earlier two-monitor setup is not coverage for this run. The reader had a fixed environment epoch and targeted the fixture while it was backgrounded; frontend delivery, environment invalidation, generic app behavior, and a CG/AX identity bridge are not validated. Baseline and later geometry differed; no geometry stability across the operator interval is claimed. Exact timings, geometry, hashes, and limits are in [validation](validation.md).
