import Foundation

/// One problem in a config file, shown as `modes.json:12:5 modes[1].color: <message>`.
/// `path` is the display path (`modes[1].color`, empty for the whole file); `line` and
/// `column` are 1-based and absent when the problem has no place in the text.
public struct ConfigProblem: Error, Equatable, Sendable, CustomStringConvertible {
    public let file: String
    public let line: Int?
    public let column: Int?
    public let path: String
    public let message: String

    public init(file: String = "", line: Int? = nil, column: Int? = nil, path: String = "", message: String) {
        self.file = file
        self.line = line
        self.column = column
        self.path = path
        self.message = message
    }

    public var description: String {
        let location = [file.isEmpty ? nil : file, line.map(String.init), column.map(String.init)].compactMap(\.self)
        let subject = path.isEmpty ? message : "\(path): \(message)"
        return location.isEmpty ? subject : "\(location.joined(separator: ":")) \(subject)"
    }
}
