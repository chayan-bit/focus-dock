import Foundation
import Testing
@testable import FocusDockCore

struct SettingsTextTests {
    static let zed = """
    // Zed settings
    //
    // For information on how to configure Zed, see the Zed
    // documentation: https://zed.dev/docs/configuring-zed
    {
      "ui_font_size": 16, /* inline */
      "buffer_font_family": "JetBrains Mono", // "theme": "not this one"
      "theme": {
        "mode": "system",
        "light": "One Light",
        "dark": "One Dark",
      },
      "terminal": { "theme": "nested, not top level" },
    }

    """

    static let claude = """
    {
      "env": {
        "DISABLE_AUTOUPDATER": "1"
      },
      "hooks": {
        "Stop": [
          { "hooks": [{ "type": "command", "command": "echo \\"theme\\": done" }] }
        ]
      },
      "theme": "auto",
      "editorMode": "vim"
    }

    """

    @Test func readsTheTopLevelValueRaw() throws {
        let value = try JSONKey.value("theme", in: Self.zed)
        #expect(value == "{\n    \"mode\": \"system\",\n    \"light\": \"One Light\",\n    \"dark\": \"One Dark\",\n  }")
        #expect(try JSONKey.value("theme", in: Self.claude) == "\"auto\"")
    }

    @Test func replacingAndRestoringZedThemeIsByteExact() throws {
        let original = try #require(try JSONKey.value("theme", in: Self.zed))
        let themed = try JSONKey.setting("theme", to: "\"FocusDock\"", in: Self.zed)
        #expect(themed.contains("\"theme\": \"FocusDock\",\n  \"terminal\""))
        #expect(themed.contains("// \"theme\": \"not this one\""))
        #expect(try JSONKey.value("theme", in: themed) == "\"FocusDock\"")
        #expect(try JSONKey.setting("theme", to: original, in: themed) == Self.zed)
    }

    @Test func editsOnlyTheThemeKeyInClaudeSettings() throws {
        let themed = try JSONKey.setting("theme", to: "\"custom:focusdock\"", in: Self.claude)
        #expect(themed == Self.claude.replacingOccurrences(of: "\"theme\": \"auto\"", with: "\"theme\": \"custom:focusdock\""))
        let parsed = try JSONSerialization.jsonObject(with: Data(themed.utf8)) as? [String: Any]
        #expect(parsed?["hooks"] != nil)
        #expect(try JSONKey.setting("theme", to: "\"auto\"", in: themed) == Self.claude)
    }

    @Test func insertsAnAbsentKeyAndRemovesItExactly() throws {
        let without = "{\n  \"model\": \"opus\",\n  \"hooks\": {}\n}\n"
        let with = try JSONKey.setting("theme", to: "\"custom:focusdock\"", in: without)
        #expect(with == "{\n  \"theme\": \"custom:focusdock\",\n  \"model\": \"opus\",\n  \"hooks\": {}\n}\n")
        #expect(try JSONKey.removing("theme", in: with) == without)
    }

    @Test func removesALastMemberWithItsLeadingComma() throws {
        let text = "{\n  \"a\": 1,\n  \"theme\": \"x\"\n}\n"
        #expect(try JSONKey.removing("theme", in: text) == "{\n  \"a\": 1\n}\n")
    }

    @Test func insertsIntoAnEmptyObject() throws {
        #expect(try JSONKey.setting("theme", to: "\"x\"", in: "{}\n") == "{\n  \"theme\": \"x\"\n}\n")
    }

    @Test func rejectsANonObject() {
        #expect(throws: SettingsTextError.self) { try JSONKey.value("theme", in: "[1, 2]") }
    }

    static let btop = """
    #? Config file for btop v. 1.4.7

    #* Name of a btop++/bpytop/bashtop formatted ".theme" file.
    color_theme = "Default"

    #* If the theme set background should be shown.
    theme_background = true

    """

    @Test func btopLineEditKeepsEveryOtherLine() {
        let themed = ConfLine.setting("color_theme", line: "color_theme = \"focusdock\"", in: Self.btop)
        #expect(themed == Self.btop.replacingOccurrences(of: "\"Default\"", with: "\"focusdock\""))
        #expect(ConfLine.line("color_theme", in: themed) == "color_theme = \"focusdock\"")
        #expect(ConfLine.setting("color_theme", line: "color_theme = \"Default\"", in: themed) == Self.btop)
    }

    @Test func btopLineIsAppendedAndRemovedWhenAbsent() {
        let base = "theme_background = true\n"
        let themed = ConfLine.setting("color_theme", line: "color_theme = \"focusdock\"", in: base)
        #expect(themed == "theme_background = true\ncolor_theme = \"focusdock\"\n")
        #expect(ConfLine.removing("color_theme", in: themed) == base)
        #expect(ConfLine.line("color_theme_x", in: themed) == nil)
    }
}
