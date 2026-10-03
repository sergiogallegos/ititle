# Product design

## Purpose

Arrange terminal, editor, and browser windows with a small, learnable set of keyboard commands. Favor predictable behavior, visible status, and recoverability over a large feature inventory.

This is a macOS user-session application, not a kernel driver or compositor. WindowServer and applications retain control over rendering and window behavior. Fast layout calculation cannot guarantee fast application responses.

## Principles

1. Zero third-party packages or vendored dependencies; use Apple frameworks and Swift.
2. Explicit user intent wins over automatic layout. Pause and quit remain available.
3. Public APIs and SIP enabled. No Dock injection, private Space APIs, or hidden offscreen desktops in the first release.
4. Keep desired layout separate from observed window state. Failure to move one window must not stall the whole desktop.
5. Start small, measure on real applications, expand only after reliability is demonstrated.
6. Local operation without telemetry, accounts, background networking, or content logging.

## First useful workflow (planned)

Start paused. Invoke Tile to explicitly enroll eligible windows on the current desktop and focused monitor. Split horizontally or vertically, focus by direction, swap windows, adjust split ratios, and toggle floating. Maximize means using the available desktop area, not entering native fullscreen. Moving between monitors is added after coordinate conversion is validated.

A status menu exposes paused/active/degraded state, reload configuration, and quit. Proposed shortcuts use Control+Option to leave common Command shortcuts available; they are configurable and must be checked against application shortcuts and keyboard layouts. The example JSON is not currently consumed.

Dialogs, sheets, minimized windows, native fullscreen windows, and unsupported windows remain outside the tiled tree. An app-specific rule can float a window that classification gets wrong. Manual dragging temporarily suspends writes to that window; explicit re-tile restores management. The first version does not continuously undo the user's mouse movements.

## Desktop boundary

Initial integration should be validated on one native desktop and one monitor. Public APIs do not supply a full reliable native Space identity/membership model. A Space-change notification is an invalidation signal, not a Space identifier.

On a native desktop transition: suspend writes, invalidate pending plans, rediscover eligible visible windows, and require explicit re-tiling until membership detection is proven. Never infer desktop membership only from a window's rectangle. Screen/window-list metadata and Accessibility visibility can be incomplete; ambiguous windows stay unmanaged.

Custom numbered workspaces are a separate future decision. i3-like navigation does not imply complete i3 workspace behavior. Do not hide this limitation in the UI or documentation.

## Non-goals for the initial release

Animations, blur, custom decorations, a status-bar ecosystem, plugins, shell execution in bindings, custom virtual desktops, native tab manipulation, automatic login, and updates over the network.

## Proposed configuration contract

JSON at `~/.config/itile/config.json`, schema version 1. The loader will use Codable plus explicit unknown-key checking. Reject duplicate/conflicting bindings and out-of-range gaps; preserve the previous valid configuration on failed reload. Error messages identify the field. No file watching until manual reload is reliable. No configuration or app state is written by the current preview.

## Naming and identity

iTile communicates i3 inspiration and tiling but is only a working name. Check existing apps, package names, domains, and trademarks before publishing. Bundle identifier `local.itile.app` is temporary. Choose a stable identity before daily use with Accessibility permission.
