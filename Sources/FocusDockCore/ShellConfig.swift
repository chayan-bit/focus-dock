import Foundation

/// `~/.config/focusdock/shell.jsonc` (SHELL-SPEC 7). Only `motion` is read today; every other
/// section is accepted and ignored until its surface lands. A missing `motion` means defaults.
public struct ShellConfig: Codable, Equatable, Sendable {
    public static let currentVersion = 2
    public static let fileName = "shell.jsonc"

    public let version: Int
    public let motion: MotionConfig

    public init(version: Int = currentVersion, motion: MotionConfig = MotionConfig()) {
        self.version = version
        self.motion = motion
    }

    private enum CodingKeys: String, CodingKey { case version, motion }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try c.decode(Int.self, forKey: .version),
            motion: try c.decodeIfPresent(MotionConfig.self, forKey: .motion) ?? MotionConfig()
        )
    }

    /// `schemas` defaults to the shipped `schemas/` (`ShippedResources`).
    public static func document(schemas: URL = ShippedResources.schemas) -> ConfigDocument<ShellConfig> {
        ConfigDocument(fileName: fileName, schema: schemas.appending(path: "shell.schema.json"))
    }

    /// Structure and value ranges live in `schemas/shell.schema.json`.
    public static func parse(_ data: Data, schemas: URL = ShippedResources.schemas) throws(ConfigError) -> ShellConfig {
        try document(schemas: schemas).parse(data)
    }
}
