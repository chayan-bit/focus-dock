import FocusDockCore
import SwiftUI

/// The hover label (phase0 section 4): a pill with a downward tail; the tail tip sits at the
/// view's offset point, horizontally centred on the hovered tile.
struct Cartouche: View {
    let title: String
    let reduceTransparency: Bool

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .overlay(alignment: .bottom) { label.fixedSize() }
            .allowsHitTesting(false)
    }

    @ViewBuilder private var label: some View {
        let text = Text(title)
            .font(.system(size: DockMetrics.cartoucheFontSize, weight: .regular))
            .lineLimit(1)
            .padding(.horizontal, DockMetrics.cartoucheHorizontalPadding)
            .frame(height: DockMetrics.cartoucheBodyHeight)
            .padding(.bottom, DockMetrics.cartoucheTailHeight)
        if reduceTransparency {
            let rgb = DockMetrics.cartoucheFallbackDarkRGB
            text.background(CartoucheShape().fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue)))
                .environment(\.colorScheme, .dark)
        } else {
            text.glassEffect(.regular, in: CartoucheShape())
        }
    }
}

struct CartoucheShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tailHeight = DockMetrics.cartoucheTailHeight
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailHeight)
        let half = DockMetrics.cartoucheTailBaseWidth / 2
        let (mid, top, tip) = (rect.midX, body.maxY - 1, rect.maxY)
        // Concave flanks and a rounded tip, like the Dock's cartouche (docs/research/phase0.md z_label).
        var tail = Path()
        tail.move(to: CGPoint(x: mid - half - 2, y: top))
        tail.addQuadCurve(to: CGPoint(x: mid - 1.5, y: tip - 0.75), control: CGPoint(x: mid - half + 1.5, y: top + 1))
        tail.addQuadCurve(to: CGPoint(x: mid + 1.5, y: tip - 0.75), control: CGPoint(x: mid, y: tip + 0.75))
        tail.addQuadCurve(to: CGPoint(x: mid + half + 2, y: top), control: CGPoint(x: mid + half - 1.5, y: top + 1))
        tail.closeSubpath()
        let pill = Path(roundedRect: body, cornerRadius: DockMetrics.cartoucheCornerRadius, style: .continuous)
        return pill.union(tail)
    }
}
