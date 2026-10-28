import Foundation

public enum SettingsTextError: Error, Equatable, CustomStringConvertible {
    case notAnObject(String)

    public var description: String {
        switch self {
        case .notAnObject(let detail): "not a JSON object: \(detail)"
        }
    }
}

/// Edits one top-level key of a JSON or JSON-with-comments file (Zed's settings.json, Claude
/// Code's settings.json) as text, so every other byte, comment and trailing comma survives.
public enum JSONKey {
    /// The raw text of the key's value, e.g. `"auto"` or a whole `{ ... }` block.
    public static func value(_ key: String, in text: String) throws(SettingsTextError) -> String? {
        let bytes = Array(text.utf8)
        guard let member = try find(key, in: bytes) else { return nil }
        return String(decoding: bytes[member.value], as: UTF8.self)
    }

    /// Replaces the key's value with `raw` (JSON text), or inserts the key as the first member.
    public static func setting(_ key: String, to raw: String, in text: String) throws(SettingsTextError) -> String {
        var bytes = Array(text.utf8)
        if let member = try find(key, in: bytes) {
            bytes.replaceSubrange(member.value, with: Array(raw.utf8))
            return String(decoding: bytes, as: UTF8.self)
        }
        var scanner = Scanner(bytes)
        scanner.skipTrivia()
        let open = scanner.index
        let afterOpen = open + 1
        var probe = Scanner(bytes, at: afterOpen)
        probe.skipTrivia()
        let member = "\"\(key)\": \(raw)"
        if probe.peek == UInt8(ascii: "}") {
            bytes.replaceSubrange(afterOpen..<probe.index, with: Array("\n  \(member)\n".utf8))
        } else {
            let indent = indentation(of: probe.index, in: bytes) ?? "  "
            bytes.insert(contentsOf: Array("\n\(indent)\(member),".utf8), at: afterOpen)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Removes the key and its comma; text is unchanged when the key is absent.
    public static func removing(_ key: String, in text: String) throws(SettingsTextError) -> String {
        var bytes = Array(text.utf8)
        guard let member = try find(key, in: bytes) else { return text }
        var end = member.value.upperBound
        var start = member.key
        var after = Scanner(bytes, at: end)
        after.skipSpaces()
        if after.peek == UInt8(ascii: ",") {
            end = after.index + 1
        } else if let comma = member.previousComma {
            start = comma
        }
        // Take the whole line when the member sat on lines of its own.
        let lineStart = bytes[..<start].lastIndex(of: UInt8(ascii: "\n"))
        let before = bytes[(lineStart.map { $0 + 1 } ?? 0)..<start]
        var tail = Scanner(bytes, at: end)
        tail.skipSpaces()
        if let lineStart, before.allSatisfy(Scanner.isSpace), tail.peek == UInt8(ascii: "\n") {
            start = lineStart
            end = tail.index
        }
        bytes.removeSubrange(start..<end)
        return String(decoding: bytes, as: UTF8.self)
    }

    struct Member {
        let key: Int
        let value: Range<Int>
        /// The comma ending the previous member, when there is one.
        let previousComma: Int?
    }

    static func find(_ key: String, in bytes: [UInt8]) throws(SettingsTextError) -> Member? {
        var s = Scanner(bytes)
        s.skipTrivia()
        guard s.peek == UInt8(ascii: "{") else { throw .notAnObject("expected {") }
        s.index += 1
        var lastComma: Int?
        while true {
            s.skipTrivia()
            guard let byte = s.peek else { throw .notAnObject("unterminated object") }
            if byte == UInt8(ascii: "}") { return nil }
            guard byte == UInt8(ascii: "\"") else { throw .notAnObject("expected a key at byte \(s.index)") }
            let keyStart = s.index
            s.skipString()
            let name = String(decoding: bytes[(keyStart + 1)..<max(keyStart + 1, s.index - 1)], as: UTF8.self)
            s.skipTrivia()
            guard s.peek == UInt8(ascii: ":") else { throw .notAnObject("expected : after \(name)") }
            s.index += 1
            s.skipTrivia()
            let valueStart = s.index
            s.skipValue()
            if name == key { return Member(key: keyStart, value: valueStart..<s.index, previousComma: lastComma) }
            s.skipTrivia()
            if s.peek == UInt8(ascii: ",") {
                lastComma = s.index
                s.index += 1
            }
        }
    }

    private static func indentation(of index: Int, in bytes: [UInt8]) -> String? {
        guard let newline = bytes[..<index].lastIndex(of: UInt8(ascii: "\n")) else { return nil }
        let run = bytes[(newline + 1)..<index]
        return run.allSatisfy(Scanner.isSpace) ? String(decoding: run, as: UTF8.self) : nil
    }
}

/// A byte scanner that knows JSON strings, nesting and both comment styles.
struct Scanner {
    let bytes: [UInt8]
    var index: Int

    init(_ bytes: [UInt8], at index: Int = 0) {
        self.bytes = bytes
        self.index = index
    }

    var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

    static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 || byte == 0x0D }

    mutating func skipSpaces() {
        while let byte = peek, Self.isSpace(byte) { index += 1 }
    }

    mutating func skipTrivia() {
        while let byte = peek {
            if Self.isSpace(byte) || byte == 0x0A {
                index += 1
            } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "/") {
                while let next = peek, next != 0x0A { index += 1 }
            } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "*") {
                index += 2
                while index + 1 < bytes.count, !(bytes[index] == UInt8(ascii: "*") && bytes[index + 1] == UInt8(ascii: "/")) { index += 1 }
                index = min(index + 2, bytes.count)
            } else {
                return
            }
        }
    }

    /// From an opening quote to just past the closing one.
    mutating func skipString() {
        index += 1
        while let byte = peek {
            index += 1
            if byte == UInt8(ascii: "\\") { index += 1 } else if byte == UInt8(ascii: "\"") { return }
        }
    }

    mutating func skipValue() {
        guard let byte = peek else { return }
        if byte == UInt8(ascii: "\"") { return skipString() }
        if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") { return skipNested() }
        let stops: Set<UInt8> = [UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"), UInt8(ascii: "/"), 0x0A]
        while let next = peek, !stops.contains(next), !Self.isSpace(next) { index += 1 }
    }

    private mutating func skipNested() {
        var depth = 0
        while let byte = peek {
            if byte == UInt8(ascii: "\"") {
                skipString()
                continue
            }
            if byte == UInt8(ascii: "/") {
                let before = index
                skipTrivia()
                if index != before { continue }
            }
            if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") { depth += 1 }
            if byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]") { depth -= 1 }
            index += 1
            if depth == 0 { return }
        }
    }
}

/// Edits `key = value` lines of a flat config such as btop.conf, keeping every other line.
public enum ConfLine {
    /// The whole line that sets the key, without its newline.
    public static func line(_ key: String, in text: String) -> String? {
        lines(text).first { matches($0, key) }
    }

    /// Replaces the line that sets the key, or appends `line` when there is none.
    public static func setting(_ key: String, line: String, in text: String) -> String {
        var all = lines(text)
        if let index = all.firstIndex(where: { matches($0, key) }) {
            all[index] = line
            return all.joined(separator: "\n")
        }
        let separator = text.isEmpty || text.hasSuffix("\n") ? "" : "\n"
        return text + separator + line + "\n"
    }

    public static func removing(_ key: String, in text: String) -> String {
        lines(text).filter { !matches($0, key) }.joined(separator: "\n")
    }

    private static func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func matches(_ line: String, _ key: String) -> Bool {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard trimmed.hasPrefix(key) else { return false }
        return trimmed.dropFirst(key.count).drop { $0 == " " || $0 == "\t" }.first == "="
    }
}
