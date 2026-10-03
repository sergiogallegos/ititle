# Privacy and security

The current preview checks Accessibility trust without prompting. It does not enumerate window contents, capture keyboard events, move windows, communicate over the network, or persist diagnostics.

Planned capabilities require explicit Accessibility permission and any input permissions required by the chosen event-tap mode. Do not request Screen Recording solely for window tiling; if a future visibility strategy needs additional permission, reassess the design and document it.

Default logs must exclude window titles, typed keys, URLs, and document paths. Configuration must not execute arbitrary shell commands. Preserve public-API and SIP-enabled operation. A paused manager must not continue scheduling frame writes.

Before public release, configure a real private vulnerability-reporting channel. No reporting address exists yet; do not place sensitive reproduction data in a public issue. Ad-hoc local app signatures are not Developer ID signing or notarization.
