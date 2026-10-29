// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FocusDock",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/objecthub/swift-dynamicjson.git", exact: "2.0.1"),
    ],
    targets: [
        .target(name: "FocusDockCore", dependencies: [.product(name: "DynamicJSON", package: "swift-dynamicjson")]),
        .executableTarget(name: "FocusDock", dependencies: ["FocusDockCore"]),
        .testTarget(name: "FocusDockCoreTests", dependencies: ["FocusDockCore"]),
    ]
)
