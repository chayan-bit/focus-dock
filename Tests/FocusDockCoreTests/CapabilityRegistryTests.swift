import Darwin
import Testing
@testable import FocusDockCore

private let image = "/System/Library/PrivateFrameworks/Example.framework/Versions/A/Example"
private let a = SymbolRef(image: image, name: "ExampleA", kind: .function)
private let b = SymbolRef(image: image, name: "ExampleB", kind: .objcClass)
private let c = SymbolRef(image: image, name: "__ZL7ExampleC", kind: .localSymbol, minimumOS: 27)

private let fakeCatalog = [
    Capability(id: "plain", symbols: [], permissions: [], summary: "Public API"),
    Capability(id: "spi", symbols: [a, b, c], permissions: [], summary: "Needs symbols"),
    Capability(id: "tcc", symbols: [], permissions: [.location, .accessibility, .screenRecording], summary: "Needs grants"),
    Capability(id: "both", symbols: [a], permissions: [.fullDiskAccess], summary: "Needs both"),
]

struct CapabilityRegistryTests {
    @Test func availableWhenEverySymbolResolvesAndEveryPermissionIsGranted() {
        let registry = CapabilityRegistry(catalog: fakeCatalog, resolved: [a, b, c], granted: Set(Permission.allCases))
        for capability in fakeCatalog { #expect(registry.status(capability.id) == .available) }
    }

    @Test func missingSymbolsAreListedInCatalogOrder() {
        let registry = CapabilityRegistry(catalog: fakeCatalog, resolved: [b], granted: [])
        #expect(registry.status("spi") == .missingSymbols([a, c]))
    }

    @Test func missingPermissionsAreListedInOnboardingOrder() {
        let registry = CapabilityRegistry(catalog: fakeCatalog, resolved: [], granted: [.screenRecording])
        #expect(registry.status("tcc") == .needsPermission([.accessibility, .location]))
    }

    @Test func missingSymbolsWinOverMissingPermissions() {
        let registry = CapabilityRegistry(catalog: fakeCatalog, resolved: [], granted: [])
        #expect(registry.status("both") == .missingSymbols([a]))
    }

    @Test func publicCapabilityNeedsNothing() {
        let registry = CapabilityRegistry(catalog: fakeCatalog, resolved: [], granted: [])
        #expect(registry.status("plain") == .available)
    }

    @Test func unknownCapabilityIsNeverAvailable() {
        let registry = CapabilityRegistry(catalog: fakeCatalog, resolved: [a, b, c], granted: Set(Permission.allCases))
        #expect(registry.status("no.such.capability") == .missingSymbols([]))
    }

    @Test func reportKeepsCatalogOrder() {
        let registry = CapabilityRegistry(catalog: fakeCatalog, resolved: [a], granted: [.fullDiskAccess])
        let report = registry.report
        #expect(report.map(\.0.id) == ["plain", "spi", "tcc", "both"])
        #expect(report.map(\.1) == [
            .available, .missingSymbols([b, c]), .needsPermission([.accessibility, .screenRecording, .location]), .available,
        ])
    }

    @Test func permissionsFollowTheOnboardingOrder() {
        #expect(Permission.allCases == [.accessibility, .screenRecording, .fullDiskAccess, .location, .automation])
    }
}

struct CapabilityCatalogTests {
    private let catalog = CapabilityRegistry.catalog

    @Test func idsAreUnique() {
        #expect(Set(catalog.map(\.id)).count == catalog.count)
    }

    @Test func coversEverySpecSymbol() {
        let names = Set(catalog.flatMap(\.symbols).map(\.name))
        let spec = [
            "SLSCopyManagedDisplaySpaces", "SLSGetActiveSpace", "SLSBridgedMoveWindowsToManagedSpaceOperation",
            "SLSRegisterNotifyProc", "SLSRequestNotificationsForWindows", "SLSTransactionOrderWindow",
            "CGSSetMenuBarAutohideEnabled", "DisplayServicesSetBrightness", "DisplayServicesSetBrightnessSmooth",
            "CBBlueLightClient", "CBTrueToneClient", "IOBluetoothPreferenceSetControllerPowerState",
            "SLSSetAppearanceThemeLegacy", "CGSSetSymbolicHotKeyEnabled", "CoreDockSendNotification",
            "SACLockScreenImmediate", "CoreDockSetAutoHideEnabled",
        ]
        for name in spec { #expect(names.contains(name), "\(name) missing from the catalog") }
    }

    @Test func objcClassesAndLocalSymbolsAreMarked() {
        let byName = Dictionary(catalog.flatMap(\.symbols).map { ($0.name, $0.kind) }, uniquingKeysWith: { first, _ in first })
        #expect(byName["SLSBridgedMoveWindowsToManagedSpaceOperation"] == .objcClass)
        #expect(byName["CBBlueLightClient"] == .objcClass)
        #expect(byName["CBTrueToneClient"] == .objcClass)
        #expect(byName[SymbolRef.performBridgedOperation.name] == .localSymbol)
        #expect(byName["SLSMainConnectionID"] == .function)
    }

    @Test func aSymbolSharedByCapabilitiesIsTheSameReference() {
        let refs = catalog.flatMap(\.symbols)
        let byName = Dictionary(grouping: refs, by: \.name)
        for (name, group) in byName { #expect(Set(group).count == 1, "\(name) is declared inconsistently") }
    }

    @Test func spiCapabilitiesUseOnlyTheirStatedPermissions() {
        let registry = CapabilityRegistry(resolved: Set(catalog.flatMap(\.symbols)), granted: [])
        #expect(registry.status("window.moveToSpace") == .available)
        #expect(registry.status("switcher") == .needsPermission([.screenRecording]))
        #expect(registry.status("notifications.read") == .needsPermission([.accessibility, .fullDiskAccess]))
    }
}

struct SymbolTableTests {
    private let missingImage = "/System/Library/PrivateFrameworks/NoSuchFramework.framework/Versions/A/NoSuchFramework"

    @Test func missingImageOrSymbolResolvesToNil() {
        #expect(SymbolTable.address(SymbolRef(image: missingImage, name: "NoSuchFunction", kind: .function)) == nil)
        #expect(SymbolTable.address(SymbolRef(image: missingImage, name: "__ZL12NoSuchLocal", kind: .localSymbol)) == nil)
        #expect(SymbolTable.address(SymbolRef(image: missingImage, name: "NoSuchClass", kind: .objcClass)) == nil)
        let skyLight = SymbolRef.mainConnectionID.image
        #expect(SymbolTable.address(SymbolRef(image: skyLight, name: "NoSuchFunction", kind: .function)) == nil)
        #expect(SymbolTable.address(SymbolRef(image: skyLight, name: "__ZL12NoSuchLocal", kind: .localSymbol)) == nil)
    }

    @Test func publicFunctionResolvesThroughItsImageAndCalls() throws {
        typealias GetPID = @convention(c) () -> Int32
        let ref = SymbolRef(image: "/usr/lib/libSystem.B.dylib", name: "getpid", kind: .function)
        let call = try #require(SymbolTable.function(ref, as: GetPID.self))
        #expect(call() == getpid())
    }

    @Test func functionRefusesClassesAndWrongSizedTypes() {
        #expect(SymbolTable.function(.bridgedMoveOperation, as: (@convention(c) () -> Void).self) == nil)
        #expect(SymbolTable.function(.mainConnectionID, as: (Int, Int).self) == nil)
    }

    @Test func resolvedKeepsOnlyWhatResolves() {
        let missing = SymbolRef(image: missingImage, name: "NoSuchFunction", kind: .function)
        let catalog = [Capability(id: "x", symbols: [.mainConnectionID, missing], permissions: [], summary: "x")]
        #expect(SymbolTable.resolved(catalog) == [.mainConnectionID])
    }
}
