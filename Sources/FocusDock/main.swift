import AppKit

let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: NativeDock.watchdogFlag) {
    guard flag + 1 < arguments.count, let parent = pid_t(arguments[flag + 1]), parent > 1 else {
        FileHandle.standardError.write(Data("usage: FocusDock --watchdog <parentPID>\n".utf8))
        exit(64)
    }
    NativeDock.runWatchdog(parentPID: parent)
}

if arguments.count > 1, arguments[1] == "theme" {
    ThemeCLI.runAndExit(Array(arguments.dropFirst(2)))
}

// One dock at a time; a second copy must not touch the native Dock state.
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
       .contains(where: { $0.processIdentifier != getpid() && !$0.isTerminated }) {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
