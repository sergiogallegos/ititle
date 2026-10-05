# Contributing

This project is an early prototype hosted at [sergiogallegos/ititle](https://github.com/sergiogallegos/ititle). Read the README, architecture, and roadmap to distinguish implemented behavior from proposals.

Prefer a small reproducible problem and a focused change. Include macOS/app versions and a redacted event sequence for platform bugs. Keep pure policy in ITileCore and macOS behavior in ITilePlatform. Introduce no third-party dependencies or private APIs. Explain architecture changes in a decision record.

Run scripts/verify. For platform changes, describe the manual scenarios tested and remaining gaps. Tests must protect behavior or invariants rather than repeat implementation details. Do not claim broad compatibility from one local machine.

Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) for naming and API clarity. Format Swift with the official [swift-format](https://github.com/swiftlang/swift-format) included in Apple's Swift 6 toolchain. Swift does not mandate one whitespace style; this repository uses the tool's defaults, captured in `.swift-format` (two-space indentation and a 100-column line-length target). This is a reproducible project convention, not a claim that every Apple project uses identical formatting. No third-party formatter or package installation is needed.

Run `scripts/format` after editing Swift. It formats `Package.swift`, `Sources`, and `Tests`; `scripts/verify` checks the same paths with strict lint before building/testing. Keep the checked-in configuration stable and review formatter changes when upgrading the toolchain. Formatting does not replace API or behavior review.

The project uses the [MIT License](LICENSE). Submit contributions under that license and preserve existing notices. All source in the initial scaffold is original. Review the license and attribution requirements before copying any upstream material. Use the GitHub repository for focused issues and pull requests; omit sensitive diagnostics.
