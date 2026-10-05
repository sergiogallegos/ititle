// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "iTile",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "iTile", targets: ["ITileApp"]),
    .executable(name: "iTileP3Lab", targets: ["ITileP3Lab"]),
    .executable(name: "iTileAXFixture", targets: ["ITileAXFixture"]),
  ],
  dependencies: [],
  targets: [
    .target(name: "ITileCore"),
    .target(name: "ITilePlatform", dependencies: ["ITileCore"]),
    .executableTarget(name: "ITileApp", dependencies: ["ITileCore", "ITilePlatform"]),
    .executableTarget(name: "ITileP3Lab", dependencies: ["ITileCore", "ITilePlatform"]),
    .executableTarget(name: "ITileAXFixture"),
    .testTarget(name: "ITileCoreTests", dependencies: ["ITileCore"]),
    .testTarget(name: "ITilePlatformTests", dependencies: ["ITilePlatform", "ITileCore"]),
  ]
)
