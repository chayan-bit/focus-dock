import Foundation

/// Maps every value of a JSONC text (JSON plus `//` and `/* */` comments and trailing commas)
/// to the 1-based line and column of its first character, keyed by JSON pointer (RFC 6901;
/// "" is the root). It is also the syntax gate for config files: anything that is not JSONC
/// is reported with its position. Columns count Unicode scalars.
public enum JSONCPositions {
    public static let maximumDepth = 256

    public static func index(_ text: String) throws(ConfigProblem) -> [String: (line: Int, column: Int)] {
        var parser = JSONCParser(Array(text.utf8))
        let lines = LineTable(parser.bytes)
        do {
            try parser.document()
        } catch {
            let at = lines.position(error.offset)
            throw ConfigProblem(line: at.line, column: at.column, message: "not valid JSON: \(error.message)")
        }
        return parser.offsets.mapValues(lines.position)
    }
}

private struct SyntaxError: Error {
    let offset: Int
    let message: String
}

private struct JSONCParser {
    static let quote = UInt8(ascii: "\""), slash = UInt8(ascii: "/"), star = UInt8(ascii: "*"), newline = UInt8(ascii: "\n")
    static let spaces: Set<UInt8> = [0x20, 0x09, 0x0D, 0x0A]
    static let delimiters = spaces.union([",", "]", "}", ":", "/", "\"", "{", "["].map { UInt8(ascii: $0) })

    let bytes: [UInt8]
    private var index = 0
    /// Byte offset of each value's first byte, by JSON pointer.
    private(set) var offsets: [String: Int] = [:]

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    private var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

    mutating func document() throws(SyntaxError) {
        try value(at: "", depth: 0)
        try skipTrivia()
        if peek != nil { throw unexpected("the end of the file") }
    }

    private mutating func value(at pointer: String, depth: Int) throws(SyntaxError) {
        try skipTrivia()
        guard depth < JSONCPositions.maximumDepth else {
            throw SyntaxError(offset: index, message: "nested deeper than \(JSONCPositions.maximumDepth) levels")
        }
        offsets[pointer] = index
        switch peek {
        case UInt8(ascii: "{"): try object(at: pointer, depth: depth + 1)
        case UInt8(ascii: "["): try array(at: pointer, depth: depth + 1)
        case Self.quote: _ = try string()
        case nil, UInt8(ascii: ","), UInt8(ascii: "]"), UInt8(ascii: "}"), UInt8(ascii: ":"): throw unexpected("a value")
        default: try scalar()
        }
    }

    private mutating func object(at pointer: String, depth: Int) throws(SyntaxError) {
        index += 1
        repeat {
            try skipTrivia()
            if peek == UInt8(ascii: "}") {
                index += 1
                return
            }
            guard peek == Self.quote else { throw unexpected("a quoted key") }
            let key = try string()
            try skipTrivia()
            guard peek == UInt8(ascii: ":") else { throw unexpected(":") }
            index += 1
            let token = key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
            try value(at: "\(pointer)/\(token)", depth: depth)
        } while try separator(UInt8(ascii: "}"))
    }

    private mutating func array(at pointer: String, depth: Int) throws(SyntaxError) {
        index += 1
        var count = 0
        repeat {
            try skipTrivia()
            if peek == UInt8(ascii: "]") {
                index += 1
                return
            }
            try value(at: "\(pointer)/\(count)", depth: depth)
            count += 1
        } while try separator(UInt8(ascii: "]"))
    }

    /// Consumes `,` (true: another member may follow) or the closer (false).
    private mutating func separator(_ closer: UInt8) throws(SyntaxError) -> Bool {
        try skipTrivia()
        if peek == UInt8(ascii: ",") {
            index += 1
            return true
        }
        guard peek == closer else { throw unexpected(", or \(Character(Unicode.Scalar(closer)))") }
        index += 1
        return false
    }

    /// Scans to the closing quote, then lets Foundation check escapes and decode the text.
    private mutating func string() throws(SyntaxError) -> String {
        let start = index
        index += 1
        while let byte = peek, byte != Self.quote, byte != Self.newline {
            index += byte == UInt8(ascii: "\\") ? 2 : 1
        }
        guard peek == Self.quote else { throw SyntaxError(offset: start, message: "unterminated string") }
        index += 1
        let decoded = try? JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: .fragmentsAllowed)
        guard let text = decoded as? String else {
            throw SyntaxError(offset: start, message: "invalid escape or control character in string")
        }
        return text
    }

    /// A number, `true`, `false` or `null`, checked by Foundation's strict JSON grammar.
    private mutating func scalar() throws(SyntaxError) {
        let start = index
        index += 1
        while let byte = peek, !Self.delimiters.contains(byte) { index += 1 }
        let token = Data(bytes[start..<index])
        guard (try? JSONSerialization.jsonObject(with: token, options: .fragmentsAllowed)) != nil else {
            throw SyntaxError(offset: start, message: "\"\(String(decoding: token, as: UTF8.self))\" is not a value")
        }
    }

    private mutating func skipTrivia() throws(SyntaxError) {
        while let byte = peek {
            if Self.spaces.contains(byte) {
                index += 1
            } else if byte == Self.slash, index + 1 < bytes.count, bytes[index + 1] == Self.slash {
                while let next = peek, next != Self.newline { index += 1 }
            } else if byte == Self.slash, index + 1 < bytes.count, bytes[index + 1] == Self.star {
                try skipBlockComment()
            } else {
                return
            }
        }
    }

    private mutating func skipBlockComment() throws(SyntaxError) {
        let start = index
        index += 2
        while index + 1 < bytes.count {
            if bytes[index] == Self.star, bytes[index + 1] == Self.slash {
                index += 2
                return
            }
            index += 1
        }
        throw SyntaxError(offset: start, message: "unterminated comment")
    }

    private func unexpected(_ expected: String) -> SyntaxError {
        let found = peek.map { _ in
            String(decoding: bytes[index..<min(index + 4, bytes.count)], as: UTF8.self).first.map(String.init) ?? "?"
        }
        return SyntaxError(offset: index, message: "expected \(expected) but found \(found ?? "the end of the file")")
    }
}

/// Byte offset to 1-based line and column.
private struct LineTable {
    let bytes: [UInt8]
    let starts: [Int]

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
        starts = [0] + bytes.indices.filter { bytes[$0] == JSONCParser.newline }.map { $0 + 1 }
    }

    func position(_ offset: Int) -> (line: Int, column: Int) {
        let line = starts.lastIndex { $0 <= offset } ?? 0
        let scalars = bytes[starts[line]..<offset].count { $0 & 0xC0 != 0x80 }
        return (line + 1, scalars + 1)
    }
}
