import AppKit

/// Runs blocks on the main thread through the run loop rather than the main dispatch queue.
/// AppKit's nested waits (the `.terminateLater` wait inside `terminate:`) spin the run loop, but
/// libdispatch will not drain the main queue re-entrantly, so when such a wait is entered from a
/// main-queue block or a main-actor task, nothing on the main queue runs until it ends. Anything
/// the wait depends on, and every quit trigger, goes through here instead.
enum MainRunLoop {
    static func perform(_ block: @escaping @Sendable @MainActor () -> Void) {
        let main = CFRunLoopGetMain()
        // The terminate wait runs in NSModalPanelRunLoopMode, a common mode on macOS 27; named as well in case that changes.
        let modes = [CFRunLoopMode.commonModes.rawValue, RunLoop.Mode.modalPanel.rawValue as CFString] as CFArray
        CFRunLoopPerformBlock(main, modes) { MainActor.assumeIsolated(block) }
        CFRunLoopWakeUp(main)
    }

    /// `NSApp.terminate` from the run loop, so the main queue keeps draining during the quit wait.
    static func terminate() {
        perform { NSApp.terminate(nil) }
    }
}
