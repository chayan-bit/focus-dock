import Darwin
import Foundation

/// A switch that reached `current/theme`; its generation names it for the retint batch.
public struct AppliedTheme: Equatable, Sendable {
    public let name: String
    public let generation: String
    public let background: URL?
    /// User-theme files dropped by the git safety rule.
    public let ignored: [String]
}

/// `omarchy-theme-set` for macOS: stage, swap atomically under a lock, then retint every
/// target in parallel unless a newer switch has replaced this one (docs/THEMES.md).
public struct ThemeEngine: Sendable {
    public let paths: ThemePaths
    public let targets: [any ThemeTarget]

    public init(paths: ThemePaths, targets: [any ThemeTarget]) {
        self.paths = paths
        self.targets = targets
    }

    private var fm: FileManager { .default }

    public func list() -> [String] {
        let names = [paths.shippedThemes, paths.userThemes].flatMap { directory in
            ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? []).filter { name in
                var isDirectory: ObjCBool = false
                return !name.hasPrefix(".") && fm.fileExists(atPath: directory.appending(path: name).path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
        }
        return Array(Set(names)).sorted()
    }

    /// The applied theme's name, or nil when no theme is set (or after reset).
    public func current() -> String? {
        guard fm.fileExists(atPath: paths.currentTheme.path) else { return nil }
        return TextFile.read(paths.themeName)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The theme `offset` places after the current one in `list()`, wrapping around.
    public func neighbour(offset: Int) -> String? {
        let names = list()
        guard !names.isEmpty else { return nil }
        guard let current = current(), let index = names.firstIndex(of: current) else {
            return offset >= 0 ? names.first : names.last
        }
        return names[((index + offset) % names.count + names.count) % names.count]
    }

    /// Stages, renders and swaps the theme in; the retint is a separate step (`retint`).
    public func set(_ input: String) throws(ThemeError) -> AppliedTheme {
        guard let name = ThemeRules.normalizedName(input) else { throw .invalidName(input) }
        let available = list()
        guard available.contains(name) else { throw .notFound(name, available: available) }
        do {
            return try FileLock.withLock(paths.lock) { try swapIn(name) }
        } catch let error as ThemeError {
            throw error
        } catch {
            throw .io("could not apply \(name): \(error.localizedDescription)")
        }
    }

    private func swapIn(_ name: String) throws -> AppliedTheme {
        let previous = current()
        let stager = ThemeStager(paths: paths)
        let ignored = try stager.stage(name)
        let background = ThemeRules.chooseBackground(
            candidates: stager.backgroundCandidates(name),
            sameTheme: previous == name,
            current: try? fm.destinationOfSymbolicLink(atPath: paths.background.path),
            remembered: TextFile.read(paths.rememberedBackgrounds.appending(path: name))?.trimmingCharacters(in: .newlines)
        )
        try Self.swap(paths.nextTheme, into: paths.currentTheme)
        let generation = "\(getpid())-\(DispatchTime.now().uptimeNanoseconds)"
        try Data((generation + "\n").utf8).write(to: paths.generation, options: .atomic)
        try Data((name + "\n").utf8).write(to: paths.themeName, options: .atomic)
        try link(background: background, theme: name)
        return AppliedTheme(name: name, generation: generation, background: background.map { URL(filePath: $0) }, ignored: ignored)
    }

    /// Replaces `destination` with `staged` in one step: `renamex_np(RENAME_SWAP)` exchanges the
    /// two directories, so the old theme stays whole until the new one is in place.
    static func swap(_ staged: URL, into destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            guard renamex_np(staged.path, destination.path, UInt32(RENAME_SWAP)) == 0 else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "swap failed: \(String(cString: strerror(errno)))"])
            }
            try FileManager.default.removeItem(at: staged)
        } else {
            try FileManager.default.moveItem(at: staged, to: destination)
        }
    }

    private func link(background: String?, theme: String) throws {
        guard let background else {
            try? fm.removeItem(at: paths.background)
            return
        }
        let temporary = paths.current.appending(path: ".background-\(getpid())")
        try? fm.removeItem(at: temporary)
        try fm.createSymbolicLink(atPath: temporary.path, withDestinationPath: background)
        guard rename(temporary.path, paths.background.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        try fm.createDirectory(at: paths.rememberedBackgrounds, withIntermediateDirectories: true)
        try Data((background + "\n").utf8).write(to: paths.rememberedBackgrounds.appending(path: theme), options: .atomic)
    }

    /// Whether `generation` still names the theme in place.
    public func isCurrent(_ generation: String) -> Bool {
        TextFile.read(paths.generation)?.trimmingCharacters(in: .newlines) == generation
    }

    /// Retints every target in parallel. Batches run one at a time, and one whose switch was
    /// replaced while it waited does nothing, so an older theme never lands after a newer one.
    /// Returns the failures; a failed retint does not undo the switch.
    public func retint(_ applied: AppliedTheme) async -> [String] {
        do {
            return try await FileLock.withLock(paths.retintLock) {
                guard isCurrent(applied.generation) else {
                    log(["superseded: \(applied.name) (\(applied.generation))"], truncate: false)
                    return []
                }
                guard let text = TextFile.read(paths.currentTheme.appending(path: "colors.toml")) else { return ["colors.toml missing"] }
                let hasLight = fm.fileExists(atPath: paths.currentTheme.appending(path: "light.mode").path)
                let context = ThemeContext(theme: paths.currentTheme, colors: .parse(text, hasLightModeFile: hasLight), background: applied.background)
                return await run(header: "set \(applied.name) (\(applied.generation))") { try await $0.apply(context) }
            }
        } catch {
            return ["retint lock: \(error.localizedDescription)"]
        }
    }

    /// Removes the current theme and restores every original the targets saved.
    public func reset() async throws(ThemeError) -> [String] {
        do {
            try FileLock.withLock(paths.lock) {
                try? fm.removeItem(at: paths.currentTheme)
                try? fm.removeItem(at: paths.nextTheme)
                try? fm.removeItem(at: paths.themeName)
                try? fm.removeItem(at: paths.background)
                try fm.createDirectory(at: paths.current, withIntermediateDirectories: true)
                // A new generation makes any queued retint batch stand down.
                try Data("reset-\(getpid())-\(DispatchTime.now().uptimeNanoseconds)\n".utf8).write(to: paths.generation, options: .atomic)
            }
            return try await FileLock.withLock(paths.retintLock) {
                await run(header: "reset") { try await $0.reset() }
            }
        } catch {
            throw .io("could not reset: \(error.localizedDescription)")
        }
    }

    private func run(header: String, _ body: @escaping @Sendable (any ThemeTarget) async throws -> String) async -> [String] {
        let results = await withTaskGroup(of: (String, Bool).self) { group in
            for target in targets {
                group.addTask {
                    do { return (try await body(target), true) } catch { return ("\(target.name): \(error)", false) }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        log([header] + results.map { ($0.1 ? "  " : "  FAILED ") + $0.0 }, truncate: true)
        return results.filter { !$0.1 }.map(\.0).sorted()
    }

    /// `theme-set.log`: rewritten by each batch that runs, appended to by superseded ones.
    private func log(_ lines: [String], truncate: Bool) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = lines.map { "\(stamp) \($0)" }.joined(separator: "\n") + "\n"
        if truncate || !fm.fileExists(atPath: paths.log.path) {
            try? Data(text.utf8).write(to: paths.log)
        } else if let handle = try? FileHandle(forWritingTo: paths.log) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
            try? handle.close()
        }
    }
}
