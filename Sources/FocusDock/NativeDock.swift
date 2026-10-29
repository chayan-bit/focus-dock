import AppKit
import Darwin
import FocusDockCore

/// Hides the system Dock via the CoreDock SPI (the one private API, SPEC 4.4) and makes sure
/// it comes back: on normal quit, on SIGTERM/SIGINT/SIGHUP, and via a watchdog that replays
/// the restore ledger (SHELL-SPEC 4.3) on a crash.
enum NativeDock {
    static let watchdogFlag = "--watchdog"

    private static let dockDomain = "com.apple.dock"
    private static let delayKey = "autohide-delay"

    /// Resolves CoreDock{Get,Set}AutoHideEnabled through the capability symbol table (nil if
    /// the SPI is gone, so hiding is skipped) and pairs them with the Dock's `autohide-delay`
    /// pref, written through CFPreferences.
    static func dockAPI() -> NativeDockAPI? {
        guard let getter = SymbolTable.function(.coreDockGetAutoHide, as: (@convention(c) () -> Bool).self),
              let setter = SymbolTable.function(.coreDockSetAutoHide, as: (@convention(c) (Bool) -> Void).self)
        else { return nil }
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

    static func ledger() -> RestoreLedger {
        RestoreLedger(paths: ThemeSystem.paths)
    }

    /// Where Phases 1-4 kept the Dock originals; imported into the ledger once, then deleted.
    private static var legacyStore: JSONFileStore<NativeDockState> { .standard("native-dock.json") }

    static func keeper() -> NativeDockKeeper? {
        dockAPI().map { NativeDockKeeper(ledger: ledger(), dock: $0) }
    }

    /// The launch sequence: the watchdog first, so a crash at any later step is restored; then a
    /// stale ledger left by a crashed run is replayed, so its originals are back before this run
    /// records anything; then the Dock is hidden. No watchdog means the Dock is never touched.
    @MainActor
    static func launch() async {
        do {
            try spawnWatchdog()
        } catch {
            return NSLog("FocusDock: no watchdog (%@); leaving the system Dock alone", String(describing: error))
        }
        await replayLogging()
        await hide()
    }

    /// Starts the watchdog, records the originals and writes the delay, makes sure the running
    /// Dock has applied it, then hides. Without a watchdog a crash would strand the user without
    /// a Dock, and without the delay the hidden Dock pops up at the screen edge; in either case
    /// the Dock is left visible and the ledger is replayed.
    @MainActor
    static func hide() async {
        guard let keeper = keeper() else {
            NSLog("FocusDock: CoreDock SPI not found; leaving the system Dock visible")
            return
        }
        do {
            try spawnWatchdog()
            try await NativeDockKeeper.importLegacy(legacyStore, into: ledger())
            try await keeper.prepare()
            let delayWrittenAt = Date().timeIntervalSince1970
            guard await DockPrimer.prime(delayWrittenAt: delayWrittenAt) else {
                NSLog("FocusDock: the Dock did not apply autohide-delay; leaving it visible")
                return await replayLogging()
            }
            try await keeper.hide()
        } catch {
            NSLog("FocusDock: not hiding the system Dock: %@", String(describing: error))
            await replayLogging()
        }
    }

    /// Imports a leftover `native-dock.json`, then replays the whole restore ledger. The
    /// watchdog and `focusdock restore` call it; so do launch (a stale ledger, before hiding)
    /// and quit once they are wired up.
    static func replayLedger() async throws -> RestoreReport {
        let ledger = ledger()
        try await NativeDockKeeper.importLegacy(legacyStore, into: ledger)
        return try await ledger.replay(SystemRestorers.all())
    }

    private static func replayLogging() async {
        do {
            let report = try await replayLedger()
            for (key, reason) in report.failed.sorted(by: { $0.key < $1.key }) {
                NSLog("FocusDock: not restored %@: %@", key, reason)
            }
        } catch {
            NSLog("FocusDock: replaying the restore ledger failed: %@", String(describing: error))
        }
    }

    /// The synchronous quit path (applicationWillTerminate): puts the Dock originals back now
    /// without awaiting; the watchdog's replay confirms them and truncates the ledger when this
    /// process exits.
    static func restore(_ keeper: NativeDockKeeper?) {
        do {
            try keeper?.applyOriginals()
        } catch {
            NSLog("FocusDock: restoring the system Dock failed: %@", String(describing: error))
        }
    }

    @MainActor private static var watchdog: Process?

    /// Starts the watchdog once per process; it must exist before the first system setter runs.
    @MainActor
    static func spawnWatchdog() throws {
        guard watchdog == nil else { return }
        let process = Process()
        process.executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [watchdogFlag, String(getpid())]
        try process.run()
        watchdog = process
    }

    /// Watchdog mode: wait for the parent to exit, then replay whatever it left in the ledger.
    static func runWatchdog(parentPID: pid_t) -> Never {
        // A terminal Ctrl-C hits the whole process group; the watchdog must outlive the parent.
        signal(SIGINT, SIG_IGN)
        signal(SIGHUP, SIG_IGN)
        let source = DispatchSource.makeProcessSource(identifier: parentPID, eventMask: .exit, queue: .main)
        source.setEventHandler { replayAndExit() }
        source.resume()
        // The parent may already be gone before the source was armed.
        if kill(parentPID, 0) != 0, errno == ESRCH {
            source.cancel()
            replayAndExit()
        }
        withExtendedLifetime(source) { dispatchMain() }
    }

    private static func replayAndExit() {
        Task {
            await replayLogging()
            exit(0)
        }
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
