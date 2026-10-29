import DynamicJSON
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

/// Every problem found in a config file, in file order.
public struct ConfigError: Error, Equatable, Sendable, CustomStringConvertible {
    public let items: [ConfigProblem]

    public init(items: [ConfigProblem]) { self.items = items }

    /// Problems with no place in a file, such as a read error.
    public init(_ problems: [String]) { items = problems.map { ConfigProblem(message: $0) } }

    public var problems: [String] { items.map(\.description) }

    public var description: String { problems.joined(separator: "\n") }
}

/// Where shipped resources live: the app bundle's Resources, or `$FOCUSDOCK_RESOURCES`
/// (a repo checkout). Same rule as `ThemeSystem.resources` in the app.
public enum ShippedResources {
    public static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["FOCUSDOCK_RESOURCES"], !override.isEmpty {
            return URL(filePath: override)
        }
        return Bundle.main.resourceURL ?? Bundle.main.bundleURL
    }

    public static var schemas: URL { directory.appending(path: "schemas") }
}

/// A JSONC config file checked in four steps, each reporting every problem it finds:
/// syntax (with positions), the JSON Schema, Codable decoding, then `semantic` checks
/// that a schema cannot express (cross-references). A later step runs only when the
/// earlier ones found nothing.
public struct ConfigDocument<Value: Decodable & Sendable>: Sendable {
    public let fileName: String
    public let schema: URL
    private let semantic: @Sendable (Value) -> [ConfigProblem]

    public init(fileName: String, schema: URL, semantic: @escaping @Sendable (Value) -> [ConfigProblem] = { _ in [] }) {
        self.fileName = fileName
        self.schema = schema
        self.semantic = semantic
    }

    public func parse(_ data: Data) throws(ConfigError) -> Value {
        guard let text = String(data: data, encoding: .utf8) else { throw failure([ConfigProblem(message: "not UTF-8 text")]) }
        let locator: ConfigLocator
        do {
            locator = ConfigLocator(file: fileName, positions: try JSONCPositions.index(text))
        } catch {
            throw failure([error])
        }
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        try check(locator.place(try schemaProblems(data, decoder: decoder)))
        let value: Value
        do {
            value = try decoder.decode(Value.self, from: data)
        } catch {
            throw ConfigError(items: locator.place([DecodingProblem.describe(error)]))
        }
        try check(locator.place(semantic(value)))
        return value
    }

    private func schemaProblems(_ data: Data, decoder: JSONDecoder) throws(ConfigError) -> [ConfigProblem] {
        let resource: JSONSchemaResource
        do {
            resource = try JSONSchemaResource(url: schema)
        } catch {
            throw failure([ConfigProblem(message: "cannot load schema \(schema.path): \(error)")])
        }
        do {
            return SchemaProblem.list(try decoder.decode(JSON.self, from: data).validate(with: resource))
        } catch {
            throw failure([ConfigProblem(message: "cannot validate against \(schema.lastPathComponent): \(error)")])
        }
    }

    private func check(_ problems: [ConfigProblem]) throws(ConfigError) {
        guard problems.isEmpty else { throw ConfigError(items: problems) }
    }

    private func failure(_ problems: [ConfigProblem]) -> ConfigError {
        ConfigError(items: problems.map {
            ConfigProblem(file: fileName, line: $0.line, column: $0.column, path: $0.path, message: $0.message)
        })
    }
}

/// A display path such as `modes[1].exit.to.social`, as segments.
enum ConfigPath {
    enum Segment: Equatable {
        case key(String)
        case index(Int)
    }

    static func display(_ segments: [Segment]) -> String {
        let joined = segments.map { segment in
            switch segment {
            case .key(let key): ".\(key)"
            case .index(let index): "[\(index)]"
            }
        }.joined()
        return joined.hasPrefix(".") ? String(joined.dropFirst()) : joined
    }

    static func pointer(_ segments: some Sequence<Segment>) -> String {
        segments.map { segment in
            switch segment {
            case .key(let key): "/" + key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
            case .index(let index): "/\(index)"
            }
        }.joined()
    }

    /// Inverse of `display`; a key that itself holds `.` or `[` splits, which only costs
    /// precision, since lookups fall back to the nearest enclosing value.
    static func segments(_ path: String) -> [Segment] {
        path.split(separator: ".").flatMap { part -> [Segment] in
            let pieces = part.split(separator: "[", omittingEmptySubsequences: false)
            let key: [Segment] = pieces[0].isEmpty ? [] : [.key(String(pieces[0]))]
            return key + pieces.dropFirst().map { piece in
                Int(piece.dropLast()).map(Segment.index) ?? .key("[\(piece)")
            }
        }
    }
}

/// Puts the file name and the line and column of the nearest enclosing value on problems,
/// and sorts them into file order.
struct ConfigLocator {
    let file: String
    let positions: [String: (line: Int, column: Int)]

    func place(_ problems: [ConfigProblem]) -> [ConfigProblem] {
        problems.enumerated().map { offset, problem in
            let at = position(ConfigPath.segments(problem.path))
            let placed = ConfigProblem(file: file, line: at?.line, column: at?.column, path: problem.path, message: problem.message)
            return (offset, placed)
        }
        .sorted { a, b in
            let left = (a.1.line ?? .max, a.1.column ?? .max, a.0)
            let right = (b.1.line ?? .max, b.1.column ?? .max, b.0)
            return left < right
        }
        .map(\.1)
    }

    private func position(_ segments: [ConfigPath.Segment]) -> (line: Int, column: Int)? {
        nearest(segments[...], under: "")?.at ?? positions[""]
    }

    /// The deepest indexed value on the path. A key that holds `.` (`dock.reveal`) arrives
    /// as several segments, so each run of keys is also tried as one joined key.
    private func nearest(_ rest: ArraySlice<ConfigPath.Segment>, under pointer: String) -> (depth: Int, at: (line: Int, column: Int))? {
        var best: (depth: Int, at: (line: Int, column: Int))?
        var key = ""
        for (offset, segment) in rest.enumerated() {
            let next: String
            switch segment {
            case .index(let index):
                next = pointer + "/\(index)"
            case .key(let name):
                key += offset == 0 ? name : ".\(name)"
                next = pointer + ConfigPath.pointer([.key(key)])
            }
            if let at = positions[next] {
                let deeper = nearest(rest.dropFirst(offset + 1), under: next)
                let found = deeper.map { (depth: offset + 1 + $0.depth, at: $0.at) } ?? (depth: offset + 1, at: at)
                if found.depth > (best?.depth ?? 0) { best = found }
            }
            if case .index = segment { break }
        }
        return best
    }
}

/// JSON Schema errors as readable problems. A failed `pattern` uses the schema's
/// `patternErrorMessage` (the VS Code convention); a missing property is reported at its own path.
enum SchemaProblem {
    static func list(_ result: JSONSchemaValidationResult) -> [ConfigProblem] {
        result.errors.flatMap { error -> [ConfigProblem] in
            let at = error.value.location.segments.map { segment -> ConfigPath.Segment in
                switch segment {
                case .member(let key): .key(key)
                case .index(let index): .index(index)
                }
            }
            guard let reason = error.message.reason as? JSONSchemaDraft2020.Reason else {
                return [ConfigProblem(path: ConfigPath.display(at), message: error.message.reason.reason)]
            }
            if case .propertiesMissing(let names) = reason {
                return names.map { ConfigProblem(path: ConfigPath.display(at + [.key($0)]), message: "missing") }
            }
            let text = message(reason, value: error.value.value, schema: error.message.schema)
            return [ConfigProblem(path: ConfigPath.display(at), message: text)]
        }
    }

    private static func message(_ reason: JSONSchemaDraft2020.Reason, value: JSON, schema: JSONSchema) -> String {
        if case .alwaysFails = reason { return "unknown key" }
        guard case .descriptor(let descriptor, let raw) = schema else { return reason.reason }
        switch reason {
        case .invalidType(let expected, _):
            return "expected \(phrase(expected.subtracting(.null)))"
        case .valueNotConst:
            return descriptor.const.map { "must be \($0), found \(value)" } ?? reason.reason
        case .valueNotFoundInEnum:
            return "must be one of \((descriptor.enum ?? []).map(\.description).joined(separator: ", "))"
        case .patternNotMatching:
            guard case .object(let members) = raw, case .string(let custom)? = members["patternErrorMessage"] else { return reason.reason }
            return custom
        case .lessThanMinLength(_, let minimum):
            return minimum == 1 ? "must not be empty" : "must be at least \(minimum) characters"
        case .tooFewArrayItems(_, let minimum):
            return minimum == 1 ? "must not be empty" : "must have at least \(minimum) items"
        case .belowIntMinimum(_, let bound, let exclusive), .belowFloatMinimum(_, let bound, let exclusive):
            return "must be \(exclusive ? ">" : ">=") \(number(bound))"
        case .exceedsIntMaximum(_, let bound, let exclusive), .exceedsFloatMaximum(_, let bound, let exclusive):
            return "must be \(exclusive ? "<" : "<=") \(number(bound))"
        default:
            return reason.reason
        }
    }

    private static func phrase(_ type: JSONType) -> String {
        switch type {
        case .string: "a string"
        case .number: "a number"
        case .integer: "an integer"
        case .boolean: "true or false"
        case .array: "an array"
        case .object: "an object"
        default: type.description
        }
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(value)
    }
}

/// A Codable failure (after the schema passed) as a problem at its coding path.
enum DecodingProblem {
    static func describe(_ error: any Error) -> ConfigProblem {
        guard let error = error as? DecodingError else { return ConfigProblem(message: String(describing: error)) }
        switch error {
        case .keyNotFound(let key, let context):
            return ConfigProblem(path: path(context.codingPath + [key]), message: "missing")
        case .typeMismatch(let type, let context):
            return ConfigProblem(path: path(context.codingPath), message: "expected \(typeName(type))")
        case .valueNotFound(let type, let context):
            return ConfigProblem(path: path(context.codingPath), message: "expected \(typeName(type)), found null")
        case .dataCorrupted(let context):
            let underlying = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return ConfigProblem(path: path(context.codingPath), message: underlying ?? context.debugDescription)
        @unknown default:
            return ConfigProblem(message: String(describing: error))
        }
    }

    private static func path(_ keys: [any CodingKey]) -> String {
        ConfigPath.display(keys.map { key in key.intValue.map(ConfigPath.Segment.index) ?? .key(key.stringValue) })
    }

    private static func typeName(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: "a string"
        case is Double.Type, is Int.Type: "a number"
        case is Bool.Type: "true or false"
        case is [Any].Type: "an array"
        default: "an object"
        }
    }
}
