import AppKit
import FocusDockCore
import Observation

/// One mode pill as drawn: collapsed (icon only) unless it has a label.
struct PillItem: Equatable, Identifiable {
    let mode: Mode
    /// The mode name when active, "Name m:ss" for the pending target, nil when collapsed.
    let label: String?
    let isCountdown: Bool
    var id: String { mode.id }
}

/// UI state of the dock. ModeController, Workspace and the hosting view are its only writers.
@MainActor @Observable
final class DockModel {
    static let stayLabel = "Stay"

    private(set) var tiles = TileList.empty
    private(set) var tileSize: CGFloat
    private(set) var modes: [Mode] = []
    private(set) var modeState: ModeState?
    private(set) var countdown: Int?
    /// A tile id, or "mode:<id>" for a pill.
    private(set) var hoveredID: String?
    /// Launch start per tile id, so every bounce starts from rest.
    private(set) var launchStarts: [String: Date] = [:]
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    init(tileSize: CGFloat) {
        self.tileSize = tileSize
    }

    var pills: [PillItem] {
        let active: String? = switch modeState {
        case .active(let id), .pending(let id, _, _): id
        case nil: nil
        }
        let pendingTarget: String? = if case .pending(_, let to, _) = modeState { to } else { nil }
        return modes.map { mode in
            if mode.id == pendingTarget, let countdown {
                return PillItem(mode: mode, label: "\(mode.name) \(Countdown.format(seconds: countdown))", isCountdown: true)
            }
            return PillItem(mode: mode, label: mode.id == active ? mode.name : nil, isCountdown: false)
        }
    }

    var layout: PlatterLayout {
        let pills = pills
        let collapsed = DockMetrics.pillHeight(tileSize: tileSize)
        let widths = pills.map { pill in
            pill.label.map { DockMetrics.expandedPillWidth(labelWidth: Self.textWidth($0, tileSize: tileSize), tileSize: tileSize) } ?? collapsed
        }
        let stayWidth = DockMetrics.stayWidth(labelWidth: Self.textWidth(Self.stayLabel, tileSize: tileSize), tileSize: tileSize)
        let row = PillRow(widths: widths, stayAfter: pills.firstIndex(where: \.isCountdown), stayWidth: stayWidth)
        return PlatterLayout(tileCount: tiles.count, dividerAfter: nil, tileSize: tileSize, pills: row)
    }

    /// The font pill labels are drawn with; digits are monospaced so the countdown does not jiggle.
    static func pillFont(tileSize: CGFloat) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: DockMetrics.pillFontSize(tileSize: tileSize), weight: .semibold)
    }

    private static func textWidth(_ text: String, tileSize: CGFloat) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: pillFont(tileSize: tileSize)]).size().width.rounded(.up)
    }

    var hoveredTile: (index: Int, tile: DockTile)? {
        guard let index = tiles.firstIndex(where: { $0.id == hoveredID }) else { return nil }
        return (index, tiles[index])
    }

    /// Only collapsed pills get a hover label; expanded ones already show their name.
    var hoveredPill: (index: Int, mode: Mode)? {
        let pills = pills
        guard let index = pills.firstIndex(where: { "mode:\($0.id)" == hoveredID }), pills[index].label == nil else { return nil }
        return (index, pills[index].mode)
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
        if let hoveredID, !hoveredID.hasPrefix("mode:"), !tiles.contains(where: { $0.id == hoveredID }) { self.hoveredID = nil }
    }

    func setModes(_ modes: [Mode], state: ModeState, countdown: Int?) {
        if modes != self.modes { self.modes = modes }
        if state != modeState { modeState = state }
        if countdown != self.countdown { self.countdown = countdown }
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
