import CoreGraphics

/// Absolute geometry of the dock canvas. Both the SwiftUI drawing and the mouse hit-testing
/// read it, so what is drawn and what is clickable cannot drift apart.
/// Coordinates are top-left origin, in points; `cellXs` and `dividerX` are platter-relative.
/// Model (phase0): abutting cells of tile + 4 pt with the icon centred, an inset to the platter
/// edge, and a divider slot between the pinned and the running-only cells.
public struct PlatterLayout: Equatable, Sendable {
    public let tileSize: CGFloat
    public let cellWidth: CGFloat
    public let platterSize: CGSize
    public let cellXs: [CGFloat]
    /// Centre x of the divider line, when there are cells on both sides of it.
    public let dividerX: CGFloat?

    public init(tileCount: Int, dividerAfter: Int?, tileSize: CGFloat) {
        let m = DockMetrics.self
        let split = dividerAfter.flatMap { (1..<max(tileCount, 1)).contains($0) ? $0 : nil }
        let cell = m.cellWidth(tileSize: tileSize)
        let inset = m.platterHorizontalInset(tileSize: tileSize)
        let slot = split == nil ? 0 : m.dividerSlot(tileSize: tileSize)
        self.tileSize = tileSize
        self.cellWidth = cell
        self.cellXs = (0..<tileCount).map { index in
            inset + CGFloat(index) * cell + (split.map { index >= $0 ? slot : 0 } ?? 0)
        }
        let lineOffset = tileSize * m.dividerLineOffsetRatio
        self.dividerX = split.map { inset + CGFloat($0) * cell + slot / 2 + lineOffset }
        self.platterSize = CGSize(
            width: 2 * inset + CGFloat(tileCount) * cell + slot,
            height: tileSize + 2 * m.platterVerticalInset(tileSize: tileSize)
        )
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
}
