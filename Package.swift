// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FocusDock",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "FocusDockCore"),
        .executableTarget(name: "FocusDock", dependencies: ["FocusDockCore"]),
        .testTarget(name: "FocusDockCoreTests", dependencies: ["FocusDockCore"]),
    ]
)
