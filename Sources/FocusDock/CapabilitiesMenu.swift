import AppKit
import FocusDockCore

/// The "Capabilities" submenu: each permission with a Grant item while it is missing, then
/// every catalog capability, checked when available, otherwise with what it lacks.
@MainActor
final class CapabilitiesMenu: NSObject {
    private let resolved: Set<SymbolRef>
    private let monitor: PermissionMonitor
    private let actions: ActionRegistry

    /// `resolved` is `SymbolTable.resolved(CapabilityRegistry.catalog)`, taken once at launch.
    init(resolved: Set<SymbolRef>, monitor: PermissionMonitor, actions: ActionRegistry) {
        self.resolved = resolved
        self.monitor = monitor
        self.actions = actions
    }

    func item() -> NSMenuItem {
        let item = NSMenuItem(title: "Capabilities", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Capabilities")
        menu.autoenablesItems = false
        for permission in Permission.allCases { menu.addItem(permissionItem(permission)) }
        menu.addItem(.separator())
        let registry = CapabilityRegistry(resolved: resolved, granted: monitor.granted)
        for (capability, status) in registry.report { menu.addItem(capabilityItem(capability, status)) }
        item.submenu = menu
        // The menu is rebuilt on every open, so the next one shows grants made since this one.
        let monitor = monitor
        Task { await monitor.refresh() }
        return item
    }

    private func permissionItem(_ permission: Permission) -> NSMenuItem {
        let isGranted = monitor.granted.contains(permission)
        let entry = NSMenuItem(title: isGranted ? permission.title : "Grant \(permission.title)…",
                               action: #selector(grant(_:)), keyEquivalent: "")
        entry.target = self
        entry.representedObject = permission.rawValue
        entry.state = isGranted ? .on : .off
        entry.isEnabled = !isGranted
        if let modules = monitor.neededBy[permission], !modules.isEmpty {
            entry.subtitle = "Needed by " + modules.sorted().joined(separator: ", ")
        }
        return entry
    }

    private func capabilityItem(_ capability: Capability, _ status: CapabilityStatus) -> NSMenuItem {
        let entry = NSMenuItem(title: capability.summary, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        switch status {
        case .available:
            entry.state = .on
        case .missingSymbols(let symbols):
            entry.subtitle = "Not available on this macOS"
            entry.toolTip = "Missing: " + symbols.map(\.name).joined(separator: ", ")
        case .needsPermission(let permissions):
            entry.subtitle = "Needs " + permissions.map(\.title).joined(separator: ", ")
            entry.action = #selector(grant(_:))
            entry.target = self
            entry.representedObject = permissions.first?.rawValue
            entry.isEnabled = true
        }
        return entry
    }

    @objc private func grant(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        actions.performFromMenu("permission.grant", raw)
    }
}
