# M2.26 — Owned-fixture safety snapshots

Status: implemented with scoped owned-process acceptance. No production eligibility, AX identity bridge, or window mutation capability is added.

## Implemented boundary

`ITileFixtureDiagnostics` is a Foundation-only laboratory protocol/parser module. Only the fixture, standalone snapshot lab, and their tests depend on it; production app/core/platform targets do not. The production evidence-source vocabulary and all three unproven safety requirements remain unchanged.

The fixture accepts `safety-snapshot <request>` only with `--safety-probe`. Requests must be canonical positive UInt64 values, increasing within the fixture run; the command is at most 64 UTF-8 bytes. A checked sequence issuer closes on exhaustion. The fixture emits its random run UUID in a `safety-ready` event and one versioned snapshot line per accepted request. Replays/exhaustion yield a fixed rejection event. An invalid command is ignored and a lab wait expires; no user input is echoed.

Snapshots query own AppKit objects on the main thread without calling `accessibilityFocusedWindow`, `accessibilityRole`, or synthetic AX child accessors. They report:

- Schema 1, coverage `ownedFixtureOnly`, run UUID, echoed request, sequence, and enclosing monotonic interval.
- Original fixture-local window serial 1 and sampled AppKit window number, or `unavailable`.
- Active-Space, visibility, minimization, fullscreen, app hiding/frontmost, and original key/main state.
- Native tab member count, selected-original and bar state; own sheet count/attachment and modal-window presence.
- Synthetic-tree presence, a fixed scenario code, and focused/window/structural fault flags.

Counts are bounded to 64; unavailable values stay explicit. Flags can preserve `unavailable`/`notApplicable`. No `safe` or `eligible` value exists. A native one-window group can remain after closing a tab, so group existence alone is not a safety conclusion. Synthetic scenarios and application modal state do not describe every custom dialog in another app.

The parser requires exactly the schema's field set, rejects duplicate/extra/missing fields, unsupported schemas/coverage, invalid identifiers/counts/vocabulary, nonfinite/reversed intervals, and records over 4 KiB. Its consumer allows one pending request, requires exact run/request, increasing sequence, and acquisition between submission and receipt. Rejected replies do not lower its watermark. It does not merge samples, set an age policy, or issue a permit. A run UUID correlates an owned child; it is not authentication for arbitrary IPC.

This is an enclosing, non-atomic observation. Fixture-main-thread serialization does not freeze WindowServer, focus, or Space state after the reply. The original serial identifies the retained fixture object within this run; its window number is diagnostic, not persistent identity or a mapped production AX token.

## Run the lab

From the repository root:

```sh
scripts/package-ax-fixture
swift build --product iTileSafetySnapshotLab
.build/debug/iTileSafetySnapshotLab --run
```

Quit an existing ordinary fixture before starting; the lab refuses to replace it. Normal iTile may remain open. The lab requires no Accessibility grant and makes no AX calls. It launches only its owned packaged fixture with explicit probe flags, sends fixed commands through parent-only pipes, and exports fixed metadata to stdout. No transcript is saved automatically; redirect stdout if desired. Only the disposable fixture creates/closes native tabs/sheets and hides/unhides itself.

The lab checks baseline, hide/recovery, two native tabs and second-tab selection, closure, one-tab visible/hidden bar, native sheet open/close, synthetic structural fault state, and repeated focused-fault snapshots. Actions execute once; at most ten fresh observation requests per scenario allow asynchronous AppKit state to settle. Every observation has its own request and sequence. The lab does not call the fixture's older `desktop-status` command, which would consume an armed focused-accessor fault.

Bounds: one owned child, one snapshot request outstanding, 30-second workflow deadline, five-second event waits, 512 received lines, 8 KiB buffered-input bound, and 16 reported displays. Parser records have the stricter 4 KiB bound. Cleanup sends Quit, closes input, waits three seconds, then terminates and waits one second before killing only a still-running owned child; forced cleanup is incomplete. These workflow deadlines do not bound every OS process-launch call. Missing/rejected/malformed/stale replies or unexpected states return status 1. `lab-owned-snapshot-passed` plus orderly cleanup returns status 0 for this laboratory scope only.

## Validation — 2026-10-09

Final `scripts/format` and `scripts/verify` passed **200 tests** (130 core, 65 platform, five fixture protocol tests), plus the existing recovery-lab parser self-check. New protocol tests cover round-trip unavailable states, strict schema/duplicates/limits, exact outstanding request/run/time, stale/rejected sequence behavior, and checked issuer exhaustion. Fixture release build and strict ad-hoc signature verification passed.

Artifact hashes:

- Rebuilt fixture executable: `f39b19f61cf66d4ee65abb3b2500c33c107d90a43629764feaa334389760f9cc`.
- Running iTile remained the M2.22 artifact: `bd8f2a7da660befa0b54b72064dc737daa3d8e5640eac835fc35fefadfe6a08a`; it was not rebuilt or restarted for this lab.

OS: macOS 27.0.1 build 26A434. Lab-reported AppKit display coordinates use **bottom-origin** rectangles, not the production report's top-origin conversion:

| Display | Frame | Usable area | Scale |
| --- | --- | --- | --- |
| 0 | (0, 0, 1920, 1080) | (0, 60, 1920, 990) | 1 |
| 1 | (-1920, 0, 1920, 1080) | (-1920, 0, 1920, 1080) | 1 |

All 14 final scenario samples were accepted with requests/sequences 1–14 in one run. The original sampled number was 28339, retained as diagnostic data only. Hide/recovery changed own hidden state; two tabs exposed count 2 and selection changes; after closing the second tab, the remaining count 1 group exposed both visible and hidden bar states. Native sheets exposed count 1/attachment, then count 0/no attachment. Repeated synthetic snapshots retained the armed structural fault; repeated focused snapshots retained `focusedFault=true` and `hidden=false`. The owned child exited normally. No new AX-focused report or cross-process identity comparison was collected.

An initial run tried hiding the bar with two tabs; AppKit kept it visible through the bounded observations. That run was incomplete and cleaned up normally. The final lab uses the feasible one-tab hidden-bar case; it does not claim two-tab hidden-bar acceptance. No source change forces AppKit to violate its native behavior.

No permission change, user-window setter, desktop switch, display configuration change, or production scope expansion occurred. This adds own-object ground truth, not generic safety coverage.

## Next task

Specify and test an explicit fixture-local AX identity binding for paired AX/snapshot observations, including wrong-run/window, same-bounds peer, and tab/sheet transitions. Do not infer the binding from geometry, a single AX window, or a shared PID. Keep the experiment separate from production eligibility and any real setter proposal.
