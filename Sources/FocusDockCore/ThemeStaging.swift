import Foundation

public enum ThemeError: Error, Equatable, CustomStringConvertible {
    case invalidName(String)
    case notFound(String, available: [String])
    case noColors(String)
    case io(String)

    public var description: String {
        switch self {
        case .invalidName(let name): "invalid theme name: \"\(name)\""
        case .notFound(let name, let available): "no theme named \"\(name)\"; available: \(available.joined(separator: ", "))"
        case .noColors(let name): "theme \"\(name)\" has no colors.toml"
        case .io(let detail): detail
        }
    }
}

/// Builds `next-theme` the way `omarchy-theme-set` does: the shipped theme, then the user's
/// theme on top (filtered when it came from git), then templates for every file still missing.
/// Backgrounds are not copied; they are chosen from their durable directories instead.
struct ThemeStager {
    let paths: ThemePaths
    private var fm: FileManager { .default }

    /// Stages `name` into `paths.nextTheme`; returns the user-theme files the safety rule dropped.
    func stage(_ name: String) throws -> [String] {
        try? fm.removeItem(at: paths.nextTheme)
        try fm.createDirectory(at: paths.nextTheme, withIntermediateDirectories: true)
        _ = try copyContents(of: paths.shippedThemes.appending(path: name), into: paths.nextTheme, filtered: false)
        let user = paths.userThemes.appending(path: name)
        let ignored = try copyContents(of: user, into: paths.nextTheme, filtered: Self.cameFromGit(user))
        let colorsFile = paths.nextTheme.appending(path: "colors.toml")
        guard let text = TextFile.read(colorsFile) else { throw ThemeError.noColors(name) }
        let hasLightMode = fm.fileExists(atPath: paths.nextTheme.appending(path: "light.mode").path)
        try renderTemplates(ThemeColors.parse(text, hasLightModeFile: hasLightMode))
        return ignored
    }

    /// A `.git` directory in a real (non-symlinked) theme directory means a stranger wrote it.
    static func cameFromGit(_ directory: URL) -> Bool {
        let isLink = (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
        return !isLink && FileManager.default.fileExists(atPath: directory.appending(path: ".git").path)
    }

    /// `cp -r src/* dest/`, minus backgrounds; with `filtered`, Omarchy's `stage_installed_theme`:
    /// no symlinks at any depth and no code at the top level.
    private func copyContents(of source: URL, into destination: URL, filtered: Bool, top: Bool = true) throws -> [String] {
        guard let entries = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey]) else { return [] }
        var ignored: [String] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            guard !name.hasPrefix("."), !(top && name == "backgrounds") else { continue }
            let values = try entry.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if filtered, values.isSymbolicLink == true || (top && ThemeRules.isDeniedFromGit(name)) {
                if !ThemeRules.isDocumentation(name) { ignored.append(name) }
                continue
            }
            let target = destination.appending(path: name)
            if values.isDirectory == true, values.isSymbolicLink != true {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                ignored += try copyContents(of: entry, into: target, filtered: filtered, top: false)
            } else {
                try? fm.removeItem(at: target)
                try fm.copyItem(at: entry, to: target)
            }
        }
        return ignored
    }

    private func renderTemplates(_ colors: ThemeColors) throws {
        let user = templateNames(paths.userTemplates)
        let shipped = templateNames(paths.shippedTemplates)
        let existing = Set((try? fm.contentsOfDirectory(atPath: paths.nextTheme.path)) ?? [])
        let renderer = TemplateRenderer(colors: colors)
        for item in ThemeRules.templatePlan(user: user, shipped: shipped, existing: existing) {
            let directory = item.isUser ? paths.userTemplates : paths.shippedTemplates
            guard let template = TextFile.read(directory.appending(path: item.template)) else { continue }
            try Data(renderer.render(template).utf8).write(to: paths.nextTheme.appending(path: item.output))
        }
    }

    private func templateNames(_ directory: URL) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".tpl") }
    }

    /// Sorted image paths for a theme from every background directory.
    func backgroundCandidates(_ name: String) -> [String] {
        let gitTheme = Self.cameFromGit(paths.userThemes.appending(path: name))
        var found: [String] = []
        for directory in paths.backgroundDirectories(name) {
            let skipLinks = gitTheme && directory.path.hasPrefix(paths.userThemes.path)
            let entries = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey])) ?? []
            for entry in entries where ThemeRules.imageExtensions.contains(entry.pathExtension.lowercased()) {
                let values = try? entry.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                if skipLinks, values?.isSymbolicLink == true { continue }
                let resolved = entry.resolvingSymlinksInPath()
                if (try? resolved.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { found.append(entry.path) }
            }
        }
        return found.sorted()
    }
}
