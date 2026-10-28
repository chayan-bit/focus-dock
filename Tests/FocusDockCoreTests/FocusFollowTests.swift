import Foundation
import Testing
@testable import FocusDockCore

private let t0 = Date(timeIntervalSinceReferenceDate: 2_000_000)
private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

private let focusExit = ExitPolicy(delaySeconds: 10, perPressSeconds: 3, to: ["social": 30])

private func mode(_ id: String, _ workspace: String, exit: ExitPolicy = .free) -> Mode {
    Mode(id: id, name: id, symbol: "circle", color: "#000000", workspace: workspace, exit: exit)
}

private let config = ModesConfig(initialMode: nil, modes: [
    mode("writing", "W", exit: focusExit), mode("building", "B", exit: focusExit), mode("social", "S"),
])

private func machine(_ id: String) -> ModeMachine { ModeMachine(config: config, restoredModeID: id) }

/// A tracker that has seen `workspace` and expects nothing.
private func settled(on workspace: String) -> FocusTracker {
    FocusTracker(expectedWorkspace: nil, focusedWorkspace: workspace, jump: nil)
}

private func focus(_ workspace: String, _ window: UInt32? = 7) -> FocusChanged {
    FocusChanged(windowId: window, workspace: workspace)
}

struct FocusFollowTests {
    @Test func theActiveModesWorkspaceIsNoAction() {
        let outcome = FocusFollow.handle(focus("W"), machine: machine("writing"), tracker: settled(on: "1"), now: t0)
        #expect(outcome.machine == machine("writing"))
        #expect(outcome.bounceTo == nil)
        #expect(outcome.tracker.focusedWorkspace == "W")
    }

    @Test func aWorkspaceOfNoModeIsNoAction() {
        let outcome = FocusFollow.handle(focus("3"), machine: machine("writing"), tracker: settled(on: "W"), now: t0)
        #expect(outcome.machine == machine("writing"))
        #expect(outcome.bounceTo == nil)
    }

    @Test func zeroDelayFollowsTheJump() {
        let outcome = FocusFollow.handle(focus("W"), machine: machine("social"), tracker: settled(on: "S"), now: t0)
        #expect(outcome.machine.state == .active("writing"))
        #expect(outcome.bounceTo == nil)
        #expect(outcome.tracker.jump == nil)
    }

    @Test func aDelayedJumpRequestsAndBouncesBack() {
        let outcome = FocusFollow.handle(focus("S", 42), machine: machine("writing"), tracker: settled(on: "W"), now: t0)
        #expect(outcome.machine.state == .pending(from: "writing", to: "social", deadline: at(30)))
        #expect(outcome.bounceTo == "W")
        #expect(outcome.tracker.jump == JumpTarget(modeID: "social", windowId: 42))
        #expect(outcome.tracker.expectedWorkspace == "W")
    }

    @Test func aJumpToThePendingTargetOnlyBouncesBack() {
        let pending = machine("writing").request("social", now: t0)
        let outcome = FocusFollow.handle(focus("S", 43), machine: pending, tracker: settled(on: "W"), now: at(5))
        #expect(outcome.machine == pending)
        #expect(outcome.bounceTo == "W")
        #expect(outcome.tracker.jump == JumpTarget(modeID: "social", windowId: 43))
    }

    @Test func aJumpToAnotherModeReplacesThePendingTargetWithItsOwnDelay() {
        let pending = machine("writing").request("social", now: t0)
        let outcome = FocusFollow.handle(focus("B", 44), machine: pending, tracker: settled(on: "W"), now: at(5))
        #expect(outcome.machine.state == .pending(from: "writing", to: "building", deadline: at(15)))
        #expect(outcome.bounceTo == "W")
        #expect(outcome.tracker.jump == JumpTarget(modeID: "building", windowId: 44))
    }

    @Test func aWindowlessFocusOnAnotherModeBouncesBackWithoutARequest() {
        let outcome = FocusFollow.handle(focus("S", nil), machine: machine("writing"), tracker: settled(on: "W"), now: t0)
        #expect(outcome.machine == machine("writing"))
        #expect(outcome.bounceTo == "W")
        #expect(outcome.tracker.expectedWorkspace == "W")
        #expect(outcome.tracker.jump == nil)
    }

    @Test func aWindowlessFocusElsewhereIsNoAction() {
        let onActive = FocusFollow.handle(focus("W", nil), machine: machine("writing"), tracker: settled(on: "3"), now: t0)
        #expect(onActive.bounceTo == nil)
        let onNoMode = FocusFollow.handle(focus("3", nil), machine: machine("writing"), tracker: settled(on: "W"), now: t0)
        #expect(onNoMode.bounceTo == nil)
        #expect(onNoMode.machine == machine("writing"))
    }

    @Test func switchingToTheFocusedWorkspaceSetsNoToken() {
        #expect(settled(on: "W").expecting("W").expectedWorkspace == nil)
        #expect(settled(on: "W").expecting("S").expectedWorkspace == "S")
        #expect(FocusTracker.initial.expecting("W").expectedWorkspace == "W")
        #expect(settled(on: "W").expecting("S").commandFailed().expectedWorkspace == nil)
    }
}

/// FocusDock's own workspace switches must never be read back as a user jump.
struct FocusFollowNoLoopTests {
    @Test func staleEventsBeforeTheBounceEchoAreIgnored() {
        let jumped = FocusFollow.handle(focus("S"), machine: machine("writing"), tracker: settled(on: "W"), now: t0)
        let stale = FocusFollow.handle(focus("S"), machine: jumped.machine, tracker: jumped.tracker, now: at(1))
        #expect(stale.machine == jumped.machine)
        #expect(stale.bounceTo == nil)
        let echo = FocusFollow.handle(focus("W"), machine: stale.machine, tracker: stale.tracker, now: at(1))
        #expect(echo.machine == jumped.machine)
        #expect(echo.bounceTo == nil)
        #expect(echo.tracker.expectedWorkspace == nil)
    }

    @Test func activationDoesNotBounceBackToTheModeItLeft() {
        // Countdown to Social completes; FocusDock switches to S. A focus event for W still
        // in flight must not request Writing, which would switch at once (Social exits free).
        let jumped = FocusFollow.handle(focus("S"), machine: machine("writing"), tracker: settled(on: "W"), now: t0)
        let echoed = FocusFollow.handle(focus("W"), machine: jumped.machine, tracker: jumped.tracker, now: at(1))
        let activated = echoed.machine.tick(now: at(30))
        #expect(activated.state == .active("social"))
        let switching = echoed.tracker.expecting("S")
        let stale = FocusFollow.handle(focus("W"), machine: activated, tracker: switching, now: at(30))
        #expect(stale.machine == activated)
        #expect(stale.bounceTo == nil)
        let echo = FocusFollow.handle(focus("S"), machine: stale.machine, tracker: stale.tracker, now: at(30))
        #expect(echo.machine == activated)
        #expect(echo.bounceTo == nil)
        #expect(echo.tracker.expectedWorkspace == nil)
    }

    @Test func withoutTheTokenTheSameStaleEventWouldSwitchBack() {
        let activated = machine("social")
        let unguarded = FocusFollow.handle(focus("W"), machine: activated, tracker: settled(on: "S"), now: t0)
        #expect(unguarded.machine.state == .active("writing"))
    }
}

struct AeroSpaceEventParsingTests {
    @Test func parsesFocusChanged() {
        #expect(AeroSpaceEvent.parse(line: #"{"_event":"focus-changed","windowId":28218,"workspace":"M"}"#)
            == .focusChanged(FocusChanged(windowId: 28218, workspace: "M")))
        #expect(AeroSpaceEvent.parse(line: #"{"_event":"focus-changed","workspace":"3"}"#)
            == .focusChanged(FocusChanged(windowId: nil, workspace: "3")))
    }

    @Test func parsesWindowDetected() {
        let line = #"{"_event":"window-detected","windowId":5,"workspace":"1","appBundleId":"com.x"}"#
        #expect(AeroSpaceEvent.parse(line: line)
            == .windowDetected(WindowDetected(windowId: 5, workspace: "1", appBundleId: "com.x", appName: nil)))
    }

    @Test func ignoresOtherEventsAndMalformedLines() {
        #expect(AeroSpaceEvent.parse(line: #"{"_event":"mode-changed","mode":"main"}"#) == nil)
        #expect(AeroSpaceEvent.parse(line: #"{"_event":"focus-changed"}"#) == nil)
        #expect(AeroSpaceEvent.parse(line: "{") == nil)
    }
}

/// Live E2E: quitting Calculator, the last window on S, while in Social. AeroSpace reported a
/// window on W (the app macOS activated next), then a windowless focus on S.
struct FocusFollowQuitSequenceTests {
    @Test func modeAndWorkspaceEndOnWriting() {
        let quitWindow = FocusFollow.handle(focus("W", 5), machine: machine("social"), tracker: settled(on: "S"), now: t0)
        #expect(quitWindow.machine.state == .active("writing"))
        #expect(quitWindow.bounceTo == nil)
        // ModeController.activate(writing) then asks AeroSpace for W through the token path.
        let activating = quitWindow.tracker.expecting("W")
        let emptyS = FocusFollow.handle(focus("S", nil), machine: quitWindow.machine, tracker: activating, now: t0)
        #expect(emptyS.machine.state == .active("writing"))
        #expect(emptyS.bounceTo == "W")
        let echo = FocusFollow.handle(focus("W", 5), machine: emptyS.machine, tracker: emptyS.tracker, now: t0)
        #expect(echo.machine.state == .active("writing"))
        #expect(echo.bounceTo == nil)
        #expect(echo.tracker.expectedWorkspace == nil)
    }

    @Test func theSameHoldsWhileTheActivationSwitchIsStillExpected() {
        let quitWindow = FocusFollow.handle(focus("W", 5), machine: machine("social"), tracker: settled(on: "S"), now: t0)
        let inFlight = FocusTracker(expectedWorkspace: "W", focusedWorkspace: "W", jump: nil)
        let emptyS = FocusFollow.handle(focus("S", nil), machine: quitWindow.machine, tracker: inFlight, now: t0)
        #expect(emptyS.machine.state == .active("writing"))
        #expect(emptyS.bounceTo == "W")
    }
}
