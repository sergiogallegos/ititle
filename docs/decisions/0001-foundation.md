# ADR 0001: Native, dependency-free foundation

Status: accepted for the local prototype. Date: 2026-10-02.

## Context

We want i3-inspired keyboard tiling on macOS with minimal maintenance and a possible future community project. macOS Accessibility is an IPC boundary controlled by other applications; Linux compositor capabilities cannot be assumed.

## Decisions

- Swift 6 language mode, macOS 14 deployment target, SwiftPM internal modules.
- Zero external packages at build or runtime; Apple frameworks and system developer tools only.
- AppKit menu-bar process; no daemon, root component, or startup registration initially.
- Public APIs, SIP enabled, explicit permission onboarding when input/window control exists.
- Foundation JSON configuration; no custom language or scripting hooks.
- Binary split geometry first; app workers and serialized coordination later.
- Current-desktop explicit tiling before automatic tiling or workspace emulation.
- No custom UI renderer, decorations, networking, updater, plugin system, or CLI in the first milestone.
- iTile is provisional. Signing identity and release distribution remain separate decisions. The repository is now hosted on GitHub; MIT was selected by the owner on 2026-10-02.
- [ADR 0002](0002-control-boundary.md) refines the control, enrollment, and keyboard decisions after the second-pass review.

## Alternatives considered

Rust/C++ core: feasible but adds interop without an identified computational bottleneck.
TOML: pleasant for users but needs a dependency or maintained parser.
Private Spaces APIs: broader functionality with compatibility and maintenance costs.
Offscreen workspace emulation: fast switching, but introduces visibility and recovery complexities.
Full i3 container parity: larger scope than needed to prove useful tiling.

## Consequences

Simple offline builds and clear module ownership. We own a small platform adapter and its testing. Some apps will be excluded. Native workspace control is limited. Performance and stability must be demonstrated, not inferred from implementation size.

Revisit desktop/workspace strategy only after an explicit use case and comparative prototype. Revisit the dependency policy only if the project owner changes the zero-dependency requirement.
