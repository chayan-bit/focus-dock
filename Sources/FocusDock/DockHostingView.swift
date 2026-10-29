import AppKit
import FocusDockCore
import SwiftUI

/// Hosts DockView and owns all mouse input. Hover uses an `.activeAlways` tracking area
/// because the panel is never key, and hit-testing uses the same PlatterLayout the view draws.
final class DockHostingView: NSHostingView<MotionScope> {
    private let model: DockModel
    private let actions: DockActions
    private var pressedHit: DockHit?
    private var trackingArea: NSTrackingArea?

    init(model: DockModel, actions: DockActions, motion: MotionConfig = MotionConfig()) {
        self.model = model
        self.actions = actions
        super.init(rootView: MotionScope(model: model, actions: actions, config: motion))
        sizingOptions = []
    }

    /// Applies a reloaded `shell.jsonc` motion block live; view state (running bounces) survives.
    func setMotion(_ motion: MotionConfig) {
        rootView = MotionScope(model: model, actions: actions, config: motion)
    }

    @available(*, unavailable)
    required init(rootView: MotionScope) { fatalError("use init(model:actions:motion:)") }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("use init(model:actions:motion:)") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: viewRect(model.layout.platterFrame),
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) { updateHover(event) }
    override func mouseEntered(with event: NSEvent) { updateHover(event) }
    override func mouseExited(with event: NSEvent) { model.setHovered(nil) }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { return rightMouseDown(with: event) }
        pressedHit = model.layout.hit(at: canvasPoint(event))
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedHit = nil }
        guard let hit = model.layout.hit(at: canvasPoint(event)), hit == pressedHit else { return }
        switch hit {
        case .tile(let index): actions.open(model.tiles[index])
        case .pill(let index): actions.pill(model.pills[index].id)
        case .stay: actions.stay()
        }
    }

    /// Right-click on empty platter space offers Quit, like the menu bar item.
    override func rightMouseDown(with event: NSEvent) {
        let point = canvasPoint(event)
        guard model.layout.isOnPlatter(point), model.layout.hit(at: point) == nil else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit FocusDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func updateHover(_ event: NSEvent) {
        let hovered: String? = switch model.layout.hit(at: canvasPoint(event)) {
        case .tile(let index): model.tiles[index].id
        case .pill(let index): "mode:\(model.pills[index].id)"
        case .stay, nil: nil
        }
        model.setHovered(hovered)
    }

    /// Event location in PlatterLayout's top-left coordinates.
    private func canvasPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y)
    }

    private func viewRect(_ rect: CGRect) -> CGRect {
        isFlipped ? rect : CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }
}
