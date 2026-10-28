import AppKit
import FocusDockCore
import SwiftUI

/// Hosts DockView and owns all mouse input. Hover uses an `.activeAlways` tracking area
/// because the panel is never key, and hit-testing uses the same PlatterLayout the view draws.
final class DockHostingView: NSHostingView<DockView> {
    private let model: DockModel
    private let onOpen: (DockTile) -> Void
    private var pressedIndex: Int?
    private var trackingArea: NSTrackingArea?

    init(model: DockModel, onOpen: @escaping (DockTile) -> Void) {
        self.model = model
        self.onOpen = onOpen
        super.init(rootView: DockView(model: model, onOpen: onOpen))
        sizingOptions = []
    }

    @available(*, unavailable)
    required init(rootView: DockView) { fatalError("use init(model:onOpen:)") }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("use init(model:onOpen:)") }

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
        pressedIndex = model.layout.tileIndex(at: canvasPoint(event))
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedIndex = nil }
        guard let index = model.layout.tileIndex(at: canvasPoint(event)), index == pressedIndex else { return }
        onOpen(model.tiles[index])
    }

    /// Hidden quit until the Phase 2 menu bar item exists: right-click empty platter space.
    override func rightMouseDown(with event: NSEvent) {
        let point = canvasPoint(event)
        guard model.layout.isOnPlatter(point), model.layout.tileIndex(at: point) == nil else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit FocusDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func updateHover(_ event: NSEvent) {
        let layout = model.layout
        model.setHovered(layout.tileIndex(at: canvasPoint(event)).map { model.tiles[$0].id })
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
