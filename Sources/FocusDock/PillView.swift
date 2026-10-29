import FocusDockCore
import SwiftUI

/// A mode pill: a filled capsule in the mode's colour with symbol and label when active or
/// counting down, otherwise a small circle with just the symbol.
struct PillView: View {
    let pill: PillItem
    let size: CGSize
    let tileSize: CGFloat
    let press: () -> Void
    @Environment(\.motion) private var motion
    @Environment(\.shellTheme) private var theme

    var body: some View {
        let isExpanded = pill.label != nil
        HStack(spacing: tileSize * DockMetrics.pillSymbolLabelGapRatio) {
            Image(systemName: pill.mode.symbol)
                .font(.system(size: DockMetrics.pillSymbolSize(tileSize: tileSize), weight: .semibold))
                .frame(width: isExpanded ? tileSize * DockMetrics.pillSymbolBoxRatio : nil)
            if let label = pill.label {
                Text(label)
                    .font(Font(DockModel.pillFont(tileSize: tileSize)))
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(motion.isReduced ? .identity : .numericText(countsDown: true))
                    .animation(motion.isReduced ? nil : motion.spec(pill.isCountdown ? .countdownTick : .pillExpand).animation, value: label)
            }
        }
        .foregroundStyle(isExpanded ? AnyShapeStyle(.white) : AnyShapeStyle(Color.themed(theme?.text, or: .primary).opacity(0.85)))
        .frame(width: size.width, height: size.height)
        .background(Capsule().fill(isExpanded ? AnyShapeStyle(color) : AnyShapeStyle(collapsedFill)))
        .accessibilityElement()
        .accessibilityLabel(pill.mode.name)
        .accessibilityValue(pill.isCountdown ? (pill.label ?? "") : (isExpanded ? "active" : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, press)
    }

    /// A theme's collapsed pills carry its accent; without one they stay neutral.
    private var collapsedFill: Color {
        guard let accent = theme?.accent else { return Color.primary.opacity(DockMetrics.pillCollapsedFillOpacity) }
        return Color(accent).opacity(DockMetrics.themedPillFillOpacity)
    }

    private var color: Color {
        let rgb = RGB(hex: pill.mode.color) ?? RGB(hex: "#808080")!
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// The white "Stay" capsule next to the countdown pill.
struct StayButton: View {
    let size: CGSize
    let tileSize: CGFloat
    let stay: () -> Void

    var body: some View {
        Text(DockModel.stayLabel)
            .font(Font(DockModel.pillFont(tileSize: tileSize)))
            .foregroundStyle(.black)
            .frame(width: size.width, height: size.height)
            .background(Capsule().fill(.white))
            .accessibilityElement()
            .accessibilityLabel(DockModel.stayLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, stay)
    }
}

/// The small globe drawn at the bottom-right of a web app tile.
struct WebAppBadge: View {
    let tileSize: CGFloat

    var body: some View {
        let diameter = (tileSize * 0.34).rounded()
        Image(systemName: "globe")
            .font(.system(size: diameter * 0.62, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Color(red: 0.16, green: 0.47, blue: 0.96)))
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
    }
}
