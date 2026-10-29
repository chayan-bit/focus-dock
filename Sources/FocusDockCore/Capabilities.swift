/// A TCC permission FocusDock may need, in the order onboarding offers them (SHELL-SPEC 4.2).
public enum Permission: String, CaseIterable, Codable, Sendable {
    case accessibility, screenRecording, fullDiskAccess, location, automation
}

/// One private symbol a capability depends on. `image` is the install name of the binary
/// that exports it; `minimumOS` (a macOS major version) marks a symbol only verified from
/// that release on, which the drift test skips below it.
public struct SymbolRef: Hashable, Sendable, CustomStringConvertible {
    public enum Kind: Sendable {
        /// An exported C function, found with `dlsym`.
        case function
        /// An Objective-C class, found with `objc_lookUpClass` once its image is loaded.
        case objcClass
        /// A non-exported symbol `dlsym` cannot see, found by walking the image's symbol table.
        case localSymbol
    }

    public let image: String
    public let name: String
    public let kind: Kind
    public let minimumOS: Int?

    public init(image: String, name: String, kind: Kind, minimumOS: Int? = nil) {
        self.image = image
        self.name = name
        self.kind = kind
        self.minimumOS = minimumOS
    }

    public var description: String { name }
}

/// Something FocusDock can do, with the private symbols and permissions it needs.
public struct Capability: Identifiable, Sendable {
    public let id: String
    public let symbols: [SymbolRef]
    public let permissions: [Permission]
    public let summary: String

    public init(id: String, symbols: [SymbolRef], permissions: [Permission], summary: String) {
        self.id = id
        self.symbols = symbols
        self.permissions = permissions
        self.summary = summary
    }
}

public enum CapabilityStatus: Equatable, Sendable {
    case available
    /// The OS lacks these symbols; the feature stays hidden whatever the user grants.
    case missingSymbols([SymbolRef])
    /// Everything resolved; these grants are missing, in onboarding order.
    case needsPermission([Permission])
}

/// What this Mac can do: the catalog checked against the symbols that resolved at launch and
/// the permissions granted now. A missing symbol hides what needs it, never crashes.
public struct CapabilityRegistry: Sendable {
    public let catalog: [Capability]
    public let resolved: Set<SymbolRef>
    public let granted: Set<Permission>

    public init(catalog: [Capability] = CapabilityRegistry.catalog, resolved: Set<SymbolRef>, granted: Set<Permission>) {
        self.catalog = catalog
        self.resolved = resolved
        self.granted = granted
    }

    /// An id not in the catalog is reported as unavailable rather than trapping.
    public func status(_ id: String) -> CapabilityStatus {
        guard let capability = catalog.first(where: { $0.id == id }) else { return .missingSymbols([]) }
        return status(of: capability)
    }

    public var report: [(Capability, CapabilityStatus)] {
        catalog.map { ($0, status(of: $0)) }
    }

    private func status(of capability: Capability) -> CapabilityStatus {
        let missing = capability.symbols.filter { !resolved.contains($0) }
        if !missing.isEmpty { return .missingSymbols(missing) }
        let needed = Permission.allCases.filter { capability.permissions.contains($0) && !granted.contains($0) }
        return needed.isEmpty ? .available : .needsPermission(needed)
    }
}
