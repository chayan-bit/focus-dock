import AppKit
import FocusDockCore

/// The handlers behind `ActionCatalog`, each wrapping the call the menu makes today.
enum AppActions {
    @MainActor
    static func register(
        in registry: ActionRegistry, controller: ModeController, permissions: PermissionMonitor,
        engine: ThemeEngine = ThemeSystem.engine()
    ) {
        registry.register("mode.set") { arguments in
            guard controller.config.mode(arguments[0]) != nil else { throw ActionFailure.failed("no mode named \"\(arguments[0])\"") }
            controller.request(arguments[0])
        }
        registry.register("mode.stay") { _ in controller.stay() }
        registry.register("theme.set") { arguments in try await setTheme(engine, arguments[0]) }
        registry.register("theme.next") { _ in try await setTheme(engine, neighbour(engine, offset: 1)) }
        registry.register("theme.prev") { _ in try await setTheme(engine, neighbour(engine, offset: -1)) }
        registry.register("theme.reset") { _ in try await resetTheme(engine) }
        registry.register("config.edit") { _ in NSWorkspace.shared.open(ConfigFiles.modes) }
        registry.register("config.reveal") { _ in NSWorkspace.shared.activateFileViewerSelecting([ConfigFiles.modes]) }
        registry.register("permission.grant") { arguments in
            guard let permission = Permission(rawValue: arguments[0]) else {
                let known = Permission.allCases.map(\.rawValue).joined(separator: ", ")
                throw ActionFailure.failed("unknown permission \"\(arguments[0])\"; one of \(known)")
            }
            permissions.request(permission)
        }
        // Same path as the menu's Quit: applicationWillTerminate restores the Dock.
        registry.register("app.quit") { _ in NSApp.terminate(nil) }
    }

    private static func neighbour(_ engine: ThemeEngine, offset: Int) throws -> String {
        guard let name = engine.neighbour(offset: offset) else { throw ActionFailure.failed("no themes installed") }
        return name
    }

    /// Off the main thread, like the theme menu; a failed retint leaves one app behind but the switch stands.
    private static func setTheme(_ engine: ThemeEngine, _ name: String) async throws {
        try await Task.detached {
            let applied = try await engine.set(name)
            for failure in await engine.retint(applied) { NSLog("FocusDock: retint failed: %@", failure) }
        }.value
    }

    private static func resetTheme(_ engine: ThemeEngine) async throws {
        try await Task.detached {
            for failure in try await engine.reset() { NSLog("FocusDock: reset failed: %@", failure) }
        }.value
    }
}
