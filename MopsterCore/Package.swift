// swift-tools-version: 5.10
import PackageDescription

// Business logic of Mopster: scanning, safety checks, removal, catalogs.
// Static library: no dynamic framework to embed or sign.
let package = Package(
    name: "MopsterCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MopsterCore", targets: ["MopsterCore"])
    ],
    targets: [
        .target(name: "MopsterCore"),
        .testTarget(name: "MopsterCoreTests", dependencies: ["MopsterCore"])
    ]
)
