import Foundation
import Testing
@testable import FocusDockCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

private let focusExit = ExitPolicy(delaySeconds: 10, perPressSeconds: 3, to: ["social": 30])

private func modes(_ list: [Mode], initial: String? = nil) -> ModesConfig {
    ModesConfig(initialMode: initial, modes: list)
}

private func mode(_ id: String, exit: ExitPolicy = .free) -> Mode {
    Mode(id: id, name: id.capitalized, symbol: "circle", color: "#000000", workspace: id.uppercased(), exit: exit)
}

private let config = modes([mode("writing", exit: focusExit), mode("building", exit: focusExit), mode("social")])

private func machine(_ id: String = "writing") -> ModeMachine { ModeMachine(config: config, restoredModeID: id) }

struct ModeMachineTests {
    @Test func startsInRestoredModeElseInitialElseFirst() {
        #expect(ModeMachine(config: config, restoredModeID: "social").state == .active("social"))
        #expect(ModeMachine(config: modes(config.modes, initial: "building"), restoredModeID: "gone").state == .active("building"))
        #expect(ModeMachine(config: config, restoredModeID: nil).state == .active("writing"))
    }

    @Test func requestWithDelayEntersPendingUsingThePerTargetOverride() {
        let toBuilding = machine().request("building", now: t0)
        #expect(toBuilding.state == .pending(from: "writing", to: "building", deadline: at(10)))
        #expect(toBuilding.activeModeID == "writing")
        #expect(machine().request("social", now: t0).state == .pending(from: "writing", to: "social", deadline: at(30)))
    }

    @Test func zeroDelayActivatesAtOnce() {
        #expect(machine("social").request("writing", now: t0).state == .active("writing"))
    }

    @Test func requestingTheActiveModeOrAnUnknownModeDoesNothing() {
        #expect(machine().request("writing", now: t0) == machine())
        #expect(machine().request("nope", now: t0) == machine())
    }

    @Test func tickActivatesOnlyAtTheDeadline() {
        let pending = machine().request("social", now: t0)
        #expect(pending.tick(now: at(29.9)) == pending)
        #expect(pending.tick(now: at(30)).state == .active("social"))
    }

    @Test func stayCancels() {
        #expect(machine().request("social", now: t0).stay().state == .active("writing"))
    }

    @Test func requestingThePendingTargetAgainCancels() {
        #expect(machine().request("social", now: t0).request("social", now: at(1)).state == .active("writing"))
    }

    @Test func requestingTheModeBeingLeftCancels() {
        #expect(machine().request("social", now: t0).request("writing", now: at(1)).state == .active("writing"))
    }

    @Test func requestingAnotherTargetRestartsTheWait() {
        let retargeted = machine().request("social", now: t0).request("building", now: at(5))
        #expect(retargeted.state == .pending(from: "writing", to: "building", deadline: at(15)))
    }

    @Test func pressShortensByTheLeavingModesPerPress() {
        let pressed = machine().request("social", now: t0).press("social", now: at(1)).press("social", now: at(2))
        #expect(pressed.state == .pending(from: "writing", to: "social", deadline: at(24)))
        #expect(pressed.remainingSeconds(now: at(2)) == 22)
    }

    @Test func pressIsFlooredAtNowAndThenActivates() {
        let nearlyDone = machine().request("building", now: t0).press("building", now: at(8))
        #expect(nearlyDone.state == .active("building"))
    }

    @Test func pressOnANonPendingModeIsARequest() {
        #expect(machine().press("social", now: t0) == machine().request("social", now: t0))
    }

    @Test func remainingSecondsRoundsUp() {
        let pending = machine().request("building", now: t0)
        #expect(pending.remainingSeconds(now: at(0.2)) == 10)
        #expect(pending.remainingSeconds(now: at(9.01)) == 1)
        #expect(machine().remainingSeconds(now: t0) == nil)
    }

    @Test func reloadKeepsAPendingSwitchWhoseModesSurvive() {
        let pending = machine().request("social", now: t0)
        let renamed = modes([mode("writing", exit: .free), mode("social")])
        let reloaded = pending.reloaded(with: renamed)
        #expect(reloaded.state == pending.state)
        #expect(reloaded.config == renamed)
    }

    @Test func reloadCancelsWhenTheTargetDisappears() {
        let pending = machine().request("social", now: t0)
        #expect(pending.reloaded(with: modes([mode("writing"), mode("building")])).state == .active("writing"))
    }

    @Test func reloadFallsBackWhenTheModeBeingLeftDisappears() {
        let pending = machine().request("social", now: t0)
        #expect(pending.reloaded(with: modes([mode("building"), mode("social")], initial: "social")).state == .active("social"))
        #expect(pending.reloaded(with: modes([mode("building"), mode("social")])).state == .active("building"))
    }

    @Test func reloadMovesAnActiveModeThatDisappeared() {
        #expect(machine("building").reloaded(with: modes([mode("writing"), mode("social")])).state == .active("writing"))
        #expect(machine("social").reloaded(with: config).state == .active("social"))
    }

    @Test func countdownFormatsMinutesAndSeconds() {
        #expect(Countdown.format(seconds: 10) == "0:10")
        #expect(Countdown.format(seconds: 75) == "1:15")
        #expect(Countdown.format(seconds: 0) == "0:00")
        #expect(Countdown.format(seconds: -3) == "0:00")
    }
}
