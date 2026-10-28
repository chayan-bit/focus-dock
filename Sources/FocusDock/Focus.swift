import Foundation
import FocusDockCore

/// Turns macOS Focus modes on and off by running the user's "FocusDock <focus>" and
/// "FocusDock Off" shortcuts (README, "Focus modes"). Shortcuts that do not exist are
/// reported, never run.
@MainActor
final class FocusSwitcher {
    private static let shortcuts = URL(fileURLWithPath: "/usr/bin/shortcuts")
    private static let listTimeout = 15.0
    private static let runTimeout = 30.0

    private(set) var available: Set<String> = []
    /// Menu warnings: missing shortcuts, or why the list could not be read.
    private(set) var warnings: [String] = []

    /// Re-reads the shortcut list; called once per config load.
    func refresh(for config: ModesConfig) async {
        do {
            let result = try await ProcessRunner.run(Self.shortcuts, ["list"], timeout: Self.listTimeout)
            guard result.succeeded else {
                warnings = ["Shortcuts: `shortcuts list` failed (exit \(result.status))"]
                return
            }
            available = FocusShortcuts.parseList(result.output)
            warnings = FocusShortcuts.missing(in: config, available: available).map { "Shortcut \"\($0)\" not found" }
        } catch {
            warnings = ["Shortcuts: \(error)"]
        }
    }

    func apply(_ mode: Mode) async {
        guard let name = FocusShortcuts.shortcut(for: mode, available: available) else { return }
        do {
            let result = try await ProcessRunner.run(Self.shortcuts, ["run", name], timeout: Self.runTimeout)
            if !result.succeeded { NSLog("FocusDock: shortcut %@ failed with exit %d", name, result.status) }
        } catch {
            NSLog("FocusDock: shortcut %@ failed: %@", name, String(describing: error))
        }
    }
}
