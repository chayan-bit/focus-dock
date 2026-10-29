import DynamicJSON
import Foundation
import Testing
@testable import FocusDockCore

/// The schema, the Codable shapes (MotionCoding) and the built-in defaults must describe the same files.
struct SchemaDriftTests {
    private func shellSchema() throws -> JSON {
        try JSONDecoder().decode(JSON.self, from: Data(contentsOf: repoSchemas.appending(path: "shell.schema.json")))
    }

    @Test func schemaElementNamesAreTheMotionKeys() throws {
        let schema = try shellSchema()
        let names = try #require(schema["$defs"]?["motion"]?["properties"]?["elements"]?["properties"]?.objectValue?.keys)
        #expect(Set(names) == Set(MotionKey.allCases.map(\.rawValue)))
    }

    @Test func schemaAcceptsEveryBuiltInDefaultAfterARoundTrip() throws {
        let config = ShellConfig(motion: MotionConfig(
            defaults: ["spring": MotionDefaults.spring, "spaceSlide": MotionDefaults.spaceSlide],
            elements: MotionDefaults.table
        ))
        let data = try JSONEncoder().encode(config)
        #expect(try ShellConfig.parse(data, schemas: repoSchemas) == config)
    }

    @Test func schemaAcceptsEverySpecShapeAfterARoundTrip() throws {
        let shapes: [MotionSpec] = [
            .spring(response: 0.4, damping: 0.75),
            .timed(duration: 0.27, curve: .easeOut),
            .timed(duration: 0.4, curve: .bezier(0.2, 0, 0.1, 1)),
            .dockSwipe(velocity: 9999),
            .proxy(duration: 0.22, curve: .easeInOutCos),
            .crossFade(duration: 0.2),
            .instant,
        ]
        let curves: [MotionCurve] = [.linear, .easeIn, .easeOut, .easeInOut, .easeInOutCos, .dockBounce]
        let elements = Dictionary(uniqueKeysWithValues: zip(MotionKey.allCases, shapes + curves.map { .timed(duration: 0.1, curve: $0) }))
        let config = ShellConfig(motion: MotionConfig(speed: 2, reduceMotion: .always, elements: elements))
        let data = try JSONEncoder().encode(config)
        #expect(try ShellConfig.parse(data, schemas: repoSchemas) == config)
    }
}
