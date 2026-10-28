import AppKit
import FocusDockCore

/// The "Theme" submenu: every theme with a checkmark on the current one, and Reset Theme.
/// Picking one runs the same engine as `focusdock theme set`, off the main thread; the dock
/// itself re-tints through its watch on `current/theme`.
@MainActor
final class ThemeMenu: NSObject {
    private let engine = ThemeSystem.engine()

    func item() -> NSMenuItem {
        let item = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Theme")
        menu.autoenablesItems = false
        let current = engine.current()
        for name in engine.list() {
            let entry = NSMenuItem(title: Self.title(name), action: #selector(choose(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = name
            entry.state = name == current ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let reset = NSMenuItem(title: "Reset Theme", action: #selector(resetTheme), keyEquivalent: "")
        reset.target = self
        reset.isEnabled = current != nil
        menu.addItem(reset)
        item.submenu = menu
        return item
    }

    /// "tokyo-night" -> "Tokyo Night".
    static func title(_ name: String) -> String {
        name.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let engine = engine
        Task.detached {
            do {
                let applied = try engine.set(name)
                for failure in await engine.retint(applied) { NSLog("FocusDock: retint failed: %@", failure) }
            } catch {
                NSLog("FocusDock: theme %@ failed: %@", name, String(describing: error))
            }
        }
    }

    @objc private func resetTheme() {
        let engine = engine
        Task.detached {
            do {
                for failure in try await engine.reset() { NSLog("FocusDock: reset failed: %@", failure) }
            } catch {
                NSLog("FocusDock: theme reset failed: %@", String(describing: error))
            }
        }
    }
}
