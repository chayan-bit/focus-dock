import Foundation

/// `~/.config/focusdock/modes.json` (SPEC 5). Decoding fills optional fields with their
/// defaults; `ModesConfig.parse` adds the semantic checks and readable errors.
public struct ModesConfig: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let initialMode: String?
    public let modes: [Mode]

    public init(version: Int = currentVersion, initialMode: String?, modes: [Mode]) {
        self.version = version
        self.initialMode = initialMode
        self.modes = modes
    }

    public func mode(_ id: String) -> Mode? { modes.first { $0.id == id } }

    /// Valid configs always have a mode, and `initialMode` names one of them.
    public var fallbackModeID: String { initialMode.flatMap { mode($0)?.id } ?? modes.first?.id ?? "" }
}

public struct Mode: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// SF Symbol name.
    public let symbol: String
    /// `#RRGGBB`.
    public let color: String
    /// AeroSpace workspace that holds the mode's windows.
    public let workspace: String
    /// Bundle ids, in dock order.
    public let apps: [String]
    public let webApps: [WebApp]
    /// macOS Focus to turn on, via the Shortcuts shortcut "FocusDock <focus>".
    public let focus: String?
    /// Friction when leaving this mode; absent means leaving is free.
    public let exit: ExitPolicy
    /// Plain-language description for the activity classifier (Phase 3+).
    public let allow: String?
    public let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, color, workspace, apps, webApps, focus, exit, allow
        case isPrivate = "private"
    }

    public init(
        id: String, name: String, symbol: String, color: String, workspace: String,
        apps: [String] = [], webApps: [WebApp] = [], focus: String? = nil,
        exit: ExitPolicy = .free, allow: String? = nil, isPrivate: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.workspace = workspace
        self.apps = apps
        self.webApps = webApps
        self.focus = focus
        self.exit = exit
        self.allow = allow
        self.isPrivate = isPrivate
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            symbol: try c.decode(String.self, forKey: .symbol),
            color: try c.decode(String.self, forKey: .color),
            workspace: try c.decode(String.self, forKey: .workspace),
            apps: try c.decodeIfPresent([String].self, forKey: .apps) ?? [],
            webApps: try c.decodeIfPresent([WebApp].self, forKey: .webApps) ?? [],
            focus: try c.decodeIfPresent(String.self, forKey: .focus),
            exit: try c.decodeIfPresent(ExitPolicy.self, forKey: .exit) ?? .free,
            allow: try c.decodeIfPresent(String.self, forKey: .allow),
            isPrivate: try c.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        )
    }

    /// Bundle ids whose new windows belong to this mode; web apps open as Chrome windows.
    public var routedBundleIDs: [String] { webApps.isEmpty ? apps : apps + [WebApp.chromeBundleID] }
}

public struct WebApp: Codable, Equatable, Sendable {
    public static let chromeBundleID = "com.google.Chrome"

    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

public struct ExitPolicy: Codable, Equatable, Sendable {
    public static let free = ExitPolicy(delaySeconds: 0, perPressSeconds: 0, to: [:])

    public let delaySeconds: Double
    public let perPressSeconds: Double
    /// Per-target delay overrides, by mode id.
    public let to: [String: Double]

    public init(delaySeconds: Double, perPressSeconds: Double, to: [String: Double] = [:]) {
        self.delaySeconds = delaySeconds
        self.perPressSeconds = perPressSeconds
        self.to = to
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            delaySeconds: try c.decodeIfPresent(Double.self, forKey: .delaySeconds) ?? 0,
            perPressSeconds: try c.decodeIfPresent(Double.self, forKey: .perPressSeconds) ?? 0,
            to: try c.decodeIfPresent([String: Double].self, forKey: .to) ?? [:]
        )
    }

    public func delay(to target: String) -> Double { to[target] ?? delaySeconds }
}

/// Every problem found in a config file, in file order.
public struct ConfigError: Error, Equatable, CustomStringConvertible {
    public let problems: [String]

    public init(_ problems: [String]) { self.problems = problems }

    public var description: String { problems.joined(separator: "\n") }
}

public struct RGB: Equatable, Sendable {
    public let red: Double, green: Double, blue: Double

    /// Parses `#RRGGBB` (case-insensitive).
    public init?(hex: String) {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }
}

extension ModesConfig {
    public static func parse(_ data: Data) throws(ConfigError) -> ModesConfig {
        let config: ModesConfig
        do {
            config = try JSONDecoder().decode(ModesConfig.self, from: data)
        } catch let error as DecodingError {
            throw ConfigError([ConfigValidation.describe(error)])
        } catch {
            throw ConfigError([String(describing: error)])
        }
        let problems = ConfigValidation.problems(in: config)
        guard problems.isEmpty else { throw ConfigError(problems) }
        return config
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

enum ConfigValidation {
    static func problems(in config: ModesConfig) -> [String] {
        var problems: [String] = []
        if config.version != ModesConfig.currentVersion {
            problems.append("version: must be \(ModesConfig.currentVersion), found \(config.version)")
        }
        if config.modes.isEmpty { problems.append("modes: at least one mode is required") }
        let ids = Set(config.modes.map(\.id))
        var seen: Set<String> = []
        for (index, mode) in config.modes.enumerated() {
            if !seen.insert(mode.id).inserted { problems.append("modes[\(index)].id: \"\(mode.id)\" is used by an earlier mode") }
            problems += self.problems(in: mode, at: "modes[\(index)]", knownIDs: ids)
        }
        if let initial = config.initialMode, !ids.contains(initial) {
            problems.append("initialMode: no mode has id \"\(initial)\"")
        }
        return problems
    }

    private static func problems(in mode: Mode, at path: String, knownIDs: Set<String>) -> [String] {
        var problems: [String] = []
        let required = [("id", mode.id), ("name", mode.name), ("symbol", mode.symbol), ("workspace", mode.workspace)]
        for (key, value) in required where value.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append("\(path).\(key): must not be empty")
        }
        if RGB(hex: mode.color) == nil { problems.append("\(path).color: \"\(mode.color)\" is not a #RRGGBB colour") }
        for (index, app) in mode.apps.enumerated() where app.isEmpty {
            problems.append("\(path).apps[\(index)]: must not be empty")
        }
        for (index, web) in mode.webApps.enumerated() {
            if web.name.isEmpty { problems.append("\(path).webApps[\(index)].name: must not be empty") }
            if !["http", "https"].contains(web.url.scheme?.lowercased() ?? "") || web.url.host() == nil {
                problems.append("\(path).webApps[\(index)].url: \"\(web.url.absoluteString)\" is not an http(s) URL")
            }
        }
        return problems + exitProblems(mode.exit, at: "\(path).exit", knownIDs: knownIDs)
    }

    private static func exitProblems(_ exit: ExitPolicy, at path: String, knownIDs: Set<String>) -> [String] {
        var problems: [String] = []
        if exit.delaySeconds < 0 { problems.append("\(path).delaySeconds: must not be negative") }
        if exit.perPressSeconds < 0 { problems.append("\(path).perPressSeconds: must not be negative") }
        for (target, seconds) in exit.to.sorted(by: { $0.key < $1.key }) {
            if !knownIDs.contains(target) { problems.append("\(path).to.\(target): no mode has id \"\(target)\"") }
            if seconds < 0 { problems.append("\(path).to.\(target): must not be negative") }
        }
        return problems
    }

    static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "\(path(context.codingPath + [key])): missing"
        case .typeMismatch(let type, let context):
            return "\(path(context.codingPath)): expected \(typeName(type))"
        case .valueNotFound(let type, let context):
            return "\(path(context.codingPath)): expected \(typeName(type)), found null"
        case .dataCorrupted(let context):
            let underlying = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            let detail = underlying ?? context.debugDescription
            return context.codingPath.isEmpty ? "not valid JSON: \(detail)" : "\(path(context.codingPath)): \(detail)"
        @unknown default:
            return String(describing: error)
        }
    }

    private static func path(_ keys: [any CodingKey]) -> String {
        let joined = keys.map { key in key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)" }.joined()
        let trimmed = joined.hasPrefix(".") ? String(joined.dropFirst()) : joined
        return trimmed.isEmpty ? "file" : trimmed
    }

    private static func typeName(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: "a string"
        case is Double.Type, is Int.Type: "a number"
        case is Bool.Type: "true or false"
        case is [Any].Type: "an array"
        default: "an object"
        }
    }
}
