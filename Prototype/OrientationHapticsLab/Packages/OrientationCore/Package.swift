// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OrientationCore",
    platforms: [.macOS(.v13), .iOS("26.0")],
    products: [.library(name: "OrientationCore", targets: ["OrientationCore"])],
    targets: [
        .target(name: "OrientationCore"),
        .testTarget(name: "OrientationCoreTests", dependencies: ["OrientationCore"])
    ]
)
