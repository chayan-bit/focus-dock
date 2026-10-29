import Foundation

// The shell.jsonc shapes of SHELL-SPEC 7:
//   spring    { "spring": { "response": 0.4, "damping": 0.75 } }
//   timed     { "duration": 0.27, "curve": "easeOut" }
//   via       { "via": "dockSwipe", "velocity": 1 } | { "via": "proxy", "duration": .., "curve": .. }
//             | { "via": "crossFade", "duration": .. } | { "via": "instant" }
// `defaults` entries are bare `{ "response": .., "damping": .. }` springs.

private struct SpringParams: Codable {
    let response: Double
    let damping: Double
}

extension MotionCurve: Codable {
    private enum CodingKeys: String, CodingKey { case bezier }

    public init(from decoder: any Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            switch name {
            case "linear": self = .linear
            case "easeIn": self = .easeIn
            case "easeOut": self = .easeOut
            case "easeInOut": self = .easeInOut
            case "easeInOutCos": self = .easeInOutCos
            case "dockBounce": self = .dockBounce
            default: throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown curve \"\(name)\""))
            }
            return
        }
        let points = try decoder.container(keyedBy: CodingKeys.self).decode([Double].self, forKey: .bezier)
        guard points.count == 4 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bezier needs 4 numbers"))
        }
        self = .bezier(points[0], points[1], points[2], points[3])
    }

    public func encode(to encoder: any Encoder) throws {
        if case .bezier(let x1, let y1, let x2, let y2) = self {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode([x1, y1, x2, y2], forKey: .bezier)
            return
        }
        var container = encoder.singleValueContainer()
        switch self {
        case .linear: try container.encode("linear")
        case .easeIn: try container.encode("easeIn")
        case .easeOut: try container.encode("easeOut")
        case .easeInOut: try container.encode("easeInOut")
        case .easeInOutCos: try container.encode("easeInOutCos")
        case .dockBounce: try container.encode("dockBounce")
        case .bezier: break
        }
    }
}

extension MotionSpec: Codable {
    private enum CodingKeys: String, CodingKey { case spring, via, duration, curve, velocity }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.spring) {
            let p = try c.decode(SpringParams.self, forKey: .spring)
            self = .spring(response: p.response, damping: p.damping)
        } else if let via = try c.decodeIfPresent(String.self, forKey: .via) {
            switch via {
            case "dockSwipe": self = .dockSwipe(velocity: try c.decode(Double.self, forKey: .velocity))
            case "proxy": self = .proxy(duration: try c.decode(Double.self, forKey: .duration), curve: try c.decode(MotionCurve.self, forKey: .curve))
            case "crossFade": self = .crossFade(duration: try c.decode(Double.self, forKey: .duration))
            case "instant": self = .instant
            default: throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "unknown via \"\(via)\""))
            }
        } else {
            self = .timed(duration: try c.decode(Double.self, forKey: .duration), curve: try c.decode(MotionCurve.self, forKey: .curve))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .spring(let response, let damping): try c.encode(SpringParams(response: response, damping: damping), forKey: .spring)
        case .timed(let duration, let curve):
            try c.encode(duration, forKey: .duration)
            try c.encode(curve, forKey: .curve)
        case .dockSwipe(let velocity):
            try c.encode("dockSwipe", forKey: .via)
            try c.encode(velocity, forKey: .velocity)
        case .proxy(let duration, let curve):
            try c.encode("proxy", forKey: .via)
            try c.encode(duration, forKey: .duration)
            try c.encode(curve, forKey: .curve)
        case .crossFade(let duration):
            try c.encode("crossFade", forKey: .via)
            try c.encode(duration, forKey: .duration)
        case .instant: try c.encode("instant", forKey: .via)
        }
    }
}

extension MotionConfig {
    private enum CodingKeys: String, CodingKey { case speed, reduceMotion, defaults, elements }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = MotionConfig()
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? base.speed
        reduceMotion = try c.decodeIfPresent(ReduceMotion.self, forKey: .reduceMotion) ?? base.reduceMotion
        defaults = try (c.decodeIfPresent([String: DefaultSpring].self, forKey: .defaults) ?? [:]).mapValues(\.spec)
        let raw = try c.decodeIfPresent([String: MotionSpec].self, forKey: .elements) ?? [:]
        elements = try Dictionary(uniqueKeysWithValues: raw.map { name, spec in
            guard let key = MotionKey(rawValue: name) else {
                throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath + [CodingKeys.elements], debugDescription: "unknown motion key \"\(name)\""))
            }
            return (key, spec)
        })
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(speed, forKey: .speed)
        try c.encode(reduceMotion, forKey: .reduceMotion)
        try c.encode(defaults.mapValues(DefaultSpring.init), forKey: .defaults)
        try c.encode(Dictionary(uniqueKeysWithValues: elements.map { ($0.rawValue, $1) }), forKey: .elements)
    }
}

/// A `defaults` entry: a bare spring in the file; a spec in any other shape is kept as the full form.
private struct DefaultSpring: Codable {
    let spec: MotionSpec

    init(_ spec: MotionSpec) { self.spec = spec }

    init(from decoder: any Decoder) throws {
        if let bare = try? SpringParams(from: decoder) {
            spec = .spring(response: bare.response, damping: bare.damping)
        } else {
            spec = try MotionSpec(from: decoder)
        }
    }

    func encode(to encoder: any Encoder) throws {
        if case .spring(let response, let damping) = spec {
            try SpringParams(response: response, damping: damping).encode(to: encoder)
        } else {
            try spec.encode(to: encoder)
        }
    }
}
