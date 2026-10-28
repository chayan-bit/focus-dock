import Foundation
import Testing
@testable import FocusDockCore

struct TemplateRendererTests {
    private func render(_ template: String, theme: String) -> String {
        TemplateRenderer(colors: Repo.colors(theme)).render(template)
    }

    private func shipped(_ name: String) -> String {
        TextFile.read(Repo.templates.appending(path: name)) ?? ""
    }

    @Test func substitutesKeyStripAndRGB() {
        let out = render("plain {{ accent }} strip {{ accent_strip }} rgb {{ accent_rgb }}", theme: "tokyo-night")
        #expect(out == "plain #7aa2f7 strip 7aa2f7 rgb 122,162,247")
    }

    @Test func mixesInEveryForm() {
        let out = render("{{ mix background foreground 10% }} {{ mix_strip background accent 0.35 }} {{ mix_rgb color0 color7 50 }}", theme: "tokyo-night")
        // (26,27,38) toward (169,177,214) by .10; toward (122,162,247) by .35; halfway.
        #expect(out == "#282a38 3c4a6f 98,102,126")
    }

    @Test func gradientHelpersReadHyprlandBorders() {
        let template = "{{ hypr_gradient hyprland_active_border accent }}|{{ gradient_start hyprland_active_border accent }}|{{ shell_gradient hyprland_active_border foreground }}"
        #expect(render(template, theme: "hackerman") == "{ colors = { \"rgba(26a269ee)\", \"rgba(2ec27eee)\" }, angle = 45 }|#26a269|rgba(26a269ee) rgba(2ec27eee) 45deg")
        #expect(render(template, theme: "last-horizon") == "{ colors = { \"rgba(8a8588ee)\", \"rgba(e2dddcee)\" } }|#8a8588|rgba(8a8588ee) rgba(e2dddcee)")
        #expect(render(template, theme: "tokyo-night") == "\"#7aa2f7\"|#7aa2f7|#a9b1d6")
    }

    @Test func gradientFallbacksAreUsedVerbatimWhenNotKeys() {
        let template = "{{ hypr_gradient hyprland_inactive_border rgba(595959aa) }}|{{ gradient_start missing #123456 }}|{{ gradient_start missing rgb(1,2,300) }}"
        #expect(render(template, theme: "tokyo-night") == "\"rgba(595959aa)\"|#123456|#0102ff")
        #expect(render("{{ hypr_gradient hyprland_inactive_border rgba(595959aa) }}", theme: "last-horizon") == "\"rgba(584e51aa)\"")
    }

    @Test func leavesUnknownAndMalformedTokensAlone() {
        let template = "{{accent}} {{ nope }} {{ mix accent nope 10% }} {{{ accent }}} {{ accent"
        #expect(render(template, theme: "tokyo-night") == "{{accent}} {{ nope }} {{ mix accent nope 10% }} {#7aa2f7} {{ accent")
    }

    @Test func spansNeverCrossALine() {
        #expect(render("a {{ accent\n}} b {{ red }}\n", theme: "tokyo-night") == "a {{ accent\n}} b #f7768e\n")
    }

    @Test func rendersOmarchysClaudeTemplate() throws {
        let out = render(shipped("claude.json.tpl"), theme: "tokyo-night")
        #expect(!out.contains("{{"))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        let overrides = try #require(json["overrides"] as? [String: String])
        #expect(json["name"] as? String == "FocusDock")
        #expect(json["base"] as? String == "dark")
        #expect(overrides["claude"] == "#7aa2f7")
        #expect(overrides["claudeShimmer"] == "#8aa7eb")
        #expect(overrides["diffAdded"] == "#2e3630")
        #expect(overrides["inactive"] == "#707590")
    }

    @Test func rendersOmarchysBtopTemplateForALightTheme() {
        let colors = Repo.colors("catppuccin-latte")
        let out = render(shipped("btop.theme.tpl"), theme: "catppuccin-latte")
        #expect(out.contains("theme[main_bg]=\"\(colors["background"] ?? "")\""))
        #expect(out.contains("theme[hi_fg]=\"\(colors["accent"] ?? "")\""))
        #expect(!out.contains("{{"))
    }

    @Test(arguments: Repo.themeNames())
    func everyShippedTemplateRendersCompletelyForEveryTheme(theme: String) throws {
        for name in ["btop.theme.tpl", "claude.json.tpl", "focusdock.toml.tpl", "neovim.lua.tpl", "wezterm.lua.tpl", "zed.json.tpl"] {
            let out = render(shipped(name), theme: theme)
            #expect(!out.contains("{{"), "\(theme) \(name)")
            if name.hasSuffix(".json.tpl") {
                #expect((try? JSONSerialization.jsonObject(with: Data(out.utf8))) != nil, "\(theme) \(name)")
            }
        }
    }

    @Test func zedThemeAppearanceFollowsTheMode() throws {
        let out = render(shipped("zed.json.tpl"), theme: "catppuccin-latte")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        let themes = try #require(json["themes"] as? [[String: Any]])
        #expect(json["name"] as? String == "FocusDock")
        #expect(themes.first?["name"] as? String == "FocusDock")
        #expect(themes.first?["appearance"] as? String == "light")
    }

    @Test func shellThemeReadsTheRenderedFocusDockFile() {
        let shell = ShellTheme.parse(render(shipped("focusdock.toml.tpl"), theme: "catppuccin-latte"))
        #expect(shell.isLight)
        #expect(shell.accent == RGB(hex: Repo.colors("catppuccin-latte")["accent"] ?? ""))
        #expect(shell.glassTint == RGB(hex: Repo.colors("catppuccin-latte")["background"] ?? ""))
        #expect(shell.glassTintOpacity == 0.35)
    }
}
