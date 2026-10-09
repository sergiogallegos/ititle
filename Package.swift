// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "iTile",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "iTile", targets: ["ITileApp"]),
    .executable(name: "iTileP3Lab", targets: ["ITileP3Lab"]),
    .executable(name: "iTileAXFixture", targets: ["ITileAXFixture"]),
    .executable(name: "iTileSafetySnapshotLab", targets: ["ITileSafetySnapshotLab"]),
  ],
  dependencies: [],
  targets: [
    .target(name: "ITileCore"),
    .target(name: "ITilePlatform", dependencies: ["ITileCore"]),
    .executableTarget(name: "ITileApp", dependencies: ["ITileCore", "ITilePlatform"]),
    .executableTarget(name: "ITileP3Lab", dependencies: ["ITileCore", "ITilePlatform"]),
    .target(name: "ITileFixtureDiagnostics"),
    .executableTarget(name: "ITileAXFixture", dependencies: ["ITileFixtureDiagnostics"]),
    .executableTarget(name: "ITileSafetySnapshotLab", dependencies: ["ITileFixtureDiagnostics"]),
    .testTarget(name: "ITileFixtureDiagnosticsTests", dependencies: ["ITileFixtureDiagnostics"]),
    .testTarget(name: "ITileCoreTests", dependencies: ["ITileCore"]),
    .testTarget(name: "ITilePlatformTests", dependencies: ["ITilePlatform", "ITileCore"]),
  ]
)
