import Foundation
import FocusDockCore

/// The one client for the `aerospace` CLI: switching workspaces and routing new windows to
/// their mode's workspace from `aerospace subscribe window-detected`. Every failure only
/// marks AeroSpace unavailable; the dock keeps working without it.
@MainActor
final class AeroSpace {
    enum Status: Equatable {
        case unknown
        case available
        case unavailable(String)
    }

    private(set) var status: Status = .unknown {
        didSet { if status != oldValue { onStatusChange?() } }
    }
    var onStatusChange: (() -> Void)?

    /// Resolved once: a GUI app's PATH does not include the nix-darwin profiles.
    private let executable: URL? = AeroSpaceLocator.find(
        path: ProcessInfo.processInfo.environment["PATH"],
        user: NSUserName(),
        isExecutable: FileManager.default.isExecutableFile(atPath:)
    ).map(URL.init(fileURLWithPath:))

    private static let timeout = 5.0
    private static let maxBackoff = 30.0
    /// A subscription that lived this long was healthy, so the next failure starts the backoff over.
    private static let healthyRun = 30.0

    private var routingTask: Task<Void, Never>?
    private var subscription: ProcessBox?

    func focus(workspace: String) async {
        _ = await run(["workspace", workspace])
    }

    /// Streams new windows to `route`, which returns `move-node-to-workspace` arguments or nil.
    /// The subscription restarts with exponential backoff whenever it ends.
    func startRouting(_ route: @escaping @MainActor (WindowDetected) -> [String]?) {
        routingTask?.cancel()
        routingTask = Task { [weak self] in
            var backoff = 1.0
            while !Task.isCancelled, let self {
                let started = Date()
                await self.probe()
                await self.subscribe(route)
                if Date().timeIntervalSince(started) > Self.healthyRun { backoff = 1 }
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2, Self.maxBackoff)
            }
        }
    }

    /// Kills the subscription child; otherwise it outlives us until its next write fails.
    func stop() {
        routingTask?.cancel()
        routingTask = nil
        if let process = subscription?.process, process.isRunning { process.terminate() }
        subscription = nil
    }

    private func probe() async {
        _ = await run(["list-workspaces", "--focused"])
    }

    private func subscribe(_ route: @escaping @MainActor (WindowDetected) -> [String]?) async {
        guard let executable, status == .available else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["subscribe", "window-detected"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            status = .unavailable("cannot run aerospace: \(error.localizedDescription)")
            return
        }
        subscription = ProcessBox(process)
        defer { subscription = nil }
        do {
            for try await line in output.fileHandleForReading.bytes.lines {
                guard let window = WindowDetected.parse(line: line), let arguments = route(window) else { continue }
                _ = await run(arguments)
            }
        } catch {
            NSLog("FocusDock: aerospace subscription read failed: %@", String(describing: error))
        }
        if process.isRunning { process.terminate() }
        NSLog("FocusDock: aerospace subscription ended; restarting")
    }

    /// Runs one command and records the outcome in `status`; returns stdout on success.
    @discardableResult
    private func run(_ arguments: [String]) async -> String? {
        guard let executable else {
            status = .unavailable("not installed")
            return nil
        }
        do {
            let result = try await ProcessRunner.run(executable, arguments, timeout: Self.timeout)
            guard result.succeeded else {
                status = .unavailable("not running")
                return nil
            }
            status = .available
            return result.output
        } catch {
            status = .unavailable(String(describing: error))
            return nil
        }
    }
}
