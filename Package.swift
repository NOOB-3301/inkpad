// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "InkPad",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "InkPadCore"),
        .executableTarget(name: "InkPad", dependencies: ["InkPadCore"]),
        .testTarget(name: "InkPadCoreTests", dependencies: ["InkPadCore"]),
    ],
    swiftLanguageModes: [.v5]
)
