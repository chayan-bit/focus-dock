import AppKit
import FocusDockCore

/// The status item: the active mode's symbol and name, or the pending target's countdown,
/// and a menu to switch modes (through the same friction as the dock), open the config,
/// see warnings and quit.
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: ModeController

    init(controller: ModeController) {
        self.controller = controller
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.imagePosition = .imageLeading
        update()
    }

    func update() {
        guard let button = item.button else { return }
        let modes = controller.config
        let shown: Mode
        let title: String
        if case .pending(_, let to, _) = controller.state, let target = modes.mode(to) {
            shown = target
            title = "\(target.name) \(Countdown.format(seconds: controller.remainingSeconds() ?? 0))"
        } else {
            shown = controller.activeMode
            title = shown.name
        }
        button.image = Self.symbol(shown.symbol, description: shown.name)
        button.title = " " + title
        button.toolTip = "FocusDock: \(controller.activeMode.name)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let pending = controller.state
        for mode in controller.config.modes {
            let entry = NSMenuItem(title: mode.name, action: #selector(selectMode(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = mode.id
            entry.image = Self.symbol(mode.symbol, description: mode.name)
            if mode.id == controller.activeMode.id { entry.state = .on }
            if case .pending(_, let to, _) = pending, to == mode.id {
                entry.state = .mixed
                entry.title = "\(mode.name) (\(Countdown.format(seconds: controller.remainingSeconds() ?? 0)))"
            }
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(action("Edit modes.json", #selector(editConfig)))
        menu.addItem(action("Reveal config folder", #selector(revealConfig)))
        let warnings = controller.warnings
        if !warnings.isEmpty {
            menu.addItem(.separator())
            for warning in warnings {
                let line = NSMenuItem(title: warning, action: nil, keyEquivalent: "")
                line.isEnabled = false
                menu.addItem(line)
            }
        }
        menu.addItem(.separator())
        // Same path as the dock's right-click Quit: applicationWillTerminate restores the Dock.
        menu.addItem(withTitle: "Quit FocusDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        entry.target = self
        return entry
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        controller.request(id)
    }

    @objc private func editConfig() {
        NSWorkspace.shared.open(ConfigStore.file)
    }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.file])
    }

    private static func symbol(_ name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "circle", accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }
}
