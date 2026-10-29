import AppKit
import FocusDockCore

/// Builds the theme engine with every retint target (SHELL-SPEC 3). FocusDock, WezTerm and
/// Neovim have no target: each watches `current/theme` itself.
enum ThemeSystem {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Themes/ and Templates/ come from `ShippedResources` (the bundle, or `$FOCUSDOCK_RESOURCES`).
    static var paths: ThemePaths {
        let resources = ShippedResources.directory
        return ThemePaths(home: home, shippedThemes: resources.appending(path: "Themes"), shippedTemplates: resources.appending(path: "Templates"))
    }

    static func engine() -> ThemeEngine {
        let paths = paths
        let originals = Originals(directory: paths.originals)
        let targets: [any ThemeTarget] = [
            JSONSettingTarget(
                name: "zed", settings: home.appending(path: ".config/zed/settings.json"), key: "theme",
                value: "\"FocusDock\"", source: "zed.json",
                destination: home.appending(path: ".config/zed/themes/focusdock.json"), originals: originals
            ),
            JSONSettingTarget(
                name: "claude", settings: home.appending(path: ".claude/settings.json"), key: "theme",
                value: "\"custom:focusdock\"", source: "claude.json",
                destination: home.appending(path: ".claude/themes/focusdock.json"), originals: originals
            ),
            BtopTarget(home: home, currentTheme: paths.currentTheme, originals: originals) {
                _ = try? await ProcessRunner.run(URL(filePath: "/usr/bin/pkill"), ["-USR2", "-x", "btop"], timeout: 5)
            },
            BordersTarget(),
            WallpaperTarget(originals: originals),
        ]
        return ThemeEngine(paths: paths, targets: targets)
    }

    /// Looks a tool up on PATH and in the nix-darwin profiles (GUI apps get a minimal PATH).
    static func executable(_ name: String) -> URL? {
        AeroSpaceLocator.find(
            path: ProcessInfo.processInfo.environment["PATH"], user: NSUserName(), name: name,
            isExecutable: FileManager.default.isExecutableFile(atPath:)
        ).map { URL(filePath: $0) }
    }
}

/// JankyBorders: `borders active_color=0xffRRGGBB inactive_color=0xaaRRGGBB`. Reset pushes
/// the transparent colours the Nix config starts it with.
struct BordersTarget: ThemeTarget {
    let name = "borders"
    static let inert = ["active_color=0x00000000", "inactive_color=0x00000000"]

    static func arguments(_ colors: ThemeColors) -> [String] {
        func flat(_ key: String, _ fallback: String) -> String {
            let start = Gradient.start(key, fallback: fallback, palette: colors.values)
            return String((ColorMath.components(start) != nil ? start : colors[fallback] ?? "#000000").dropFirst())
        }
        return ["active_color=0xff\(flat("hyprland_active_border", "accent"))", "inactive_color=0xaa\(flat("hyprland_inactive_border", "muted"))"]
    }

    func apply(_ context: ThemeContext) async throws -> String {
        try await run(Self.arguments(context.colors))
    }

    func reset() async throws -> String {
        try await run(Self.inert)
    }

    private func run(_ arguments: [String]) async throws -> String {
        guard let borders = ThemeSystem.executable("borders") else { return "borders: not installed, skipped" }
        let result = try await ProcessRunner.run(borders, arguments, timeout: 5)
        let command = "\(borders.path) \(arguments.joined(separator: " "))"
        guard result.succeeded else { throw ThemeError.io("\(command) exited \(result.status)") }
        return "borders: ran \(command)"
    }
}

/// The desktop picture of every screen. The first apply records each screen's own picture
/// (by display id) and a copy of the wallpaper store, and reset puts both back.
struct WallpaperTarget: ThemeTarget {
    let name = "wallpaper"
    let originals: Originals

    /// The private store behind System Settings > Wallpaper. NSWorkspace can set an image but
    /// not a dynamic wallpaper's style ("Dynamic" for Catalina.heic), so only the store's own
    /// bytes bring the original back exactly.
    static let store = ThemeSystem.home.appending(path: "Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    private var storeCopy: URL { originals.directory.appending(path: "wallpaper-store.plist") }

    func apply(_ context: ThemeContext) async throws -> String {
        guard let background = context.background?.resolvingSymlinksInPath() else {
            return "wallpaper: theme has no backgrounds (scripts/sync-backgrounds.sh), unchanged"
        }
        try await MainActor.run {
            var saved = originals.load(name, as: [String: String].self) ?? [:]
            for screen in NSScreen.screens {
                let id = Self.id(screen)
                if saved[id] == nil, let url = NSWorkspace.shared.desktopImageURL(for: screen) { saved[id] = url.absoluteString }
            }
            try originals.save(name, saved)
            if !FileManager.default.fileExists(atPath: storeCopy.path), FileManager.default.fileExists(atPath: Self.store.path) {
                try FileManager.default.copyItem(at: Self.store, to: storeCopy)
            }
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(background, for: screen, options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:])
            }
        }
        return "wallpaper: \(background.path) on \(NSScreen.screens.count) screen(s)"
    }

    func reset() async throws -> String {
        guard let saved = originals.load(name, as: [String: String].self) else { return "wallpaper: nothing to restore" }
        let restored = try await MainActor.run {
            var count = 0
            for screen in NSScreen.screens {
                guard let url = saved[Self.id(screen)].flatMap(URL.init(string:)) else { continue }
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:])
                count += 1
            }
            return count
        }
        let store = try await restoreStore()
        originals.remove(name)
        return "wallpaper: restored \(restored) screen(s)" + (store ? " and the wallpaper store" : "")
    }

    /// Puts the saved store back and restarts WallpaperAgent (SIGKILL, so it cannot write its
    /// in-memory state over the file); launchd starts it again and it reads the restored store.
    private func restoreStore() async throws -> Bool {
        guard FileManager.default.fileExists(atPath: storeCopy.path) else { return false }
        // Let the agent finish writing the URL restore before the file is replaced.
        try await Task.sleep(for: .seconds(1))
        _ = try FileManager.default.replaceItemAt(Self.store, withItemAt: storeCopy)
        _ = try await ProcessRunner.run(URL(filePath: "/usr/bin/killall"), ["-KILL", "WallpaperAgent"], timeout: 5)
        return true
    }

    @MainActor private static func id(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { "\($0.uint32Value)" } ?? screen.localizedName
    }
}
