import Foundation
import Testing
@testable import FocusDockCore

/// Resolves every private symbol in the real catalog on this machine, so an OS update that
/// renames or drops one fails CI instead of silently hiding a feature. Entries above the
/// runner's macOS are cancelled (reported as skipped) and reviewed by hand.
struct SPIDriftTests {
    static let symbols: [SymbolRef] = {
        var seen = Set<SymbolRef>()
        return CapabilityRegistry.catalog.flatMap(\.symbols).filter { seen.insert($0).inserted }
    }()

    @Test(arguments: symbols)
    func resolvesOnThisMac(_ ref: SymbolRef) throws {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if let minimum = ref.minimumOS, major < minimum {
            try Test.cancel("\(ref.name) needs macOS \(minimum); this runner is \(major)")
        }
        #expect(SymbolTable.address(ref) != nil, "\(ref.kind) \(ref.name) in \(ref.image)")
    }
}
