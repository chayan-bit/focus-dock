// Reproduces FocusDock's quit path (AppDelegate.applicationShouldTerminate) in a bare
// NSApplication that touches no system state, compiled with the app's MainRunLoop.swift.
// Each run quits once and exits 0 when the `.terminateLater` reply arrived, 2 when it deadlocked.
// Scenarios: signal (terminate from a main-queue block, as the signal sources do), task (from a
// main-actor task, as app.quit does), stuck (the replay never ends, so the timeout must reply).
import AppKit

let scenario = CommandLine.arguments.dropFirst().first ?? "signal"
let timeout: TimeInterval = 2
setvbuf(stdout, nil, _IONBF, 0)

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    static var hasReplied = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 3 * timeout) {
            print("\(scenario): deadlock, no reply")
            exit(2)
        }
        if scenario == "task" {
            Task { MainRunLoop.terminate() }
        } else {
            DispatchQueue.main.async { MainRunLoop.terminate() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let replay: Duration = scenario == "stuck" ? .seconds(60) : .milliseconds(100)
        Task.detached {
            try? await Task.sleep(for: replay)
            MainRunLoop.perform { Delegate.reply("replay") }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            MainRunLoop.perform { Delegate.reply("timeout") }
        }
        return .terminateLater
    }

    static func reply(_ source: String) {
        guard !hasReplied else { return }
        hasReplied = true
        print("\(scenario): reply from \(source) in \(RunLoop.current.currentMode?.rawValue ?? "no mode")")
        NSApp.reply(toApplicationShouldTerminate: true)
    }
}

let delegate = Delegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
