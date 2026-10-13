// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "hark",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "HarkCore"),
        .executableTarget(name: "hark", dependencies: ["HarkCore"]),
        .testTarget(name: "HarkCoreTests", dependencies: ["HarkCore"]),
    ],
    swiftLanguageModes: [.v5]
)
