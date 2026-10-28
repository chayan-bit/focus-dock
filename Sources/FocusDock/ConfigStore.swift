import AppKit
import FocusDockCore

/// Reads `~/.config/focusdock/modes.json`, writes a default one built from the installed apps
/// when it is missing, and reports edits. Both the directory (atomic saves rename into it)
/// and the file itself (in-place writes) are watched, then the reload is debounced.
@MainActor
final class ConfigStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/focusdock")
    static let file = directory.appending(path: "modes.json")

    private static let debounce: Duration = .milliseconds(250)

    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: Task<Void, Never>?
    private var lastData: Data?

    static func defaultConfig() -> ModesConfig {
        DefaultModes.make { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    /// The parsed file; a missing file is replaced by the default, which is written to disk.
    func load() -> Result<ModesConfig, ConfigError> {
        let data: Data
        do {
            data = try Data(contentsOf: Self.file)
        } catch CocoaError.fileReadNoSuchFile {
            return writeDefault()
        } catch {
            return .failure(ConfigError(["cannot read \(Self.file.path): \(error.localizedDescription)"]))
        }
        lastData = data
        do {
            return .success(try ModesConfig.parse(data))
        } catch {
            return .failure(error)
        }
    }

    private func writeDefault() -> Result<ModesConfig, ConfigError> {
        let config = Self.defaultConfig()
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            let data = try config.encoded()
            try data.write(to: Self.file, options: .atomic)
            lastData = data
        } catch {
            NSLog("FocusDock: could not write the default config: %@", String(describing: error))
        }
        return .success(config)
    }

    /// Calls `onChange` after the file's bytes change, at most once per debounce window.
    func watch(_ onChange: @escaping @MainActor () -> Void) {
        rearm(onChange)
    }

    private func rearm(_ onChange: @escaping @MainActor () -> Void) {
        sources.forEach { $0.cancel() }
        sources = [Self.directory, Self.file].compactMap { url in
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete, .attrib], queue: .main
            )
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.changed(onChange) } }
            source.setCancelHandler { close(fd) }
            source.resume()
            return source
        }
    }

    private func changed(_ onChange: @escaping @MainActor () -> Void) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            // An atomic save replaced the file's inode, so the file watch must be re-opened.
            self.rearm(onChange)
            let data = try? Data(contentsOf: Self.file)
            guard data != self.lastData else { return }
            onChange()
        }
    }
}
