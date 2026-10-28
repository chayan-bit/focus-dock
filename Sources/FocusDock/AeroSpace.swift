import Foundation
import FocusDockCore

/// The one client for the `aerospace` CLI: commands, plus one long-lived
/// `aerospace subscribe window-detected focus-changed` whose events go to a handler. Every
/// failure only marks AeroSpace unavailable; the dock keeps working without it.
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

    /// Returns whether the command succeeded. Commands on a window that may be gone already
    /// pass `affectsStatus: false`, so their failure does not mark AeroSpace unavailable.
    func perform(_ arguments: [String], affectsStatus: Bool = true) async -> Bool {
        await run(arguments, affectsStatus: affectsStatus) != nil
    }

    /// Streams subscription events to `handle`, one at a time. The subscription restarts with
    /// exponential backoff whenever it ends.
    func startEvents(_ handle: @escaping @MainActor (AeroSpaceEvent) async -> Void) {
        routingTask?.cancel()
        routingTask = Task { [weak self] in
            var backoff = 1.0
            while !Task.isCancelled, let self {
                let started = Date()
                await self.probe()
                await self.subscribe(handle)
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

    private func subscribe(_ handle: @escaping @MainActor (AeroSpaceEvent) async -> Void) async {
        guard let executable, status == .available else { return }
        let process = Process()
        process.executableURL = executable
        // With the initial state, so the focused workspace is known from the start.
        process.arguments = AeroSpaceEvent.subscribeArguments
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
                guard let event = AeroSpaceEvent.parse(line: line) else { continue }
                await handle(event)
            }
        } catch {
            NSLog("FocusDock: aerospace subscription read failed: %@", String(describing: error))
        }
        if process.isRunning { process.terminate() }
        NSLog("FocusDock: aerospace subscription ended; restarting")
    }

    /// Runs one command and records the outcome in `status`; returns stdout on success.
    @discardableResult
    private func run(_ arguments: [String], affectsStatus: Bool = true) async -> String? {
        guard let executable else {
            status = .unavailable("not installed")
            return nil
        }
        do {
            let result = try await ProcessRunner.run(executable, arguments, timeout: Self.timeout)
            guard result.succeeded else {
                if affectsStatus { status = .unavailable("not running") }
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
