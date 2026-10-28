import Foundation
import Testing
@testable import FocusDockCore

private let config = ModesConfig(initialMode: nil, modes: [
    Mode(id: "writing", name: "Writing", symbol: "pencil", color: "#000000", workspace: "W",
         apps: ["com.apple.Notes", "com.apple.TextEdit"],
         webApps: [WebApp(name: "Drive", url: URL(string: "https://drive.google.com")!)]),
    Mode(id: "building", name: "Building", symbol: "hammer", color: "#000000", workspace: "B",
         apps: ["dev.zed.Zed", "com.apple.TextEdit", "com.google.Chrome"]),
    Mode(id: "social", name: "Social", symbol: "bubble", color: "#000000", workspace: "S", apps: ["com.hnc.Discord"]),
])

struct WindowRoutingTests {
    @Test func appInOneModeGoesToThatModesWorkspace() {
        #expect(WindowRouting.workspace(forBundleID: "dev.zed.Zed", config: config, currentModeID: "social") == "B")
    }

    @Test func appInSeveralModesGoesToTheCurrentModesWorkspace() {
        #expect(WindowRouting.workspace(forBundleID: "com.apple.TextEdit", config: config, currentModeID: "building") == "B")
        #expect(WindowRouting.workspace(forBundleID: "com.apple.TextEdit", config: config, currentModeID: "writing") == "W")
    }

    @Test func webAppsMakeChromeBelongToTheirMode() {
        #expect(WindowRouting.workspace(forBundleID: "com.google.Chrome", config: config, currentModeID: "writing") == "W")
    }

    @Test func appInNoModeIsLeftAlone() {
        #expect(WindowRouting.workspace(forBundleID: "com.apple.calculator", config: config, currentModeID: "writing") == nil)
        #expect(WindowRouting.workspace(forBundleID: nil, config: config, currentModeID: "writing") == nil)
        #expect(WindowRouting.workspace(forBundleID: "", config: config, currentModeID: "writing") == nil)
    }

    @Test func movesOnlyWindowsThatAreNotAlreadyThere() {
        let zed = WindowDetected(windowId: 42, workspace: "W", appBundleId: "dev.zed.Zed", appName: "Zed")
        #expect(WindowRouting.moveArguments(for: zed, config: config, currentModeID: "writing")
            == ["move-node-to-workspace", "--window-id", "42", "B"])
        let settled = WindowDetected(windowId: 42, workspace: "B", appBundleId: "dev.zed.Zed", appName: "Zed")
        #expect(WindowRouting.moveArguments(for: settled, config: config, currentModeID: "writing") == nil)
    }
}

struct WindowDetectedParsingTests {
    @Test func parsesWindowDetectedLines() {
        let line = #"{"_event":"window-detected","windowId":28218,"workspace":"M","appBundleId":"com.apple.TextEdit","appName":"TextEdit"}"#
        #expect(WindowDetected.parse(line: line)
            == WindowDetected(windowId: 28218, workspace: "M", appBundleId: "com.apple.TextEdit", appName: "TextEdit"))
    }

    @Test func toleratesMissingOptionalFields() {
        #expect(WindowDetected.parse(line: #"{"_event":"window-detected","windowId":7}"#)
            == WindowDetected(windowId: 7, workspace: nil, appBundleId: nil, appName: nil))
    }

    @Test func ignoresOtherEventsAndGarbage() {
        #expect(WindowDetected.parse(line: #"{"_event":"focus-changed","windowId":28218,"workspace":"M"}"#) == nil)
        #expect(WindowDetected.parse(line: #"{"_event":"window-detected"}"#) == nil)
        #expect(WindowDetected.parse(line: "not json") == nil)
        #expect(WindowDetected.parse(line: "") == nil)
    }
}

struct AeroSpaceLocatorTests {
    @Test func searchesPathThenNixProfilesWithoutDuplicates() {
        let candidates = AeroSpaceLocator.candidates(path: "/usr/bin:/run/current-system/sw/bin::/bin", user: "me")
        #expect(candidates == [
            "/usr/bin/aerospace", "/run/current-system/sw/bin/aerospace", "/bin/aerospace",
            "/etc/profiles/per-user/me/bin/aerospace", "/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace",
        ])
    }

    @Test func findsTheFirstExecutable() {
        let found = AeroSpaceLocator.find(path: "/usr/bin", user: "me") { $0 == "/etc/profiles/per-user/me/bin/aerospace" }
        #expect(found == "/etc/profiles/per-user/me/bin/aerospace")
        #expect(AeroSpaceLocator.find(path: nil, user: "me") { _ in false } == nil)
    }
}

struct FocusShortcutsTests {
    private let focusConfig = ModesConfig(initialMode: nil, modes: [
        Mode(id: "w", name: "W", symbol: "s", color: "#000000", workspace: "W", focus: "Writing"),
        Mode(id: "b", name: "B", symbol: "s", color: "#000000", workspace: "B", focus: "Writing"),
        Mode(id: "s", name: "S", symbol: "s", color: "#000000", workspace: "S"),
    ])

    @Test func runsTheFocusShortcutOrOffOnlyWhenItExists() {
        let available: Set = ["FocusDock Writing", "FocusDock Off"]
        #expect(FocusShortcuts.shortcut(for: focusConfig.modes[0], available: available) == "FocusDock Writing")
        #expect(FocusShortcuts.shortcut(for: focusConfig.modes[2], available: available) == "FocusDock Off")
        #expect(FocusShortcuts.shortcut(for: focusConfig.modes[0], available: []) == nil)
    }

    @Test func reportsEachMissingShortcutOnce() {
        #expect(FocusShortcuts.missing(in: focusConfig, available: []) == ["FocusDock Writing", "FocusDock Off"])
        #expect(FocusShortcuts.missing(in: focusConfig, available: ["FocusDock Off"]) == ["FocusDock Writing"])
    }

    @Test func offIsNotNeededWithoutAnyFocus() {
        let noFocus = ModesConfig(initialMode: nil, modes: [focusConfig.modes[2]])
        #expect(FocusShortcuts.missing(in: noFocus, available: []).isEmpty)
    }

    @Test func parsesShortcutsListOutput() {
        #expect(FocusShortcuts.parseList("FocusDock Off\n  Morning  \n\nFocusDock Writing\n") == ["FocusDock Off", "Morning", "FocusDock Writing"])
    }
}
