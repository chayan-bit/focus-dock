import Foundation

/// Colour helpers with the exact arithmetic of Omarchy's awk and bash (basecamp/omarchy, MIT),
/// so a rendered file matches what `omarchy-theme-set-templates` would write byte for byte.
public enum ColorMath {
    /// `#rrggbb` (either case) as 0...255 components; anything else is nil.
    public static func components(_ hex: String) -> (Int, Int, Int)? {
        guard hex.count == 7, hex.first == "#",
              hex.dropFirst().allSatisfy(\.isHexDigit),
              let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }

    /// `mix_color`: blend `start` toward `end`. The amount is "15%", "0.15" or "15" (over 1 means percent).
    public static func mix(_ start: String, _ end: String, amount: String) -> String? {
        guard let a = components(start), let b = components(end) else { return nil }
        let t = fraction(amount)
        func channel(_ x: Int, _ y: Int) -> Int { Int((Double(x) * (1 - t) + Double(y) * t + 0.5).rounded(.down)) }
        return hex(channel(a.0, b.0), channel(a.1, b.1), channel(a.2, b.2))
    }

    static func fraction(_ amount: String) -> Double {
        var t: Double
        if amount.hasSuffix("%") {
            t = leadingNumber(String(amount.dropLast())) / 100
        } else {
            t = leadingNumber(amount)
            if t > 1 { t /= 100 }
        }
        return min(max(t, 0), 1)
    }

    /// awk's string-to-number: the longest numeric prefix, else 0.
    private static func leadingNumber(_ text: String) -> Double {
        let prefix = text.prefix { $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" }
        return Double(prefix) ?? 0
    }

    public static func hex(_ r: Int, _ g: Int, _ b: Int) -> String {
        String(format: "#%02x%02x%02x", r, g, b)
    }

    /// `hex_to_rgb`: "#1e1e2e" -> "30,30,46".
    public static func rgbList(_ hex: String) -> String? {
        components(hex).map { "\($0.0),\($0.1),\($0.2)" }
    }

    /// `color_to_shell_hex`: the flat `#rrggbb` of a hex, rgb()/rgba() or 0xAARRGGBB colour;
    /// anything else is returned unchanged.
    public static func shellHex(_ color: String) -> String {
        let body = color.dropFirst()
        if color.first == "#", body.allSatisfy(\.isHexDigit), body.count == 6 || body.count == 8 {
            return "#" + body.prefix(6)
        }
        if color.hasPrefix("0x"), color.count == 10, color.dropFirst(2).allSatisfy(\.isHexDigit) {
            return "#" + color.dropFirst(4)
        }
        return rgbFunction(color) ?? color
    }

    private static func rgbFunction(_ color: String) -> String? {
        let lower = color.lowercased()
        let open = lower.hasPrefix("rgba(") ? 5 : lower.hasPrefix("rgb(") ? 4 : 0
        guard open > 0, color.hasSuffix(")") else { return nil }
        let inner = String(color.dropFirst(open).dropLast())
        if inner.allSatisfy(\.isHexDigit), inner.count == 6 || inner.count == 8 {
            return "#" + inner.prefix(6)
        }
        let parts = inner.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 3 || parts.count == 4,
              parts.prefix(3).allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let r = Int(parts[0]), let g = Int(parts[1]), let b = Int(parts[2]) else { return nil }
        if parts.count == 4, !(parts[3].allSatisfy { $0.isNumber || $0 == "." } && !parts[3].isEmpty) { return nil }
        return hex(min(r, 255), min(g, 255), min(b, 255))
    }
}

/// Hyprland-style gradient values ("rgba(33ccffee) rgba(00ff99ee) 45deg") and the three
/// template helpers that read them (`hypr_gradient`, `gradient_start`, `shell_gradient`).
public struct Gradient: Equatable, Sendable {
    public let colors: [String]
    public let angle: String?

    /// `parse_gradient`: whitespace-separated stops, palette keys resolved, an optional "<n>deg".
    public init(_ spec: String, palette: [String: String]) {
        var colors: [String] = []
        var angle: String?
        for part in spec.split(whereSeparator: \.isWhitespace).map(String.init) {
            if Self.isAngle(part) {
                angle = String(part.dropLast(3))
            } else {
                colors.append(palette[part] ?? part)
            }
        }
        self.colors = colors
        self.angle = angle
    }

    private static func isAngle(_ part: String) -> Bool {
        guard part.hasSuffix("deg") else { return false }
        var number = part.dropLast(3)
        if number.first == "-" { number = number.dropFirst() }
        let pieces = number.split(separator: ".", omittingEmptySubsequences: false)
        return (pieces.count == 1 || pieces.count == 2) && pieces.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    /// `resolve_theme_ref`: the key's value, else the fallback key's value, else the fallback verbatim.
    public static func reference(_ key: String, fallback: String?, palette: [String: String]) -> String {
        if let value = palette[key] { return value }
        guard let fallback, !fallback.isEmpty else { return key }
        return palette[fallback] ?? fallback
    }

    public static func hypr(_ key: String, fallback: String?, palette: [String: String]) -> String {
        let spec = reference(key, fallback: fallback, palette: palette)
        let gradient = Gradient(spec, palette: palette)
        switch gradient.colors.count {
        case 0: return "\"\(spec)\""
        case 1: return "\"\(gradient.colors[0])\""
        default:
            let stops = gradient.colors.map { " \"\($0)\"" }.joined(separator: ",")
            return "{ colors = {\(stops) }" + (gradient.angle.map { ", angle = \($0)" } ?? "") + " }"
        }
    }

    public static func start(_ key: String, fallback: String?, palette: [String: String]) -> String {
        let spec = reference(key, fallback: fallback, palette: palette)
        let first = Gradient(spec, palette: palette).colors.first ?? spec
        return ColorMath.shellHex(palette[first.trimmingCharacters(in: .whitespaces)] ?? first)
    }

    public static func shell(_ key: String, fallback: String?, palette: [String: String]) -> String {
        let spec = reference(key, fallback: fallback, palette: palette)
        let gradient = Gradient(spec, palette: palette)
        guard !gradient.colors.isEmpty else { return spec }
        return gradient.colors.joined(separator: " ") + (gradient.angle.map { " \($0)deg" } ?? "")
    }
}
