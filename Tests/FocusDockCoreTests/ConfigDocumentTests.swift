import Foundation
import Testing
@testable import FocusDockCore

private struct Sample: Codable, Sendable {
    let speed: Double
    let tags: [String: Int]?
}

private let schemaText = #"""
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["version", "speed"],
  "properties": {
    "version": { "const": 2 },
    "speed": { "type": "number", "minimum": 0, "maximum": 4 },
    "count": { "type": "integer", "exclusiveMinimum": 0 },
    "mode": { "enum": ["always", "never"] },
    "tags": { "type": "object", "additionalProperties": { "type": "integer" } }
  }
}
"""#

/// Writes the schema into `directory`; the caller removes it.
private func document(
    in directory: URL, semantic: @escaping @Sendable (Sample) -> [ConfigProblem] = { _ in [] }
) throws -> ConfigDocument<Sample> {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let schema = directory.appending(path: "sample.schema.json")
    try Data(schemaText.utf8).write(to: schema)
    return ConfigDocument(fileName: "shell.jsonc", schema: schema, semantic: semantic)
}

private func problems(_ text: String, _ document: ConfigDocument<Sample>) -> [String] {
    do {
        _ = try document.parse(Data(text.utf8))
        return []
    } catch {
        return error.problems
    }
}

struct ConfigDocumentTests {
    @Test func turnsSchemaKeywordsIntoReadableMessages() throws {
        let text = """
        {
          "version": 3,
          "speed": 5,
          "count": 0,
          "mode": "sometimes",
          "tags": { "a": "x" }
        }
        """
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(problems(text, try document(in: dir)) == [
            "shell.jsonc:2:14 version: must be 2, found 3",
            "shell.jsonc:3:12 speed: must be <= 4",
            "shell.jsonc:4:12 count: must be > 0",
            #"shell.jsonc:5:11 mode: must be one of "always", "never""#,
            "shell.jsonc:6:18 tags.a: expected an integer",
        ])
    }

    @Test func runsSemanticChecksOnlyOnValidValuesAndPlacesThemAtTheNearestValue() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try document(in: dir) { _ in
            [ConfigProblem(path: "tags.a.b", message: "deep"), ConfigProblem(path: "speed", message: "too slow")]
        }
        #expect(problems(#"{"version": 2, "speed": -1}"#, doc) == ["shell.jsonc:1:25 speed: must be >= 0"])
        #expect(problems(#"{"version": 2, "tags": {"a": 1}, "speed": 1}"#, doc) == [
            "shell.jsonc:1:30 tags.a.b: deep", "shell.jsonc:1:43 speed: too slow",
        ])
    }

    @Test func reportsSyntaxAndEncodingErrorsAgainstTheFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try document(in: dir)
        #expect(problems("{\n  \"speed\": 1,,\n}", doc) == ["shell.jsonc:2:14 not valid JSON: expected a quoted key but found ,"])
        #expect(throws: ConfigError(items: [ConfigProblem(file: "shell.jsonc", message: "not UTF-8 text")])) {
            try doc.parse(Data([0x7B, 0xFF, 0x7D]))
        }
    }

    @Test func roundTripsDisplayPaths() {
        let segments: [ConfigPath.Segment] = [.key("modes"), .index(1), .key("exit"), .key("to"), .key("social")]
        #expect(ConfigPath.display(segments) == "modes[1].exit.to.social")
        #expect(ConfigPath.segments("modes[1].exit.to.social") == segments)
        #expect(ConfigPath.segments("[0][2].a") == [.index(0), .index(2), .key("a")])
        #expect(ConfigPath.segments("") == [])
        #expect(ConfigPath.pointer([.key("a/b"), .key("~"), .index(3)]) == "/a~1b/~0/3")
    }
}
