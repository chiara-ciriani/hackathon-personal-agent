// swift-tools-version: 6.0
// QuietCore: platform-independent logic (contracts, DSP features, route simplification, aggregation).
// It has no AVFoundation or ARKit imports, so `swift test` runs on macOS and on Linux.
import PackageDescription

let package = Package(
    name: "QuietCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "QuietCore", targets: ["QuietCore"])
    ],
    targets: [
        .target(name: "QuietCore"),
        .testTarget(name: "QuietCoreTests", dependencies: ["QuietCore"])
    ]
)
