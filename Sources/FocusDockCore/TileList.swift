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
    public let app: AppRef
    public let isPinned: Bool
    public let isRunning: Bool
    public var id: String { app.id }
}

/// Reads the native Dock's `persistent-apps` array (`com.apple.dock` defaults).
public enum PersistentApps {
    public static func parse(_ value: Any?) -> [AppRef] {
        guard let entries = value as? [Any] else { return [] }
        return entries.compactMap(appRef(from:))
    }

    private static func appRef(from entry: Any) -> AppRef? {
        guard let entry = entry as? [String: Any],
              entry["tile-type"] as? String == "file-tile",
              let tileData = entry["tile-data"] as? [String: Any],
              let fileData = tileData["file-data"] as? [String: Any],
              let urlString = fileData["_CFURLString"] as? String,
              let url = fileURL(urlString, type: fileData["_CFURLStringType"] as? Int)
        else { return nil }
        let name = tileData["file-label"] as? String ?? url.deletingPathExtension().lastPathComponent
        return AppRef(bundleID: tileData["bundle-identifier"] as? String, url: url, name: name)
    }

    /// `_CFURLStringType` 15 is a full URL string, 0 is a POSIX path (CFURLPathStyle).
    private static func fileURL(_ string: String, type: Int?) -> URL? {
        if type == 0 { return URL(fileURLWithPath: string) }
        guard let url = URL(string: string), url.isFileURL else { return nil }
        return url
    }
}

public struct TileList: Equatable, Sendable {
    public let tiles: [DockTile]
    public let hasDivider: Bool

    /// Pinned apps in Dock order, then running apps that are not pinned, like the native Dock.
    public static func merge(pinned: [AppRef], running: [AppRef]) -> TileList {
        let uniquePinned = deduplicated(pinned)
        let uniqueRunning = deduplicated(running)
        let pinnedTiles = uniquePinned.map { app in
            DockTile(app: app, isPinned: true, isRunning: uniqueRunning.contains { $0.isSameApp(as: app) })
        }
        let runningOnly = uniqueRunning
            .filter { app in !uniquePinned.contains { $0.isSameApp(as: app) } }
            .map { DockTile(app: $0, isPinned: false, isRunning: true) }
        return TileList(tiles: pinnedTiles + runningOnly, hasDivider: !pinnedTiles.isEmpty && !runningOnly.isEmpty)
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
