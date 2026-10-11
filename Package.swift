// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WayDetectCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "WayDetectCore", targets: ["WayDetectCore"])],
    targets: [
        .target(name: "WayDetectCore"),
        .testTarget(name: "WayDetectCoreTests", dependencies: ["WayDetectCore"])
    ]
)
