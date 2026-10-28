import Foundation
import Testing
@testable import FocusDockCore

private final class MemoryStore: NativeDockStateStore {
    var state: NativeDockState?
    var isCorrupt = false
    init(_ state: NativeDockState? = nil) { self.state = state }
    func load() throws -> NativeDockState? {
        if isCorrupt { throw CocoaError(.fileReadCorruptFile) }
        return state
    }
    func save(_ state: NativeDockState) throws { self.state = state; isCorrupt = false }
    func remove() throws { state = nil; isCorrupt = false }
}

private final class FakeDock {
    var autoHide: Bool
    var delay: Double?
    var setCalls: [Bool] = []
    var delayCalls: [Double?] = []
    init(autoHide: Bool, delay: Double? = nil) {
        self.autoHide = autoHide
        self.delay = delay
    }
    var api: NativeDockAPI {
        NativeDockAPI(
            getAutoHide: { self.autoHide },
            setAutoHide: { self.autoHide = $0; self.setCalls.append($0) },
            getAutoHideDelay: { self.delay },
            setAutoHideDelay: { self.delay = $0; self.delayCalls.append($0) }
        )
    }
}

struct NativeDockKeeperTests {
    @Test func firstLaunchRecordsOriginalAndHides() throws {
        let store = MemoryStore(), dock = FakeDock(autoHide: false)
        try NativeDockKeeper(store: store, dock: dock.api).hide()
        #expect(store.state == NativeDockState(originalAutoHide: false, originalAutoHideDelay: nil))
        #expect(dock.autoHide)
        #expect(dock.delay == NativeDockKeeper.hiddenAutoHideDelay)
    }

    @Test func prepareRecordsOriginalsAndWritesDelayWithoutHiding() throws {
        let store = MemoryStore(), dock = FakeDock(autoHide: false, delay: nil)
        try NativeDockKeeper(store: store, dock: dock.api).prepare()
        #expect(store.state == NativeDockState(originalAutoHide: false, originalAutoHideDelay: nil))
        #expect(dock.delay == NativeDockKeeper.hiddenAutoHideDelay)
        #expect(!dock.autoHide)
        #expect(dock.setCalls.isEmpty)
    }

    @Test func recordsAnExistingDelayAndRestoresIt() throws {
        let store = MemoryStore(), dock = FakeDock(autoHide: false, delay: 0.3)
        let keeper = NativeDockKeeper(store: store, dock: dock.api)
        try keeper.hide()
        #expect(store.state?.originalAutoHideDelay == 0.3)
        try keeper.restore()
        #expect(dock.delay == 0.3)
        #expect(!dock.autoHide)
    }

    @Test func absentDelayIsDeletedOnRestore() throws {
        let store = MemoryStore(), dock = FakeDock(autoHide: false, delay: nil)
        let keeper = NativeDockKeeper(store: store, dock: dock.api)
        try keeper.hide()
        try keeper.restore()
        #expect(dock.delay == nil)
        #expect(dock.delayCalls == [NativeDockKeeper.hiddenAutoHideDelay, nil])
    }

    @Test func relaunchAfterCrashKeepsRecordedDelay() throws {
        let store = MemoryStore(NativeDockState(originalAutoHide: false, originalAutoHideDelay: nil))
        let dock = FakeDock(autoHide: true, delay: NativeDockKeeper.hiddenAutoHideDelay)
        let keeper = NativeDockKeeper(store: store, dock: dock.api)
        try keeper.hide()
        #expect(store.state == NativeDockState(originalAutoHide: false, originalAutoHideDelay: nil))
        try keeper.restore()
        #expect(dock.delay == nil)
    }

    @Test func stateFileFromPhase1WithoutDelayDecodes() throws {
        let data = Data(#"{"originalAutoHide":true}"#.utf8)
        let state = try JSONDecoder().decode(NativeDockState.self, from: data)
        #expect(state == NativeDockState(originalAutoHide: true, originalAutoHideDelay: nil))
    }

    @Test func relaunchAfterCrashKeepsRecordedOriginal() throws {
        let store = MemoryStore(NativeDockState(originalAutoHide: false, originalAutoHideDelay: nil))
        let dock = FakeDock(autoHide: true)
        try NativeDockKeeper(store: store, dock: dock.api).hide()
        #expect(store.state == NativeDockState(originalAutoHide: false, originalAutoHideDelay: nil))
    }

    @Test func userWhoAlreadyAutohidesGetsAutohideBack() throws {
        let store = MemoryStore(), dock = FakeDock(autoHide: true)
        let keeper = NativeDockKeeper(store: store, dock: dock.api)
        try keeper.hide()
        try keeper.restore()
        #expect(dock.autoHide)
        #expect(store.state == nil)
    }

    @Test func restoreAppliesOriginalAndDeletesFile() throws {
        let store = MemoryStore(), dock = FakeDock(autoHide: false)
        let keeper = NativeDockKeeper(store: store, dock: dock.api)
        try keeper.hide()
        try keeper.restore()
        #expect(!dock.autoHide)
        #expect(store.state == nil)
    }

    @Test func restoreWithoutFileTouchesNothing() throws {
        let dock = FakeDock(autoHide: true)
        let restored = try NativeDockKeeper(store: MemoryStore(), dock: dock.api).restore()
        #expect(!restored)
        #expect(dock.setCalls.isEmpty)
        #expect(dock.delayCalls.isEmpty)
    }

    @Test func corruptFileFallsBackToVisibleDock() throws {
        let store = MemoryStore()
        store.isCorrupt = true
        let dock = FakeDock(autoHide: true)
        try NativeDockKeeper(store: store, dock: dock.api).hide()
        #expect(store.state == NativeDockState(originalAutoHide: false, originalAutoHideDelay: nil))
    }

    @Test func fileStoreRoundTripsAndRemoves() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStateStore(url: dir.appending(path: "nested/native-dock.json"))
        #expect(try store.load() == nil)
        try store.save(NativeDockState(originalAutoHide: true, originalAutoHideDelay: 0.5))
        #expect(try store.load() == NativeDockState(originalAutoHide: true, originalAutoHideDelay: 0.5))
        try store.remove()
        #expect(try store.load() == nil)
        try store.remove()
    }
}
