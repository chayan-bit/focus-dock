import Foundation
import Testing
@testable import FocusDockCore

private func parse(_ text: String) throws(ConfigError) -> ShellConfig {
    try ShellConfig.parse(Data(text.utf8), schemas: repoSchemas)
}

private func problems(_ text: String) -> [String] {
    do {
        _ = try parse(text)
        return []
    } catch {
        return error.problems
    }
}

private func motion(_ body: String) -> String { #"{"version":2,"motion":{\#(body)}}"# }

struct ShellConfigTests {
    @Test func parsesTheSpecExample() throws {
        let text = """
        {
          "version": 2,
          "spaces": { "engine": "native", "count": 6, "tiler": { "default": "columns", "gaps": 8 } },
          "bar": { "height": 32, "left": ["mode", "spaces", "appMenu"] },
          "dock": { "magnify": true },
          "motion": {
            "speed": 1.0, "reduceMotion": "system",
            "defaults": { "spring": { "response": 0.35, "damping": 0.86 },
                          "spaceSlide": { "response": 0.52, "damping": 0.91 } },
            "elements": {
              "workspace.switch": { "via": "dockSwipe", "velocity": 1.0 },
              "workspace.jump":   { "via": "dockSwipe", "velocity": 9999 },
              "overview.open":    { "duration": 0.27, "curve": "easeOut" },
              "dock.magnify":     { "spring": { "response": 0.12, "damping": 0.75 } },
              "window.move":      { "via": "proxy", "duration": 0.22, "curve": "easeInOutCos" },
              "card.enter":       { "spring": { "response": 0.4, "damping": 0.75 } } } }
        }
        """
        let config = try parse(text)
        #expect(config.version == 2)
        #expect(config.motion.speed == 1)
        #expect(config.motion.defaults["spaceSlide"] == .spring(response: 0.52, damping: 0.91))
        #expect(config.motion.elements[.overviewOpen] == .timed(duration: 0.27, curve: .easeOut))
        #expect(config.motion.elements[.windowMove] == .proxy(duration: 0.22, curve: .easeInOutCos))
        #expect(config.motion.elements[.workspaceJump] == .dockSwipe(velocity: 9999))
    }

    @Test func acceptsEveryMotionShape() throws {
        let config = try parse(motion(#"""
        "elements": {
          "dock.reveal": { "duration": 0.4, "curve": { "bezier": [0.2, 0, 0.1, 1] } },
          "bar.reveal": { "via": "crossFade", "duration": 0.2 },
          "card.exit": { "via": "instant" }
        }
        """#))
        #expect(config.motion.elements[.dockReveal] == .timed(duration: 0.4, curve: .bezier(0.2, 0, 0.1, 1)))
        #expect(config.motion.elements[.barReveal] == .crossFade(duration: 0.2))
        #expect(config.motion.elements[.cardExit] == .instant)
    }

    @Test func aMissingMotionSectionMeansDefaults() throws {
        #expect(try parse(#"{"version":2}"#).motion == MotionConfig())
    }

    @Test func unknownTopLevelSectionsAreAccepted() throws {
        #expect(try parse(#"{"version":2,"future":{"anything":[1,2]},"bar":3}"#).motion == MotionConfig())
    }

    @Test func aTypoInAMotionElementKeyIsPlaced() {
        let text = "{\n  \"version\": 2,\n  \"motion\": { \"elements\": {\n    \"dock.revael\": { \"duration\": 0.4, \"curve\": \"easeOut\" }\n  } }\n}"
        #expect(problems(text) == ["shell.jsonc:4:20 motion.elements.dock.revael: unknown key"])
    }

    @Test func aMisspelledMotionMemberIsPlaced() {
        #expect(problems(motion(#""spedd": 1"#)) == ["shell.jsonc:1:33 motion.spedd: unknown key"])
    }

    @Test func aBrokenElementIsPlacedAtItsOwnMember() {
        let found = problems(motion(#""elements": {"card.exit": {"duration": 0.3, "curve": "easeOutt"}, "bar.reveal": {"via": "crossFade"}}"#))
        #expect(found.count == 2)
        #expect(found[0].hasPrefix("shell.jsonc:1:") && found[0].contains("motion.elements.card.exit.curve: must be one of"))
        #expect(found[1].contains("motion.elements.bar.reveal.duration: missing"))
    }

    @Test(arguments: [
        (#""speed": -1"#, "shell.jsonc:1:33 motion.speed: must be >= 0"),
        (#""reduceMotion": "sometimes""#, #"shell.jsonc:1:40 motion.reduceMotion: must be one of "system", "always", "never""#),
        (#""elements": {"overview.open": {"duration": -0.2, "curve": "easeOut"}}"#, "shell.jsonc:1:67 motion.elements.overview.open.duration: must be >= 0"),
        (#""defaults": {"spring": {"response": 0, "damping": 0.5}}"#, "shell.jsonc:1:60 motion.defaults.spring.response: must be > 0"),
        (#""defaults": {"spring": {"response": 0.3, "damping": 1.5}}"#, "shell.jsonc:1:76 motion.defaults.spring.damping: must be <= 1"),
        (#""defaults": {"spring": {"response": 0.3, "damping": 0}}"#, "shell.jsonc:1:76 motion.defaults.spring.damping: must be > 0"),
    ])
    func outOfRangeValuesAreReportedWithAPosition(body: String, expected: String) {
        #expect(problems(motion(body)) == [expected])
    }

    @Test func reportsEveryProblemInFileOrder() {
        let found = problems("{\n \"version\": 2,\n \"motion\": {\n  \"speed\": -1,\n  \"reduceMotion\": \"x\"\n }\n}")
        #expect(found.map { $0.prefix(16) } == ["shell.jsonc:4:12", "shell.jsonc:5:19"])
    }

    @Test func aWrongVersionIsReported() {
        #expect(problems(#"{"version":1}"#) == ["shell.jsonc:1:12 version: must be 2, found 1"])
    }

    @Test func aMissingFileDefaultsAreTheEmptyConfig() {
        #expect(ShellConfig() == ShellConfig(version: 2, motion: MotionConfig()))
    }
}
