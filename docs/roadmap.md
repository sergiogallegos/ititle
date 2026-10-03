# Roadmap

## M0 — Foundation (implemented)

- Local Git repository and documentation.
- Zero-dependency package, pure split solver, tests.
- Inert menu-bar shell and local app packaging.

## M1 — Read-only platform probe

Implement permission onboarding and per-application discovery. List redacted window tokens, roles, supported operations, and display geometry through an explicit diagnostic command. Prove identity survives title changes and rejects stale handles after destruction. Validate visible-window membership before any mutation.

Exit: correct classification on terminal, editor, browser, Finder, dialogs, and native tabs; no window movement. This is the next development step.

## M2 — Explicit tiling

Enroll eligible windows on one desktop/monitor. Add per-application workers, frame diffing, conservative application, pause, and failure reporting. Keep all windows visible. Minimum-size rejection must stop retrying.

Exit: repeatable manual tiling and clean pause/quit; one stalled app does not block others.

## M3 — Keyboard workflow

Add hotkeys, focus/swap, split resizing, floating, desktop-area maximize, and JSON reload. Verify keyboard layouts, secure input, event-tap disablement, permission loss, and no typing interception outside handled chords.

Exit: ordinary terminal/editor/browser session operated by keyboard without runaway writes.

## M4 — Daily-use hardening

Add automatic enrollment only after explicit tiling works. Handle manual dragging, multiple displays, mixed scale, hotplug, sleep/wake, native Spaces/fullscreen/Mission Control, crash restart, and constrained applications. Add trace-based fake-platform tests and latency measurements.

Exit: multi-day local usage with documented app/OS coverage and no unrecovered hidden windows or unbounded resource growth. No stability claims based solely on unit tests.

## M5 — Public preview

Choose final name, ownership and license; audit attribution and secrets; select stable bundle identifier; add hosted macOS CI, release notes, reproducible packaging, contribution templates, and a private vulnerability-reporting channel. Decide Developer ID signing/notarization and explain any preview distribution limitations.

Publish only when requested. Hosting workflow actions, if added, are development infrastructure and must be documented separately from the zero-package product policy.

## Deferred research

Custom workspaces, IPC/CLI, richer containers, restoration across app restarts, and extra layout families. Each needs a concrete use case and an architecture decision before implementation.
