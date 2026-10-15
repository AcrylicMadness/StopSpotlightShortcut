// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StopSpotlightShortcut",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "StopSpotlightShortcut", path: "Sources/StopSpotlightShortcut")
    ]
)
