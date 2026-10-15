// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PoC4Core", platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "PoC4Core", targets: ["PoC4Core"])],
    targets: [.target(name: "PoC4Core"), .testTarget(name: "PoC4CoreTests", dependencies: ["PoC4Core"])],
    swiftLanguageModes: [.v5])
