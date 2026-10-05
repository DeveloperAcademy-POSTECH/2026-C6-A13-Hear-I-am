// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DirectionHapticsCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "DirectionHapticsCore", targets: ["DirectionHapticsCore"])],
    targets: [
        .target(name: "DirectionHapticsCore", path: "Sources/Core"),
        .testTarget(name: "DirectionHapticsCoreTests", dependencies: ["DirectionHapticsCore"], path: "Tests/CoreTests")
    ]
)
