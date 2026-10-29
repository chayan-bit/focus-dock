import Foundation
import FocusDockCore

/// `focusdock capabilities`: every catalog capability with its status on this Mac, and what a
/// missing one lacks. Read-only; exits 0 whatever the statuses are.
enum CapabilitiesCLI {
    static let usage = "usage: focusdock capabilities"

    static func runAndExit(_ arguments: [String]) -> Never {
        guard arguments.isEmpty else {
            FileHandle.standardError.write(Data("focusdock: \(usage)\n".utf8))
            exit(1)
        }
        let granted = Set(PermissionProbe.all().filter { $0.value == .granted }.keys)
        let registry = CapabilityRegistry(resolved: SymbolTable.resolved(CapabilityRegistry.catalog), granted: granted)
        lines(registry.report).forEach { print($0) }
        // TCC judges a CLI by its responsible process, so a terminal's own grants show here.
        print("\npermissions are those of this process; the menu bar's Capabilities submenu shows the app's")
        exit(0)
    }

    /// `id  status  detail`, the id column padded to the longest id.
    static func lines(_ report: [(Capability, CapabilityStatus)]) -> [String] {
        let width = report.map(\.0.id.count).max() ?? 0
        return report.map { capability, status in
            let id = capability.id.padding(toLength: width, withPad: " ", startingAt: 0)
            return "\(id)  \(describe(status))"
        }
    }

    private static func describe(_ status: CapabilityStatus) -> String {
        switch status {
        case .available: "available"
        case .missingSymbols(let symbols): "missing symbols: " + symbols.map(\.name).joined(separator: ", ")
        case .needsPermission(let permissions): "needs permission: " + permissions.map(\.rawValue).joined(separator: ", ")
        }
    }
}
