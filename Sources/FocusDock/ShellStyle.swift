import FocusDockCore
import SwiftUI

extension EnvironmentValues {
    /// The applied theme's dock colours, set once at the root of DockView.
    @Entry var shellTheme: ShellTheme?
}

extension Color {
    init(_ rgb: RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// The theme's colour when there is one, else the native style's.
    static func themed(_ rgb: RGB?, or fallback: Color) -> Color {
        rgb.map(Color.init) ?? fallback
    }
}

/// Puts the theme in the environment and, only while a theme is applied, matches the glass's
/// light or dark rendering to the theme's mode; without a theme the system appearance stays.
struct ShellThemeScope: ViewModifier {
    let theme: ShellTheme?

    func body(content: Content) -> some View {
        if let theme {
            content.environment(\.shellTheme, theme).environment(\.colorScheme, theme.isLight ? .light : .dark)
        } else {
            content
        }
    }
}

extension Glass {
    /// Liquid Glass tinted with the theme's glass colour, or the plain regular glass.
    static func themed(_ theme: ShellTheme?) -> Glass {
        guard let tint = theme?.glassTint else { return .regular }
        return .regular.tint(Color(tint).opacity(theme?.glassTintOpacity ?? ShellTheme.defaultTintOpacity))
    }
}
