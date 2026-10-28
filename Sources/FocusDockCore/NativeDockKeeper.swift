import Foundation

public struct NativeDockState: Codable, Equatable, Sendable {
    public let originalAutoHide: Bool
    /// `com.apple.dock autohide-delay`; nil means the key was absent.
    public let originalAutoHideDelay: Double?

    public init(originalAutoHide: Bool, originalAutoHideDelay: Double?) {
        self.originalAutoHide = originalAutoHide
        self.originalAutoHideDelay = originalAutoHideDelay
    }
}

public protocol NativeDockStateStore {
    func load() throws -> NativeDockState?
    func save(_ state: NativeDockState) throws
    func remove() throws
}

/// The CoreDock autohide calls and the `autohide-delay` pref, injected so the decision logic is
/// testable without touching the Dock. A nil delay means "key absent" (set nil deletes it).
public struct NativeDockAPI {
    public let getAutoHide: () -> Bool
    public let setAutoHide: (Bool) -> Void
    public let getAutoHideDelay: () -> Double?
    public let setAutoHideDelay: (Double?) -> Void

    public init(
        getAutoHide: @escaping () -> Bool,
        setAutoHide: @escaping (Bool) -> Void,
        getAutoHideDelay: @escaping () -> Double?,
        setAutoHideDelay: @escaping (Double?) -> Void
    ) {
        self.getAutoHide = getAutoHide
        self.setAutoHide = setAutoHide
        self.getAutoHideDelay = getAutoHideDelay
        self.setAutoHideDelay = setAutoHideDelay
    }
}

/// Hides the system Dock and guarantees the user's original setting comes back.
/// The state file exists exactly while the Dock is hidden by us, so a crash leaves it behind
/// and the next launch or the watchdog can restore from it.
public struct NativeDockKeeper {
    /// Seconds before the autohidden Dock reveals at the screen edge; large enough to never happen.
    public static let hiddenAutoHideDelay: Double = 1000

    private let store: NativeDockStateStore
    private let dock: NativeDockAPI

    public init(store: NativeDockStateStore, dock: NativeDockAPI) {
        self.store = store
        self.dock = dock
    }

    public func hide() throws {
        if try existingOriginal() == nil {
            try store.save(NativeDockState(originalAutoHide: dock.getAutoHide(), originalAutoHideDelay: dock.getAutoHideDelay()))
        }
        dock.setAutoHideDelay(Self.hiddenAutoHideDelay)
        dock.setAutoHide(true)
    }

    /// Returns whether a recorded state was restored.
    @discardableResult
    public func restore() throws -> Bool {
        guard let state = try existingOriginal() else { return false }
        dock.setAutoHideDelay(state.originalAutoHideDelay)
        dock.setAutoHide(state.originalAutoHide)
        try store.remove()
        return true
    }

    /// A leftover file means a previous run crashed, so it holds the true original; an
    /// unreadable one is replaced by "visible, default delay", since losing the Dock is worse than
    /// unhiding it.
    private func existingOriginal() throws -> NativeDockState? {
        do {
            return try store.load()
        } catch {
            let fallback = NativeDockState(originalAutoHide: false, originalAutoHideDelay: nil)
            try store.save(fallback)
            return fallback
        }
    }
}

public struct FileStateStore: NativeDockStateStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: FileStateStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileStateStore(url: support.appending(path: "FocusDock/native-dock.json"))
    }

    public func load() throws -> NativeDockState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(NativeDockState.self, from: Data(contentsOf: url))
    }

    public func save(_ state: NativeDockState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }

    public func remove() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
