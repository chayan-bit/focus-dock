import Foundation
import Testing
@testable import FocusDockCore

struct ThemeTargetsTests {
    private func targets(_ box: Sandbox, reloads: Counter = Counter()) -> [any ThemeTarget] {
        let home = box.paths.home
        let originals = Originals(directory: box.paths.originals)
        return [
            JSONSettingTarget(name: "zed", settings: home.appending(path: ".config/zed/settings.json"), key: "theme",
                              value: "\"FocusDock\"", source: "claude.json",
                              destination: home.appending(path: ".config/zed/themes/focusdock.json"), originals: originals),
            JSONSettingTarget(name: "claude", settings: home.appending(path: ".claude/settings.json"), key: "theme",
                              value: "\"custom:focusdock\"", source: "claude.json",
                              destination: home.appending(path: ".claude/themes/focusdock.json"), originals: originals),
            BtopTarget(home: home, currentTheme: box.paths.currentTheme, originals: originals) { reloads.increment() },
        ]
    }

    @Test func setThenResetRestoresEverySettingsFileByteForByte() async throws {
        let box = try Sandbox()
        try box.write("home/.config/zed/settings.json", SettingsTextTests.zed)
        try box.write("home/.claude/settings.json", SettingsTextTests.claude)
        try box.write("home/.config/btop/btop.conf", SettingsTextTests.btop)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: box.root.appending(path: "home/.claude/settings.json").path)
        let reloads = Counter()
        let engine = ThemeEngine(paths: box.paths, targets: targets(box, reloads: reloads))

        #expect(await engine.retint(try engine.set("dusk")).isEmpty)
        #expect(await engine.retint(try engine.set("paper")).isEmpty)
        let home = box.paths.home
        let zed = try #require(box.read(home.appending(path: ".config/zed/settings.json")))
        #expect(try JSONKey.value("theme", in: zed) == "\"FocusDock\"")
        #expect(zed.contains("\"ui_font_size\": 16, /* inline */"))
        #expect(box.read(home.appending(path: ".claude/themes/focusdock.json")) == "{ \"base\": \"light\" }\n")
        let claude = try #require(box.read(home.appending(path: ".claude/settings.json")))
        #expect(claude == SettingsTextTests.claude.replacingOccurrences(of: "\"auto\"", with: "\"custom:focusdock\""))
        #expect(ConfLine.line("color_theme", in: box.read(home.appending(path: ".config/btop/btop.conf")) ?? "") == BtopTarget.line)
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: home.appending(path: ".config/btop/themes/focusdock.theme").path)
        #expect(link == box.paths.currentTheme.appending(path: "btop.theme").path)

        #expect(try await engine.reset().isEmpty)
        #expect(box.read(home.appending(path: ".config/zed/settings.json")) == SettingsTextTests.zed)
        #expect(box.read(home.appending(path: ".claude/settings.json")) == SettingsTextTests.claude)
        #expect(box.read(home.appending(path: ".config/btop/btop.conf")) == SettingsTextTests.btop)
        let permissions = try FileManager.default.attributesOfItem(atPath: home.appending(path: ".claude/settings.json").path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        #expect(!box.exists(home.appending(path: ".claude/themes")))
        #expect(!box.exists(home.appending(path: ".config/btop/themes")))
        #expect(!box.exists(home.appending(path: ".config/zed/themes/focusdock.json")))
        #expect(reloads.value == 3)
    }

    @Test func resetRemovesKeysAndFilesThatWereAbsent() async throws {
        let box = try Sandbox()
        try box.write("home/.claude/settings.json", "{\n  \"model\": \"opus\"\n}\n")
        let engine = ThemeEngine(paths: box.paths, targets: targets(box))
        #expect(await engine.retint(try engine.set("dusk")).isEmpty)
        let home = box.paths.home
        #expect(box.exists(home.appending(path: ".config/btop/btop.conf")))
        #expect(try await engine.reset().isEmpty)
        #expect(box.read(home.appending(path: ".claude/settings.json")) == "{\n  \"model\": \"opus\"\n}\n")
        #expect(!box.exists(home.appending(path: ".config/btop")))
        #expect(!box.exists(home.appending(path: ".config/zed")))
    }

    @Test func resetLeavesAValueTheUserChangedSince() async throws {
        let box = try Sandbox()
        try box.write("home/.claude/settings.json", SettingsTextTests.claude)
        let engine = ThemeEngine(paths: box.paths, targets: targets(box))
        #expect(await engine.retint(try engine.set("dusk")).isEmpty)
        let file = box.paths.home.appending(path: ".claude/settings.json")
        try TextFile.write(try JSONKey.setting("theme", to: "\"light\"", in: box.read(file) ?? ""), to: file)
        #expect(try await engine.reset().isEmpty)
        #expect(try JSONKey.value("theme", in: box.read(file) ?? "") == "\"light\"")
    }

    @Test func theOriginalIsSavedOnlyOnce() async throws {
        let box = try Sandbox()
        try box.write("home/.claude/settings.json", SettingsTextTests.claude)
        let engine = ThemeEngine(paths: box.paths, targets: targets(box))
        #expect(await engine.retint(try engine.set("dusk")).isEmpty)
        #expect(await engine.retint(try engine.set("dusk")).isEmpty)
        let saved = Originals(directory: box.paths.originals).load("claude", as: SavedSetting.self)
        #expect(saved?.raw == "\"auto\"")
    }

    @Test func backgroundsAreRememberedAndCycledLikeOmarchy() throws {
        let candidates = ["/b/1.jpg", "/b/2.jpg", "/b/3.jpg"]
        #expect(ThemeRules.chooseBackground(candidates: candidates, sameTheme: false, current: nil, remembered: nil) == "/b/1.jpg")
        #expect(ThemeRules.chooseBackground(candidates: candidates, sameTheme: false, current: "/x", remembered: "/b/2.jpg") == "/b/2.jpg")
        #expect(ThemeRules.chooseBackground(candidates: candidates, sameTheme: false, current: nil, remembered: "/gone.jpg") == "/b/1.jpg")
        #expect(ThemeRules.chooseBackground(candidates: candidates, sameTheme: true, current: "/b/3.jpg", remembered: nil) == "/b/1.jpg")
        #expect(ThemeRules.chooseBackground(candidates: [], sameTheme: false, current: nil, remembered: nil) == nil)
    }

    @Test func engineLinksTheBackgroundFromDurableDirectories() throws {
        let box = try Sandbox()
        try box.write("home/.local/share/focusdock/themes/dusk/backgrounds/b.webp", "x")
        try box.write("home/.local/share/focusdock/themes/dusk/backgrounds/a.jpg", "x")
        try box.write("home/.local/share/focusdock/themes/dusk/backgrounds/intro.mp4", "x")
        let engine = ThemeEngine(paths: box.paths, targets: [])
        let first = try engine.set("dusk")
        #expect(first.background?.lastPathComponent == "a.jpg")
        let again = try engine.set("dusk")
        #expect(again.background?.lastPathComponent == "b.webp")
        _ = try engine.set("paper")
        #expect(!box.exists(box.paths.background))
        let back = try engine.set("dusk")
        #expect(back.background?.lastPathComponent == "b.webp")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: box.paths.background.path) == back.background?.path)
    }

    @Test func templatePlanFollowsOmarchysPrecedence() {
        let plan = ThemeRules.templatePlan(user: ["zed.json.tpl", "extra.conf.tpl"], shipped: ["zed.json.tpl", "btop.theme.tpl", "neovim.lua.tpl"], existing: ["neovim.lua"])
        let described = plan.map { "\($0.output):\($0.isUser ? "user" : "shipped")" }
        #expect(described == ["extra.conf:user", "zed.json:user", "btop.theme:shipped"])
    }

    @Test func gitSafetyRuleCoversLuaAndTerminalConfigs() {
        #expect(ThemeRules.isDeniedFromGit("wezterm.lua"))
        #expect(ThemeRules.isDeniedFromGit("kitty.conf"))
        #expect(ThemeRules.isDeniedFromGit("vscode.json"))
        #expect(!ThemeRules.isDeniedFromGit("btop.theme"))
        #expect(!ThemeRules.isDeniedFromGit("colors.toml"))
        #expect(ThemeRules.normalizedName("Tokyo Night") == "tokyo-night")
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
