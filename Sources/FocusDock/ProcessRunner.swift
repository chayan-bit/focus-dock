import Foundation

/// Carries a `Process` into `@Sendable` closures; it is only started, signalled and read.
final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

struct ProcessResult: Sendable {
    let status: Int32
    let output: String
    var succeeded: Bool { status == 0 }
}

enum ProcessError: Error, CustomStringConvertible {
    case timedOut(String)

    var description: String {
        switch self {
        case .timedOut(let command): "\(command) timed out"
        }
    }
}

/// Runs a command without a shell and collects stdout. Adapted from aerospace-iconz
/// `CLIClient.run` (MIT, github.com/ankondeadlarx/aerospace-iconz): read before waiting so a
/// full pipe cannot deadlock the child, and SIGKILL it after `timeout` so a stuck call cannot
/// block later ones.
enum ProcessRunner {
    static func run(_ executable: URL, _ arguments: [String], timeout: Double) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let box = ProcessBox(process)
        let command = ([executable.lastPathComponent] + arguments).joined(separator: " ")
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = box.process
                let exited = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in exited.signal() }
                do {
                    try process.run()
                } catch {
                    return continuation.resume(throwing: error)
                }
                let watchdog = DispatchWorkItem {
                    if box.process.isRunning { kill(box.process.processIdentifier, SIGKILL) }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                let data = output.fileHandleForReading.readDataToEndOfFile()
                exited.wait()
                watchdog.cancel()
                if process.terminationReason == .uncaughtSignal, process.terminationStatus == SIGKILL {
                    continuation.resume(throwing: ProcessError.timedOut(command))
                } else {
                    continuation.resume(returning: ProcessResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self)))
                }
            }
        }
    }
}
