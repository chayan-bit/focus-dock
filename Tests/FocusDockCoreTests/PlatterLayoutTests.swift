import CoreGraphics
import Testing
@testable import FocusDockCore

/// Absolute values are the native Dock measured at tilesize 75 (docs/research/phase0.md).
struct PlatterLayoutTests {
    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

    @Test func matchesNativeGeometryAtTile75() {
        let layout = PlatterLayout(tileCount: 3, dividerAfter: nil, tileSize: 75)
        #expect(close(layout.cellWidth, 79))
        #expect(close(layout.platterSize.height, 95))
        #expect(close(layout.platterSize.width, 2 * 8.75 + 3 * 79))
        #expect(close(layout.cellXs[0], 8.75) && close(layout.cellXs[2], 8.75 + 158))
        #expect(close(layout.iconX(0), 10.75))
        #expect(close(layout.iconY, 10))
        #expect(close(DockMetrics.platterCornerRadius(tileSize: 75), 30))
        #expect(layout.dividerX == nil)
    }

    @Test func dividerTakesA36PointSlotAfterThePinnedCells() {
        let plain = PlatterLayout(tileCount: 3, dividerAfter: nil, tileSize: 75)
        let split = PlatterLayout(tileCount: 3, dividerAfter: 2, tileSize: 75)
        #expect(close(split.platterSize.width, plain.platterSize.width + 36))
        #expect(split.cellXs[0...1] == plain.cellXs[0...1])
        #expect(close(split.cellXs[2], plain.cellXs[2] + 36))
        #expect(close(try! #require(split.dividerX), 8.75 + 2 * 79 + 18 + 1))
    }

    @Test func dividerAtTheEdgesIsIgnored() {
        #expect(PlatterLayout(tileCount: 3, dividerAfter: 0, tileSize: 64).dividerX == nil)
        #expect(PlatterLayout(tileCount: 3, dividerAfter: 3, tileSize: 64).dividerX == nil)
    }

    @Test func addingATileWidensThePlatterByOnePitch() {
        let three = PlatterLayout(tileCount: 3, dividerAfter: nil, tileSize: 75)
        let four = PlatterLayout(tileCount: 4, dividerAfter: nil, tileSize: 75)
        #expect(close(four.platterSize.width - three.platterSize.width, 79))
    }

    @Test func canvasLeavesRoomForCartoucheAndBounce() {
        let layout = PlatterLayout(tileCount: 2, dividerAfter: nil, tileSize: 75)
        let headroom = DockMetrics.headroom(tileSize: 75)
        #expect(layout.platterOrigin == CGPoint(x: DockMetrics.cartoucheMaxHalfWidth, y: headroom))
        #expect(layout.canvasSize.width == layout.platterSize.width + 2 * DockMetrics.cartoucheMaxHalfWidth)
        #expect(layout.canvasSize.height == layout.platterSize.height + headroom)
        #expect(headroom >= DockMetrics.cartoucheGapAbovePlatter + DockMetrics.cartoucheBodyHeight)
        #expect(headroom >= 20)
    }

    @Test func hitTestCoversWholeCellsAndPlatterHeight() {
        let layout = PlatterLayout(tileCount: 2, dividerAfter: nil, tileSize: 75)
        let o = layout.platterOrigin
        #expect(layout.tileIndex(at: CGPoint(x: o.x + layout.cellXs[0], y: o.y)) == 0)
        #expect(layout.tileIndex(at: CGPoint(x: o.x + layout.cellXs[1] - 0.01, y: o.y + 30)) == 0)
        #expect(layout.tileIndex(at: CGPoint(x: o.x + layout.cellXs[1], y: o.y + 94.9)) == 1)
        #expect(layout.tileIndex(at: CGPoint(x: o.x + 8, y: o.y + 30)) == nil)
    }

    @Test func hitTestMissesOutsideThePlatterAndOnTheDivider() {
        let layout = PlatterLayout(tileCount: 2, dividerAfter: 1, tileSize: 64)
        let o = layout.platterOrigin
        #expect(layout.tileIndex(at: CGPoint(x: o.x + layout.cellXs[0] + 10, y: o.y - 1)) == nil)
        #expect(layout.tileIndex(at: CGPoint(x: o.x - 1, y: o.y + 10)) == nil)
        let divider = try! #require(layout.dividerX)
        #expect(layout.tileIndex(at: CGPoint(x: o.x + divider, y: o.y + 10)) == nil)
        #expect(layout.isOnPlatter(CGPoint(x: o.x + divider, y: o.y + 10)))
        #expect(!layout.isOnPlatter(CGPoint(x: o.x + divider, y: o.y - 1)))
    }
}
