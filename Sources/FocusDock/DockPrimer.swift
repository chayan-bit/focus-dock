import AppKit
import Darwin
import FocusDockCore

/// Restarts the native Dock at most once per launch so it reads `autohide-delay`, which it only
/// does at startup (docs/research/e2e-phase1.md, "Dock pop-up fix"). The primed Dock is recorded
/// by PID and start time and kept across quits: it still holds the delay in memory.
@MainActor
enum DockPrimer {
    private static let record = JSONFileStore<ProcessIdentity>.standard("primed-dock.json")
    private static let timeout: Duration = .seconds(5)
    private static let pollInterval: Duration = .milliseconds(100)

    /// Returns whether the running Dock holds the delay, restarting it if needed.
    static func prime(delayWrittenAt: Double) async -> Bool {
        let primed = loadRecord()
        var restarted = false
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            switch DockPriming.decide(running: runningDock(), primed: primed, delayWrittenAt: delayWrittenAt) {
            case .primed(let dock):
                saveRecord(dock)
                return true
            case .restart(let dock) where !restarted:
                NSLog("FocusDock: restarting the Dock (pid %d) so it applies autohide-delay", dock.pid)
                guard kill(dock.pid, SIGTERM) == 0 else {
                    NSLog("FocusDock: could not restart the Dock: errno %d", errno)
                    return false
                }
                restarted = true
            case .restart, .waitForDock:
                break
            }
            try? await Task.sleep(for: pollInterval)
        }
        return false
    }

    private static func runningDock() -> ProcessIdentity? {
        let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first { !$0.isTerminated }
        guard let pid = dock?.processIdentifier, let start = startTime(of: pid) else { return nil }
        return ProcessIdentity(pid: pid, startTime: start)
    }

    private static func startTime(of pid: pid_t) -> Double? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
    }

    private static func loadRecord() -> ProcessIdentity? {
        do {
            return try record.load()
        } catch {
            NSLog("FocusDock: ignoring unreadable primed-dock record: %@", String(describing: error))
            return nil
        }
    }

    private static func saveRecord(_ dock: ProcessIdentity) {
        do {
            try record.save(dock)
        } catch {
            NSLog("FocusDock: could not save the primed-dock record: %@", String(describing: error))
        }
    }
}
