import Foundation
import Testing
@testable import FocusDockCore

/// The repo's Themes/ and Templates/ directories, found from this file.
enum Repo {
    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let themes = root.appending(path: "Themes")
    static let templates = root.appending(path: "Templates")

    static func themeNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: themes.path)) ?? [])
            .filter { !$0.contains(".") }
            .sorted()
    }

    static func colors(_ theme: String) -> ThemeColors {
        let text = TextFile.read(themes.appending(path: "\(theme)/colors.toml")) ?? ""
        return ThemeColors.parse(text)
    }
}

struct ThemeColorsTests {
    static let semanticKeys = [
        "accent", "selection", "muted", "background", "dark_background", "darker_background", "lighter_background",
        "foreground", "dark_foreground", "light_foreground", "bright_foreground", "red", "yellow", "orange", "green",
        "cyan", "blue", "magenta", "brown", "bright_red", "bright_yellow", "bright_green", "bright_cyan",
        "bright_blue", "bright_magenta", "selection_background", "selection_foreground", "cursor",
    ] + (0...15).map { "color\($0)" }

    @Test func shipsEveryOmarchyTheme() {
        #expect(Repo.themeNames().count == 23)
    }

    @Test(arguments: Repo.themeNames())
    func everyShippedThemeResolvesAFullHexPalette(theme: String) {
        let colors = Repo.colors(theme)
        let missing = Self.semanticKeys.filter { ColorMath.components(colors[$0] ?? "") == nil }
        #expect(missing.isEmpty, "\(theme): \(missing)")
        let mode = colors.mode
        #expect(mode == "dark" || mode == "light")
    }

    @Test func readsTokyoNightAsWritten() {
        let colors = Repo.colors("tokyo-night")
        #expect(colors["accent"] == "#7aa2f7")
        #expect(colors["bright_magenta"] == "#bb9af7")
        #expect(colors["mode"] == "dark")
    }

    @Test func derivesAliasesForTokyoNight() {
        let colors = Repo.colors("tokyo-night")
        #expect(colors["cursor"] == "#c0caf5")
        #expect(colors["selection_background"] == "#292e42")
        #expect(colors["selection_foreground"] == "#c0caf5")
        #expect(colors["color0"] == "#1a1b26")
        #expect(colors["color8"] == "#414868")
        #expect(colors["purple"] == "#ad8ee6")
        #expect(colors["bg"] == "#1a1b26")
        #expect(colors["theme_type"] == "dark")
    }

    @Test func catppuccinLatteIsLight() {
        #expect(Repo.colors("catppuccin-latte").isLight)
        #expect(Repo.colors("flexoki-light").isLight)
    }

    static let legacy = """
    # A theme from before the semantic palette.
    accent = "#ff8800"
    bg = '#202020'
    fg = "#d0d0d0"   # inline comment
    color1 = "#cc0000"
    color2 = "#00aa00"
    color3 = "#aaaa00"
    color4 = "#0000cc"
    color5 = "#aa00aa"
    color6 = "#00aaaa"
    color8 = "#555555"
    color15 = "#ffffff"
    bad = "#00$(rm)"
    [section]
    """

    @Test func resolvesTheLegacyShortAndANSINames() {
        let colors = ThemeColors.parse(Self.legacy)
        #expect(colors["background"] == "#202020")
        #expect(colors["foreground"] == "#d0d0d0")
        #expect(colors["red"] == "#cc0000")
        #expect(colors["muted"] == "#555555")
        #expect(colors["selection"] == "#555555")
        #expect(colors["orange"] == "#aaaa00")
        #expect(colors["light_foreground"] == "#d0d0d0")
        #expect(colors["lighter_background"] == "#202020")
    }

    @Test func derivesShadesWithOmarchysRounding() {
        let colors = ThemeColors.parse(Self.legacy)
        #expect(colors["brown"] == "#555500")
        #expect(colors["dark_background"] == "#181818")
        #expect(colors["darker_background"] == "#101010")
        #expect(colors["bright_red"] == "#d63333")
        #expect(colors["bright_yellow"] == "#bbbb33")
        #expect(colors["bright_blue"] == "#3333d6")
        #expect(colors["bright_purple"] == "#bb33bb")
        #expect(colors["color12"] == "#3333d6")
        #expect(colors["dark_bg"] == "#181818")
    }

    @Test func rejectsUnsafeValuesAndKeys() {
        let colors = ThemeColors.parse(Self.legacy)
        #expect(colors["bad"] == nil)
        #expect(colors["[section]"] == nil)
    }

    @Test func detectsModeFromBackgroundLuminance() {
        #expect(ThemeColors.parse("background = \"#f0f0f0\"").mode == "light")
        #expect(ThemeColors.parse("background = \"#7f7f7f\"").mode == "dark")
        #expect(ThemeColors.parse("background = \"#101010\"", hasLightModeFile: true).mode == "light")
        #expect(ThemeColors.parse("theme_type = \"light\"").mode == "light")
    }

    @Test func flatTomlTakesTheFirstQuotedRun() {
        #expect(Self.entry("a = \"#123456\" # x") == "a=#123456")
        #expect(Self.entry("\"quoted\" = 'rgba(1,2,3,0.5)'") == "quoted=rgba(1,2,3,0.5)")
        #expect(Self.entry("bare =  -45deg  ") == "bare=-45deg")
        #expect(Self.entry("# comment = \"#000000\"") == nil)
    }

    private static func entry(_ line: String) -> String? {
        FlatToml.entry(line).map { "\($0.0)=\($0.1)" }
    }

    @Test func mixMatchesAwkArithmetic() {
        #expect(ColorMath.mix("#7aa2f7", "#a9b1d6", amount: "35%") == "#8aa7eb")
        #expect(ColorMath.mix("#1a1b26", "#9ece6a", amount: "15%") == "#2e3630")
        #expect(ColorMath.mix("#a9b1d6", "#1a1b26", amount: "40%") == "#707590")
        #expect(ColorMath.mix("#000000", "#ffffff", amount: "0.5") == "#808080")
        #expect(ColorMath.mix("#000000", "#ffffff", amount: "50") == "#808080")
        #expect(ColorMath.mix("#000000", "#ffffff", amount: "250%") == "#ffffff")
        #expect(ColorMath.mix("red", "#ffffff", amount: "5%") == nil)
    }

    @Test func shellHexFlattensEveryColourForm() {
        #expect(ColorMath.shellHex("rgba(8a8588ee)") == "#8a8588")
        #expect(ColorMath.shellHex("rgb(1,2,300)") == "#0102ff")
        #expect(ColorMath.shellHex("0xee112233") == "#112233")
        #expect(ColorMath.shellHex("#11223344") == "#112233")
        #expect(ColorMath.shellHex("accent") == "accent")
    }
}
