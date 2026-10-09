# ADR 0004: Keep production control read-only after the visibility review

Status: accepted scope decision; read-only integration now implemented in [M2.8](../m2-read-only-preview.md), with scoped foreground-handler acceptance. Date: 2026-10-06 local.

## Decision

The supported production mutation scope remains empty. Continue explicit read-only focused inspection and historical-token revalidation. Do not enable enrollment, setters, focus/raise actions, or automatic reconciliation on the basis of the existing candidate diagnostics. No new permission or user assertion can replace the missing evidence.

The next implementation task is a read-only control-model integration: pass accepted production observations through the existing pure model and explain why an explicit preview cannot become an admitted tiling plan. This advances the app/control boundary without asserting eligibility. It does not implement the live setter admission mailbox.

This is a decision about the providers reviewed and evidence obtained so far. It is not a claim that every public-API strategy is impossible. A later proposal may establish a narrower scope, but must identify its provider and acceptance criteria before changing eligibility.

## Evidence and its limits

The [M2.6 cross-desktop sequence](../validation.md) recorded an off-active-Space original AX window and an equal-frame owned peer on the active Space, with one complete same-PID on-screen bounds candidate. This rejects unique geometry as an AX-to-CG identity proof. Equal-overlap and hide/recovery checks additionally recorded ambiguous and absent candidates. All outcomes retained unknown visibility.

That cross-desktop reader targeted a background application with a fixed environment epoch. It did not exercise the app's foreground delivery guards, and does not by itself disprove a future foreground-only scope. The app currently checks frontmost process lifetime, activation revision, environment epoch, trust, pause, request identity, and focused AX equality before presenting a result. Those checks reject observed stale reads; they do not supply an identity-correlated desktop-membership provider or eliminate transitions after the last check.

[Native-tab checks](../m2-native-tabs.md) found positive groups and token changes in the owned fixture, Finder, and TextEdit. Zero groups, including a complete scan, do not establish native-tab lifecycle safety. [Nested-dialog checks](../m2-nested-dialogs.md) detect positive findings and retain explicit limits/incomplete outcomes; a negative tree sample does not prove safety throughout a later write sequence. No representative application currently satisfies all three outstanding requirements.

## Providers and narrower scopes considered

| Candidate | Available evidence | Decision |
| --- | --- | --- |
| Same-PID on-screen bounds, including one candidate | Window-server geometry alongside a separate AX read | Rejected as an identity-correlated visibility provider by the scoped collision; retain diagnostics only |
| Frontmost app and stable focused AX element | Existing request/delivery checks and scoped stale-result rejection | Useful sampled prerequisites; investigate further if proposing focused-only control, but not enough for current eligibility |
| Ordinary role, writable geometry, no detected sheets/tabs | Capability reads and bounded structural samples | Positive exclusions are useful; negative samples cannot clear desktop or structural lifecycle requirements |
| User declares one desktop, one display, or no tabs | Consent and operator context | Not an enforceable provider; cannot grant eligibility or cover transitions |
| Fixed application/version allowlist | Scoped behavior from a few UI sequences | No demonstrated provider for the missing requirements; names and versions alone cannot grant eligibility |
| Owned AppKit fixture | Direct access to its own window state and controlled tab/dialog creation | Suitable for lab ground truth; not a provider for arbitrary user applications and not a production mutation scope |

Apple documents [AXFocusedWindow](https://developer.apple.com/documentation/applicationservices/kaxfocusedwindowattribute) as an application's focused accessibility window. It documents [CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)) as window-server information for selected windows. Our reviewed adapter establishes no identity bridge between those results. This is an assessment of the adapter, not a statement that Apple's API documentation proves universal impossibility.

Apple's [NSWindow.isOnActiveSpace](https://developer.apple.com/documentation/appkit/nswindow/isonactivespace) supplies the active-Space property for an AppKit window. The fixture can query its own `NSWindow` objects; the production AX adapter holds other applications' accessibility elements, not their `NSWindow` instances. Fixture instrumentation must not be exported as a generic eligibility override.

## Requirements for reopening production eligibility

A proposal must describe all of the following before implementing an eligible branch:

1. **Acquisition and coverage:** an enforceable provider for current-desktop membership, native-tab safety, and nested-dialog safety; exact supported app/OS/window forms and excluded environments. Tie the evidence to the current process lifetime, AX window token, and environment rather than only PID or bounds.
2. **Freshness and expiry:** when the evidence is obtained, its measured age limit, and how it expires before each setter. Before/after sampled focus equality alone is not continuous proof.
3. **Transitions and failures:** invalidate on observed focus/activation changes, tab/sheet transitions, destruction, process replacement, permission loss, Space/display changes, sleep/wake, pause, quit, overflow, unsupported reads, and uncertain outcomes. State how missing notifications or late delivery are handled.
4. **Admission and residual races:** a synchronized worker admission check before every call, with no lock held over IPC. Document the remaining non-atomic gap between validation and application changes; an already admitted synchronous call may finish after invalidation.
5. **Acceptance:** deterministic rejection/race tests plus separately recorded real-window checks across the declared scope. Include same-frame cross-desktop peers, tabs/sheets, permission loss, pause/quit, stale completions, and constrained geometry. Consent to a disposable setter test is separate from production enablement.

This review accepts no freshness number or performance guarantee for live control. The pure model's existing 0.5-second age limit remains a simulation assumption.

## Specified follow-up: read-only control-model integration

Implement an explicit preview using the production focused worker and `FocusedWindowEvidence.controlObservation`. Keep invalid geometry/timing/sequence projection failures visible. Preserve the existing request-context checks before delivering evidence to the control boundary. Show unknown requirements and positive exclusions alongside the model's rejection; use wording that makes clear no window was enrolled or moved.

The integration needs one process-generation issuer, bounded registration of window serials (now supplied by M2.9 tracked-set replacements), monotonic delivery time, and one authoritative control environment epoch. The app's report request counter and activation revision must stay distinct. Trust loss, pause/resume, app termination, and environment invalidation must reach the control boundary consistently; do not copy unrelated numeric counters into the model or silently restart it to accept stale evidence. A resumed preview requires fresh inspection.

Keep an explicit boundary with no platform handler for `prepare`, `perform`, or `readback`. If those effects unexpectedly appear in the read-only path, reject the preview and expose an internal failure; never substitute synthetic `eligible` observations. Reconciliation in this stage invalidates evidence or requests an explicit fresh read, not automatic polling or window actions. Read-only preview must preserve menu Pause and Quit.

Acceptance for this next task:

- Real projected unknown/ineligible observations cannot produce an admitted plan or setter effect.
- Stale delivery, context changes, invalid projection, permission loss, pause/quit, and process replacement reject or invalidate the preview with fixed, content-free reasons.
- Storage and outstanding work remain bounded; no AX call moves onto the main thread or Swift cooperative executor.
- Deterministic integration tests and `scripts/verify` pass. A separate manual check verifies the menu/report path and rejection from a real application, with no frame setters or focus actions.

The live coordinator, atomic setter admission mailbox, frame application policy, and opted-in real setter checks remain subsequent tasks. Completing a blocked preview will not close the platform eligibility gates.

The specified source integration and deterministic checks are now implemented in [M2.8](../m2-read-only-preview.md). Its separate scoped foreground-handler/report, operator-driven TextEdit menu, and in-flight Pause/native desktop/LaunchServices permission-loss acceptance do not establish generic application coverage or production eligibility. The bounded explicit-read registry replacement protocol is now implemented in [M2.9](../m2-registry-lifecycle.md); remaining acceptance and live delivery/admission contracts still precede live control integration.

## M2.25 provider follow-up

[The public-API feasibility review](../m2-provider-feasibility.md) additionally considers AppKit active-Space window-number enumeration. It provides membership for known numbers without an AX identity bridge, so this decision remains unchanged. An owned-fixture read-only snapshot is selected for ground-truth experiments only; it cannot override production eligibility.
