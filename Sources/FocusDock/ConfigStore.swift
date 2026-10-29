import AppKit
import FocusDockCore

/// The user's config directory (`~/.config/focusdock`) and its files.
enum ConfigFiles {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/focusdock")
    static let modes = directory.appending(path: ModesConfig.fileName)
    static let shell = directory.appending(path: ShellConfig.fileName)
}

private let debounce: Duration = .milliseconds(250)

/// Reads one config file through its `ConfigDocument` and reports edits. A missing file gives
/// `whenMissing`'s value, and its bytes when there are any to write. Both the directory (atomic
/// saves rename into it) and the file itself (in-place writes) are watched, then the reload
/// is debounced. The caller keeps the last good value when `load` fails.
@MainActor
final class ConfigStore<Value: Decodable & Sendable> {
    let file: URL
    private let document: ConfigDocument<Value>
    private let whenMissing: @MainActor () -> (value: Value, write: Data?)

    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: Task<Void, Never>?
    private var lastData: Data?

    init(file: URL, document: ConfigDocument<Value>, whenMissing: @escaping @MainActor () -> (value: Value, write: Data?)) {
        self.file = file
        self.document = document
        self.whenMissing = whenMissing
    }

    /// The parsed file; a missing file is replaced by the default, which is written to disk when it has bytes.
    func load() -> Result<Value, ConfigError> {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile {
            return useDefault()
        } catch {
            return .failure(ConfigError(["cannot read \(file.path): \(error.localizedDescription)"]))
        }
        lastData = data
        do {
            return .success(try document.parse(data))
        } catch {
            return .failure(error)
        }
    }

    private func useDefault() -> Result<Value, ConfigError> {
        lastData = nil
        let missing = whenMissing()
        guard let data = missing.write else { return .success(missing.value) }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            lastData = data
        } catch {
            NSLog("FocusDock: could not write the default %@: %@", file.lastPathComponent, String(describing: error))
        }
        return .success(missing.value)
    }

    /// Calls `onChange` after the file's bytes change, at most once per debounce window.
    func watch(_ onChange: @escaping @MainActor () -> Void) {
        rearm(onChange)
    }

    private func rearm(_ onChange: @escaping @MainActor () -> Void) {
        sources.forEach { $0.cancel() }
        sources = [file.deletingLastPathComponent(), file].compactMap { url in
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
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            // An atomic save replaced the file's inode, so the file watch must be re-opened.
            self.rearm(onChange)
            let data = try? Data(contentsOf: self.file)
            guard data != self.lastData else { return }
            onChange()
        }
    }
}

extension ConfigStore where Value == ModesConfig {
    static func defaultConfig() -> ModesConfig {
        DefaultModes.make { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    /// `modes.json`; a missing file is written with the default built from the installed apps.
    static func modes() -> ConfigStore<ModesConfig> {
        ConfigStore<ModesConfig>(file: ConfigFiles.modes, document: ModesConfig.document()) {
            let config = defaultConfig()
            do {
                return (config, try config.encoded())
            } catch {
                NSLog("FocusDock: could not encode the default config: %@", String(describing: error))
                return (config, nil)
            }
        }
    }
}

extension ConfigStore where Value == ShellConfig {
    /// `shell.jsonc`; a missing file means the built-in defaults and is not created.
    static func shell() -> ConfigStore<ShellConfig> {
        ConfigStore<ShellConfig>(file: ConfigFiles.shell, document: ShellConfig.document()) { (ShellConfig(), nil) }
    }
}
