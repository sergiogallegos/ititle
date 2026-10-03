# Roadmap

## M0 — Foundation (implemented)

- Local Git repository and documentation.
- Zero-dependency package, pure split solver, tests.
- Inert menu-bar shell and local app packaging.

## M1 — Read-only platform probe

Implement permission onboarding and per-application discovery. List redacted window tokens, roles, supported operations, and display geometry through an explicit diagnostic command. Prove identity survives title changes and rejects stale handles after destruction. Run [the platform experiments](platform-experiments.md) before any mutation; record where visibility or identity remains ambiguous.

Exit: correct classification on terminal, editor, browser, Finder, dialogs, and native tabs; no window movement. This is the next development step.

## M2 — Explicit tiling

Start with explicit focused-window enrollment on one desktop/monitor; bulk discovery is gated on visibility evidence. Add per-application workers, frame diffing, conservative application, pause, and failure reporting. Keep all windows visible. Minimum-size rejection must stop retrying.

Exit: repeatable manual tiling and clean pause/quit; one stalled app does not block others. Fake-worker tests must cover pause races, late completions, queue overflow, and PID reuse before real writes. See [control contracts](control-contracts.md).

## M3 — Keyboard workflow

Add hotkeys, focus/swap, split resizing, floating, desktop-area maximize, and JSON reload. Verify keyboard layouts, secure input, event-tap disablement, permission loss, and no typing interception outside handled chords.

Exit: ordinary terminal/editor/browser session operated by keyboard without runaway writes.

## M4 — Daily-use hardening

Add automatic enrollment only after explicit tiling works and the visibility gate passes for supported cases. Handle manual dragging, multiple displays, mixed scale, hotplug, sleep/wake, native Spaces/fullscreen/Mission Control, crash restart, and constrained applications. Add trace-based fake-platform tests and latency measurements.

Exit: multi-day local usage with documented app/OS coverage and no unrecovered hidden windows or unbounded resource growth. No stability claims based solely on unit tests.

## M5 — Public preview

MIT licensing and GitHub source hosting are complete. Choose the final name; audit attribution and secrets; select stable bundle identifier; add hosted macOS CI, release notes, reproducible packaging, contribution templates, and a private vulnerability-reporting channel. Decide Developer ID signing/notarization and explain any preview distribution limitations.

Publish release artifacts only when requested. Hosting workflow actions, if added, are development infrastructure and must be documented separately from the zero-package product policy.

## Deferred research

Custom workspaces, IPC/CLI, richer containers, restoration across app restarts, and extra layout families. Each needs a concrete use case and an architecture decision before implementation.
