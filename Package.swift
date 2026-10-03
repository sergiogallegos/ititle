// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iTile",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "iTile", targets: ["ITileApp"])],
    dependencies: [],
    targets: [
        .target(name: "ITileCore"),
        .target(name: "ITilePlatform", dependencies: ["ITileCore"]),
        .executableTarget(name: "ITileApp", dependencies: ["ITileCore", "ITilePlatform"]),
        .testTarget(name: "ITileCoreTests", dependencies: ["ITileCore"])
    ]
)
