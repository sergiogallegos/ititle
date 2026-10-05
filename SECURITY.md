# Privacy and security

The current preview checks Accessibility trust without prompting. It does not enumerate window contents, capture keyboard events, move windows, communicate over the network, or persist diagnostics by default.

The explicit `--trace-focused-probe` diagnostic launch option emits request phases, host-uptime timestamps, session-local app/request/epoch numbers, and observed trust booleans through Apple's unified logging system. The menu identifies this mode. It logs no window titles, content, paths, or process IDs. macOS controls log retention, and a test operator can explicitly save a filtered stream; do not treat these opt-in traces as memory-only reports. Quit and relaunch without the flag to disable them. See [focused-probe tracing](docs/m2-focused-probe.md#opt-in-request-lifecycle-trace).

Planned capabilities require explicit Accessibility permission and any input permissions required by the chosen event-tap mode. Do not request Screen Recording solely for window tiling; if a future visibility strategy needs additional permission, reassess the design and document it.

Default logs must exclude window titles, typed keys, URLs, and document paths. Configuration must not execute arbitrary shell commands. Preserve public-API and SIP-enabled operation. A paused manager must not admit new frame writes. A call admitted before pause can finish afterward; invalidate pending work and never schedule a follow-up write while paused. See [control contracts](docs/control-contracts.md).

Before public release, configure a real private vulnerability-reporting channel. No reporting address exists yet; do not place sensitive reproduction data in a public issue. Ad-hoc local app signatures are not Developer ID signing or notarization.

The explicit local `--manual-probe` lab flag reads only fixed commands from parent-owned stdin. It exports the redacted report to stdout only on `report`; the parent controls any retention. A visible menu indicator identifies this mode. Fixed backend targets are the two owned fixture bundles and TextEdit, with the foreground-coordinator bypass clearly labelled. This is a read-only test path, disabled in ordinary launches; it accepts no arbitrary PID, listener, or window mutation command. `--show-probe-report` opens a static initial diagnostic window and performs no inspection.
