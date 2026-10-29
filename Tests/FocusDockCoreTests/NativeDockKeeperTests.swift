import Foundation
import Testing
@testable import FocusDockCore

private final class FakeDock: Sendable {
    struct State {
        var autoHide: Bool
        var delay: Double?
        var setCalls: [Bool] = []
        var delayCalls: [Double?] = []
    }

    let shared: Shared<State>

    init(autoHide: Bool, delay: Double? = nil) {
        shared = Shared(State(autoHide: autoHide, delay: delay))
    }

    var state: State { shared.state.withLock { $0 } }

    var api: NativeDockAPI {
        NativeDockAPI(
            getAutoHide: { self.shared.state.withLock { $0.autoHide } },
            setAutoHide: { on in self.shared.state.withLock { $0.autoHide = on; $0.setCalls.append(on) } },
            getAutoHideDelay: { self.shared.state.withLock { $0.delay } },
            setAutoHideDelay: { delay in self.shared.state.withLock { $0.delay = delay; $0.delayCalls.append(delay) } }
        )
    }
}

struct NativeDockKeeperTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "keeper-\(UUID().uuidString)")
    private let hidden = NativeDockKeeper.hiddenAutoHideDelay
    private let autoHide = NativeDockKeeper.autoHideKey
    private let delay = NativeDockKeeper.autoHideDelayKey

    private var ledger: RestoreLedger {
        RestoreLedger(paths: ThemePaths(home: root, shippedThemes: root, shippedTemplates: root))
    }

    private var legacy: JSONFileStore<NativeDockState> {
        JSONFileStore(url: root.appending(path: "Application Support/FocusDock/native-dock.json"))
    }

    private func keeper(_ dock: FakeDock) -> NativeDockKeeper { NativeDockKeeper(ledger: ledger, dock: dock.api) }

    private func recorded() throws -> [String: LedgerValue] {
        Dictionary(uniqueKeysWithValues: try ledger.entries().entries.map { ($0.key, $0.original) })
    }

    private func cleanUp() { try? FileManager.default.removeItem(at: root) }

    @Test func firstLaunchRecordsOriginalsAndHides() async throws {
        defer { cleanUp() }
        let dock = FakeDock(autoHide: false)
        try await keeper(dock).hide()
        #expect(try recorded() == [autoHide: .bool(false), delay: .unset])
        #expect(dock.state.autoHide)
        #expect(dock.state.delay == hidden)
    }

    @Test func prepareRecordsOriginalsAndWritesDelayWithoutHiding() async throws {
        defer { cleanUp() }
        let dock = FakeDock(autoHide: false)
        try await keeper(dock).prepare()
        #expect(try recorded() == [autoHide: .bool(false), delay: .unset])
        #expect(dock.state.delay == hidden)
        #expect(!dock.state.autoHide)
        #expect(dock.state.setCalls.isEmpty)
    }

    @Test func replayRestoresAnExistingDelayAndEmptiesTheLedger() async throws {
        defer { cleanUp() }
        let dock = FakeDock(autoHide: false, delay: 0.5)
        let keeper = keeper(dock)
        try await keeper.hide()
        #expect(try recorded()[delay] == .number(0.5))
        let report = try await ledger.replay(keeper.restorers)
        #expect(report == RestoreReport(restored: [delay, autoHide], failed: [:], skippedLines: 0))
        #expect(dock.state.delay == 0.5)
        #expect(!dock.state.autoHide)
        #expect(try ledger.entries().entries.isEmpty)
    }

    @Test func absentDelayIsDeletedOnReplay() async throws {
        defer { cleanUp() }
        let dock = FakeDock(autoHide: false)
        let keeper = keeper(dock)
        try await keeper.hide()
        _ = try await ledger.replay(keeper.restorers)
        #expect(dock.state.delay == nil)
        #expect(dock.state.delayCalls == [hidden, nil])
    }

    @Test func delayIsComparedAtTheDocksFloatPrecision() async throws {
        defer { cleanUp() }
        let dock = FakeDock(autoHide: false, delay: 0.3)
        let keeper = keeper(dock)
        try await keeper.hide()
        let report = try await ledger.replay(keeper.restorers)
        #expect(report.failed.isEmpty)
        #expect(dock.state.delay == Double(Float(0.3)))
    }

    @Test func relaunchAfterCrashKeepsTheRecordedOriginals() async throws {
        defer { cleanUp() }
        let crashed = FakeDock(autoHide: false)
        try await keeper(crashed).hide()
        let dock = FakeDock(autoHide: true, delay: hidden)
        let keeper = keeper(dock)
        try await keeper.hide()
        #expect(try recorded() == [autoHide: .bool(false), delay: .unset])
        _ = try await ledger.replay(keeper.restorers)
        #expect(!dock.state.autoHide)
        #expect(dock.state.delay == nil)
    }

    @Test func userWhoAlreadyAutohidesGetsAutohideBack() async throws {
        defer { cleanUp() }
        let dock = FakeDock(autoHide: true)
        let keeper = keeper(dock)
        try await keeper.hide()
        _ = try await ledger.replay(keeper.restorers)
        #expect(dock.state.autoHide)
    }

    @Test func replayWithAnEmptyLedgerTouchesNothing() async throws {
        defer { cleanUp() }
        let dock = FakeDock(autoHide: true)
        let report = try await ledger.replay(keeper(dock).restorers)
        #expect(report.restored.isEmpty)
        #expect(dock.state.setCalls.isEmpty)
        #expect(dock.state.delayCalls.isEmpty)
    }

    @Test func applyOriginalsRestoresTheDockAndLeavesTheLedger() async throws {
        defer { cleanUp() }
        let dock = FakeDock(autoHide: false, delay: 0.5)
        let keeper = keeper(dock)
        #expect(try !keeper.applyOriginals())
        try await keeper.hide()
        #expect(try keeper.applyOriginals())
        #expect(!dock.state.autoHide)
        #expect(dock.state.delay == 0.5)
        #expect(try ledger.entries().entries.count == 2)
    }

    @Test func aValueOfTheWrongKindIsNotRestored() async throws {
        defer { cleanUp() }
        try await ledger.recordOriginal(autoHide, .string("yes"))
        let dock = FakeDock(autoHide: true)
        let report = try await ledger.replay(keeper(dock).restorers)
        #expect(report.failed[autoHide] != nil)
        #expect(dock.state.setCalls.isEmpty)
        #expect(try recorded() == [autoHide: .string("yes")])
    }

    @Test func legacyStateFileIsImportedAndDeleted() async throws {
        defer { cleanUp() }
        try legacy.save(NativeDockState(originalAutoHide: true, originalAutoHideDelay: 0.5))
        try await NativeDockKeeper.importLegacy(legacy, into: ledger)
        #expect(try recorded() == [autoHide: .bool(true), delay: .number(0.5)])
        #expect(try legacy.load() == nil)
    }

    @Test func unreadableLegacyFileImportsAsAVisibleDock() async throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(at: legacy.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: legacy.url)
        try await NativeDockKeeper.importLegacy(legacy, into: ledger)
        #expect(try recorded() == [autoHide: .bool(false), delay: .unset])
        #expect(!FileManager.default.fileExists(atPath: legacy.url.path))
    }

    @Test func legacyImportKeepsOriginalsTheLedgerAlreadyHas() async throws {
        defer { cleanUp() }
        try await ledger.recordOriginal(autoHide, .bool(false))
        try legacy.save(NativeDockState(originalAutoHide: true, originalAutoHideDelay: nil))
        try await NativeDockKeeper.importLegacy(legacy, into: ledger)
        #expect(try recorded() == [autoHide: .bool(false), delay: .unset])
    }

    @Test func noLegacyFileImportsNothing() async throws {
        defer { cleanUp() }
        try await NativeDockKeeper.importLegacy(legacy, into: ledger)
        #expect(try ledger.entries().entries.isEmpty)
    }

    @Test func stateFileFromPhase1WithoutDelayDecodes() throws {
        let data = Data(#"{"originalAutoHide":true}"#.utf8)
        let state = try JSONDecoder().decode(NativeDockState.self, from: data)
        #expect(state == NativeDockState(originalAutoHide: true, originalAutoHideDelay: nil))
    }

    @Test func fileStoreRoundTripsAndRemoves() throws {
        defer { cleanUp() }
        let store = JSONFileStore<NativeDockState>(url: root.appending(path: "nested/native-dock.json"))
        #expect(try store.load() == nil)
        try store.save(NativeDockState(originalAutoHide: true, originalAutoHideDelay: 0.5))
        #expect(try store.load() == NativeDockState(originalAutoHide: true, originalAutoHideDelay: 0.5))
        try store.remove()
        #expect(try store.load() == nil)
        try store.remove()
    }
}
