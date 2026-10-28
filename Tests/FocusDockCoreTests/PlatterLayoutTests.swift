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

/// Mode pills (Phase 2): geometry and hit-testing of pills, the countdown pill and Stay.
struct PillLayoutTests {
    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
    private let tile: CGFloat = 75
    private var pillHeight: CGFloat { DockMetrics.pillHeight(tileSize: tile) }
    private var spacing: CGFloat { DockMetrics.pillSpacing(tileSize: tile) }

    @Test func pillsSitWhereAnIconWouldStartCentredOnTheIconRow() {
        let layout = PlatterLayout(tileCount: 2, dividerAfter: nil, tileSize: tile, pills: PillRow(widths: [120, 44, 44]))
        #expect(layout.pillFrames.count == 3)
        #expect(close(layout.pillFrames[0].minX, 10.75))
        #expect(close(layout.pillFrames[0].midY, layout.iconY + tile / 2))
        #expect(close(layout.pillFrames[0].height, pillHeight))
        #expect(close(layout.pillFrames[1].minX, layout.pillFrames[0].maxX + spacing))
        #expect(close(layout.pillFrames[2].width, 44))
    }

    @Test func pillsTakeADividerSlotBeforeTheTiles() {
        let plain = PlatterLayout(tileCount: 2, dividerAfter: nil, tileSize: tile)
        let pills = PlatterLayout(tileCount: 2, dividerAfter: nil, tileSize: tile, pills: PillRow(widths: [44, 44]))
        let pillsEnd = 8.75 + 2 + 44 + spacing + 44 + 2
        #expect(close(pills.cellXs[0], pillsEnd + 36))
        #expect(close(pills.platterSize.width, plain.platterSize.width + pillsEnd - 8.75 + 36))
        #expect(close(try! #require(pills.pillDividerX), pillsEnd + 18 + 1))
        #expect(pills.dividerX == nil)
    }

    @Test func pillsWithoutTilesHaveNoDivider() {
        let layout = PlatterLayout(tileCount: 0, dividerAfter: nil, tileSize: tile, pills: PillRow(widths: [44]))
        #expect(layout.pillDividerX == nil)
        #expect(close(layout.platterSize.width, 8.75 + 2 + 44 + 2 + 8.75))
    }

    @Test func stayFollowsTheCountdownPillAndPushesTheRest() {
        let row = PillRow(widths: [120, 140, 44], stayAfter: 1, stayWidth: 60)
        let layout = PlatterLayout(tileCount: 1, dividerAfter: nil, tileSize: tile, pills: row)
        let stay = try! #require(layout.stayFrame)
        #expect(close(stay.minX, layout.pillFrames[1].maxX + spacing))
        #expect(close(stay.width, 60) && close(stay.minY, layout.pillFrames[1].minY))
        #expect(close(layout.pillFrames[2].minX, stay.maxX + spacing))
    }

    @Test func stayAfterAMissingPillIsDropped() {
        #expect(PillRow(widths: [44], stayAfter: 3, stayWidth: 60).stayAfter == nil)
        #expect(PlatterLayout(tileCount: 1, dividerAfter: nil, tileSize: tile, pills: PillRow(widths: [44], stayAfter: 3)).stayFrame == nil)
    }

    @Test func hitTestFindsPillsStayAndTilesOverTheFullHeight() {
        let row = PillRow(widths: [120, 140], stayAfter: 1, stayWidth: 60)
        let layout = PlatterLayout(tileCount: 2, dividerAfter: nil, tileSize: tile, pills: row)
        let o = layout.platterOrigin
        func hit(_ x: CGFloat, _ y: CGFloat = 2) -> DockHit? { layout.hit(at: CGPoint(x: o.x + x, y: o.y + y)) }
        #expect(hit(layout.pillFrames[0].midX) == .pill(0))
        #expect(hit(layout.pillFrames[1].minX, 94) == .pill(1))
        #expect(hit(layout.stayFrame!.midX) == .stay)
        #expect(hit(layout.cellXs[1] + 1) == .tile(1))
        #expect(hit(layout.pillFrames[0].maxX + spacing / 2) == nil)
        #expect(hit(layout.pillDividerX!) == nil)
        #expect(hit(2) == nil)
        #expect(layout.hit(at: CGPoint(x: o.x + layout.pillFrames[0].midX, y: o.y - 1)) == nil)
    }

    @Test func expandedPillsAreSymbolPlusLabelPadded() {
        let width = DockMetrics.expandedPillWidth(labelWidth: 50, tileSize: 75)
        #expect(close(width, (75 * (2 * 13.0 / 75 + 22.0 / 75 + 6.0 / 75) + 50).rounded(.up)))
        #expect(DockMetrics.stayWidth(labelWidth: 30, tileSize: 75) == 56)
        #expect(DockMetrics.pillHeight(tileSize: 75) == 44)
    }
}
