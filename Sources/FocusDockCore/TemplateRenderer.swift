import Foundation

/// Omarchy's template syntax (`omarchy-theme-set-templates`, basecamp/omarchy, MIT):
/// `{{ key }}`, `{{ key_strip }}`, `{{ key_rgb }}`, `{{ mix[_strip|_rgb] a b 15% }}` and the
/// gradient helpers. A span is looked up whole, so `{{key}}` without the spaces, an unknown key
/// or a mix of non-hex colours stays in the output as written. Spans never cross a line.
public struct TemplateRenderer: Sendable {
    private let table: [String: String]
    private let palette: [String: String]

    public init(colors: ThemeColors) {
        palette = colors.values
        var table: [String: String] = [:]
        for (key, value) in colors.values {
            table["{{ \(key) }}"] = value
            table["{{ \(key)_strip }}"] = value.hasPrefix("#") ? String(value.dropFirst()) : value
            if let rgb = ColorMath.rgbList(value) { table["{{ \(key)_rgb }}"] = rgb }
        }
        self.table = table
    }

    public func render(_ template: String) -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.range(of: "{{") {
            let lineEnd = rest[open.upperBound...].firstIndex(where: \.isNewline) ?? rest.endIndex
            guard let close = rest[open.upperBound..<lineEnd].range(of: "}}") else {
                out += rest[..<lineEnd]
                rest = rest[lineEnd...]
                continue
            }
            let span = String(rest[open.lowerBound..<close.upperBound])
            if let value = table[span] ?? function(span) {
                out += rest[..<open.lowerBound] + value
                rest = rest[close.upperBound...]
            } else {
                let next = rest.index(after: open.lowerBound)
                out += rest[..<next]
                rest = rest[next...]
            }
        }
        return out + rest
    }

    /// The value of a `mix` or gradient span, or nil when it is neither or cannot be computed.
    func function(_ span: String) -> String? {
        let words = span.dropFirst(2).dropLast(2).split(whereSeparator: \.isWhitespace).map(String.init)
        guard let name = words.first else { return nil }
        switch name {
        case "mix", "mix_strip", "mix_rgb": return mix(name, words)
        case "hypr_gradient", "gradient_start", "shell_gradient": return gradient(name, words)
        default: return nil
        }
    }

    private func mix(_ name: String, _ words: [String]) -> String? {
        guard words.count == 4, Self.isKey(words[1]), Self.isKey(words[2]), Self.isAmount(words[3]),
              let start = palette[words[1]], let end = palette[words[2]],
              let mixed = ColorMath.mix(start, end, amount: words[3]) else { return nil }
        switch name {
        case "mix_strip": return String(mixed.dropFirst())
        case "mix_rgb": return ColorMath.rgbList(mixed)
        default: return mixed
        }
    }

    private func gradient(_ name: String, _ words: [String]) -> String? {
        guard words.count >= 2 else { return nil }
        let fallback = words.count > 2 ? words[2...].joined(separator: " ") : nil
        switch name {
        case "hypr_gradient": return Gradient.hypr(words[1], fallback: fallback, palette: palette)
        case "gradient_start": return Gradient.start(words[1], fallback: fallback, palette: palette)
        default: return Gradient.shell(words[1], fallback: fallback, palette: palette)
        }
    }

    private static func isKey(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    /// `[0-9]+([.][0-9]+)?%?`
    private static func isAmount(_ word: String) -> Bool {
        let number = word.hasSuffix("%") ? word.dropLast() : Substring(word)
        let parts = number.split(separator: ".", omittingEmptySubsequences: false)
        return (1...2).contains(parts.count) && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }
}
