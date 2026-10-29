import FocusDockCore
import QuartzCore
import SwiftUI

extension EnvironmentValues {
    /// Resolves a motion key to its spec; set at the root of DockView, the defaults reproduce the pre-engine look.
    @Entry var motion = MotionResolver(config: MotionConfig(), systemReduceMotion: false)
}

extension MotionSpec {
    /// The SwiftUI animation for this spec; nil when something else drives the move (`dockSwipe`) or it is `instant`.
    var animation: Animation? {
        switch self {
        case .spring(let response, let damping): .spring(response: response, dampingFraction: damping)
        case .timed(let duration, let curve), .proxy(let duration, let curve): Self.timing(curve, duration: duration)
        case .crossFade(let duration): .easeInOut(duration: duration)
        case .dockSwipe, .instant: nil
        }
    }

    /// The Core Animation equivalent for `keyPath`: a mass-1 `CASpringAnimation` for springs, a timed
    /// `CABasicAnimation` otherwise; nil under the same conditions as `animation`.
    func caAnimation(keyPath: String) -> CAAnimation? {
        switch self {
        case .spring(let response, let damping):
            let spring = Spring(response: response, dampingRatio: damping)
            let animation = CASpringAnimation(keyPath: keyPath)
            animation.mass = 1
            animation.stiffness = spring.stiffness
            animation.damping = spring.damping
            animation.duration = spring.settlingDuration
            return animation
        case .timed(let duration, let curve), .proxy(let duration, let curve):
            return Self.basic(keyPath, duration: duration, function: Self.timingFunction(curve))
        case .crossFade(let duration):
            return Self.basic(keyPath, duration: duration, function: CAMediaTimingFunction(name: .easeInEaseOut))
        case .dockSwipe, .instant: return nil
        }
    }

    // shortcut: dockBounce has no cubic form and is driven by DockMetrics.bounceOffset; as a plain animation it is linear.
    private static func timing(_ curve: MotionCurve, duration: Double) -> Animation {
        guard let p = curve.controlPoints, curve != .dockBounce else { return .linear(duration: duration) }
        return .timingCurve(p.0, p.1, p.2, p.3, duration: duration)
    }

    private static func timingFunction(_ curve: MotionCurve) -> CAMediaTimingFunction {
        guard let p = curve.controlPoints else { return CAMediaTimingFunction(name: .linear) }
        return CAMediaTimingFunction(controlPoints: Float(p.0), Float(p.1), Float(p.2), Float(p.3))
    }

    private static func basic(_ keyPath: String, duration: Double, function: CAMediaTimingFunction) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.duration = duration
        animation.timingFunction = function
        return animation
    }
}

/// DockView with the motion resolver in its environment. The system Reduce Motion flag is read
/// from SwiftUI's environment, which is `NSWorkspace.accessibilityDisplayShouldReduceMotion` and
/// updates live, so no separate notification observer is needed.
struct MotionScope: View {
    let model: DockModel
    let actions: DockActions
    let config: MotionConfig
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        DockView(model: model, actions: actions)
            .environment(\.motion, MotionResolver(config: config, systemReduceMotion: systemReduceMotion))
    }
}
