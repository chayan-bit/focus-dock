import Foundation
import Testing
@testable import FocusDockCore

private func fileTile(_ bundleID: String?, _ url: String, label: String, type: Int = 15) -> [String: Any] {
    var tileData: [String: Any] = [
        "file-data": ["_CFURLString": url, "_CFURLStringType": type],
        "file-label": label,
    ]
    tileData["bundle-identifier"] = bundleID
    return ["tile-type": "file-tile", "tile-data": tileData, "GUID": 1]
}

/// Mirrors the shape of a real `com.apple.dock` `persistent-apps` array.
private func makeFixture() -> [Any] { [
    fileTile("com.apple.Safari", "file:///Applications/Safari.app/", label: "Safari"),
    ["tile-type": "spacer-tile", "tile-data": [:] as [String: Any]],
    fileTile("com.tinyspeck.slackmacgap", "file:///Applications/Slack.app/", label: "Slack"),
    fileTile(nil, "/Applications/Tool%20Without%20ID.app", label: "Tool", type: 0),
    ["tile-type": "file-tile"],
    "garbage",
    fileTile("com.apple.Safari", "file:///Applications/Safari.app/", label: "Safari"),
] }

struct PersistentAppsTests {
    @Test func parsesFileTilesInOrderSkippingSpacersAndJunk() {
        let apps = PersistentApps.parse(makeFixture())
        // Duplicates survive parsing; TileList.merge removes them.
        #expect(apps.map(\.name) == ["Safari", "Slack", "Tool", "Safari"])
        #expect(apps[0].bundleID == "com.apple.Safari")
        #expect(apps[0].url.path == "/Applications/Safari.app")
    }

    @Test func handlesPosixPathUrlsWithoutBundleID() {
        let tool = PersistentApps.parse(makeFixture())[2]
        #expect(tool.bundleID == nil)
        #expect(tool.url.path == "/Applications/Tool%20Without%20ID.app")
        #expect(tool.id == "/Applications/Tool%20Without%20ID.app")
    }

    @Test func returnsEmptyForMissingOrWrongTypedValue() {
        #expect(PersistentApps.parse(nil).isEmpty)
        #expect(PersistentApps.parse(["not": "an array"]).isEmpty)
    }
}

struct TileListTests {
    private let safari = AppRef(bundleID: "com.apple.Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"), name: "Safari")
    private let slack = AppRef(bundleID: "com.tinyspeck.slackmacgap", url: URL(fileURLWithPath: "/Applications/Slack.app"), name: "Slack")
    private let zed = AppRef(bundleID: "dev.zed.Zed", url: URL(fileURLWithPath: "/Applications/Zed.app"), name: "Zed")
    private let term = AppRef(bundleID: "com.apple.Terminal", url: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), name: "Terminal")

    @Test func pinnedFirstThenUnpinnedRunningInRunningOrder() {
        let tiles = TileList.merge(pinned: [safari, slack], running: [term, slack, zed])
        #expect(tiles.map(\.app.name) == ["Safari", "Slack", "Terminal", "Zed"])
        #expect(tiles.map(\.isPinned) == [true, true, false, false])
        #expect(tiles.map(\.isRunning) == [false, true, true, true])
    }

    @Test func doesNotDuplicateAppsAcrossOrWithinLists() {
        let tiles = TileList.merge(pinned: [safari, safari], running: [safari, zed, zed])
        #expect(tiles.map(\.id) == ["com.apple.Safari", "dev.zed.Zed"])
        #expect(tiles[0].isRunning)
    }

    @Test func matchesByPathWhenBundleIDIsMissing() {
        let pinnedNoID = AppRef(bundleID: nil, url: URL(fileURLWithPath: "/Applications/Zed.app/"), name: "Zed")
        let tiles = TileList.merge(pinned: [pinnedNoID], running: [zed])
        #expect(tiles.count == 1)
        #expect(tiles[0].isRunning)
    }

    @Test func dividerOnlyWhenBothSectionsExist() {
        #expect(TileList.merge(pinned: [safari], running: [zed]).hasDivider)
        #expect(!TileList.merge(pinned: [safari], running: [safari]).hasDivider)
        #expect(!TileList.merge(pinned: [], running: [zed]).hasDivider)
    }
}
