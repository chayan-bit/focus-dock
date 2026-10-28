import Foundation
import Testing
@testable import FocusDockCore

struct DockPrimingTests {
    private let writtenAt = 1_000.0
    private let oldDock = ProcessIdentity(pid: 823, startTime: 500.25)
    private let newDock = ProcessIdentity(pid: 4_000, startTime: 1_000.5)

    @Test func restartsAnUnprimedDockStartedBeforeTheDelayWasWritten() {
        #expect(DockPriming.decide(running: oldDock, primed: nil, delayWrittenAt: writtenAt) == .restart(oldDock))
    }

    @Test func keepsTheDockRecordedAsPrimed() {
        #expect(DockPriming.decide(running: oldDock, primed: oldDock, delayWrittenAt: writtenAt) == .primed(oldDock))
    }

    @Test func reusedPidWithADifferentStartTimeIsNotPrimed() {
        let reused = ProcessIdentity(pid: 823, startTime: 700)
        #expect(DockPriming.decide(running: reused, primed: oldDock, delayWrittenAt: writtenAt) == .restart(reused))
    }

    @Test func aDockStartedAfterTheDelayWasWrittenIsPrimed() {
        #expect(DockPriming.decide(running: newDock, primed: oldDock, delayWrittenAt: writtenAt) == .primed(newDock))
    }

    @Test func waitsWhenNoDockIsRunning() {
        #expect(DockPriming.decide(running: nil, primed: oldDock, delayWrittenAt: writtenAt) == .waitForDock)
        #expect(DockPriming.decide(running: nil, primed: nil, delayWrittenAt: writtenAt) == .waitForDock)
    }

    @Test func primedRecordRoundTripsThroughItsFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileStore<ProcessIdentity>(url: dir.appending(path: "primed-dock.json"))
        #expect(try store.load() == nil)
        try store.save(oldDock)
        #expect(try store.load() == oldDock)
    }
}
