import Foundation

public enum PermissionState: Sendable, Equatable {
    case granted, denied, notDetermined
}

extension Permission {
    /// The name System Settings uses for the grant.
    public var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .fullDiskAccess: "Full Disk Access"
        case .location: "Location"
        case .automation: "Automation"
        }
    }
}

/// Deep links into System Settings > Privacy & Security, one per permission.
public enum SettingsPane {
    public static func url(for permission: Permission) -> URL {
        // Built from fixed anchors only, so the URL always parses.
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(anchor(permission))")!
    }

    private static func anchor(_ permission: Permission) -> String {
        switch permission {
        case .accessibility: "Accessibility"
        case .screenRecording: "ScreenCapture"
        case .fullDiskAccess: "AllFiles"
        case .location: "LocationServices"
        case .automation: "Automation"
        }
    }
}

public enum Onboarding {
    /// The next grant to offer: the first needed and missing one in SHELL-SPEC 4.2 order.
    public static func next(needed: Set<Permission>, granted: Set<Permission>) -> Permission? {
        Permission.allCases.first { needed.contains($0) && !granted.contains($0) }
    }
}
