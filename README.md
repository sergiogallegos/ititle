# iTile

A minimal, keyboard-driven tiling companion for macOS. Built from scratch in Swift with zero third-party dependencies.

**Status: local foundation prototype. This is not yet a working window manager.** The name is provisional; availability and trademarks have not been checked. Repository: [sergiogallegos/ititle](https://github.com/sergiogallegos/ititle).

The goal is a small tool that arranges ordinary windows predictably, responds quickly to commands, and yields gracefully when macOS or an application cannot cooperate. One menu-bar app, public APIs, SIP enabled, no external services.

## What exists

- A dependency-free Swift package with separate core, platform, and app targets.
- A pure binary split layout engine with geometry validation and unit tests.
- A menu-bar preview showing status and a Quit action; it never moves windows or captures keyboard input.
- A read-only Accessibility trust check.
- Local app packaging and architecture, decision, testing, and contribution documentation.

Window discovery, frame mutation, hotkeys, configuration loading, automatic tiling, and workspaces are **not implemented**. `config/proposed-v1.json` is a design example, not a working configuration.

## Build

Development target: macOS 14+, Swift 6.0+ with Apple command-line developer tools. Only the local toolchain has been exercised; deployment compatibility still needs testing on older macOS versions.

```sh
scripts/verify
scripts/package-app
```

Packaging produces `dist/iTile.app` with an ad-hoc signature. Open it in Finder to try the inert menu-bar preview; Quit iTile exits it. No Accessibility permission is needed for this preview. Rebuilding an ad-hoc signed app may invalidate future permission grants; distribution signing is a later milestone.

No package manager or network downloads are needed once Apple's developer tools are installed. Zero dependencies means zero third-party build/runtime packages; the Swift toolchain, Apple frameworks, and system shell utilities remain prerequisites.

## Project map

```text
Sources/ITileCore/       Value types and deterministic layout geometry
Sources/ITilePlatform/   macOS boundary (currently trust check only)
Sources/ITileApp/        AppKit menu-bar lifecycle
Tests/ITileCoreTests/    Geometry and invariant tests
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
- [Read-only feasibility experiments](docs/platform-experiments.md)
- [Inspirations and source references](docs/inspirations.md)
- [Roadmap](docs/roadmap.md)
- [Testing and measurement](docs/testing.md)
- [Contributing](CONTRIBUTING.md)
- [Privacy and security](SECURITY.md)

## Open-source direction

Develop locally and prove the workflow, with source hosted on GitHub for review. The code and documentation are licensed under the [MIT License](LICENSE), copyright 2026 Sergio Gallegos. The final name and distribution identity remain provisional. No upstream source has been copied into this scaffold. See [inspirations](docs/inspirations.md) for attribution and future source-review rules.
