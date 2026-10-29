import Foundation
import FocusDockCore

/// `focusdock config check [file]`: validates modes.json and shell.jsonc against their schemas
/// without touching the running dock. Problems print as `file:line:col: message`, one per
/// line on stdout, and the exit status is 1 when there are any. With no file, both files in
/// `~/.config/focusdock` are checked, and one that does not exist counts as clean (defaults apply).
enum ConfigCLI {
    static let usage = "usage: focusdock config check [file]"

    /// The file kinds `check` knows, by file name.
    private static let checks: [String: @Sendable (Data) throws(ConfigError) -> Void] = [
        ModesConfig.fileName: { (data: Data) throws(ConfigError) in _ = try ModesConfig.parse(data) },
        ShellConfig.fileName: { (data: Data) throws(ConfigError) in _ = try ShellConfig.parse(data) },
    ]

    static func runAndExit(_ arguments: [String]) -> Never {
        exit(run(arguments))
    }

    static func run(_ arguments: [String]) -> Int32 {
        guard arguments.first == "check", arguments.count <= 2 else { return fail(usage) }
        if arguments.count == 2 {
            let file = URL(filePath: arguments[1])
            guard checks[file.lastPathComponent] != nil else {
                return fail("unknown config file \(file.lastPathComponent); expected \(checks.keys.sorted().joined(separator: " or "))")
            }
            return check(file, missingIsClean: false)
        }
        return [ConfigFiles.modes, ConfigFiles.shell].map { check($0, missingIsClean: true) }.max() ?? 0
    }

    private static func check(_ file: URL, missingIsClean: Bool) -> Int32 {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile where missingIsClean {
            print("\(file.path): not present, defaults apply")
            return 0
        } catch {
            print("\(file.path): cannot read: \(error.localizedDescription)")
            return 1
        }
        do {
            try checks[file.lastPathComponent]?(data)
            print("\(file.path): ok")
            return 0
        } catch {
            error.items.forEach { print(line($0, file: file)) }
            return 1
        }
    }

    /// `file:line:col: path: message`, the shape editors and terminals turn into links.
    static func line(_ problem: ConfigProblem, file: URL) -> String {
        let place = [file.path, problem.line.map(String.init), problem.column.map(String.init)].compactMap(\.self).joined(separator: ":")
        return "\(place): \(problem.path.isEmpty ? "" : "\(problem.path): ")\(problem.message)"
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("focusdock: \(message)\n".utf8))
        return 1
    }
}
