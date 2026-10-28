import AppKit
import FocusDockCore
import Observation

/// UI state of the dock. Workspace and the hosting view are its only writers.
@MainActor @Observable
final class DockModel {
    private(set) var tiles = TileList.merge(pinned: [], running: [])
    private(set) var tileSize: CGFloat
    private(set) var hoveredID: String?
    /// Launch start per tile id, so every bounce starts from rest.
    private(set) var launchStarts: [String: Date] = [:]
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    init(tileSize: CGFloat) {
        self.tileSize = tileSize
    }

    var layout: PlatterLayout {
        let pinnedCount = tiles.prefix { $0.isPinned }.count
        return PlatterLayout(tileCount: tiles.count, dividerAfter: tiles.hasDivider ? pinnedCount : nil, tileSize: tileSize)
    }

    var hoveredTile: (index: Int, tile: DockTile)? {
        guard let index = tiles.firstIndex(where: { $0.id == hoveredID }) else { return nil }
        return (index, tiles[index])
    }

    func icon(for app: AppRef) -> NSImage {
        if let cached = icons[app.id] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: app.url.path)
        icons[app.id] = icon
        return icon
    }

    func setTiles(_ tiles: TileList) {
        guard tiles != self.tiles else { return }
        self.tiles = tiles
        if let hoveredID, !tiles.contains(where: { $0.id == hoveredID }) { self.hoveredID = nil }
    }

    func setTileSize(_ size: CGFloat) {
        guard size != tileSize else { return }
        tileSize = size
    }

    func setHovered(_ id: String?) {
        guard id != hoveredID else { return }
        hoveredID = id
    }

    func setLaunching(_ id: String, _ isLaunching: Bool) {
        guard isLaunching != (launchStarts[id] != nil) else { return }
        var starts = launchStarts
        starts[id] = isLaunching ? Date() : nil
        launchStarts = starts
    }
}
