# Foundation validation — 2026-10-02

Environment: Apple Silicon, macOS 27.0.1 (26A434), Apple Swift 6.4. Deployment target: macOS 14 (not tested on that OS).

- `scripts/verify`: passed debug build, all 4 XCTest cases (0 failures), and Info.plist lint.
- `scripts/package-app`: passed release build and local ad-hoc signing.
- `codesign --verify --strict --verbose=2 dist/iTile.app`: passed.
- Shell scripts passed `sh -n`.
- Swift package declares no external dependencies; repository has no remote.

SwiftPM initially could not start its nested sandbox inside the execution sandbox. Verification and packaging succeeded outside that restriction; no package dependencies were downloaded.

The menu-bar app was not launched or visually verified in this session. No Accessibility permission was requested, no keyboard interception was enabled, and no windows were moved. No real-window integration or latency benchmark has been performed.
