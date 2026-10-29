import Foundation
import Testing
@testable import FocusDockCore

private func positions(_ text: String) throws(ConfigProblem) -> [String: String] {
    try JSONCPositions.index(text).mapValues { "\($0.line):\($0.column)" }
}

private func syntaxError(_ text: String) -> ConfigProblem? {
    do {
        _ = try JSONCPositions.index(text)
        return nil
    } catch {
        return error
    }
}

struct JSONCPositionsTests {
    @Test func indexesEveryValueByJSONPointerAtItsFirstCharacter() throws {
        let text = """
        {
          "version": 1,
          "modes": [
            { "id": "a", "apps": ["x", "y"] },
            { "id": "b" }
          ]
        }
        """
        #expect(try positions(text) == [
            "": "1:1", "/version": "2:14", "/modes": "3:12",
            "/modes/0": "4:5", "/modes/0/id": "4:13", "/modes/0/apps": "4:26", "/modes/0/apps/0": "4:27", "/modes/0/apps/1": "4:32",
            "/modes/1": "5:5", "/modes/1/id": "5:13",
        ])
    }

    @Test func skipsLineAndBlockCommentsButNotSlashesInStrings() throws {
        let text = """
        // header { "not": "a key" }
        {
          /* block
             "still": "comment" */ "url": "https://example.com", // trailing
          "n": /* inline */ 2
        }
        """
        #expect(try positions(text) == ["": "2:1", "/url": "4:35", "/n": "5:21"])
    }

    @Test func acceptsTrailingCommas() throws {
        #expect(try positions(#"{"a": [1, 2,], "b": {"c": true,},}"#) == [
            "": "1:1", "/a": "1:7", "/a/0": "1:8", "/a/1": "1:11", "/b": "1:21", "/b/c": "1:27",
        ])
    }

    @Test func unescapesKeysAndEscapesThemAsPointerTokens() throws {
        let found = try positions(#"{"a/b": 1, "m~n": 2, "q\"\u0041": 3, "": 4}"#)
        #expect(found == ["": "1:1", "/a~1b": "1:9", "/m~0n": "1:19", "/q\"A": "1:35", "/": "1:42"])
    }

    @Test func countsColumnsInCharactersNotBytes() throws {
        #expect(try positions(#"{"é": "日本", "k": null}"#)["/k"] == "1:18")
    }

    @Test func indexesScalarAndEmptyRoots() throws {
        #expect(try positions("  42 ") == ["": "1:3"])
        #expect(try positions("[]") == ["": "1:1"])
        #expect(try positions("{ }") == ["": "1:1"])
    }

    @Test(arguments: [
        ("{\n  \"a\": \"open\n}", 2, 8, "not valid JSON: unterminated string"),
        ("{\"a\": 1", 1, 8, "not valid JSON: expected , or } but found the end of the file"),
        ("[1, 2", 1, 6, "not valid JSON: expected , or ] but found the end of the file"),
        ("{} /* never closed", 1, 4, "not valid JSON: unterminated comment"),
        ("", 1, 1, "not valid JSON: expected a value but found the end of the file"),
        ("{\"a\": tru}", 1, 7, "not valid JSON: \"tru\" is not a value"),
        ("{\"a\": 01}", 1, 7, "not valid JSON: \"01\" is not a value"),
        ("{\"a\" 1}", 1, 6, "not valid JSON: expected : but found 1"),
        ("{a: 1}", 1, 2, "not valid JSON: expected a quoted key but found a"),
        ("{\"a\": 1 \"b\": 2}", 1, 9, "not valid JSON: expected , or } but found \""),
        ("[1,,2]", 1, 4, "not valid JSON: expected a value but found ,"),
        ("{} {}", 1, 4, "not valid JSON: expected the end of the file but found {"),
        ("{\"a\": \"\\x\"}", 1, 7, "not valid JSON: invalid escape or control character in string"),
    ])
    func reportsSyntaxErrorsWithTheirPosition(text: String, line: Int, column: Int, message: String) throws {
        let problem = try #require(syntaxError(text))
        #expect(problem.line == line)
        #expect(problem.column == column)
        #expect(problem.message == message)
        #expect(problem.path.isEmpty)
    }

    @Test func rejectsNestingDeeperThanTheLimit() throws {
        let deep = String(repeating: "[", count: 10_000)
        let problem = try #require(syntaxError(deep))
        #expect(problem.message == "not valid JSON: nested deeper than \(JSONCPositions.maximumDepth) levels")
        #expect(try positions(String(repeating: "[", count: 20) + String(repeating: "]", count: 20)).count == 20)
    }
}

struct ConfigProblemTests {
    @Test func describesFileLineColumnPathAndMessage() {
        #expect(ConfigProblem(file: "shell.jsonc", line: 12, column: 5, path: "motion.speed", message: "must be >= 0").description
            == "shell.jsonc:12:5 motion.speed: must be >= 0")
        #expect(ConfigProblem(file: "modes.json", line: 2, column: 1, path: "", message: "not valid JSON: x").description
            == "modes.json:2:1 not valid JSON: x")
        #expect(ConfigProblem(file: "modes.json", path: "modes", message: "m").description == "modes.json modes: m")
        #expect(ConfigProblem(message: "cannot read /Users/example/x").description == "cannot read /Users/example/x")
    }
}
