import Foundation
import Testing
@testable import FocusDockCore

/// The repo's `schemas/`, as the app finds it under `$FOCUSDOCK_RESOURCES`.
let repoSchemas = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "schemas")

private func parse(_ json: String) throws(ConfigError) -> ModesConfig {
    try ModesConfig.parse(Data(json.utf8), schemas: repoSchemas)
}

private func errors(_ json: String) -> [ConfigProblem] {
    do {
        _ = try parse(json)
        return []
    } catch {
        return error.items
    }
}

/// `path: message`, without the file and position.
private func problems(_ json: String) -> [String] {
    errors(json).map { ConfigProblem(path: $0.path, message: $0.message).description }
}

private func mode(_ id: String, _ extra: String = "") -> String {
    ##"{"id":"\##(id)","name":"N","symbol":"pencil","color":"#D9822B","workspace":"W"\##(extra)}"##
}

private func config(_ modes: String..., extra: String = "") -> String {
    #"{"version":1\#(extra),"modes":[\#(modes.joined(separator: ","))]}"#
}

struct ConfigDecodingTests {
    @Test func decodesTheSpecExample() throws {
        let json = """
        {"version": 1, "initialMode": "writing", "modes": [{
          "id": "writing", "name": "Writing", "symbol": "pencil", "color": "#D9822B", "workspace": "W",
          "apps": ["com.google.Chrome", "notion.id"],
          "webApps": [{ "name": "Drive", "url": "https://drive.google.com" }],
          "focus": "Writing",
          "exit": { "delaySeconds": 10, "perPressSeconds": 3, "to": { "writing": 30 } },
          "allow": "Long-form writing", "private": true
        }]}
        """
        let config = try parse(json)
        let writing = try #require(config.mode("writing"))
        #expect(config.initialMode == "writing")
        #expect(writing.apps == ["com.google.Chrome", "notion.id"])
        #expect(writing.webApps == [WebApp(name: "Drive", url: URL(string: "https://drive.google.com")!)])
        #expect(writing.focus == "Writing")
        #expect(writing.exit == ExitPolicy(delaySeconds: 10, perPressSeconds: 3, to: ["writing": 30]))
        #expect(writing.exit.delay(to: "writing") == 30 && writing.exit.delay(to: "other") == 10)
        #expect(writing.isPrivate)
    }

    @Test func optionalFieldsDefault() throws {
        let only = try #require(try parse(config(mode("a"))).modes.first)
        #expect(only.apps.isEmpty && only.webApps.isEmpty)
        #expect(only.focus == nil && only.allow == nil && !only.isPrivate)
        #expect(only.exit == .free)
        let partialExit = try parse(config(mode("a", #","exit":{"delaySeconds":5}"#))).modes[0].exit
        #expect(partialExit == ExitPolicy(delaySeconds: 5, perPressSeconds: 0, to: [:]))
    }

    @Test func fallbackModeIsInitialModeElseFirst() throws {
        #expect(try parse(config(mode("a"), mode("b"), extra: #","initialMode":"b""#)).fallbackModeID == "b")
        #expect(try parse(config(mode("a"), mode("b"))).fallbackModeID == "a")
    }

    @Test func roundTripsThroughEncoding() throws {
        let original = DefaultModes.make { _ in true }
        #expect(try ModesConfig.parse(original.encoded(), schemas: repoSchemas) == original)
    }

    @Test func acceptsCommentsTrailingCommasAndNullForAbsent() throws {
        let jsonc = """
        // modes
        {
          "version": 1, /* v1 */
          "initialMode": null,
          "modes": [{"id": "a", "name": "N", "symbol": "s", "color": "#000000", "workspace": "W",
                     "apps": null, "focus": null, "exit": {"delaySeconds": null, "to": null}, "private": null,},],
        }
        """
        let only = try #require(try parse(jsonc).modes.first)
        #expect(only.apps.isEmpty && only.focus == nil && only.exit == .free && !only.isPrivate)
    }

    @Test func parsesHexColours() {
        #expect(RGB(hex: "#FF8000") == RGB(hex: "#ff8000"))
        #expect(RGB(hex: "#FF8000")?.red == 1 && RGB(hex: "#FF8000")?.blue == 0)
        for bad in ["FF8000", "#FF800", "#FF80001", "#GG8000", ""] { #expect(RGB(hex: bad) == nil) }
    }
}

struct ConfigValidationTests {
    @Test func rejectsInvalidJSONWithAReadableMessage() {
        let found = errors(#"{"version": 1, "modes": [}"#)
        #expect(found.map(\.description) == ["modes.json:1:26 not valid JSON: expected a value but found }"])
    }

    @Test func namesTheMissingKeyWithItsPath() {
        #expect(problems(#"{"version":1,"modes":[{"id":"a"}]}"#) == [
            "modes[0].name: missing", "modes[0].symbol: missing", "modes[0].color: missing", "modes[0].workspace: missing",
        ])
        #expect(problems(#"{"modes":[]}"#) == ["version: missing", "modes: must not be empty"])
    }

    @Test func namesTypeMismatches() {
        #expect(problems(config(mode("a", #","apps":"com.x""#))) == ["modes[0].apps: expected an array"])
        #expect(problems(config(mode("a", #","exit":{"delaySeconds":"ten"}"#))) == ["modes[0].exit.delaySeconds: expected a number"])
    }

    @Test func requiresVersionOneAndAtLeastOneMode() {
        #expect(problems(#"{"version":2,"modes":[]}"#) == ["version: must be 1, found 2", "modes: must not be empty"])
    }

    @Test func rejectsDuplicateIDs() {
        #expect(problems(config(mode("a"), mode("a"))) == [#"modes[1].id: "a" is used by an earlier mode"#])
    }

    @Test func rejectsUnknownExitTargetsAndInitialMode() {
        let found = problems(config(mode("a", #","exit":{"to":{"socal":30}}"#), extra: #","initialMode":"zzz""#))
        #expect(found == [#"initialMode: no mode has id "zzz""#, #"modes[0].exit.to.socal: no mode has id "socal""#])
    }

    @Test func rejectsBadColours() {
        let found = problems(config(#"{"id":"a","name":"N","symbol":"s","color":"orange","workspace":"W"}"#))
        #expect(found == ["modes[0].color: must be a #RRGGBB colour"])
    }

    @Test func rejectsNegativeDelays() {
        let exit = #","exit":{"delaySeconds":-1,"perPressSeconds":-2,"to":{"a":-3}}"#
        #expect(problems(config(mode("a", exit))) == [
            "modes[0].exit.delaySeconds: must be >= 0",
            "modes[0].exit.perPressSeconds: must be >= 0",
            "modes[0].exit.to.a: must be >= 0",
        ])
    }

    @Test func rejectsEmptyRequiredStrings() {
        let found = problems(config(##"{"id":"","name":" ","symbol":"s","color":"#000000","workspace":""}"##))
        #expect(found == ["modes[0].id: must not be empty", "modes[0].name: must not be empty", "modes[0].workspace: must not be empty"])
    }

    @Test func rejectsNonWebURLsAndEmptyApps() {
        let extra = #","apps":[""],"webApps":[{"name":"","url":"file:///etc/passwd"}]"#
        #expect(problems(config(mode("a", extra))) == [
            "modes[0].apps[0]: must not be empty",
            "modes[0].webApps[0].name: must not be empty",
            "modes[0].webApps[0].url: must be an http(s) URL",
        ])
        let unparsable = #","webApps":[{"name":"W","url":"https://a b"}]"#
        #expect(problems(config(mode("a", unparsable))) == ["modes[0].webApps[0].url: Invalid URL string."])
    }

    @Test func reportsEveryStructuralProblemAtOnceWithItsPosition() {
        let broken = """
        {
          "version": 1,
          "modes": [
            { "id": "writing", "name": "Writing", "symbol": "pencil", "color": "#D9822B", "workspace": "W" },
            {
              "id": "social", "name": "", "symbol": "bubble",
              "color": "orange",
              "workspace": "S",
              "exit": { "delaySeconds": -5 }
            }
          ]
        }
        """
        #expect(errors(broken).map(\.description) == [
            "modes.json:6:31 modes[1].name: must not be empty",
            "modes.json:7:16 modes[1].color: must be a #RRGGBB colour",
            "modes.json:9:33 modes[1].exit.delaySeconds: must be >= 0",
        ])
    }

    @Test func placesCrossReferenceProblemsAtTheirValueAndMissingKeysAtTheirObject() {
        let text = """
        {"version": 1, "modes": [
          {"id": "a", "name": "N", "symbol": "s", "color": "#000000", "workspace": "W", "exit": {"to": {"b": 3}}},
          {"id": "a", "name": "N", "symbol": "s", "color": "#000000", "workspace": "W"}
        ]}
        """
        #expect(errors(text).map(\.description) == [
            #"modes.json:2:102 modes[0].exit.to.b: no mode has id "b""#,
            #"modes.json:3:10 modes[1].id: "a" is used by an earlier mode"#,
        ])
        #expect(errors(#"{"version": 1, "modes": [{"id": "a"}]}"#).first?.description == "modes.json:1:26 modes[0].name: missing")
    }

    @Test func aMissingSchemaIsAnErrorNotASilentPass() {
        let nowhere = URL(filePath: "/nonexistent/schemas")
        #expect(throws: ConfigError.self) { try ModesConfig.parse(Data(config(mode("a")).utf8), schemas: nowhere) }
        do {
            _ = try ModesConfig.parse(Data(config(mode("a")).utf8), schemas: nowhere)
        } catch {
            #expect(error.items.count == 1)
            #expect(error.problems[0].hasPrefix("modes.json cannot load schema /nonexistent/schemas/modes.schema.json"))
        }
    }

    @Test func keepsPlainProblemsForReadErrors() {
        #expect(ConfigError(["cannot read /Users/example/x"]).problems == ["cannot read /Users/example/x"])
    }
}

struct DefaultModesTests {
    @Test func keepsOnlyInstalledAppsInCandidateOrder() {
        let installed: Set = ["com.apple.Notes", "dev.zed.Zed", "com.hnc.Discord"]
        let config = DefaultModes.make { installed.contains($0) }
        #expect(config.modes.map(\.id) == ["writing", "building", "social"])
        #expect(config.modes.map(\.workspace) == ["W", "B", "S"])
        #expect(config.modes.map(\.apps) == [["com.apple.Notes"], ["dev.zed.Zed"], ["com.hnc.Discord"]])
        #expect(config.modes.allSatisfy { $0.webApps.isEmpty })
    }

    @Test func addsWebAppsOnlyWithChrome() {
        let config = DefaultModes.make { $0 == WebApp.chromeBundleID }
        #expect(config.mode("writing")?.webApps.map(\.name) == ["Drive"])
        #expect(config.mode("building")?.webApps.map(\.name) == ["GitHub"])
        #expect(config.mode("social")?.webApps.isEmpty == true)
    }

    @Test func focusModesHaveFrictionAndSocialIsFree() throws {
        let config = DefaultModes.make { _ in false }
        for id in ["writing", "building"] {
            #expect(config.mode(id)?.exit == ExitPolicy(delaySeconds: 10, perPressSeconds: 3, to: ["social": 30]))
        }
        #expect(config.mode("social")?.exit == .free)
        #expect(config.initialMode == "writing")
        #expect(try ModesConfig.parse(config.encoded(), schemas: repoSchemas) == config)
    }
}
