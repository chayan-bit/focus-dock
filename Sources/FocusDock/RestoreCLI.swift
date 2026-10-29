import Foundation
import FocusDockCore

/// `focusdock restore`: replays the restore ledger by hand (SHELL-SPEC 4.3), as the watchdog
/// does after a crash, and says what came back. Exits 1 if any key could not be restored.
enum RestoreCLI {
    static let usage = "usage: focusdock restore"

    static func runAndExit(_ arguments: [String]) -> Never {
        Task {
            let status = await run(arguments)
            exit(status)
        }
        dispatchMain()
    }

    static func run(_ arguments: [String]) async -> Int32 {
        guard arguments.isEmpty else { return fail(usage) }
        let report: RestoreReport
        do {
            report = try await NativeDock.replayLedger()
        } catch {
            return fail("cannot replay the restore ledger: \(error)")
        }
        report.restored.forEach { print("restored \($0)") }
        report.failed.sorted { $0.key < $1.key }.forEach { warn("not restored \($0.key): \($0.value)") }
        if report.skippedLines > 0 {
            warn("skipped \(report.skippedLines) unreadable ledger line(s)")
        }
        if report.restored.isEmpty, report.failed.isEmpty {
            print("nothing to restore")
        }
        return report.failed.isEmpty ? 0 : 1
    }

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("focusdock: \(message)\n".utf8))
    }

    private static func fail(_ message: String) -> Int32 {
        warn(message)
        return 1
    }
}
