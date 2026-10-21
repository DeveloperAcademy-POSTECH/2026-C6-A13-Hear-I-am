// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "HearIAmCore", platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "HearIAmCore", targets: ["HearIAmCore"])],
    targets: [.target(name: "HearIAmCore", resources: [.process("Spaces/Resources")]), .testTarget(name: "HearIAmCoreTests", dependencies: ["HearIAmCore"])],
    swiftLanguageModes: [.v5])
