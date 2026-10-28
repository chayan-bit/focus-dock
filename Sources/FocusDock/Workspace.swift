import AppKit
import FocusDockCore

/// Running apps and launch/activate, via public NSWorkspace API only.
@MainActor
final class Workspace {
    private let model: DockModel
    private let pinned: [AppRef]
    private var observers: [NSObjectProtocol] = []
    /// KVO does not retain the observed app, so the app is kept alive with its observation;
    /// letting it deallocate while observed crashes in NSRunningApplication (seen in E2E).
    private var launchObservations: [String: (app: NSRunningApplication, observation: NSKeyValueObservation)] = [:]

    /// The Dock always shows Finder first; it is not stored in `persistent-apps`.
    private static let finder = AppRef(
        bundleID: "com.apple.finder",
        url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
        name: "Finder"
    )

    init(model: DockModel) {
        self.model = model
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        pinned = [Self.finder] + PersistentApps.parse(dockDefaults?.object(forKey: "persistent-apps")) + Self.extraApps()
        observeWorkspace()
        refresh()
    }

    // shortcut: launch-argument hook (`--args -FocusDockExtraApps '("/path/App.app")'`) so E2E can
    // launch an app that is not in the Dock; replace with the Phase 2 mode config.
    private static func extraApps() -> [AppRef] {
        (UserDefaults.standard.stringArray(forKey: "FocusDockExtraApps") ?? []).map { path in
            let url = URL(fileURLWithPath: path)
            let name = url.deletingPathExtension().lastPathComponent
            return AppRef(bundleID: Bundle(url: url)?.bundleIdentifier, url: url, name: name)
        }
    }

    static func currentTileSize() -> CGFloat {
        let preference = UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "tilesize") as? Double
        let height = NSScreen.screens.first?.frame.height ?? 0
        return DockMetrics.tileSize(preference: preference, mainDisplayHeight: height)
    }

    func refresh() {
        model.setTiles(TileList.merge(pinned: pinned, running: runningApps()))
    }

    /// Always goes through LaunchServices: for a running app this activates it and sends the
    /// reopen event, which is what the Dock does (the app itself opens a window if it has none).
    /// `NSRunningApplication.activate()` is not used because an app that is never active cannot
    /// take activation under cooperative activation (macOS 14+).
    func open(_ tile: DockTile) {
        let id = tile.id
        if !tile.isRunning { model.setLaunching(id, true) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: tile.app.url, configuration: configuration) { [weak self] app, error in
            let pid = app?.processIdentifier
            let message = error.map { String(describing: $0) }
            Task { @MainActor [weak self] in self?.didOpen(id: id, pid: pid, error: message) }
        }
    }

    private func didOpen(id: String, pid: pid_t?, error: String?) {
        if let error { NSLog("FocusDock: open %@ failed: %@", id, error) }
        guard let pid, let app = NSRunningApplication(processIdentifier: pid), !app.isFinishedLaunching else {
            finishLaunch(id)
            return
        }
        let observation = app.observe(\.isFinishedLaunching, options: [.new]) { [weak self] _, change in
            guard change.newValue == true else { return }
            Task { @MainActor [weak self] in self?.finishLaunch(id) }
        }
        launchObservations[id] = (app, observation)
        if app.isFinishedLaunching { finishLaunch(id) }
    }

    /// Like the Dock, a finished launch lands the current bounce instead of snapping to rest.
    private func finishLaunch(_ id: String) {
        launchObservations[id]?.observation.invalidate()
        launchObservations[id] = nil
        let elapsed = model.launchStarts[id].map { Date().timeIntervalSince($0) } ?? 0
        let landing = DockMetrics.bounceTimeToRest(elapsed: elapsed)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(landing))
            self?.model.setLaunching(id, false)
        }
    }

    private func runningApps() -> [AppRef] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, !app.isTerminated, let url = app.bundleURL else { return nil }
            let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
            return AppRef(bundleID: app.bundleIdentifier, url: url, name: name)
        }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }
}
