import Foundation

/// Every path the theme engine reads or writes, rooted at an injectable home directory so
/// tests run in a temp dir. The layout is the contract in docs/THEMES.md.
public struct ThemePaths: Sendable {
    public let home: URL
    /// Themes shipped with FocusDock (`Themes/` in the repo, `Contents/Resources/Themes` in the app).
    public let shippedThemes: URL
    /// Templates shipped with FocusDock (`Templates/`, `Contents/Resources/Templates`).
    public let shippedTemplates: URL

    public init(home: URL, shippedThemes: URL, shippedTemplates: URL) {
        self.home = home
        self.shippedThemes = shippedThemes
        self.shippedTemplates = shippedTemplates
    }

    public var config: URL { home.appending(path: ".config/focusdock") }
    public var userThemes: URL { config.appending(path: "themes") }
    public var userTemplates: URL { config.appending(path: "themed") }
    /// Extra backgrounds per theme, like `~/.config/omarchy/backgrounds/<name>/`.
    public var userBackgrounds: URL { config.appending(path: "backgrounds") }
    /// Where scripts/sync-backgrounds.sh puts the shipped themes' backgrounds.
    public var downloadedThemes: URL { home.appending(path: ".local/share/focusdock/themes") }

    public var state: URL { home.appending(path: ".local/state/focusdock") }
    public var current: URL { state.appending(path: "current") }
    public var currentTheme: URL { current.appending(path: "theme") }
    public var nextTheme: URL { current.appending(path: "next-theme") }
    public var themeName: URL { current.appending(path: "theme.name") }
    public var generation: URL { current.appending(path: "theme.generation") }
    public var background: URL { current.appending(path: "background") }
    public var rememberedBackgrounds: URL { state.appending(path: "theme-backgrounds") }
    public var originals: URL { state.appending(path: "originals") }
    public var lock: URL { state.appending(path: "theme.lock") }
    public var retintLock: URL { state.appending(path: "theme-retint.lock") }
    public var log: URL { state.appending(path: "theme-set.log") }

    /// The directories a theme's backgrounds come from, in Omarchy's order. They are durable,
    /// unlike the staged theme, so the wallpaper never points into a directory a swap deletes.
    public func backgroundDirectories(_ name: String) -> [URL] {
        [
            userBackgrounds.appending(path: name),
            userThemes.appending(path: name).appending(path: "backgrounds"),
            downloadedThemes.appending(path: name).appending(path: "backgrounds"),
            shippedThemes.appending(path: name).appending(path: "backgrounds"),
        ]
    }
}

/// Omarchy's naming and safety rules for themes.
public enum ThemeRules {
    /// What a theme cloned from git may not ship because it runs code (`INSTALLED_THEME_DENIED`
    /// plus any `*.lua`, in bin/omarchy-theme-set).
    public static let deniedFromGit: Set<String> = ["alacritty.toml", "foot.ini", "ghostty.conf", "kitty.conf", "vscode.json"]

    public static func isDeniedFromGit(_ fileName: String) -> Bool {
        fileName.hasSuffix(".lua") || deniedFromGit.contains(fileName)
    }

    /// Files dropped silently rather than reported, as Omarchy does.
    public static func isDocumentation(_ fileName: String) -> Bool {
        let lower = fileName.lowercased()
        return ["readme", "license", "changelog"].contains { lower.hasPrefix($0) } || lower.hasSuffix(".md") || lower.hasSuffix(".txt")
    }

    /// "Tokyo Night" -> "tokyo-night"; nil for names that could escape the themes directory.
    public static func normalizedName(_ input: String) -> String? {
        let withoutTags = input.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let name = withoutTags.lowercased().replacingOccurrences(of: " ", with: "-")
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/") else { return nil }
        return name
    }

    /// Which template renders which output: user templates first, then shipped ones, and never
    /// over a file the theme already has (`render_templates`). Inputs are template file names.
    public static func templatePlan(user: [String], shipped: [String], existing: Set<String>) -> [(template: String, isUser: Bool, output: String)] {
        var taken = existing
        var plan: [(String, Bool, String)] = []
        let ordered = user.sorted().map { ($0, true) } + shipped.sorted().map { ($0, false) }
        for (template, isUser) in ordered where template.hasSuffix(".tpl") {
            let output = String(template.dropLast(4))
            guard !output.isEmpty, !taken.contains(output) else { continue }
            taken.insert(output)
            plan.append((template, isUser, output))
        }
        return plan
    }

    public static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff"]

    /// `choose_theme_background`: the next background when re-applying the same theme, else
    /// the remembered one if it still exists, else the first. `candidates` are sorted paths.
    public static func chooseBackground(candidates: [String], sameTheme: Bool, current: String?, remembered: String?) -> String? {
        guard let first = candidates.first else { return nil }
        if sameTheme {
            guard let current, let index = candidates.firstIndex(of: current) else { return first }
            return candidates[(index + 1) % candidates.count]
        }
        if let remembered, candidates.contains(remembered) { return remembered }
        return first
    }
}
