import Foundation

/// An exclusive `flock` on a lock file, held for the duration of `body`. Serialises theme
/// switches across processes (the CLI, the running dock, scripts) like Omarchy's flock.
public enum FileLock {
    public static func withLock<T>(_ url: URL, _ body: () async throws -> T) async throws -> T {
        let fd = try await acquire(url)
        defer { release(fd) }
        return try await body()
    }

    /// `flock(LOCK_EX)` blocks until the holder releases, and the holder may be a task in this
    /// process waiting for a cooperative thread, so the wait runs on its own thread, never the pool.
    private static func acquire(_ url: URL) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread { continuation.resume(with: Result { try acquireBlocking(url) }) }
        }
    }

    private static func acquireBlocking(_ url: URL) throws -> Int32 {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
        while flock(fd, LOCK_EX) != 0 {
            guard errno == EINTR else {
                close(fd)
                throw CocoaError(.fileLocking, userInfo: [NSFilePathErrorKey: url.path])
            }
        }
        return fd
    }

    private static func release(_ fd: Int32) {
        flock(fd, LOCK_UN)
        close(fd)
    }
}
