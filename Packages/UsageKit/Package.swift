// swift-tools-version: 5.9
import PackageDescription

// Kept as a local package rather than plain shared source dirs so the collector
// port can be iterated and tested with `swift test`, which is seconds against
// xcodebuild's minutes. The app and widget targets consume it from project.yml.
let package = Package(
    name: "UsageKit",
    platforms: [.macOS(.v14)],
    products: [
        // Model + formatting. Linked by the app AND the sandboxed widget.
        .library(name: "UsageModel", targets: ["UsageModel"]),
        // Collection: Keychain, arbitrary paths, subprocesses. App only — the
        // widget is sandboxed and cannot do any of it.
        .library(name: "UsageCollector", targets: ["UsageCollector"]),
    ],
    targets: [
        .target(name: "UsageModel"),
        .target(name: "UsageCollector", dependencies: ["UsageModel"]),
        .testTarget(name: "UsageModelTests", dependencies: ["UsageModel"]),
    ]
)
