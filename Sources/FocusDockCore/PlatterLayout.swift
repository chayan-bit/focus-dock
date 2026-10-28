import CoreGraphics

/// The mode pills left of the tiles: one width per mode (a collapsed pill is a circle, so its
/// width is the pill height), and optionally the "Stay" button right after one of them.
public struct PillRow: Equatable, Sendable {
    public let widths: [CGFloat]
    public let stayAfter: Int?
    public let stayWidth: CGFloat

    public init(widths: [CGFloat], stayAfter: Int? = nil, stayWidth: CGFloat = 0) {
        self.widths = widths
        self.stayAfter = stayAfter.flatMap { widths.indices.contains($0) ? $0 : nil }
        self.stayWidth = stayWidth
    }

    public static let none = PillRow(widths: [])
}

/// What a point on the platter hits.
public enum DockHit: Equatable, Sendable {
    case pill(Int)
    case stay
    case tile(Int)
}

/// Absolute geometry of the dock canvas. Both the SwiftUI drawing and the mouse hit-testing
/// read it, so what is drawn and what is clickable cannot drift apart.
/// Coordinates are top-left origin, in points; frames and x positions are platter-relative.
/// Model (phase0): abutting cells of tile + 4 pt with the icon centred, an inset to the platter
/// edge, and a divider slot between the pinned and the running-only cells. Mode pills sit
/// before the cells, aligned with the icons and centred on them vertically, with a divider
/// slot of their own.
public struct PlatterLayout: Equatable, Sendable {
    public let tileSize: CGFloat
    public let cellWidth: CGFloat
    public let platterSize: CGSize
    public let cellXs: [CGFloat]
    /// Centre x of the divider line, when there are cells on both sides of it.
    public let dividerX: CGFloat?
    public let pillFrames: [CGRect]
    public let stayFrame: CGRect?
    /// Centre x of the divider between the pills and the tiles, when both exist.
    public let pillDividerX: CGFloat?

    public init(tileCount: Int, dividerAfter: Int?, tileSize: CGFloat, pills: PillRow = .none) {
        let m = DockMetrics.self
        let split = dividerAfter.flatMap { (1..<max(tileCount, 1)).contains($0) ? $0 : nil }
        let cell = m.cellWidth(tileSize: tileSize)
        let inset = m.platterHorizontalInset(tileSize: tileSize)
        let slot = m.dividerSlot(tileSize: tileSize)
        let lineOffset = tileSize * m.dividerLineOffsetRatio
        let pillBlock = Self.pillBlock(pills, start: inset, tileSize: tileSize, cellWidth: cell)
        let pillsDivided = !pills.widths.isEmpty && tileCount > 0
        let cellsStart = pillBlock.end + (pillsDivided ? slot : 0)
        let splitSlot = split == nil ? 0 : slot
        self.tileSize = tileSize
        self.cellWidth = cell
        self.pillFrames = pillBlock.frames
        self.stayFrame = pillBlock.stay
        self.pillDividerX = pillsDivided ? pillBlock.end + slot / 2 + lineOffset : nil
        self.cellXs = (0..<tileCount).map { index in
            cellsStart + CGFloat(index) * cell + (split.map { index >= $0 ? splitSlot : 0 } ?? 0)
        }
        self.dividerX = split.map { cellsStart + CGFloat($0) * cell + slot / 2 + lineOffset }
        self.platterSize = CGSize(
            width: cellsStart + CGFloat(tileCount) * cell + splitSlot + inset,
            height: tileSize + 2 * m.platterVerticalInset(tileSize: tileSize)
        )
    }

    /// Pills start where an icon would (cell padding after the inset) and end with the same padding.
    private static func pillBlock(
        _ pills: PillRow, start: CGFloat, tileSize: CGFloat, cellWidth: CGFloat
    ) -> (frames: [CGRect], stay: CGRect?, end: CGFloat) {
        guard !pills.widths.isEmpty else { return ([], nil, start) }
        let padding = (cellWidth - tileSize) / 2
        let height = DockMetrics.pillHeight(tileSize: tileSize)
        let y = DockMetrics.platterVerticalInset(tileSize: tileSize) + (tileSize - height) / 2
        let spacing = DockMetrics.pillSpacing(tileSize: tileSize)
        var x = start + padding
        var frames: [CGRect] = []
        var stay: CGRect?
        for (index, width) in pills.widths.enumerated() {
            if index > 0 { x += spacing }
            frames.append(CGRect(x: x, y: y, width: width, height: height))
            x += width
            if index == pills.stayAfter {
                stay = CGRect(x: x + spacing, y: y, width: pills.stayWidth, height: height)
                x += spacing + pills.stayWidth
            }
        }
        return (frames, stay, x + padding)
    }

    /// Icon left edge inside the platter for the cell at `index`.
    public func iconX(_ index: Int) -> CGFloat { cellXs[index] + (cellWidth - tileSize) / 2 }

    public var iconY: CGFloat { DockMetrics.platterVerticalInset(tileSize: tileSize) }

    public var platterOrigin: CGPoint {
        CGPoint(x: DockMetrics.cartoucheMaxHalfWidth, y: DockMetrics.headroom(tileSize: tileSize))
    }

    public var canvasSize: CGSize {
        CGSize(
            width: platterSize.width + 2 * DockMetrics.cartoucheMaxHalfWidth,
            height: platterSize.height + DockMetrics.headroom(tileSize: tileSize)
        )
    }

    public var platterFrame: CGRect { CGRect(origin: platterOrigin, size: platterSize) }

    public func isOnPlatter(_ point: CGPoint) -> Bool { platterFrame.contains(point) }

    /// Like the Dock, a cell owns the full platter height.
    public func tileIndex(at point: CGPoint) -> Int? {
        guard isOnPlatter(point) else { return nil }
        let x = point.x - platterOrigin.x
        return cellXs.firstIndex { x >= $0 && x < $0 + cellWidth }
    }

    /// Pills and Stay own their x range over the full platter height too, so a click just
    /// above or below a small pill still lands on it.
    public func hit(at point: CGPoint) -> DockHit? {
        guard isOnPlatter(point) else { return nil }
        let x = point.x - platterOrigin.x
        if let stayFrame, x >= stayFrame.minX, x < stayFrame.maxX { return .stay }
        if let pill = pillFrames.firstIndex(where: { x >= $0.minX && x < $0.maxX }) { return .pill(pill) }
        return tileIndex(at: point).map(DockHit.tile)
    }
}
