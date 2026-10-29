import AppKit
import FocusDockCore

/// The status item: the active mode's symbol and name, or the pending target's countdown, with
/// a warning badge while a config file has problems; and a menu to switch modes (through the
/// same friction as the dock), pick a theme, see capabilities, open the config, see problems
/// and warnings, and quit. Every item with a catalog action runs it through `ActionRegistry`.
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: ModeController
    private let themes: ThemeMenu
    private let capabilities: CapabilitiesMenu
    private let actions: ActionRegistry
    /// Problems in `shell.jsonc`; modes.json's come from the controller.
    private let shellProblems: () -> [ConfigProblem]

    init(controller: ModeController, themes: ThemeMenu, capabilities: CapabilitiesMenu, actions: ActionRegistry,
         shellProblems: @escaping () -> [ConfigProblem]) {
        self.controller = controller
        self.themes = themes
        self.capabilities = capabilities
        self.actions = actions
        self.shellProblems = shellProblems
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.imagePosition = .imageLeading
        update()
    }

    private var configProblems: [ConfigProblem] { controller.configProblems + shellProblems() }

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
        let symbol = Self.symbol(shown.symbol, description: shown.name)
        let hasProblems = !configProblems.isEmpty
        button.image = hasProblems ? Self.badged(symbol, description: "\(shown.name), config has problems") : symbol
        button.title = " " + title
        button.toolTip = "FocusDock: \(controller.activeMode.name)" + (hasProblems ? "\nConfig has problems; see the menu" : "")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addModes(to: menu)
        menu.addItem(.separator())
        menu.addItem(themes.item())
        menu.addItem(capabilities.item())
        menu.addItem(action("Edit modes.json", #selector(editConfig)))
        menu.addItem(action("Reveal config folder", #selector(revealConfig)))
        addNotes(to: menu)
        menu.addItem(.separator())
        let quit = action("Quit FocusDock", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func addModes(to menu: NSMenu) {
        let pending = controller.state
        for mode in controller.config.modes {
            let entry = action(mode.name, #selector(selectMode(_:)))
            entry.representedObject = mode.id
            entry.image = Self.symbol(mode.symbol, description: mode.name)
            if mode.id == controller.activeMode.id { entry.state = .on }
            if case .pending(_, let to, _) = pending, to == mode.id {
                entry.state = .mixed
                entry.title = "\(mode.name) (\(Countdown.format(seconds: controller.remainingSeconds() ?? 0)))"
            }
            menu.addItem(entry)
        }
    }

    /// Config problems (`file:line:col path: message`), then other warnings, as disabled lines.
    private func addNotes(to menu: NSMenu) {
        let problems = configProblems
        let warnings = controller.warnings
        guard !problems.isEmpty || !warnings.isEmpty else { return }
        menu.addItem(.separator())
        if !problems.isEmpty {
            let header = note("Config problems; the last good config stays in use:")
            header.image = Self.symbol(Self.badge, description: "Config problems")
            menu.addItem(header)
        }
        (problems.map(\.description) + warnings).forEach { menu.addItem(note($0)) }
    }

    private func note(_ text: String) -> NSMenuItem {
        let line = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        line.isEnabled = false
        return line
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        entry.target = self
        return entry
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        actions.performFromMenu("mode.set", id)
    }

    @objc private func editConfig() { actions.performFromMenu("config.edit") }
    @objc private func revealConfig() { actions.performFromMenu("config.reveal") }
    // app.quit goes through NSApp.terminate, so the Dock comes back as on any other quit.
    @objc private func quit() { actions.performFromMenu("app.quit") }

    private static let badge = "exclamationmark.triangle"

    private static func symbol(_ name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "circle", accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }

    /// The mode symbol with the warning triangle after it, one template image so the bar tints both.
    private static func badged(_ image: NSImage?, description: String) -> NSImage? {
        guard let warning = symbol(badge, description: description) else { return image }
        guard let image else { return warning }
        let gap: CGFloat = 3
        let size = NSSize(width: image.size.width + gap + warning.size.width, height: max(image.size.height, warning.size.height))
        let composite = NSImage(size: size, flipped: false) { _ in
            image.draw(in: NSRect(origin: NSPoint(x: 0, y: (size.height - image.size.height) / 2), size: image.size))
            warning.draw(in: NSRect(origin: NSPoint(x: image.size.width + gap, y: (size.height - warning.size.height) / 2), size: warning.size))
            return true
        }
        composite.isTemplate = true
        composite.accessibilityDescription = description
        return composite
    }
}
