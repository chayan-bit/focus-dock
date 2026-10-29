import Foundation

/// Every animated element of the shell (SHELL-SPEC 6); the raw value is the key used in shell.jsonc.
public enum MotionKey: String, CaseIterable, Codable, Sendable {
    case dockReveal = "dock.reveal"
    case dockMagnify = "dock.magnify"
    case dockBounce = "dock.bounce"
    case pillExpand = "pill.expand"
    case countdownTick = "countdown.tick"
    case workspaceSwitch = "workspace.switch"
    case workspaceJump = "workspace.jump"
    case windowMove = "window.move"
    case windowResize = "window.resize"
    case windowTile = "window.tile"
    case borderFollow = "border.follow"
    case barReveal = "bar.reveal"
    case barWidget = "bar.widget"
    case menuOpen = "menu.open"
    case commandBarOpen = "commandBar.open"
    case switcherOpen = "switcher.open"
    case overviewOpen = "overview.open"
    case overviewClose = "overview.close"
    case cardEnter = "card.enter"
    case cardExit = "card.exit"
    case osdShow = "osd.show"
    case fleetRow = "fleet.row"
    case agentPanel = "agent.panel"
}

/// A timing curve; `dockBounce` is the gravity-style launch bounce and has no cubic form.
public enum MotionCurve: Equatable, Sendable {
    case linear, easeIn, easeOut, easeInOut, easeInOutCos, dockBounce
    case bezier(Double, Double, Double, Double)

    /// Cubic-bezier control points `(x1, y1, x2, y2)`, or nil for `dockBounce`.
    public var controlPoints: (Double, Double, Double, Double)? {
        switch self {
        case .linear: (0, 0, 1, 1)
        case .easeIn: (0.42, 0, 1, 1)
        case .easeOut: (0, 0, 0.58, 1)
        case .easeInOut: (0.42, 0, 0.58, 1)
        // The Dock's raised cosine (rea-dock.md) approximated by the sine ease-in-out cubic.
        case .easeInOutCos: (0.37, 0, 0.63, 1)
        case .dockBounce: nil
        case .bezier(let x1, let y1, let x2, let y2): (x1, y1, x2, y2)
        }
    }
}

/// How one element moves. `response` is in seconds and `damping` the damping fraction, as in
/// SwiftUI's `Animation.spring(response:dampingFraction:)`; durations are in seconds.
public enum MotionSpec: Equatable, Sendable {
    case spring(response: Double, damping: Double)
    case timed(duration: Double, curve: MotionCurve)
    /// System-driven Space slide; `velocity` is the Dock swipe velocity.
    case dockSwipe(velocity: Double)
    /// A proxy-window move, driven by FocusDock between two frames.
    case proxy(duration: Double, curve: MotionCurve)
    case crossFade(duration: Double)
    case instant
}

public enum ReduceMotion: String, Codable, Sendable { case system, always, never }

/// The `motion` block of shell.jsonc (SHELL-SPEC 7). Every field is optional in the file.
public struct MotionConfig: Codable, Equatable, Sendable {
    public var speed: Double
    public var reduceMotion: ReduceMotion
    /// Named springs: `spring` (everything without a measured default) and `spaceSlide`.
    public var defaults: [String: MotionSpec]
    public var elements: [MotionKey: MotionSpec]

    public init(speed: Double = 1, reduceMotion: ReduceMotion = .system,
                defaults: [String: MotionSpec] = [:], elements: [MotionKey: MotionSpec] = [:]) {
        self.speed = speed
        self.reduceMotion = reduceMotion
        self.defaults = defaults
        self.elements = elements
    }
}

/// Resolves an element key to the spec every surface animates with. Precedence: the element's
/// override, then the built-in default for the key, then `defaults.spring`. `speed` 0 is
/// instant, otherwise it divides durations and spring responses; Reduce Motion swaps movement
/// for a cross-fade of the same length, except the system-driven `dockSwipe`.
public struct MotionResolver: Sendable {
    public let config: MotionConfig
    /// Whether movement is replaced by cross-fades: `reduceMotion` is `always`, or `system` with the system flag on.
    public let isReduced: Bool

    public init(config: MotionConfig, systemReduceMotion: Bool) {
        self.config = config
        isReduced = switch config.reduceMotion {
        case .system: systemReduceMotion
        case .always: true
        case .never: false
        }
    }

    public func spec(_ key: MotionKey) -> MotionSpec {
        let speed = config.speed.isFinite ? max(config.speed, 0) : 1
        if speed == 0 { return .instant }
        let scaled = Self.scaled(config.elements[key] ?? builtIn(key), by: speed)
        return isReduced ? Self.reduced(scaled) : scaled
    }

    private func builtIn(_ key: MotionKey) -> MotionSpec {
        if let spec = MotionDefaults.table[key] { return spec }
        if MotionDefaults.followsSpaceSlide.contains(key) { return config.defaults["spaceSlide"] ?? MotionDefaults.spaceSlide }
        return config.defaults["spring"] ?? MotionDefaults.spring
    }

    private static func scaled(_ spec: MotionSpec, by speed: Double) -> MotionSpec {
        switch spec {
        case .spring(let response, let damping): .spring(response: response / speed, damping: damping)
        case .timed(let duration, let curve): .timed(duration: duration / speed, curve: curve)
        case .proxy(let duration, let curve): .proxy(duration: duration / speed, curve: curve)
        case .crossFade(let duration): .crossFade(duration: duration / speed)
        case .dockSwipe, .instant: spec
        }
    }

    // A spring has no duration, so its response stands in as the length of the fade.
    private static func reduced(_ spec: MotionSpec) -> MotionSpec {
        switch spec {
        case .spring(let response, _): .crossFade(duration: response)
        case .timed(let duration, _), .proxy(let duration, _): .crossFade(duration: duration)
        case .crossFade, .dockSwipe, .instant: spec
        }
    }
}

public extension MotionSpec {
    /// The length in seconds of a spec that has one (a spring reports its response).
    var duration: Double? {
        switch self {
        case .spring(let response, _): response
        case .timed(let duration, _), .proxy(let duration, _), .crossFade(let duration): duration
        case .dockSwipe, .instant: nil
        }
    }
}
