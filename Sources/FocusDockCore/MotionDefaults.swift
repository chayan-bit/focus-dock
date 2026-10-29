/// Built-in motion defaults. Spring values are the S6 fits (docs/research/spike-v2.md); the
/// Dock timings come from docs/research/rea-dock.md and docs/research/phase0.md.
enum MotionDefaults {
    /// Anything without its own default; also what `defaults.spring` overrides.
    static let spring = MotionSpec.spring(response: 0.35, damping: 0.86)
    /// The Space slide, one spring up to velocity 4.
    static let spaceSlide = MotionSpec.spring(response: 0.52, damping: 0.91)
    /// SwiftUI's `.snappy` (duration 0.5, bounce 0.15), which the pill label animated with before the engine.
    static let snappy = MotionSpec.spring(response: 0.5, damping: 0.85)

    // shortcut: no surface follows the slide yet; only the border does, since it tracks windows across Spaces. Revisit when bar and switcher land.
    static let followsSpaceSlide: Set<MotionKey> = [.borderFollow]

    static let table: [MotionKey: MotionSpec] = [
        .pillExpand: snappy,
        .countdownTick: snappy,
        .dockMagnify: .spring(response: 0.12, damping: 0.75),
        // Rise 0.30 + hold 0.10 + fall 0.30 (DockMetrics.bouncePeriod); one bounce cycle.
        .dockBounce: .timed(duration: 0.70, curve: .dockBounce),
        // shortcut: the Dock reveals with a raised cosine but the duration was never measured; 0.4 s is a guess, measure in Phase 7.
        .dockReveal: .timed(duration: 0.4, curve: .easeInOutCos),
        .workspaceSwitch: .dockSwipe(velocity: 1),
        .workspaceJump: .dockSwipe(velocity: 9999),
        .overviewOpen: .timed(duration: 0.27, curve: .easeOut),
        .overviewClose: .spring(response: 0.28, damping: 0.99),
    ]
}
