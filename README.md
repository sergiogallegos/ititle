# iTile

A minimal, keyboard-driven tiling companion for macOS. Built from scratch in Swift with zero third-party dependencies.

**Status: M1 read-only probe implemented with partial manual validation; real window mutation remains gated. This is not yet a working window manager.** See the [readiness review and next task](docs/m1-readiness.md). The name is provisional; availability and trademarks have not been checked. Repository: [sergiogallegos/ititle](https://github.com/sergiogallegos/ititle).

The goal is a small tool that arranges ordinary windows predictably, responds quickly to commands, and yields gracefully when macOS or an application cannot cooperate. One menu-bar app, public APIs, SIP enabled, no external services.

## What exists

- A dependency-free Swift package with separate core, platform, and app targets.
- A pure binary split layout engine with geometry validation and unit tests.
- A pure control-state model with structured observations and simulated per-setter admission; not connected to live window control.
- A menu-bar read-only probe with explicit per-application inspection, permission onboarding, pause, and Quit.
- Explicit focused-window inspection and historical-token revalidation, with scoped focus-loss, mid-request permission-loss, desktop invalidation, and physical display hotplug checks. Eligibility remains unknown or ineligible.
- A pure focused eligibility assessment with explicit exclusion/missing-evidence reasons and validation before projecting control records. No eligible production scope is enabled.
- Bounded read-only nested sheet/dialog detection during focused inspection, with explicit incomplete outcomes; scoped fixture/native-sheet checks are recorded, with lifecycle acceptance still partial.
- Dedicated per-application AX threads, session-local window tokens, typed unknown/error results, and redacted diagnostic reports.
- Window roles, minimized/fullscreen state, frame capabilities, screen geometry, and uncorrelated on-screen CG bounds. It never moves windows or captures keyboard input.
- Local app packaging and architecture, decision, testing, and contribution documentation.

Automatic discovery, frame mutation, hotkeys, configuration loading, automatic tiling, and workspaces are **not implemented**. Read-only discovery runs only through explicit menu actions for a selected application or the frontmost application’s focused window. Identity continuity and current-desktop visibility are experimental, not validated guarantees. `config/proposed-v1.json` is a design example, not a working configuration.

## Build

Development target: macOS 14+, Swift 6.0+ with Apple command-line developer tools. Only the local toolchain has been exercised; deployment compatibility still needs testing on older macOS versions.

```sh
scripts/verify
scripts/package-app
```

Run `scripts/format` after Swift edits. The project uses the official toolchain's `swift-format` with a checked-in default configuration; `scripts/verify` enforces it. See [contributing](CONTRIBUTING.md) for the Swift style convention.

Packaging produces `dist/iTile.app` with an ad-hoc signature. Open it in Finder to use the menu-bar probe; Quit iTile exits it. Opening the app needs no Accessibility permission. Choose **Enable Accessibility for inspection…**, grant permission in System Settings, then choose **Inspect application**. The report stays in memory unless you explicitly use **Copy diagnostic report**. **Pause inspections** rejects new requests and discards late results. Rebuilding an ad-hoc signed app may invalidate future permission grants; distribution signing is a later milestone.

No package manager or network downloads are needed once Apple's developer tools are installed. Zero dependencies means zero third-party build/runtime packages; the Swift toolchain, Apple frameworks, and system shell utilities remain prerequisites.

## Project map

```text
Sources/ITileCore/       Value types and deterministic layout geometry
Sources/ITilePlatform/   Read-only AX workers and trust status
Sources/ITileApp/        AppKit menu-bar lifecycle
Tests/ITileCoreTests/    Geometry, identity, and coordinate tests
Tests/ITilePlatformTests/ Worker lifecycle and fault-isolation tests
Resources/              App bundle metadata
config/                 Proposed configuration
scripts/                Verify and package locally
docs/                   Product, architecture, decisions, and research
```

## Read next

- [Product design](docs/design.md)
- [Architecture](docs/architecture.md)
- [Foundation decisions](docs/decisions/0001-foundation.md)
- [Second-pass review](docs/review-2026-10-02.md)
- [Control contracts](docs/control-contracts.md)
- [M2.1 control model and simulation limits](docs/m2-control-model.md)
- [M2.2 focused inspection and manual acceptance](docs/m2-focused-probe.md)
- [M2.4 bounded nested-dialog evidence](docs/m2-nested-dialogs.md)
- [M2.3 focused eligibility decision](docs/decisions/0003-focused-eligibility.md)
- [Read-only probe usage and manual checks](docs/m1-probe.md)
- [M1 readiness and M2.1 acceptance criteria](docs/m1-readiness.md)
- [P3 delay/timeout lab](docs/p3-lab.md)
- [Read-only feasibility experiments](docs/platform-experiments.md)
- [Inspirations and source references](docs/inspirations.md)
- [Roadmap](docs/roadmap.md)
- [Testing and measurement](docs/testing.md)
- [Contributing](CONTRIBUTING.md)
- [Privacy and security](SECURITY.md)

## Open-source direction

Develop locally and prove the workflow, with source hosted on GitHub for review. The code and documentation are licensed under the [MIT License](LICENSE), copyright 2026 Sergio Gallegos. The final name and distribution identity remain provisional. No upstream source has been copied into this scaffold. See [inspirations](docs/inspirations.md) for attribution and future source-review rules.
