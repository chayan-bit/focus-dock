import Foundation

/// What a retint target needs: the swapped-in theme directory, its palette and background.
public struct ThemeContext: Sendable {
    public let theme: URL
    public let colors: ThemeColors
    public let background: URL?

    public init(theme: URL, colors: ThemeColors, background: URL?) {
        self.theme = theme
        self.colors = colors
        self.background = background
    }
}

/// One app the engine retints. `apply` and `reset` return a log line saying what they did.
public protocol ThemeTarget: Sendable {
    var name: String { get }
    func apply(_ context: ThemeContext) async throws -> String
    func reset() async throws -> String
}

/// The user's own value of a setting, saved before the first retint and restored by reset.
public struct SavedSetting: Codable, Equatable, Sendable {
    /// The raw value text (JSON) or whole line (conf); nil when the key was absent.
    public let raw: String?
    /// Files and directories that did not exist before, deepest last.
    public let created: [String]

    public init(raw: String?, created: [String]) {
        self.raw = raw
        self.created = created
    }
}

/// One JSON file per target under the state dir, written once and removed by reset.
public struct Originals: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private func file(_ name: String) -> URL { directory.appending(path: "\(name).json") }

    public func load<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: file(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Records `make()` unless a record exists, so the value saved is the user's, not ours.
    public func saveOnce<T: Codable>(_ name: String, _ make: () throws -> T) throws {
        guard !FileManager.default.fileExists(atPath: file(name).path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(try make()).write(to: file(name), options: .atomic)
    }

    public func save<T: Encodable>(_ name: String, _ value: T) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: file(name), options: .atomic)
    }

    public func remove(_ name: String) {
        try? FileManager.default.removeItem(at: file(name))
    }
}

/// Text file helpers that write through symlinks and keep the file's permissions.
public enum TextFile {
    public static func read(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    public static func write(_ text: String, to url: URL) throws {
        let target = url.resolvingSymlinksInPath()
        let permissions = (try? FileManager.default.attributesOfItem(atPath: target.path))?[.posixPermissions]
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: target, options: .atomic)
        if let permissions {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        }
    }

    /// The paths among `candidates` that do not exist yet, ancestors first.
    public static func missing(_ candidates: [URL]) -> [String] {
        candidates.map(\.path).filter { !FileManager.default.fileExists(atPath: $0) }.sorted()
    }

    /// Removes what a target created, deepest first; directories only when empty.
    public static func removeCreated(_ paths: [String]) {
        for path in paths.reversed() {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                rmdir(path)
            } else if (read(URL(filePath: path)) ?? "").allSatisfy({ $0.isWhitespace || $0 == "{" || $0 == "}" }) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }
}

/// Copies a rendered theme file into an app's theme directory and points one top-level key of
/// its JSON settings at it: Zed (`theme` = "FocusDock") and Claude Code (`theme` = "custom:focusdock").
public struct JSONSettingTarget: ThemeTarget {
    public let name: String
    public let settings: URL
    public let key: String
    /// JSON text of the value we set, e.g. `"FocusDock"` with the quotes.
    public let value: String
    /// File name inside the current theme, and where it is copied.
    public let source: String
    public let destination: URL
    let originals: Originals

    public init(name: String, settings: URL, key: String, value: String, source: String, destination: URL, originals: Originals) {
        self.name = name
        self.settings = settings
        self.key = key
        self.value = value
        self.source = source
        self.destination = destination
        self.originals = originals
    }

    public func apply(_ context: ThemeContext) async throws -> String {
        let text = TextFile.read(settings)
        try originals.saveOnce(name) {
            let paths = [destination.deletingLastPathComponent(), destination, settings.deletingLastPathComponent(), settings]
            return SavedSetting(raw: try text.flatMap { try JSONKey.value(key, in: $0) }, created: TextFile.missing(paths))
        }
        let rendered = try Data(contentsOf: context.theme.appending(path: source))
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try rendered.write(to: destination, options: .atomic)
        let updated = try JSONKey.setting(key, to: value, in: text ?? "{}\n")
        if updated != text { try TextFile.write(updated, to: settings) }
        return "\(name): wrote \(destination.path), \(key) = \(value) in \(settings.path)"
    }

    public func reset() async throws -> String {
        guard let saved = originals.load(name, as: SavedSetting.self) else { return "\(name): nothing to restore" }
        if let text = TextFile.read(settings), try JSONKey.value(key, in: text) == value {
            let restored = try saved.raw.map { raw throws(SettingsTextError) in try JSONKey.setting(key, to: raw, in: text) }
                ?? JSONKey.removing(key, in: text)
            try TextFile.write(restored, to: settings)
        }
        try? FileManager.default.removeItem(at: destination)
        TextFile.removeCreated(saved.created)
        originals.remove(name)
        return "\(name): restored \(key) = \(saved.raw ?? "(absent)")"
    }
}

/// btop: links `~/.config/btop/themes/focusdock.theme` to the state file and sets
/// `color_theme = "focusdock"`. btop only loads themes from its theme directories (it matches a
/// configured absolute path by file name alone), so the state path cannot be set directly.
public struct BtopTarget: ThemeTarget {
    public let name = "btop"
    public static let line = "color_theme = \"focusdock\""
    let home: URL
    let current: URL
    let originals: Originals
    /// Asks running btop instances to reload (`pkill -USR2 -x btop`).
    let reload: @Sendable () async -> Void

    public init(home: URL, currentTheme: URL, originals: Originals, reload: @escaping @Sendable () async -> Void) {
        self.home = home
        self.current = currentTheme
        self.originals = originals
        self.reload = reload
    }

    var directory: URL { home.appending(path: ".config/btop") }
    var conf: URL { directory.appending(path: "btop.conf") }
    var link: URL { directory.appending(path: "themes/focusdock.theme") }

    public func apply(_ context: ThemeContext) async throws -> String {
        let text = TextFile.read(conf)
        try originals.saveOnce(name) {
            SavedSetting(raw: text.flatMap { ConfLine.line("color_theme", in: $0) },
                         created: TextFile.missing([directory, link.deletingLastPathComponent(), conf]))
        }
        let target = current.appending(path: "btop.theme").path
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != target {
            try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target)
        }
        let updated = ConfLine.setting("color_theme", line: Self.line, in: text ?? "")
        if updated != text { try TextFile.write(updated, to: conf) }
        await reload()
        return "btop: \(Self.line) in \(conf.path), \(link.path) -> \(target)"
    }

    public func reset() async throws -> String {
        guard let saved = originals.load(name, as: SavedSetting.self) else { return "btop: nothing to restore" }
        if let text = TextFile.read(conf), ConfLine.line("color_theme", in: text) == Self.line {
            let restored = saved.raw.map { ConfLine.setting("color_theme", line: $0, in: text) } ?? ConfLine.removing("color_theme", in: text)
            try TextFile.write(restored, to: conf)
        }
        try? FileManager.default.removeItem(at: link)
        TextFile.removeCreated(saved.created)
        originals.remove(name)
        await reload()
        return "btop: restored \(saved.raw ?? "(no color_theme line)")"
    }
}
