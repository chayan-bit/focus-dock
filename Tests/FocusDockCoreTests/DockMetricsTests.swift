import Testing
@testable import FocusDockCore

struct DockMetricsTests {
    @Test func usesUserTileSizeWhenValid() {
        #expect(DockMetrics.tileSize(preference: 75, mainDisplayHeight: 1117) == 75)
    }

    @Test func defaultsTo64WhenPreferenceMissing() {
        #expect(DockMetrics.tileSize(preference: nil, mainDisplayHeight: 1117) == 64)
    }

    @Test func defaultsTo52OnDisplaysAtMost800PointsTall() {
        #expect(DockMetrics.tileSize(preference: nil, mainDisplayHeight: 800) == 52)
        #expect(DockMetrics.tileSize(preference: nil, mainDisplayHeight: 801) == 64)
    }

    @Test(arguments: [0.0, -5, 257, 1000])
    func rejectsOutOfRangePreference(value: Double) {
        #expect(DockMetrics.tileSize(preference: value, mainDisplayHeight: 1117) == 64)
    }

    @Test func acceptsBoundaryJustInsideRange() {
        #expect(DockMetrics.tileSize(preference: 256, mainDisplayHeight: 1117) == 256)
        #expect(DockMetrics.tileSize(preference: 0.5, mainDisplayHeight: 1117) == 0.5)
    }

    @Test func indicatorIsSmallBelow33PointTiles() {
        let small = DockMetrics.indicator(forTileSize: 32.9)
        #expect(small.diameter == 3)
        #expect(small.cornerRadius == 1.5)
    }

    @Test func indicatorIsRegularFrom33PointTiles() {
        let regular = DockMetrics.indicator(forTileSize: 33)
        #expect(regular.diameter == 4)
        #expect(regular.cornerRadius == 2)
    }

    @Test func indicatorCentreSits4PointsBelowA75PointIcon() {
        #expect(abs(75 * DockMetrics.indicatorCentreBelowTileRatio - 4) < 0.001)
    }

    @Test func bounceStartsAtRestAndPeaksAt20PointsFor75PointTiles() {
        #expect(DockMetrics.bounceOffset(elapsed: 0, tileSize: 75) == 0)
        let apex = DockMetrics.bounceOffset(elapsed: DockMetrics.bounceRiseSeconds + 0.05, tileSize: 75)
        #expect(abs(apex - 20) < 0.001)
    }

    @Test func bounceFallAcceleratesAndCycleRepeats() {
        let fallStart = DockMetrics.bounceRiseSeconds + DockMetrics.bounceHoldSeconds
        let early = 20 - DockMetrics.bounceOffset(elapsed: fallStart + 0.1, tileSize: 75)
        let late = DockMetrics.bounceOffset(elapsed: fallStart + 0.1, tileSize: 75)
            - DockMetrics.bounceOffset(elapsed: fallStart + 0.2, tileSize: 75)
        #expect(late > early)
        #expect(DockMetrics.bounceOffset(elapsed: DockMetrics.bouncePeriod, tileSize: 75) < 0.001)
        #expect(abs(DockMetrics.bounceOffset(elapsed: DockMetrics.bouncePeriod + 0.1, tileSize: 75)
            - DockMetrics.bounceOffset(elapsed: 0.1, tileSize: 75)) < 0.001)
    }

    @Test func finishedLaunchLandsTheCurrentBounce() {
        #expect(DockMetrics.bounceTimeToRest(elapsed: 0) == 0)
        let mid = DockMetrics.bouncePeriod / 2
        #expect(abs(DockMetrics.bounceTimeToRest(elapsed: mid) - mid) < 0.001)
        let landed = DockMetrics.bounceOffset(elapsed: 0.42 + DockMetrics.bounceTimeToRest(elapsed: 0.42), tileSize: 75)
        #expect(landed < 0.001)
    }

    @Test func bounceNeverLeavesTheHeadroom() {
        let samples = stride(from: 0.0, through: 2.0, by: 0.01).map { DockMetrics.bounceOffset(elapsed: $0, tileSize: 75) }
        #expect(samples.allSatisfy { $0 >= 0 && $0 <= 20.001 })
        #expect(DockMetrics.headroom(tileSize: 75) >= 20)
    }

    @Test func bounceTimeScaleStretchesTheWholeCycle() {
        for t in stride(from: 0.0, through: 1.4, by: 0.07) {
            let stretched = DockMetrics.bounceOffset(elapsed: t * 2, tileSize: 75, timeScale: 2)
            #expect(abs(stretched - DockMetrics.bounceOffset(elapsed: t, tileSize: 75)) < 0.001)
        }
        let mid = DockMetrics.bouncePeriod
        #expect(abs(DockMetrics.bounceTimeToRest(elapsed: 0.42 * 2, timeScale: 2) - 2 * DockMetrics.bounceTimeToRest(elapsed: 0.42)) < 0.001)
        #expect(DockMetrics.bounceTimeToRest(elapsed: mid * 0.5 * 3, timeScale: 3) > 0)
    }

    @Test func bounceTimeScaleFollowsTheResolvedSpec() {
        #expect(DockMetrics.bounceTimeScale(.timed(duration: 0.70, curve: .dockBounce)) == 1)
        #expect(abs(DockMetrics.bounceTimeScale(.timed(duration: 1.4, curve: .dockBounce))! - 2) < 1e-9)
        #expect(abs(DockMetrics.bounceTimeScale(.crossFade(duration: 0.35))! - 0.5) < 1e-9)
        #expect(DockMetrics.bounceTimeScale(.instant) == nil)
        #expect(DockMetrics.bounceTimeScale(.dockSwipe(velocity: 1)) == nil)
        #expect(DockMetrics.bounceTimeScale(.timed(duration: 0, curve: .linear)) == nil)
    }
}
