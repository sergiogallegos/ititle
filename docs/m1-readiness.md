# M1 readiness review — 2026-10-04

**Decision: continue with the read-only probe and M2 control-model development using simulated workers. Real window mutation remains gated.** M1 is implemented with partial manual validation; its full exit criteria are not complete. No additional unchanged-window reports are needed for the narrow cases already observed.

Follow-up: [M2.1 is now implemented as a pure simulation](m2-control-model.md); [M2.2 focused inspection is also implemented in source](m2-focused-probe.md), with partial manual acceptance including focus-loss rejection, permission recovery, and desktop invalidation. Physical display hotplug has scoped between-request evidence, and client tracing established observed permission loss during a backend request. [M2.3 now implements conservative eligibility reasons and documents the empty generic mutation scope](decisions/0003-focused-eligibility.md); eligibility proof and live integration remain separate gates. The evidence and decisions below describe the review checkpoint before that implementation.

This review consolidates the timestamped [validation log](validation.md), [probe limits](m1-probe.md), [P1–P4 experiments](platform-experiments.md), and source inspection. It does not enable a feature or replace the [control contracts](control-contracts.md).

## Evidence and scope

Manual observations cover one arm64 machine on macOS 27.0.1 (26A434). Exact application versions were not recorded, and the initial terminal application's identity was not confirmed. Older supported deployment targets have not been exercised. Most window reports were supplied by the user; P3's complete report was also matched to the live lab UI, and its active Stop/Quit checks were agent-observed.

| Gate | Evidence accepted for the observed scenario | Remaining limit |
| --- | --- | --- |
| P1 identity/classification | Repeat tokens for ordinary Finder, browser, editor, and terminal windows; Finder close/reopen retirement; minimized/fullscreen state reporting; Chrome direct-sheet appearance/cancellation | Finder tab switching replaced the containing-window token at the same epoch. No stable tab-container identity claim. Broader dialogs, nested sheets, app restart/PID reuse, and title-change coverage remain incomplete |
| P2 visibility | Chrome hidden, covered, desktop-away/return, and fullscreen round trips; report presentation no longer forced the earlier unwanted desktop switch in the user check | No general AX-to-CG identity mapping. Fully covered Chrome still appeared in CG. Same-app/same-size windows across Spaces, Stage Manager, Mission Control, and lock remain untested. Bulk enrollment is unavailable |
| P3 isolation | Five delayed/control fixture trials, recovery, responsive lab heartbeat, active Stop/Quit and fixture cleanup | Scoped fixture/API/OS result only; no hard request deadline, long resource soak, or write-timeout guarantee |
| P4 coordinates/lifecycle | Connection, negative-origin window observation, manual cross-display move, disconnection, and requested sleep/wake follow-up; matching AX/CG bounds | Both connected displays were scale 2.0; scale 1.0 was observed separately. Simultaneous mixed scale, other arrangements, and independent physical-coordinate verification remain open. Sleep attribution relies on the manual workflow |
| Permission and UI | Denied reads followed by successful grant recovery; repeated report use and user-reported quit/relaunch | Mid-scan permission revocation and the main probe's complete pause/resume matrix remain untested. Lab Stop/Quit is separate evidence |

P3 delayed AXWindows calls returned in 201.060–206.172 ms with error -25204; whole requests took 401.995–409.664 ms. Healthy paired whole requests took 1.180–4.662 ms and recovery succeeded. The 0.2-second per-handle setting remains experimental; it is not a 0.2-second whole-request deadline. Five candidate notification correlations describe notifications posted after the fixture resumed, not notification delivery during a blocked event loop.

The latest recorded `scripts/verify` run passed 23 tests: 14 core and 9 platform, plus builds, plist lint, and script syntax checks. These cover geometry, identity bookkeeping, coordinate transforms, latency summaries, incomplete sheet evidence, fake-worker isolation/lifecycle, and short pipe messages/EOF. They do not establish write safety. This documentation review does not rerun or relabel that prior verification as a new run.

## Implemented boundary

The current app offers explicit per-application read-only inspection, dedicated AX workers, bounded read admission, conservative session tokens, and redacted text reports. Its pause operation stops inspections; it is not the proposed control coordinator's paused state, which will allow read-only enrollment. No frame setters, focus/raise actions, enrollment, or input interception exist.

The app's request/environment counters reject stale diagnostic deliveries. They do not implement independent layout revision and mutation-admission generations. The worker returns a report string; there is no complete immutable observation record suitable for control. Settable attributes, a standard role, modal=false, and zero direct sheets do not together prove eligibility: nested sheets are unchecked, and supported lifecycle/visibility evidence is still required.

## Gates before real writes

1. **Structured observations and focused enrollment.** Carry process/window tokens, epoch, monotonic timestamp, worker sequence, geometry, and explicit known/unknown eligibility evidence across the boundary without AX handles. Test public frontmost/focused-window acquisition and revalidation, including focus changes caused by iTile's own UI. Do not derive identity from titles or matching bounds.
2. **Control state and admission.** Implement separate environment epoch, layout revision, and admission generation. Test pause/quit, trust loss, stale completions, process replacement/PID reuse, overflow, and revocation between simulated setters. Already admitted IPC may finish; cancellation must not be presented as interruption.
3. **Enforceable supported scope.** Begin with explicitly enrolled ordinary windows on one desktop/display. Before enabling this scope, establish how unsupported tab/dialog/visibility transitions and unknown evidence block control. A written exclusion alone is insufficient if the app cannot enforce it. Resolve focused enrollment first; bulk enrollment remains separately gated by P2.
4. **Bounded application and geometry policy.** Specify and test insertion/removal, finite geometry and depth limits, frame diff/tolerance, display-boundary rounding, latest-target coalescing, one sequence per app, and bounded correction/readback. Stale results must never restore an obsolete desired layout. A failed app must not block healthy apps or pause/quit.
5. **Separate integration acceptance.** Exercise the selected scope with exact app/build metadata, permission revocation, lifecycle invalidation, and real frame readback after explicit user opt-in. Record wider display/desktop cases as untested until exercised; do not infer them from matching read-only bounds or fake tests.

## Next task — M2.1 control model and simulated admission

Implement pure value types and a deterministic state reducer in `ITileCore`, driven by synthetic observations and fake worker events. This is preparatory M2 work, not completion of M1's experimental gates. The existing diagnostic app remains read-only during this task.

Acceptance criteria:

- Define immutable observation, target, and result records with tokens, environment epoch, layout revision where applicable, admission generation, worker sequence, and monotonic timing; preserve unknown evidence explicitly.
- Model permission-required, paused, active, suspended, and stopping states. Start without mutation admission. An explicit simulated Tile request requires fresh eligible observations; failed validation leaves control paused, and resume never replays a cached plan.
- Produce explicit effects from each state transition; keep AppKit, AX, blocking calls, and worker execution outside the reducer.
- Test pause before dispatch and between two simulated setters, late completion after pause/environment change, obsolete-revision completion requiring reconciliation, app death/PID reuse, bounded pending targets/overflow, and one stalled app alongside a healthy app.
- Preserve desired state when old work completes; dead tokens and stale epochs cannot revive enrollment. Check admission separately at each simulated setter boundary.
- Run `scripts/verify` and document the simulation boundary. Passing this task does not authorize or enable the real platform write path; focused read-only enrollment/revalidation is the next platform gate.

No hotkeys, live Tile action, packaging, or renewed Accessibility grant is needed for this review or the pure-model task.
