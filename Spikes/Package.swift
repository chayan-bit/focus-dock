// swift-tools-version: 6.2
// Phase 4 spike harness (docs/SHELL-SPEC.md 11). Separate package: never linked into FocusDock.
// FocusDockSpike is a tiny C loader that never changes, so its ad-hoc signature (and the TCC
// grants tied to it) survive rebuilds; all test code lives in libSpikeKit.dylib, loaded at runtime.
import PackageDescription

let package = Package(
    name: "FocusDockSpikes",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "FocusDockSpike", targets: ["FocusDockSpike"]),
        .library(name: "SpikeKit", type: .dynamic, targets: ["SpikeKit"]),
    ],
    targets: [
        .executableTarget(name: "FocusDockSpike"),
        .target(
            name: "SpikeKit",
            cSettings: [.unsafeFlags(["-fobjc-arc", "-Wno-deprecated-declarations"])],
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"), .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreMedia"), .linkedFramework("CoreVideo"),
                .linkedFramework("UserNotifications"), .linkedFramework("ImageIO"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
    ]
)
