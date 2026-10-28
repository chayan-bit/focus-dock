import AppKit
import FocusDockCore

/// The dock window, configured per docs/research/rea-dock.md "Implementation recipe".
final class DockPanel: NSPanel {
    init(contentView: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // No .fullScreenAuxiliary: like the Dock, stay out of fullscreen Spaces.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        isFloatingPanel = true
        // After isFloatingPanel, which resets the level to .floating (3); E2E caught this.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Bottom-centre of the menu-bar screen, sized to the dock canvas.
    func place(canvasSize: CGSize) {
        guard let screen = NSScreen.screens.first else { return }
        let origin = CGPoint(
            x: (screen.frame.midX - canvasSize.width / 2).rounded(),
            y: screen.frame.minY + DockMetrics.screenBottomMargin
        )
        setFrame(CGRect(origin: origin, size: canvasSize), display: true)
        orderFrontRegardless()
    }
}
