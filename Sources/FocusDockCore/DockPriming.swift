import Foundation

/// A process, identified so that a reused PID cannot pass for the original.
public struct ProcessIdentity: Codable, Equatable, Sendable {
    public let pid: Int32
    /// Wall-clock start time, seconds since 1970 (from `kinfo_proc.p_starttime`).
    public let startTime: Double

    public init(pid: Int32, startTime: Double) {
        self.pid = pid
        self.startTime = startTime
    }
}

/// The Dock reads `autohide-delay` only when it starts, so the delay is active only in a Dock
/// process that started after the delay was written. FocusDock records that process as "primed".
public enum DockPriming {
    public enum Decision: Equatable, Sendable {
        /// The running Dock already holds the delay; record it and hide.
        case primed(ProcessIdentity)
        /// The running Dock started before the delay was written; restart it once.
        case restart(ProcessIdentity)
        /// No Dock is running (launchd is relaunching it); wait and decide again.
        case waitForDock
    }

    public static func decide(running: ProcessIdentity?, primed: ProcessIdentity?, delayWrittenAt: Double) -> Decision {
        guard let running else { return .waitForDock }
        if running == primed || running.startTime > delayWrittenAt { return .primed(running) }
        return .restart(running)
    }
}
