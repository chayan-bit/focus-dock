import FocusDockCore
import SwiftUI

/// One app tile: icon, launch bounce, running dot. Fills `size` wide and the platter height.
struct TileView: View {
    let tile: DockTile
    let icon: NSImage
    let size: CGFloat
    let launchStart: Date?
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let indicator = DockMetrics.indicator(forTileSize: size)
        ZStack(alignment: .top) {
            TimelineView(.animation(paused: launchStart == nil)) { context in
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .modifier(LaunchFeedback(elapsed: launchStart.map { context.date.timeIntervalSince($0) },
                                             tileSize: size,
                                             reduceMotion: reduceMotion))
                    .overlay(alignment: .bottomTrailing) {
                        if tile.isWebApp { WebAppBadge(tileSize: size).offset(x: size * 0.04, y: size * 0.04) }
                    }
            }
            if tile.isRunning {
                RoundedRectangle(cornerRadius: indicator.cornerRadius)
                    .fill(Color.primary.opacity(DockMetrics.indicatorOpacity))
                    .frame(width: indicator.diameter, height: indicator.diameter)
                    .offset(y: size + size * DockMetrics.indicatorCentreBelowTileRatio - indicator.diameter / 2)
            }
        }
        .frame(width: size, height: size, alignment: .top)
        .accessibilityElement()
        .accessibilityLabel(tile.app.name)
        .accessibilityValue(tile.isRunning ? "running" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, open)
    }
}

/// Bounce while launching; with Reduce Motion, a gentle fade pulse instead of movement.
private struct LaunchFeedback: ViewModifier {
    let elapsed: Double?
    let tileSize: CGFloat
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let lift = elapsed.map { DockMetrics.bounceOffset(elapsed: $0, tileSize: tileSize) } ?? 0
        if reduceMotion {
            content.opacity(1 - 0.45 * lift / (tileSize * DockMetrics.bounceApexRatio))
        } else {
            content.offset(y: -lift)
        }
    }
}
