import AppKit
import FocusDockCore

/// `FocusDock theme list|current|set <name>|reset|next|prev`. The running dock picks every
/// change up through its watch on `current/theme`, so the CLI never talks to it.
enum ThemeCLI {
    static let usage = """
    usage: focusdock theme list | current | set <name> | reset | next | prev
    """

    /// Runs the command on a task and exits with its status; the main run loop stays free
    /// for the wallpaper target, which must call NSWorkspace on the main thread.
    static func runAndExit(_ arguments: [String]) -> Never {
        Task { @MainActor in
            let status = await run(arguments)
            exit(status)
        }
        dispatchMain()
    }

    static func run(_ arguments: [String]) async -> Int32 {
        let engine = ThemeSystem.engine()
        switch (arguments.first, arguments.count) {
        case ("list", 1):
            let current = engine.current()
            engine.list().forEach { print($0 == current ? "* \($0)" : "  \($0)") }
            return 0
        case ("current", 1):
            guard let current = engine.current() else { return fail("no theme set") }
            print(current)
            return 0
        case ("set", 2):
            return await set(engine, arguments[1])
        case ("next", 1), ("prev", 1):
            guard let name = engine.neighbour(offset: arguments[0] == "next" ? 1 : -1) else { return fail("no themes installed") }
            return await set(engine, name)
        case ("reset", 1):
            do {
                let failures = try await engine.reset()
                report(failures)
                print("theme reset")
                return 0
            } catch {
                return fail(error.description)
            }
        default:
            return fail(usage)
        }
    }

    private static func set(_ engine: ThemeEngine, _ name: String) async -> Int32 {
        let applied: AppliedTheme
        do {
            applied = try await engine.set(name)
        } catch {
            return fail(error.description)
        }
        if !applied.ignored.isEmpty {
            warn("ignored in \(engine.paths.userThemes.appending(path: applied.name).path): \(applied.ignored.joined(separator: " "))")
            warn("a theme cloned from git cannot supply Lua, a terminal config or vscode.json")
        }
        // A failed retint leaves one app behind but the switch stands, as in Omarchy.
        report(await engine.retint(applied))
        print("theme: \(applied.name)")
        return 0
    }

    private static func report(_ failures: [String]) {
        failures.forEach { warn("retint failed: \($0)") }
    }

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("focusdock: \(message)\n".utf8))
    }

    private static func fail(_ message: String) -> Int32 {
        warn(message)
        return 1
    }
}
