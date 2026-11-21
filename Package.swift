// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BlinkengraphsKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "BlinkengraphsCore", targets: ["BlinkengraphsCore"]),
    ],
    targets: [
        // Foundation only, so it builds and runs the spec vectors on Linux CI too.
        .target(name: "BlinkengraphsCore"),
        .testTarget(name: "BlinkengraphsCoreTests", dependencies: ["BlinkengraphsCore"]),
    ]
)
