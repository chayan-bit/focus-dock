import Foundation
import Testing
@testable import FocusDockCore

struct TileListTests {
    private let notes = AppRef(bundleID: "com.apple.Notes", url: URL(fileURLWithPath: "/System/Applications/Notes.app"), name: "Notes")
    private let zed = AppRef(bundleID: "dev.zed.Zed", url: URL(fileURLWithPath: "/Applications/Zed.app"), name: "Zed")
    private let chrome = AppRef(bundleID: "com.google.Chrome", url: URL(fileURLWithPath: "/Applications/Google Chrome.app"), name: "Google Chrome")
    private let drive = WebApp(name: "Drive", url: URL(string: "https://drive.google.com")!)
    private let github = WebApp(name: "GitHub", url: URL(string: "https://github.com")!)

    @Test func appsInConfigOrderThenWebApps() {
        let tiles = TileList.forMode(apps: [zed, notes], webApps: [drive, github], chrome: chrome, running: [notes])
        #expect(tiles.map(\.app.name) == ["Zed", "Notes", "Drive", "GitHub"])
        #expect(tiles.map(\.isRunning) == [false, true, false, false])
        #expect(tiles.map(\.isWebApp) == [false, false, true, true])
    }

    @Test func webAppTilesAreChromeWithTheirOwnIDs() {
        let tiles = TileList.forMode(apps: [chrome], webApps: [drive], chrome: chrome, running: [chrome])
        #expect(tiles.map(\.id) == ["com.google.Chrome", "web:https://drive.google.com"])
        #expect(tiles[1].app.url == chrome.url && tiles[1].webURL == drive.url)
        #expect(!tiles[1].isRunning)
    }

    @Test func webAppsNeedChrome() {
        #expect(TileList.forMode(apps: [notes], webApps: [drive], chrome: nil, running: []).map(\.id) == ["com.apple.Notes"])
    }

    @Test func doesNotDuplicateAppsOrWebApps() {
        let tiles = TileList.forMode(apps: [notes, notes], webApps: [drive, drive], chrome: chrome, running: [])
        #expect(tiles.count == 2)
    }

    @Test func matchesRunningByPathWhenBundleIDIsMissing() {
        let noID = AppRef(bundleID: nil, url: URL(fileURLWithPath: "/Applications/Zed.app/"), name: "Zed")
        #expect(TileList.forMode(apps: [noID], webApps: [], chrome: nil, running: [zed])[0].isRunning)
    }
}
