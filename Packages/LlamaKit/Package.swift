// swift-tools-version: 6.0
import PackageDescription

// LlamaKit wraps the llama.cpp C API in a small, Swift-concurrency friendly surface.
// The `llama` binary target is vendored by `Scripts/fetch-llama.sh` (see README) and is
// intentionally not committed: it is ~430 MB with debug symbols.
let package = Package(
    name: "LlamaKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "LlamaKit", targets: ["LlamaKit"]),
    ],
    targets: [
        .binaryTarget(name: "llama", path: "llama.xcframework"),
        .target(
            name: "LlamaKit",
            dependencies: ["llama"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(name: "LlamaKitTests", dependencies: ["LlamaKit"]),
    ],
    swiftLanguageModes: [.v6]
)
