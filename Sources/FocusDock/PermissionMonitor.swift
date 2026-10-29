import AppKit
import ApplicationServices
import CoreGraphics
import CoreLocation
import FocusDockCore
import Observation

/// Tracks the TCC grants FocusDock holds (SHELL-SPEC 4.2). Modules declare what they need;
/// while any of it is missing the monitor re-probes every 2 s, so a grant made in System
/// Settings takes effect without a relaunch. Probes run off the main thread.
@MainActor @Observable
final class PermissionMonitor {
    static let pollInterval: Duration = .seconds(2)

    private(set) var granted: Set<Permission> = []
    /// The modules that declared each permission; a requested one may have none.
    private(set) var neededBy: [Permission: Set<String>] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var prompted: Set<Permission> = []

    var missing: Set<Permission> { Set(neededBy.keys).subtracting(granted) }

    init() {
        Task { await refresh() }
    }

    func need(_ permission: Permission, by module: String) {
        neededBy[permission, default: []].insert(module)
        startPolling()
    }

    /// The system prompt the first time this session (Accessibility, Screen Recording), the
    /// Settings pane after that or for the rest: a denied prompt never shows again.
    func request(_ permission: Permission) {
        if neededBy[permission] == nil { neededBy[permission] = [] }
        startPolling()
        guard !prompted.contains(permission) else { return openSettings(permission) }
        prompted.insert(permission)
        switch permission {
        case .accessibility:
            // The value of kAXTrustedCheckOptionPrompt, a C global Swift 6 rejects as mutable state.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .fullDiskAccess, .location, .automation:
            openSettings(permission)
        }
    }

    func openSettings(_ permission: Permission) {
        NSWorkspace.shared.open(SettingsPane.url(for: permission))
    }

    func refresh() async {
        let states = await Task.detached { PermissionProbe.all() }.value
        granted = Set(states.filter { $0.value == .granted }.keys)
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task {
            await refresh()
            while !missing.isEmpty, !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                await refresh()
            }
            pollTask = nil
        }
    }
}

/// Read-only grant checks; none of them prompts.
enum PermissionProbe {
    static func all() -> [Permission: PermissionState] {
        Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, state($0)) })
    }

    static func state(_ permission: Permission) -> PermissionState {
        switch permission {
        case .accessibility:
            // Synthetic events (DockSwipe, Hyper) need the post-event grant too.
            AXIsProcessTrusted() && CGPreflightPostEventAccess() ? .granted : .denied
        case .screenRecording:
            CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .fullDiskAccess:
            canOpenNotificationsDatabase() ? .granted : .denied
        case .location:
            location(CLLocationManager().authorizationStatus)
        case .automation:
            // shortcut: Automation is granted per target app; probe it when an integration needs it.
            .notDetermined
        }
    }

    /// Resolution 8: Full Disk Access is "can we open the usernoted db".
    private static func canOpenNotificationsDatabase() -> Bool {
        let db = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
        let fd = open(db.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    private static func location(_ status: CLAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}
