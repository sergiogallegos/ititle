# M2.25 — Safety-provider feasibility review

Status: review complete, 2026-10-09. No reviewed provider establishes a production mutation scope. [ADR 0004](decisions/0004-supported-scope.md) remains authoritative. The next source task is a read-only owned-fixture safety snapshot, specified below; it is not a production eligibility provider.

## Findings

The current `WindowEligibilityAssessment` always retains desktop visibility, native-tab safety, and nested-dialog safety. `EvidenceSource` admits only focused AX, bounded AX structure, and uncorrelated CG bounds; no source has safety coverage. Historical provenance acceptance and the recovery lab validate delivery/rejection behavior, not those missing requirements. No source changes are needed to preserve this boundary.

Reviewed the installed macOS 27.0 SDK declarations in `NSWindow.h`, `CGWindow.h`, and `AXAttributeConstants.h`, Apple's documentation, the focused adapter, and prior cross-desktop/tab/dialog experiments. This is a review of these strategies, not a proof that every public-API strategy is impossible.

| Strategy | Evidence it can supply | Missing requirement / outcome |
| --- | --- | --- |
| CG on-screen list and window number | Window-server metadata and a session window ID | No implemented bridge from that ID to the exact AX token; same-PID/equal-bounds collision already observed. Diagnostic only. |
| AppKit active-Space window-number list | Current-Space visible window numbers, including other apps with the appropriate option | Additional membership evidence for known window numbers; still no AX-to-number identity proof. Not a replacement for the missing bridge. |
| Frontmost app plus focused AX equality | Sampled process/focus prerequisites | Not desktop membership or structural lifecycle coverage; checks can become stale after the last read. Retain existing rejection guards. |
| Bounded AX tabs/sheets/dialog graph | Positive exclusions and explicit incomplete outcomes | Negative samples cannot establish structural safety across later calls. Do not raise traversal bounds to turn absence into proof. |
| Notification registration and repeated negative reads | Observed changes and additional samples | Delayed/missing delivery and gaps between reads remain; no continuous safety contract or measured live age policy. |
| App/version allowlist or operator assertion | Declared scope/consent | No independent provider for any missing requirement. Cannot grant eligibility. |
| Cooperative owned AppKit fixture | Exact own-object identity, active-Space state, native tab/sheet state, and controlled scenarios | Useful laboratory ground truth. No access to arbitrary applications' AppKit objects; cross-process AX binding and lifecycle coverage still need separate work. Select for the next read-only experiment only. |

Apple's [CG window-info function](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)) returns metadata for selected windows; [the window-number key](https://developer.apple.com/documentation/coregraphics/kcgwindownumber) identifies a window within a user session. This is different from an application's [focused AX window](https://developer.apple.com/documentation/applicationservices/kaxfocusedwindowattribute). Our adapter does not correlate these identity domains. Neither a unique geometry candidate nor a single observed application window supplies the missing invariant.

The installed SDK documents [AppKit's window-number list](https://developer.apple.com/documentation/appkit/nswindow/windownumbers(options:)) as returning visible windows on the active Space by default, with options for all applications/all Spaces. That makes a known number's sampled membership useful. It does not manufacture the number of an arbitrary AX element or identify a native desktop ordinal. Do not confuse a Space-change counter with the user's requested desktop number.

For an AppKit window, [isOnActiveSpace](https://developer.apple.com/documentation/appkit/nswindow/isonactivespace) describes active-Space membership, including where a nonvisible window would appear if ordered onscreen. It must be recorded alongside visibility/minimization rather than treated as proof of visible pixels. [NSWindowTabGroup](https://developer.apple.com/documentation/appkit/nswindowtabgroup) exposes its member windows; the SDK says groups are lazily created and `tabbedWindows` can be nil when the tab bar is hidden. A hidden tab bar or nonnil group alone is therefore not a reviewed safety rule. [Attached sheets and other window relationships](https://developer.apple.com/documentation/appkit/nswindow) describe own AppKit state, not every custom dialog or AX relationship in another app.

These API facts support a **fixture instrumentation strategy**, not a production capability. A cooperative protocol does not become generic merely because both endpoints use public APIs. No private AX-to-CG bridge, injection, screenshots, title/path matching, or additional permission is selected.

## Selected next source task — owned-fixture safety snapshot

Add an explicitly enabled fixture-only diagnostic mode and a fixed `safety-snapshot` command over its existing parent-owned pipe. Capture own AppKit state on the fixture main thread, without using its faulting AX-focused accessor. Return one bounded, versioned record; do not add this record to `EvidenceSource`, `DiagnosticEvidenceEnvelope`, or production eligibility.

The proposed schema must include:

- Schema revision, fixture-run identifier, checked increasing snapshot sequence, and enclosing monotonic start/end. A restarted fixture has a new run identifier; sequence exhaustion closes snapshot issuance.
- Original-window identity expressed by a fixture-local serial and its current AppKit window number, or explicit unavailable status. Window numbers are diagnostic session identifiers, never persistent identity.
- Own active-Space, visible, minimized, fullscreen, hidden, frontmost, and key/main-window state. Record sampled values and uncertainty without a synthesized `safe` Boolean.
- Native tab member count and selected-original status where available; sheet count/attached-sheet status, application modal-window presence, and controlled synthetic scenario/fault state. A getter being unavailable or a scenario being outside the schema's coverage stays explicit.
- Fixed coverage `ownedFixtureOnly`. No titles, document paths, input values, user-app identifiers, or user-provided eligibility override.

The record is an enclosing, non-atomic sample. Main-thread serialization of fixture-owned state does not make WindowServer state atomic or guarantee stability after reply. No age policy, lease, mutation permit, or new trusted production provider is inferred. Before designing a lease, define what transitions the cooperative target can actually prevent; a promise to delay its own tab command cannot freeze global Space changes or another AX client.

Start with one original window and bounded fixture-owned native tabs/sheets and existing synthetic cases. Enforce finite record size/counts and reject malformed, duplicate, replayed, wrong-run, and unsupported-schema records in the lab consumer. Correlate replies with a single outstanding parent request and the previous sequence watermark. Keep this transport separate from the existing arbitrary user-app AX token registry. A side-by-side AX report and fixture snapshot are compared observations, not a proved identity binding.

Acceptance for this task:

1. Deterministic parser checks reject stale/restarted/malformed snapshots and preserve unavailable/out-of-coverage states; no eligible branch or production import exists.
2. Separate owned-process checks record baseline, hide/recovery, native tabs with visible/hidden bar where feasible, sheet open/close, and synthetic scenario/fault state. Snapshot reads must not consume an armed one-shot fault.
3. Missing replies and forced cleanup are incomplete; storage, commands, waits, and owned children remain bounded. Run `scripts/format` and `scripts/verify` after source edits.
4. Record exact fixture/iTile hashes, OS, reported display topology, and sampled timings. Additional desktop transitions need their own manual observation; the existing cross-desktop evidence is not a new snapshot-provider pass.

This source task will make the missing coverage measurable against controlled ground truth. It will not make iTile a working window manager. A subsequent proposal must still establish exact AX identity binding, scope, transition coverage, measured freshness, per-call admission, readback, and explicit disposable-setter consent before any mutation experiment. Production enable/disable management and yielding to mouse drag/resize remain required product work before daily use.

## Validation scope

Documentation/source/SDK review only. No GUI action, permission change, fixture launch, window mutation, or new manual platform acceptance occurred. Local Markdown links and whitespace checks validate this document. Source tests are not rerun for this review; latest source verification is M2.24's 195 tests plus the lab parser self-check.

## M2.26 follow-up

[The owned-fixture snapshots](m2-fixture-safety-snapshot.md) and bounded consumer/lab are implemented and have scoped own-process acceptance. They remain outside production evidence sources and eligibility. Exact fixture-local AX binding is the next experiment; no geometry/PID inference was accepted.
