import Foundation

/// A theme palette from Omarchy's `colors.toml`, resolved the way `omarchy-theme-color --all`
/// resolves it (basecamp/omarchy, MIT): legacy names, ANSI fallbacks, derived shades and mode.
/// Values stay strings because templates substitute them verbatim.
public struct ThemeColors: Equatable, Sendable {
    /// Every resolved key; a key that an alias created without a source maps to "".
    public let values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }

    public subscript(key: String) -> String? { values[key] }

    public var mode: String { values["mode"] ?? "dark" }
    public var isLight: Bool { mode == "light" }

    /// Parses and resolves a colors.toml. `hasLightModeFile` is a `light.mode` file beside it.
    public static func parse(_ text: String, hasLightModeFile: Bool = false) -> ThemeColors {
        ThemeColors(values: resolve(FlatToml.parse(text), hasLightModeFile: hasLightModeFile))
    }
}

/// Omarchy's line-based reader for the flat `key = "value"` files themes use
/// (`parse_colors_file` in bin/omarchy-theme-color). Ported rather than using a TOML package:
/// Omarchy itself does not parse TOML, and a real parser would accept or reject other files.
public enum FlatToml {
    private static let keyCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    // Values become template text, so the charset is Omarchy's: hex, rgb()/rgba(), angles, words.
    private static let valueCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#(),._+/% -")

    public static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if let (key, value) = entry(String(line)) { values[key] = value }
        }
        return values
    }

    static func entry(_ line: String) -> (String, String)? {
        let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let key = parts[0].filter { $0 != "\"" && $0 != "'" && $0 != " " }
        guard !key.isEmpty, !key.hasPrefix("#") else { return nil }
        let raw = parts.count > 1 ? String(parts[1]) : ""
        let value: String
        if let open = raw.firstIndex(where: { $0 == "\"" || $0 == "'" }) {
            let rest = raw[raw.index(after: open)...]
            value = String(rest.prefix { $0 != "\"" && $0 != "'" })
        } else {
            value = raw.trimmingCharacters(in: .whitespaces)
        }
        guard key.unicodeScalars.allSatisfy(keyCharacters.contains),
              value.unicodeScalars.allSatisfy(valueCharacters.contains) else { return nil }
        return (key, value)
    }
}

extension ThemeColors {
    private static let legacyPalette: [(String, String)] = [
        ("background", "bg"), ("dark_background", "dark_bg"), ("darker_background", "darker_bg"),
        ("lighter_background", "lighter_bg"), ("foreground", "fg"), ("dark_foreground", "dark_fg"),
        ("light_foreground", "light_fg"), ("bright_foreground", "bright_fg"),
    ]
    private static let legacyANSI: [(String, String)] = [
        ("red", "color1"), ("green", "color2"), ("yellow", "color3"), ("blue", "color4"),
        ("magenta", "color5"), ("cyan", "color6"), ("bright_red", "color9"), ("bright_green", "color10"),
        ("bright_yellow", "color11"), ("bright_blue", "color12"), ("bright_magenta", "color13"), ("bright_cyan", "color14"),
    ]
    private static let ansiNames = [
        "background", "red", "green", "yellow", "blue", "magenta", "cyan", "foreground",
        "muted", "bright_red", "bright_green", "bright_yellow", "bright_blue", "bright_magenta", "bright_cyan", "bright_foreground",
    ]
    private static let brightened = ["red", "yellow", "green", "cyan", "blue", "magenta"]

    /// `resolve_theme_colors`, step for step; the order matters because later steps read earlier ones.
    static func resolve(_ raw: [String: String], hasLightModeFile: Bool) -> [String: String] {
        var c = Palette(raw)
        legacyPalette.forEach { c.alias($0.0, $0.1) }
        c.fill("background", c["color0"])
        c.fill("foreground", c["color7"])
        if !c["background"].isEmpty { c.values["color0"] = c["background"] }
        if !c["foreground"].isEmpty { c.values["color7"] = c["foreground"] }
        legacyANSI.forEach { c.alias($0.0, $0.1) }
        c.alias("magenta", "purple")
        c.alias("bright_magenta", "bright_purple")
        fillNeutrals(&c)
        c.fill("dark_background", ColorMath.mix(c["background"], "#000000", amount: "25%"))
        c.fill("darker_background", ColorMath.mix(c["background"], "#000000", amount: "50%"))
        for name in brightened { c.fill("bright_\(name)", ColorMath.mix(c[name], "#ffffff", amount: "20%")) }
        c.alias("purple", "magenta")
        c.alias("bright_purple", "bright_magenta")
        for (index, name) in ansiNames.enumerated() { c.alias("color\(index)", name) }
        for (canonical, legacy) in legacyPalette where !c[canonical].isEmpty { c.values[legacy] = c[canonical] }
        c.values["mode"] = mode(c, hasLightModeFile: hasLightModeFile)
        c.values["theme_type"] = c["mode"]
        return c.values
    }

    private static func fillNeutrals(_ c: inout Palette) {
        c.fill("light_foreground", c.first("color7", "foreground"))
        c.fill("bright_foreground", c.first("color15", "foreground"))
        c.values["cursor"] = c["bright_foreground"]
        c.fill("lighter_background", c.first("color0", "background"))
        c.fill("dark_foreground", c.first("color8", "foreground"))
        c.fill("muted", c.first("color8", "dark_foreground"))
        c.fill("selection", c.first("selection_background", "color8", "color0", "background"))
        c.fill("selection_background", c["selection"])
        c.fill("selection_foreground", c["bright_foreground"])
        c.fill("orange", c["yellow"])
        c.fill("brown", ColorMath.mix(c["orange"], "#000000", amount: "50%"))
    }

    private static func mode(_ c: Palette, hasLightModeFile: Bool) -> String {
        if !c["mode"].isEmpty { return c["mode"] }
        if !c["theme_type"].isEmpty { return c["theme_type"] }
        if hasLightModeFile { return "light" }
        guard let rgb = ColorMath.components(c["background"]) else { return "dark" }
        return rgb.0 + rgb.1 + rgb.2 > 382 ? "light" : "dark"
    }
}

/// Bash associative-array semantics: a missing key reads as "", and `[[ $x ]]` means non-empty.
private struct Palette {
    var values: [String: String]
    init(_ values: [String: String]) { self.values = values }

    subscript(key: String) -> String { values[key] ?? "" }

    /// `alias_theme_color`: copy the fallback (even an empty one) when the key is empty.
    mutating func alias(_ key: String, _ fallback: String) {
        if self[key].isEmpty { values[key] = self[fallback] }
    }

    /// `[[ ${C[key]} ]] || C[key]=value`.
    mutating func fill(_ key: String, _ value: String?) {
        if self[key].isEmpty { values[key] = value ?? "" }
    }

    /// `${C[a]:-${C[b]}}`, chained.
    func first(_ keys: String...) -> String {
        keys.lazy.map { self[$0] }.first { !$0.isEmpty } ?? ""
    }
}
