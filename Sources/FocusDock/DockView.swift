import FocusDockCore
import SwiftUI

/// Draws the dock canvas at absolute PlatterLayout positions. Input lives in DockHostingView.
struct DockView: View {
    let model: DockModel
    let actions: DockActions
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let layout = model.layout
        ZStack(alignment: .topLeading) {
            GlassEffectContainer {
                platter(layout)
            }
            .offset(x: layout.platterOrigin.x, y: layout.platterOrigin.y)
            if !reduceTransparency {
                PlatterRim(cornerRadius: DockMetrics.platterCornerRadius(tileSize: layout.tileSize))
                    .frame(width: layout.platterSize.width, height: layout.platterSize.height)
                    .offset(x: layout.platterOrigin.x, y: layout.platterOrigin.y)
            }
            if let label = hoverLabel(layout) {
                Cartouche(title: label.title, reduceTransparency: reduceTransparency)
                    .offset(
                        x: layout.platterOrigin.x + label.centreX,
                        y: layout.platterOrigin.y - DockMetrics.cartoucheGapAbovePlatter + DockMetrics.cartoucheTailHeight
                    )
            }
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height, alignment: .topLeading)
    }

    private func hoverLabel(_ layout: PlatterLayout) -> (title: String, centreX: CGFloat)? {
        if let hovered = model.hoveredTile {
            return (hovered.tile.app.name, layout.cellXs[hovered.index] + layout.cellWidth / 2)
        }
        if let pill = model.hoveredPill, layout.pillFrames.indices.contains(pill.index) {
            return (pill.mode.name, layout.pillFrames[pill.index].midX)
        }
        return nil
    }

    private func platter(_ layout: PlatterLayout) -> some View {
        ZStack(alignment: .topLeading) {
            pills(layout)
            ForEach(Array(model.tiles.enumerated()), id: \.element.id) { index, tile in
                TileView(
                    tile: tile,
                    icon: model.icon(for: tile.app),
                    size: layout.tileSize,
                    launchStart: model.launchStarts[tile.id],
                    open: { actions.open(tile) }
                )
                .offset(x: layout.iconX(index), y: layout.iconY)
            }
            ForEach([layout.pillDividerX, layout.dividerX].compactMap { $0 }, id: \.self) { dividerX in
                DockDivider(tileSize: layout.tileSize)
                    .offset(x: dividerX - DockMetrics.dividerThickness / 2, y: layout.iconY + layout.tileSize * (1 - DockMetrics.dividerHeightRatio) / 2)
            }
        }
        .frame(width: layout.platterSize.width, height: layout.platterSize.height, alignment: .topLeading)
        .modifier(PlatterMaterial(cornerRadius: DockMetrics.platterCornerRadius(tileSize: layout.tileSize), reduceTransparency: reduceTransparency))
    }
}

extension DockView {
    @ViewBuilder fileprivate func pills(_ layout: PlatterLayout) -> some View {
        let pills = model.pills
        ForEach(Array(pills.enumerated()), id: \.element.id) { index, pill in
            if layout.pillFrames.indices.contains(index) {
                let frame = layout.pillFrames[index]
                PillView(pill: pill, size: frame.size, tileSize: layout.tileSize) { actions.pill(pill.id) }
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        if let stay = layout.stayFrame {
            StayButton(size: stay.size, tileSize: layout.tileSize, stay: actions.stay)
                .offset(x: stay.minX, y: stay.minY)
        }
    }
}

/// What a click on the dock does; DockHostingView calls these from its hit-testing.
struct DockActions {
    let open: (DockTile) -> Void
    let pill: (String) -> Void
    let stay: () -> Void
}

private struct DockDivider: View {
    let tileSize: CGFloat
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(DockMetrics.dividerOpacity))
            .frame(width: DockMetrics.dividerThickness, height: tileSize * DockMetrics.dividerHeightRatio)
    }
}

/// The specular top and bottom edge of the Dock's private `.dock` glass, which public glass
/// lacks. Drawn outside the glass container, where content would be blended as vibrant.
private struct PlatterRim: View {
    let cornerRadius: CGFloat

    var body: some View {
        let rim = Color.white.opacity(DockMetrics.platterRimOpacity)
        let fade = LinearGradient(stops: [
            .init(color: rim, location: 0), .init(color: .clear, location: 0.2),
            .init(color: .clear, location: 0.8), .init(color: rim, location: 1),
        ], startPoint: .top, endPoint: .bottom)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(fade, lineWidth: DockMetrics.platterRimWidth)
            .allowsHitTesting(false)
    }
}

/// Liquid Glass, or an opaque fill with its own shadow when Reduce Transparency is on.
private struct PlatterMaterial: ViewModifier {
    let cornerRadius: CGFloat
    let reduceTransparency: Bool


    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content.background(
                shape.fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(DockMetrics.shadowOpacity), radius: DockMetrics.shadowRadius, y: DockMetrics.shadowYOffset)
            )
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}
