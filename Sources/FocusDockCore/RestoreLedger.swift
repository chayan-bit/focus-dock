import Foundation

/// An original system value; `.unset` means the key was absent, so restoring deletes it.
public enum LedgerValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case number(Double)
    case string(String)
    case unset
}

/// One line of `restore.jsonl`: what `key` was before FocusDock first changed it.
public struct RestoreEntry: Codable, Equatable, Sendable {
    public let key: String
    public let original: LedgerValue
    public let at: Date
    public let pid: Int32

    public init(key: String, original: LedgerValue, at: Date, pid: Int32) {
        self.key = key
        self.original = original
        self.at = at
        self.pid = pid
    }
}

/// Puts one ledger key back: `apply` writes a value, `read` reports the live one (nil if unreadable).
public struct Restorer: Sendable {
    public let key: String
    public let apply: @Sendable (LedgerValue) async throws -> Void
    public let read: @Sendable () async -> LedgerValue?

    public init(key: String, apply: @escaping @Sendable (LedgerValue) async throws -> Void, read: @escaping @Sendable () async -> LedgerValue?) {
        self.key = key
        self.apply = apply
        self.read = read
    }
}

/// `restored` in replay order; `failed` maps a key to why its line was kept.
public struct RestoreReport: Equatable, Sendable {
    public let restored: [String]
    public let failed: [String: String]
    public let skippedLines: Int

    public init(restored: [String], failed: [String: String], skippedLines: Int) {
        self.restored = restored
        self.failed = failed
        self.skippedLines = skippedLines
    }
}

public enum RestoreError: Error, Equatable, CustomStringConvertible {
    /// A restorer was handed a value of the wrong kind for its key.
    case unexpectedValue(key: String, value: LedgerValue)

    public var description: String {
        switch self {
        case let .unexpectedValue(key, value): "\(key) cannot be restored to \(value)"
        }
    }
}

/// The crash-restore ledger (SHELL-SPEC 4.3). Every setter on system state records the original
/// here first; clean quit, the watchdog, the next launch and `focusdock restore` replay it in
/// reverse and drop what came back. Writers and replays serialise on `restore.lock`, so a
/// record never lands between a replay's read and its truncate.
public struct RestoreLedger: Sendable {
    public let file: URL
    public let lock: URL

    public init(paths: ThemePaths) {
        file = paths.state.appending(path: "restore.jsonl")
        lock = paths.state.appending(path: "restore.lock")
    }

    /// Appends `key`'s original and syncs it to disk, unless the key is already recorded: an
    /// existing line holds the older, truer original (a crashed run already changed the value).
    /// Must complete before the caller changes the value.
    public func recordOriginal(_ key: String, _ value: LedgerValue) async throws {
        try await FileLock.withLock(lock) {
            let data = try contents()
            guard !Self.parse(data).lines.contains(where: { $0.entry.key == key }) else { return }
            var line = try JSONEncoder().encode(RestoreEntry(key: key, original: value, at: Date(), pid: getpid()))
            line.append(UInt8(ascii: "\n"))
            // A torn last line has no newline; without one here the new line would be torn too.
            if let last = data.last, last != UInt8(ascii: "\n") { line.insert(UInt8(ascii: "\n"), at: 0) }
            try append(line)
        }
    }

    /// The decodable lines in file order, and how many lines were not (a torn last write).
    public func entries() throws -> (entries: [RestoreEntry], skippedLines: Int) {
        let parsed = Self.parse(try contents())
        return (parsed.lines.map(\.entry), parsed.skipped)
    }

    /// Restores every entry newest first, confirms each by reading it back, then rewrites the
    /// ledger with only the lines that failed. Throws only when the ledger itself cannot be
    /// read or rewritten; per-key failures are in the report.
    public func replay(_ restorers: [Restorer], readBackTimeout: Duration = .seconds(2)) async throws -> RestoreReport {
        try await FileLock.withLock(lock) {
            let parsed = Self.parse(try contents())
            let byKey = Dictionary(restorers.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            var restored: [String] = []
            var failed: [String: String] = [:]
            var kept: [Int] = []
            for (index, line) in parsed.lines.enumerated().reversed() {
                if let reason = await restore(line.entry, byKey[line.entry.key], readBackTimeout) {
                    failed[line.entry.key] = reason
                    kept.append(index)
                } else {
                    restored.append(line.entry.key)
                }
            }
            try rewrite(kept.reversed().map { parsed.lines[$0].raw })
            return RestoreReport(restored: restored, failed: failed, skippedLines: parsed.skipped)
        }
    }

    /// nil on success, else why the entry stays in the ledger.
    private func restore(_ entry: RestoreEntry, _ restorer: Restorer?, _ timeout: Duration) async -> String? {
        guard let restorer else { return "no restorer for \(entry.key)" }
        do {
            try await restorer.apply(entry.original)
        } catch {
            return "restoring failed: \(error)"
        }
        guard await ReadBack.poll(entry.original, timeout: timeout, read: restorer.read) else {
            return "read-back did not show \(entry.original) within \(timeout)"
        }
        return nil
    }

    private func contents() throws -> Data {
        do {
            return try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile {
            return Data()
        }
    }

    private static func parse(_ data: Data) -> (lines: [(raw: Data, entry: RestoreEntry)], skipped: Int) {
        let decoder = JSONDecoder()
        var lines: [(raw: Data, entry: RestoreEntry)] = []
        var skipped = 0
        for raw in data.split(separator: UInt8(ascii: "\n")) {
            if let entry = try? decoder.decode(RestoreEntry.self, from: raw) {
                lines.append((Data(raw), entry))
            } else {
                skipped += 1
            }
        }
        return (lines, skipped)
    }

    /// `O_APPEND` + `fsync`, so the original is on disk before the caller's setter runs.
    private func append(_ data: Data) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(file.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Self.posixError() }
        defer { close(fd) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw Self.posixError() }
                offset += written
            }
        }
        guard fsync(fd) == 0 else { throw Self.posixError() }
    }

    /// Atomic replace, so a crash mid-rewrite leaves the old lines, which replay again harmlessly.
    private func rewrite(_ lines: [Data]) throws {
        guard !lines.isEmpty else {
            do {
                try FileManager.default.removeItem(at: file)
            } catch CocoaError.fileNoSuchFile {}
            return
        }
        let newline = Data([UInt8(ascii: "\n")])
        try lines.map { $0 + newline }.reduce(Data(), +).write(to: file, options: .atomic)
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
