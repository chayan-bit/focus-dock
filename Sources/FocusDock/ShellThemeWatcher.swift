import Foundation
import FocusDockCore

/// Re-tints the running dock whenever `current/theme` is swapped or removed: it watches the
/// `current/` directory (every swap and reset renames or deletes an entry in it) and reads
/// `current/theme/focusdock.toml`. No theme means the native look.
@MainActor
final class ShellThemeWatcher {
    private let paths = ThemeSystem.paths
    private var source: DispatchSourceFileSystemObject?
    private var pending: Task<Void, Never>?
    private let apply: (ShellTheme?) -> Void

    init(apply: @escaping (ShellTheme?) -> Void) {
        self.apply = apply
    }

    func start() {
        try? FileManager.default.createDirectory(at: paths.current, withIntermediateDirectories: true)
        reload()
        let fd = open(paths.current.path, O_EVTONLY)
        guard fd >= 0 else { return NSLog("FocusDock: cannot watch %@", paths.current.path) }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .link], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.changed() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func changed() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    func reload() {
        let file = paths.currentTheme.appending(path: "focusdock.toml")
        apply(TextFile.read(file).map(ShellTheme.parse))
    }
}
