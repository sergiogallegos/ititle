# Inspirations and research

Initial review: 2026-10-02. Reviewed the linked official READMEs/guides at a concept level, not a complete source audit. These projects are independent and do not endorse iTile.

| Project | Idea to study | iTile's proposed interpretation |
| --- | --- | --- |
| [i3](https://i3wm.org/docs/userguide.html) | Explicit splits, directional commands, binding modes | Predictable commands and a small tree; start with binary splits |
| [AeroSpace](https://github.com/nikitabobko/AeroSpace) | Swift macOS implementation, text configuration, tree tiling, documented AX limitations | Native implementation and fault isolation; defer emulated workspaces |
| [yabai](https://github.com/asmvik/yabai) | Binary space partitioning and command-oriented control | Compact geometry model and observable commands |
| [Hyprland](https://github.com/hyprwm/Hyprland) | Dynamic tiling, configurable input, fast configuration iteration | Responsive interactions and simple reload; avoid compositor scope |
| [Omarchy](https://github.com/omacom/omarchy) | Opinionated, coherent Linux desktop defaults | A useful default workflow and short onboarding |

Omarchy is a desktop/distribution experience, not a replacement macOS window API. Hyprland is a Wayland compositor and i3 is an X11 window manager; their authority over windows differs fundamentally from a macOS Accessibility client. Their responsiveness cannot be transferred merely by imitating their algorithms.

AeroSpace documents virtual workspace emulation and unresolved AX-related stability work. yabai documents capabilities requiring deeper system access in its [SIP guide](https://github.com/asmvik/yabai/wiki/Disabling-System-Integrity-Protection). We treat these as evidence about platform tradeoffs, not reasons to claim a fresh project will automatically outperform them.

## Next source investigations

1. Window lifecycle and identity: record behavior for closing, reopening, native tabs, and app restarts.
2. Event feedback: study strategies for distinguishing requested movement from user movement.
3. Application stalls: inspect worker and timeout designs; reproduce with a controlled test app.
4. Display transitions: compare recovery policies and document what public APIs can establish.
5. Keyboard handling: compare public API choices and secure-input behavior.

For every investigation, record a pinned commit or documentation revision, specific observation, proposed design, and a local experiment. Current links are moving references. No source-level conclusions have been claimed yet.

## Attribution and licensing

The scaffold is independently authored; it contains no copied upstream implementation, assets, or configuration. Inspiration does not grant permission to copy code. Before incorporating any upstream material, inspect that exact revision's license, preserve required notices, and assess compatibility with our eventual license. Zero third-party dependencies also excludes vendored upstream libraries. Favor independently implementing documented behavior with focused tests.
