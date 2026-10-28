import AppKit
import Darwin
import FocusDockCore

/// Hides the system Dock via the CoreDock SPI (the one private API, SPEC 4.4) and makes sure
/// it comes back: on normal quit, on SIGTERM/SIGINT/SIGHUP, and via a watchdog on a crash.
enum NativeDock {
    static let watchdogFlag = "--watchdog"

    private static let dockDomain = "com.apple.dock"
    private static let delayKey = "autohide-delay"

    /// Resolves CoreDock{Get,Set}AutoHideEnabled at runtime (nil if the SPI is gone) and pairs
    /// them with the Dock's `autohide-delay` pref, written through CFPreferences.
    static func dockAPI() -> NativeDockAPI? {
        typealias Getter = @convention(c) () -> Bool
        typealias Setter = @convention(c) (Bool) -> Void
        let path = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        guard let handle = dlopen(path, RTLD_LAZY),
              let get = dlsym(handle, "CoreDockGetAutoHideEnabled"),
              let set = dlsym(handle, "CoreDockSetAutoHideEnabled")
        else { return nil }
        let getter = unsafeBitCast(get, to: Getter.self)
        let setter = unsafeBitCast(set, to: Setter.self)
        return NativeDockAPI(
            getAutoHide: { getter() },
            setAutoHide: { setter($0) },
            getAutoHideDelay: { (CFPreferencesCopyAppValue(delayKey as CFString, dockDomain as CFString) as? NSNumber)?.doubleValue },
            setAutoHideDelay: { delay in
                // The Dock stores it as a float, as `defaults write -float` does.
                CFPreferencesSetAppValue(delayKey as CFString, delay.map { NSNumber(value: Float($0)) }, dockDomain as CFString)
                CFPreferencesAppSynchronize(dockDomain as CFString)
            }
        )
    }

    static func keeper() -> NativeDockKeeper? {
        dockAPI().map { NativeDockKeeper(store: FileStateStore.standard, dock: $0) }
    }

    /// Starts the watchdog, records the originals and writes the delay, makes sure the running
    /// Dock has applied it, then hides. Without a watchdog a crash would strand the user without
    /// a Dock, and without the delay the hidden Dock pops up at the screen edge; in either case
    /// the Dock is left visible and the originals are restored.
    @MainActor
    static func hide() async {
        guard let keeper = keeper() else {
            NSLog("FocusDock: CoreDock SPI not found; leaving the system Dock visible")
            return
        }
        do {
            try spawnWatchdog()
            try keeper.prepare()
            let delayWrittenAt = Date().timeIntervalSince1970
            guard await DockPrimer.prime(delayWrittenAt: delayWrittenAt) else {
                NSLog("FocusDock: the Dock did not apply autohide-delay; leaving it visible")
                return restore(keeper)
            }
            try keeper.hide()
        } catch {
            NSLog("FocusDock: not hiding the system Dock: %@", String(describing: error))
            restore(keeper)
        }
    }

    static func restore(_ keeper: NativeDockKeeper?) {
        do {
            try keeper?.restore()
        } catch {
            NSLog("FocusDock: restoring the system Dock failed: %@", String(describing: error))
        }
    }

    private static func spawnWatchdog() throws {
        let process = Process()
        process.executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [watchdogFlag, String(getpid())]
        try process.run()
    }

    /// Watchdog mode: wait for the parent to exit, restore if it left the state file behind.
    static func runWatchdog(parentPID: pid_t) -> Never {
        // A terminal Ctrl-C hits the whole process group; the watchdog must outlive the parent.
        signal(SIGINT, SIG_IGN)
        signal(SIGHUP, SIG_IGN)
        let source = DispatchSource.makeProcessSource(identifier: parentPID, eventMask: .exit, queue: .main)
        source.setEventHandler { restoreAndExit() }
        source.resume()
        // The parent may already be gone before the source was armed.
        if kill(parentPID, 0) != 0, errno == ESRCH { restoreAndExit() }
        withExtendedLifetime(source) { dispatchMain() }
    }

    private static func restoreAndExit() -> Never {
        restore(keeper())
        exit(0)
    }

    /// Routes termination signals through NSApp.terminate so applicationWillTerminate restores.
    @MainActor
    static func installSignalHandlers() -> [DispatchSourceSignal] {
        [SIGTERM, SIGINT, SIGHUP].map { sig in
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            source.resume()
            return source
        }
    }
}
