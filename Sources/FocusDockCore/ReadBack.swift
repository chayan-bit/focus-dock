import Foundation

/// Foreign setters (CoreDock, CFPreferences, SkyLight) return before the change lands, and a
/// zero status does not mean it applied, so every write is confirmed by reading it back.
public enum ReadBack {
    /// Reads until `read` returns `expected` or `timeout` passes; reads at least once. A nil
    /// read (value not readable yet) keeps polling. Cancellation counts as a miss.
    public static func poll<T: Equatable & Sendable>(
        _ expected: T,
        timeout: Duration,
        interval: Duration = .milliseconds(5),
        read: @Sendable () async -> T?
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            if await read() == expected { return true }
            let remaining = deadline - clock.now
            guard remaining > .zero else { return false }
            do {
                try await Task.sleep(for: min(interval, remaining))
            } catch {
                return false
            }
        }
    }
}
