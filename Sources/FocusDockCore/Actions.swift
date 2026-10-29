/// One call of an action, from text such as `mode.set focus` or `theme.set "tokyo night"`.
public struct ActionInvocation: Equatable, Sendable {
    public let id: String
    public let arguments: [String]

    public init(id: String, arguments: [String]) {
        self.id = id
        self.arguments = arguments
    }

    /// Splits on whitespace; double quotes group an argument (`""` is an empty one) and a
    /// backslash makes the next character literal, inside quotes or out.
    public static func parse(_ text: String) throws(ConfigProblem) -> ActionInvocation {
        var tokens: [String] = []
        var current: String?
        var quoteStart: Int?
        var escapeAt: Int?
        for (offset, char) in text.enumerated() {
            if escapeAt != nil {
                current = (current ?? "") + String(char)
                escapeAt = nil
            } else if char == "\\" {
                escapeAt = offset + 1
                current = current ?? ""
            } else if char == "\"" {
                quoteStart = quoteStart == nil ? offset + 1 : nil
                current = current ?? ""
            } else if char.isWhitespace && quoteStart == nil {
                if let word = current { tokens.append(word) }
                current = nil
            } else {
                current = (current ?? "") + String(char)
            }
        }
        if let at = escapeAt { throw ConfigProblem(message: "dangling backslash at character \(at)") }
        if let at = quoteStart { throw ConfigProblem(message: "unterminated quote opened at character \(at)") }
        if let word = current { tokens.append(word) }
        guard let id = tokens.first else { throw ConfigProblem(message: "empty action") }
        return ActionInvocation(id: id, arguments: Array(tokens.dropFirst()))
    }
}

/// What one action is and needs: the menu, hotkeys, CLI, command bar and agent all read this.
/// `capability` is an id in `CapabilityRegistry.catalog`; the action fails typed while it is
/// unavailable.
public struct ActionDescriptor: Equatable, Sendable {
    public let id: String
    public let summary: String
    /// Argument names, in order; every argument is required.
    public let arguments: [String]
    /// False only for read-only actions, which the agent may run without an approval card.
    public let mutates: Bool
    public let capability: String?

    public init(id: String, summary: String, arguments: [String], mutates: Bool, capability: String?) {
        self.id = id
        self.summary = summary
        self.arguments = arguments
        self.mutates = mutates
        self.capability = capability
    }
}

/// Why an action did not run. Never a crash: every path returns one of these.
public enum ActionFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case invalid([String])
    case unavailable(String, CapabilityStatus)
    case notRegistered(String)
    case failed(String)

    public var description: String {
        switch self {
        case .invalid(let problems): problems.joined(separator: "; ")
        case .unavailable(let capability, .missingSymbols(let symbols)):
            "\(capability) is unavailable on this macOS (missing \(symbols.map(\.name).joined(separator: ", ")))"
        case .unavailable(let capability, .needsPermission(let permissions)):
            "\(capability) needs permission: \(permissions.map(\.rawValue).joined(separator: ", "))"
        case .unavailable(let capability, .available): "\(capability) is available"
        case .notRegistered(let id): "no handler for \(id)"
        case .failed(let reason): reason
        }
    }
}

public enum ActionCatalog {
    public static let all: [ActionDescriptor] = [
        ActionDescriptor(id: "mode.set", summary: "Switch to a mode, through its exit friction",
                         arguments: ["mode"], mutates: true, capability: nil),
        ActionDescriptor(id: "mode.stay", summary: "Cancel the pending mode switch",
                         arguments: [], mutates: true, capability: nil),
        ActionDescriptor(id: "theme.set", summary: "Apply a theme",
                         arguments: ["theme"], mutates: true, capability: nil),
        ActionDescriptor(id: "theme.next", summary: "Apply the next theme",
                         arguments: [], mutates: true, capability: nil),
        ActionDescriptor(id: "theme.prev", summary: "Apply the previous theme",
                         arguments: [], mutates: true, capability: nil),
        ActionDescriptor(id: "theme.reset", summary: "Put every themed app back as it was",
                         arguments: [], mutates: true, capability: nil),
        ActionDescriptor(id: "config.edit", summary: "Open modes.json in the default editor",
                         arguments: [], mutates: true, capability: nil),
        ActionDescriptor(id: "config.reveal", summary: "Reveal the config folder in Finder",
                         arguments: [], mutates: true, capability: nil),
        ActionDescriptor(id: "permission.grant", summary: "Ask for a permission or open its System Settings pane",
                         arguments: ["permission"], mutates: true, capability: nil),
        ActionDescriptor(id: "app.quit", summary: "Quit FocusDock",
                         arguments: [], mutates: true, capability: nil),
    ]

    /// Unknown id or a wrong argument count; empty when the call is well formed.
    public static func problems(_ invocation: ActionInvocation, in catalog: [ActionDescriptor] = all) -> [String] {
        guard let action = catalog.first(where: { $0.id == invocation.id }) else {
            return ["unknown action \"\(invocation.id)\""]
        }
        let expected = action.arguments.count
        guard invocation.arguments.count != expected else { return [] }
        let takes = expected == 0
            ? "takes no arguments"
            : "takes \(expected) argument\(expected == 1 ? "" : "s") (\(action.arguments.joined(separator: ", ")))"
        return ["\(action.id) \(takes), got \(invocation.arguments.count)"]
    }

    /// The descriptor when the call is well formed and its capability is available.
    public static func validate(
        _ invocation: ActionInvocation, capabilities: CapabilityRegistry, in catalog: [ActionDescriptor] = all
    ) -> Result<ActionDescriptor, ActionFailure> {
        let found = problems(invocation, in: catalog)
        guard found.isEmpty, let action = catalog.first(where: { $0.id == invocation.id }) else { return .failure(.invalid(found)) }
        if let capability = action.capability {
            let status = capabilities.status(capability)
            if status != .available { return .failure(.unavailable(capability, status)) }
        }
        return .success(action)
    }
}
