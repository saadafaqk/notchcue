// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotchCue",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "CueCore"),
        .executableTarget(name: "NotchCue", dependencies: ["CueCore"]),
        .testTarget(name: "CueCoreTests", dependencies: ["CueCore"]),
    ]
)
