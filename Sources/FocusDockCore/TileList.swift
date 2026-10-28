import Foundation

/// An app the dock can show, identified by bundle id when it has one, else by path.
public struct AppRef: Equatable, Sendable {
    public let bundleID: String?
    public let url: URL
    public let name: String

    public init(bundleID: String?, url: URL, name: String) {
        self.bundleID = bundleID
        self.url = url
        self.name = name
    }

    public var id: String { bundleID ?? url.standardizedFileURL.path }

    public func isSameApp(as other: AppRef) -> Bool {
        if let bundleID, let otherID = other.bundleID { return bundleID == otherID }
        return url.standardizedFileURL.path == other.url.standardizedFileURL.path
    }
}

public struct DockTile: Equatable, Sendable, Identifiable {
    /// For a web app, Chrome under the web app's name.
    public let app: AppRef
    public let isRunning: Bool
    /// Set for web apps, which open as `Google Chrome --app=<webURL>`.
    public let webURL: URL?

    public var id: String { webURL.map { "web:\($0.absoluteString)" } ?? app.id }
    public var isWebApp: Bool { webURL != nil }
}

/// The active mode's tiles: its installed apps in config order, then its web apps.
public struct TileList: Equatable, Sendable {
    public let tiles: [DockTile]

    public static let empty = TileList(tiles: [])

    /// `chrome` is nil when Chrome is not installed; web apps are then left out.
    public static func forMode(apps: [AppRef], webApps: [WebApp], chrome: AppRef?, running: [AppRef]) -> TileList {
        let appTiles = deduplicated(apps).map { app in
            DockTile(app: app, isRunning: running.contains { $0.isSameApp(as: app) }, webURL: nil)
        }
        let webTiles = chrome.map { chrome in
            webApps.map { web in
                DockTile(app: AppRef(bundleID: chrome.bundleID, url: chrome.url, name: web.name), isRunning: false, webURL: web.url)
            }
        } ?? []
        let unique = (appTiles + webTiles).reduce(into: [DockTile]()) { result, tile in
            if !result.contains(where: { $0.id == tile.id }) { result.append(tile) }
        }
        return TileList(tiles: unique)
    }

    private static func deduplicated(_ apps: [AppRef]) -> [AppRef] {
        apps.reduce(into: []) { result, app in
            if !result.contains(where: { $0.isSameApp(as: app) }) { result.append(app) }
        }
    }
}

extension TileList: Collection {
    public var startIndex: Int { tiles.startIndex }
    public var endIndex: Int { tiles.endIndex }
    public subscript(position: Int) -> DockTile { tiles[position] }
    public func index(after i: Int) -> Int { tiles.index(after: i) }
}
