import Foundation
import Testing
@testable import FocusDockCore

private func parse(_ json: String) throws(ConfigError) -> ModesConfig {
    try ModesConfig.parse(Data(json.utf8))
}

private func problems(_ json: String) -> [String] {
    do {
        _ = try parse(json)
        return []
    } catch {
        return error.problems
    }
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
        #expect(try ModesConfig.parse(original.encoded()) == original)
    }

    @Test func parsesHexColours() {
        #expect(RGB(hex: "#FF8000") == RGB(hex: "#ff8000"))
        #expect(RGB(hex: "#FF8000")?.red == 1 && RGB(hex: "#FF8000")?.blue == 0)
        for bad in ["FF8000", "#FF800", "#FF80001", "#GG8000", ""] { #expect(RGB(hex: bad) == nil) }
    }
}

struct ConfigValidationTests {
    @Test func rejectsInvalidJSONWithAReadableMessage() {
        let found = problems(#"{"version": 1, "modes": [}"#)
        #expect(found.count == 1)
        #expect(found[0].hasPrefix("not valid JSON"))
    }

    @Test func namesTheMissingKeyWithItsPath() {
        #expect(problems(#"{"version":1,"modes":[{"id":"a"}]}"#) == ["modes[0].name: missing"])
        #expect(problems(#"{"modes":[]}"#) == ["version: missing"])
    }

    @Test func namesTypeMismatches() {
        #expect(problems(config(mode("a", #","apps":"com.x""#))) == ["modes[0].apps: expected an array"])
        #expect(problems(config(mode("a", #","exit":{"delaySeconds":"ten"}"#))) == ["modes[0].exit.delaySeconds: expected a number"])
    }

    @Test func requiresVersionOneAndAtLeastOneMode() {
        #expect(problems(#"{"version":2,"modes":[]}"#) == ["version: must be 1, found 2", "modes: at least one mode is required"])
    }

    @Test func rejectsDuplicateIDs() {
        #expect(problems(config(mode("a"), mode("a"))) == [#"modes[1].id: "a" is used by an earlier mode"#])
    }

    @Test func rejectsUnknownExitTargetsAndInitialMode() {
        let found = problems(config(mode("a", #","exit":{"to":{"socal":30}}"#), extra: #","initialMode":"zzz""#))
        #expect(found == [#"modes[0].exit.to.socal: no mode has id "socal""#, #"initialMode: no mode has id "zzz""#])
    }

    @Test func rejectsBadColours() {
        let found = problems(config(#"{"id":"a","name":"N","symbol":"s","color":"orange","workspace":"W"}"#))
        #expect(found == [##"modes[0].color: "orange" is not a #RRGGBB colour"##])
    }

    @Test func rejectsNegativeDelays() {
        let exit = #","exit":{"delaySeconds":-1,"perPressSeconds":-2,"to":{"a":-3}}"#
        #expect(problems(config(mode("a", exit))) == [
            "modes[0].exit.delaySeconds: must not be negative",
            "modes[0].exit.perPressSeconds: must not be negative",
            "modes[0].exit.to.a: must not be negative",
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
            #"modes[0].webApps[0].url: "file:///etc/passwd" is not an http(s) URL"#,
        ])
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

    @Test func focusModesHaveFrictionAndSocialIsFree() {
        let config = DefaultModes.make { _ in false }
        for id in ["writing", "building"] {
            #expect(config.mode(id)?.exit == ExitPolicy(delaySeconds: 10, perPressSeconds: 3, to: ["social": 30]))
        }
        #expect(config.mode("social")?.exit == .free)
        #expect(config.initialMode == "writing")
        #expect(ConfigValidation.problems(in: config).isEmpty)
    }
}
