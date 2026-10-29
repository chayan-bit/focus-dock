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
    public static let fileName = "modes.json"

    /// `schemas` defaults to the shipped `schemas/` (`ShippedResources`).
    public static func document(schemas: URL = ShippedResources.schemas) -> ConfigDocument<ModesConfig> {
        ConfigDocument(fileName: fileName, schema: schemas.appending(path: "modes.schema.json"), semantic: ConfigValidation.problems(in:))
    }

    /// Structure and value rules live in `schemas/modes.schema.json`; cross-references are checked here.
    public static func parse(_ data: Data, schemas: URL = ShippedResources.schemas) throws(ConfigError) -> ModesConfig {
        try document(schemas: schemas).parse(data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// The checks `schemas/modes.schema.json` cannot express: references between modes.
enum ConfigValidation {
    static func problems(in config: ModesConfig) -> [ConfigProblem] {
        var problems: [ConfigProblem] = []
        let ids = Set(config.modes.map(\.id))
        var seen: Set<String> = []
        for (index, mode) in config.modes.enumerated() {
            if !seen.insert(mode.id).inserted {
                problems.append(ConfigProblem(path: "modes[\(index)].id", message: "\"\(mode.id)\" is used by an earlier mode"))
            }
            for target in mode.exit.to.keys.sorted() where !ids.contains(target) {
                problems.append(ConfigProblem(path: "modes[\(index)].exit.to.\(target)", message: "no mode has id \"\(target)\""))
            }        }
        if let initial = config.initialMode, !ids.contains(initial) {
            problems.append(ConfigProblem(path: "initialMode", message: "no mode has id \"\(initial)\""))
        }
        return problems
    }
}
