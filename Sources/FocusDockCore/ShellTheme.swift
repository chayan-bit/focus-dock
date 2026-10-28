import Foundation

/// FocusDock's own colours, from `current/theme/focusdock.toml` (rendered from
/// Templates/focusdock.toml.tpl or shipped by a theme). Nil fields keep the native look.
public struct ShellTheme: Equatable, Sendable {
    public let isLight: Bool
    public let glassTint: RGB?
    public let glassTintOpacity: Double
    public let accent: RGB?
    public let text: RGB?
    public let indicator: RGB?

    public static let defaultTintOpacity = 0.35

    public init(isLight: Bool, glassTint: RGB?, glassTintOpacity: Double, accent: RGB?, text: RGB?, indicator: RGB?) {
        self.isLight = isLight
        self.glassTint = glassTint
        self.glassTintOpacity = glassTintOpacity
        self.accent = accent
        self.text = text
        self.indicator = indicator
    }

    public static func parse(_ toml: String) -> ShellTheme {
        let values = FlatToml.parse(toml)
        func color(_ key: String) -> RGB? { values[key].flatMap { RGB(hex: $0) } }
        let opacity = values["glass_tint_opacity"].flatMap(Double.init).map { min(max($0, 0), 1) }
        return ShellTheme(
            isLight: values["mode"] == "light",
            glassTint: color("glass_tint"),
            glassTintOpacity: opacity ?? defaultTintOpacity,
            accent: color("accent"),
            text: color("text"),
            indicator: color("indicator")
        )
    }
}
