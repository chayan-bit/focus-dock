import Foundation
import Testing
@testable import FocusDockCore

/// A fake preferences domain: absent keys read as `.unset`, and every apply is logged.
private final class FakeSystem: Sendable {
    let values: Shared<[String: LedgerValue]>
    let applied = Shared<[String]>([])

    init(_ values: [String: LedgerValue] = [:]) { self.values = Shared(values) }

    func set(_ key: String, _ value: LedgerValue) {
        values.state.withLock { $0[key] = value == .unset ? nil : value }
    }

    func value(_ key: String) -> LedgerValue {
        values.state.withLock { $0[key] ?? .unset }
    }

    func restorer(_ key: String) -> Restorer {
        Restorer(
            key: key,
            apply: { value in
                self.applied.state.withLock { $0.append(key) }
                self.set(key, value)
            },
            read: { self.value(key) }
        )
    }

    var appliedKeys: [String] { applied.state.withLock { $0 } }
}

private struct ApplyFailed: Error {}

struct RestoreLedgerTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ledger-\(UUID().uuidString)")
    private var ledger: RestoreLedger {
        RestoreLedger(paths: ThemePaths(home: root, shippedThemes: root, shippedTemplates: root))
    }

    private func cleanUp() { try? FileManager.default.removeItem(at: root) }

    private func writeRaw(_ text: String) throws {
        try FileManager.default.createDirectory(at: ledger.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: ledger.file)
    }

    @Test func ledgerLivesInTheStateDirectory() {
        #expect(ledger.file.path.hasSuffix(".local/state/focusdock/restore.jsonl"))
        #expect(ledger.lock.path.hasSuffix(".local/state/focusdock/restore.lock"))
    }

    @Test func recordingAKeyTwiceKeepsTheFirstOriginal() async throws {
        defer { cleanUp() }
        try await ledger.recordOriginal("dock.autohide", .bool(false))
        try await ledger.recordOriginal("dock.autohide", .bool(true))
        let (entries, skipped) = try ledger.entries()
        #expect(entries.map(\.key) == ["dock.autohide"])
        #expect(entries.first?.original == .bool(false))
        #expect(entries.first?.pid == getpid())
        #expect(skipped == 0)
    }

    @Test func everyValueKindRoundTrips() async throws {
        defer { cleanUp() }
        let values: [LedgerValue] = [.bool(true), .number(0.25), .string("Graphite"), .unset]
        for (index, value) in values.enumerated() {
            try await ledger.recordOriginal("key\(index)", value)
        }
        #expect(try ledger.entries().entries.map(\.original) == values)
    }

    @Test func replayRestoresInReverseOrderAndTruncates() async throws {
        defer { cleanUp() }
        let system = FakeSystem()
        for key in ["a", "b", "c"] {
            try await ledger.recordOriginal(key, .number(1))
            system.set(key, .number(2))
        }
        let report = try await ledger.replay(["a", "b", "c"].map(system.restorer))
        #expect(report == RestoreReport(restored: ["c", "b", "a"], failed: [:], skippedLines: 0))
        #expect(system.appliedKeys == ["c", "b", "a"])
        #expect(["a", "b", "c"].allSatisfy { system.value($0) == .number(1) })
        #expect(!FileManager.default.fileExists(atPath: ledger.file.path))
    }

    @Test func unsetOriginalDeletesTheKey() async throws {
        defer { cleanUp() }
        let system = FakeSystem()
        try await ledger.recordOriginal("accent", .unset)
        system.set("accent", .number(4))
        let report = try await ledger.replay([system.restorer("accent")])
        #expect(report.restored == ["accent"])
        #expect(system.values.state.withLock { $0["accent"] } == nil)
    }

    @Test func tornLastLineIsSkippedAndCounted() async throws {
        defer { cleanUp() }
        try await ledger.recordOriginal("a", .bool(true))
        let valid = try String(contentsOf: ledger.file, encoding: .utf8)
        try writeRaw(valid + #"{"key":"b","orig"#)
        let (entries, skipped) = try ledger.entries()
        #expect(entries.map(\.key) == ["a"])
        #expect(skipped == 1)

        let system = FakeSystem(["a": .bool(false)])
        let report = try await ledger.replay([system.restorer("a")])
        #expect(report == RestoreReport(restored: ["a"], failed: [:], skippedLines: 1))
        #expect(!FileManager.default.fileExists(atPath: ledger.file.path))
    }

    @Test func recordAfterATornLineStartsOnItsOwnLine() async throws {
        defer { cleanUp() }
        try writeRaw(#"{"key":"b","orig"#)
        try await ledger.recordOriginal("a", .bool(true))
        let (entries, skipped) = try ledger.entries()
        #expect(entries.map(\.key) == ["a"])
        #expect(skipped == 1)
    }

    @Test func failedReadBackKeepsTheLineForTheNextReplay() async throws {
        defer { cleanUp() }
        try await ledger.recordOriginal("stuck", .bool(false))
        try await ledger.recordOriginal("fine", .bool(false))
        let system = FakeSystem(["stuck": .bool(true), "fine": .bool(true)])
        let ignoresWrites = Restorer(key: "stuck", apply: { _ in }, read: { .bool(true) })

        let report = try await ledger.replay([ignoresWrites, system.restorer("fine")], readBackTimeout: .milliseconds(20))
        #expect(report.restored == ["fine"])
        #expect(report.failed.keys.sorted() == ["stuck"])
        #expect(try ledger.entries().entries.map(\.key) == ["stuck"])

        let retry = try await ledger.replay([system.restorer("stuck")])
        #expect(retry.restored == ["stuck"])
        #expect(system.value("stuck") == .bool(false))
        #expect(try ledger.entries().entries.isEmpty)
    }

    @Test func applyErrorsAndMissingRestorersKeepTheirLines() async throws {
        defer { cleanUp() }
        try await ledger.recordOriginal("throws", .bool(false))
        try await ledger.recordOriginal("orphan", .string("x"))
        let throwing = Restorer(key: "throws", apply: { _ in throw ApplyFailed() }, read: { .bool(false) })
        let report = try await ledger.replay([throwing])
        #expect(report.restored.isEmpty)
        #expect(report.failed.keys.sorted() == ["orphan", "throws"])
        #expect(try ledger.entries().entries.map(\.key) == ["throws", "orphan"])
    }

    @Test func twoConcurrentReplaysRestoreExactlyOnce() async throws {
        defer { cleanUp() }
        let keys = (0..<8).map { "key\($0)" }
        for key in keys { try await ledger.recordOriginal(key, .bool(false)) }
        let system = FakeSystem()
        let restorers = keys.map(system.restorer)
        async let first = ledger.replay(restorers)
        async let second = ledger.replay(restorers)
        let reports = try await [first, second]
        #expect(reports.flatMap(\.restored).sorted() == keys.sorted())
        #expect(system.appliedKeys.sorted() == keys.sorted())
        #expect(reports.allSatisfy { $0.failed.isEmpty })
    }

    @Test func missingOrEmptyLedgerReplaysNothing() async throws {
        defer { cleanUp() }
        let empty = RestoreReport(restored: [], failed: [:], skippedLines: 0)
        #expect(try ledger.entries().entries.isEmpty)
        #expect(try await ledger.replay([]) == empty)
        try writeRaw("")
        #expect(try await ledger.replay([]) == empty)
    }
}
