import Foundation

/// The pre-ledger crash-restore file, `native-dock.json`; read only to import a leftover one.
public struct NativeDockState: Codable, Equatable, Sendable {
    public let originalAutoHide: Bool
    /// `com.apple.dock autohide-delay`; nil means the key was absent.
    public let originalAutoHideDelay: Double?

    public init(originalAutoHide: Bool, originalAutoHideDelay: Double?) {
        self.originalAutoHide = originalAutoHide
        self.originalAutoHideDelay = originalAutoHideDelay
    }
}

/// The CoreDock autohide calls and the `autohide-delay` pref, injected so the decision logic is
/// testable without touching the Dock. A nil delay means "key absent" (set nil deletes it).
public struct NativeDockAPI: Sendable {
    public let getAutoHide: @Sendable () -> Bool
    public let setAutoHide: @Sendable (Bool) -> Void
    public let getAutoHideDelay: @Sendable () -> Double?
    public let setAutoHideDelay: @Sendable (Double?) -> Void

    public init(
        getAutoHide: @escaping @Sendable () -> Bool,
        setAutoHide: @escaping @Sendable (Bool) -> Void,
        getAutoHideDelay: @escaping @Sendable () -> Double?,
        setAutoHideDelay: @escaping @Sendable (Double?) -> Void
    ) {
        self.getAutoHide = getAutoHide
        self.setAutoHide = setAutoHide
        self.getAutoHideDelay = getAutoHideDelay
        self.setAutoHideDelay = setAutoHideDelay
    }
}

/// Hides the system Dock and guarantees the user's original setting comes back. The originals
/// go into the restore ledger before anything changes, so a crash leaves them there and the
/// watchdog, the next launch or `focusdock restore` puts them back. A key already in the
/// ledger is never re-recorded: it holds the true original from before a crashed run.
public struct NativeDockKeeper: Sendable {
    /// Seconds before the autohidden Dock reveals at the screen edge; large enough to never happen.
    public static let hiddenAutoHideDelay: Double = 1000
    public static let autoHideKey = "dock.autohide"
    public static let autoHideDelayKey = "dock.autohideDelay"

    private let ledger: RestoreLedger
    private let dock: NativeDockAPI

    public init(ledger: RestoreLedger, dock: NativeDockAPI) {
        self.ledger = ledger
        self.dock = dock
    }

    /// Records the originals and writes the long delay.
    /// The Dock only applies the delay after a restart (see DockPriming).
    public func prepare() async throws {
        try await ledger.recordOriginal(Self.autoHideKey, .bool(dock.getAutoHide()))
        try await ledger.recordOriginal(Self.autoHideDelayKey, Self.delayValue(dock.getAutoHideDelay()))
        dock.setAutoHideDelay(Self.hiddenAutoHideDelay)
    }

    public func hide() async throws {
        try await prepare()
        dock.setAutoHide(true)
    }

    /// The ledger restorers for both keys, read back through the same API.
    public var restorers: [Restorer] {
        [Self.autoHideKey, Self.autoHideDelayKey].map { key in
            Restorer(key: key, apply: { try apply(key, $0) }, read: { current(key) })
        }
    }

    /// Applies the recorded originals now, without touching the ledger, for a caller that cannot
    /// await (a synchronous quit); a later replay confirms them and truncates. Returns whether
    /// there was anything to apply.
    @discardableResult
    public func applyOriginals() throws -> Bool {
        let keys: Set = [Self.autoHideKey, Self.autoHideDelayKey]
        let entries = try ledger.entries().entries.filter { keys.contains($0.key) }
        for entry in entries.reversed() {
            try apply(entry.key, entry.original)
        }
        return !entries.isEmpty
    }

    /// Moves a `native-dock.json` left by a crashed pre-ledger run into the ledger, then deletes
    /// it. An unreadable one imports as "visible, default delay", since losing the Dock is worse
    /// than unhiding it.
    public static func importLegacy(_ legacy: JSONFileStore<NativeDockState>, into ledger: RestoreLedger) async throws {
        guard FileManager.default.fileExists(atPath: legacy.url.path) else { return }
        let state = (try? legacy.load()) ?? NativeDockState(originalAutoHide: false, originalAutoHideDelay: nil)
        try await ledger.recordOriginal(autoHideKey, .bool(state.originalAutoHide))
        try await ledger.recordOriginal(autoHideDelayKey, delayValue(state.originalAutoHideDelay))
        try legacy.remove()
    }

    /// The Dock stores the delay as a float, so originals and read-backs compare at float precision.
    static func delayValue(_ delay: Double?) -> LedgerValue {
        delay.map { .number(Double(Float($0))) } ?? .unset
    }

    private func apply(_ key: String, _ value: LedgerValue) throws {
        switch (key, value) {
        case let (Self.autoHideKey, .bool(on)): dock.setAutoHide(on)
        case let (Self.autoHideDelayKey, .number(delay)): dock.setAutoHideDelay(delay)
        case (Self.autoHideDelayKey, .unset): dock.setAutoHideDelay(nil)
        default: throw RestoreError.unexpectedValue(key: key, value: value)
        }
    }

    private func current(_ key: String) -> LedgerValue {
        key == Self.autoHideKey ? .bool(dock.getAutoHide()) : Self.delayValue(dock.getAutoHideDelay())
    }
}

/// A small JSON file holding one value, or nothing.
public struct JSONFileStore<Value: Codable> {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// `~/Library/Application Support/FocusDock/<name>`.
    public static func standard(_ name: String) -> JSONFileStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return JSONFileStore(url: support.appending(path: "FocusDock/\(name)"))
    }

    public func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    public func remove() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
