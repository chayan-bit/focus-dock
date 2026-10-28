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

    /// Records the originals (unless a crashed run already did) and writes the long delay.
    /// The Dock only applies the delay after a restart (see DockPriming).
    public func prepare() throws {
        if try existingOriginal() == nil {
            try store.save(NativeDockState(originalAutoHide: dock.getAutoHide(), originalAutoHideDelay: dock.getAutoHideDelay()))
        }
        dock.setAutoHideDelay(Self.hiddenAutoHideDelay)
    }

    public func hide() throws {
        try prepare()
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

public typealias FileStateStore = JSONFileStore<NativeDockState>

extension JSONFileStore: NativeDockStateStore where Value == NativeDockState {
    public static var standard: FileStateStore { standard("native-dock.json") }
}
