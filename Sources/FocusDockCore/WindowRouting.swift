import Foundation

/// One `aerospace subscribe window-detected` JSON line, e.g.
/// `{"_event":"window-detected","windowId":123,"workspace":"1","appBundleId":"com.apple.TextEdit","appName":"TextEdit"}`
/// (field names from AeroSpace `ServerEvent.swift`).
public struct WindowDetected: Decodable, Equatable, Sendable {
    public let windowId: UInt32
    public let workspace: String?
    public let appBundleId: String?
    public let appName: String?

    public init(windowId: UInt32, workspace: String?, appBundleId: String?, appName: String?) {
        self.windowId = windowId
        self.workspace = workspace
        self.appBundleId = appBundleId
        self.appName = appName
    }

    /// The event on this line, or nil for other events and malformed lines.
    public static func parse(line: String) -> WindowDetected? {
        let data = Data(line.utf8)
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.event == "window-detected" else { return nil }
        return try? JSONDecoder().decode(WindowDetected.self, from: data)
    }

    private struct Header: Decodable {
        let event: String
        enum CodingKeys: String, CodingKey { case event = "_event" }
    }
}

public enum WindowRouting {
    /// Workspace a new window of `bundleID` belongs in: its mode's when exactly one mode has
    /// the app, the current mode's when several do, none when no mode has it.
    public static func workspace(forBundleID bundleID: String?, config: ModesConfig, currentModeID: String) -> String? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        let owners = config.modes.filter { $0.routedBundleIDs.contains(bundleID) }
        switch owners.count {
        case 0: return nil
        case 1: return owners[0].workspace
        default: return config.mode(currentModeID)?.workspace
        }
    }

    /// The `move-node-to-workspace` arguments for a new window, or nil if it should stay put.
    public static func moveArguments(for window: WindowDetected, config: ModesConfig, currentModeID: String) -> [String]? {
        guard let target = workspace(forBundleID: window.appBundleId, config: config, currentModeID: currentModeID),
              target != window.workspace
        else { return nil }
        return ["move-node-to-workspace", "--window-id", String(window.windowId), target]
    }
}

public enum AeroSpaceLocator {
    /// GUI apps get a minimal PATH, so the nix-darwin profile directories are searched too.
    public static func candidates(path: String?, user: String, name: String = "aerospace") -> [String] {
        let fromPath = (path ?? "").split(separator: ":").map(String.init)
        let extra = ["/run/current-system/sw/bin", "/etc/profiles/per-user/\(user)/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        let dirs = (fromPath + extra).reduce(into: [String]()) { result, dir in
            if !dir.isEmpty, !result.contains(dir) { result.append(dir) }
        }
        return dirs.map { "\($0)/\(name)" }
    }

    public static func find(path: String?, user: String, name: String = "aerospace", isExecutable: (String) -> Bool) -> String? {
        candidates(path: path, user: user, name: name).first(where: isExecutable)
    }
}

/// Focus modes are switched by user-made Shortcuts named "FocusDock <focus>" / "FocusDock Off".
public enum FocusShortcuts {
    public static let offName = "FocusDock Off"

    public static func name(forFocus focus: String) -> String { "FocusDock \(focus)" }

    /// The shortcut to run when `mode` activates, if it exists.
    public static func shortcut(for mode: Mode, available: Set<String>) -> String? {
        let name = mode.focus.map(name(forFocus:)) ?? offName
        return available.contains(name) ? name : nil
    }

    /// Shortcuts the config needs that `shortcuts list` did not report, in mode order.
    /// "FocusDock Off" is only needed when some mode turns a Focus on and some mode does not.
    public static func missing(in config: ModesConfig, available: Set<String>) -> [String] {
        let focusNames = config.modes.compactMap(\.focus).map(name(forFocus:))
        let needsOff = !focusNames.isEmpty && config.modes.contains { $0.focus == nil }
        let needed = focusNames + (needsOff ? [offName] : [])
        return needed.reduce(into: [String]()) { result, name in
            if !available.contains(name), !result.contains(name) { result.append(name) }
        }
    }

    /// `shortcuts list` prints one name per line.
    public static func parseList(_ output: String) -> Set<String> {
        Set(output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
}
