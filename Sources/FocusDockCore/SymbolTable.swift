import Darwin
import MachO
import ObjectiveC

/// Resolves catalog symbols at runtime. Every path returns nil for a missing image or symbol;
/// nothing here traps (ported from `Spikes/Sources/SpikeKit/Runtime.m`, `R()` and `findLocal`).
public enum SymbolTable {
    public static func address(_ ref: SymbolRef) -> UnsafeMutableRawPointer? {
        // Loads the image (a no-op when it is already loaded); nil if the OS no longer ships it.
        let handle = dlopen(ref.image, RTLD_LAZY)
        switch ref.kind {
        case .function:
            return handle.flatMap { dlsym($0, ref.name) } ?? dlsym(defaultHandle, ref.name)
        case .objcClass:
            return objc_lookUpClass(ref.name).map { UnsafeMutableRawPointer(Unmanaged<AnyObject>.passUnretained($0).toOpaque()) }
        case .localSymbol:
            return handle == nil ? nil : localSymbol(ref.name, in: ref.image)
        }
    }

    /// `RTLD_DEFAULT` is a pointer-cast macro, which Swift does not import.
    private static var defaultHandle: UnsafeMutableRawPointer? { UnsafeMutableRawPointer(bitPattern: -2) }

    /// A C function pointer of type `T` (an `@convention(c)` type), or nil when the symbol is
    /// missing, is a class, or `T` is not pointer-sized.
    public static func function<T>(_ ref: SymbolRef, as type: T.Type) -> T? {
        guard ref.kind != .objcClass,
              MemoryLayout<T>.size == MemoryLayout<UnsafeMutableRawPointer>.size,
              let pointer = address(ref)
        else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    /// The catalog's symbols that resolve on this Mac; feed it to `CapabilityRegistry`.
    public static func resolved(_ catalog: [Capability]) -> Set<SymbolRef> {
        Set(catalog.flatMap(\.symbols).filter { address($0) != nil })
    }

    /// Walks the loaded image's LC_SYMTAB, which also lists the local symbols `dlsym` skips
    /// (yabai and `tools/rea/probe.m` find the bridged move the same way).
    static func localSymbol(_ name: String, in image: String) -> UnsafeMutableRawPointer? {
        for index in 0..<_dyld_image_count() {
            guard let imageName = _dyld_get_image_name(index), String(cString: imageName) == image,
                  let header = _dyld_get_image_header(index)
            else { continue }
            return search(UnsafeRawPointer(header), slide: _dyld_get_image_vmaddr_slide(index), for: name)
        }
        return nil
    }

    private static func search(_ header: UnsafeRawPointer, slide: Int, for name: String) -> UnsafeMutableRawPointer? {
        let mach = header.loadUnaligned(as: mach_header_64.self)
        guard mach.magic == MH_MAGIC_64 else { return nil }
        var command = header + MemoryLayout<mach_header_64>.size
        var linkedit: segment_command_64?
        var symtab: symtab_command?
        for _ in 0..<mach.ncmds {
            let load = command.loadUnaligned(as: load_command.self)
            if load.cmd == UInt32(LC_SEGMENT_64) {
                let segment = command.loadUnaligned(as: segment_command_64.self)
                if segmentName(segment) == "__LINKEDIT" { linkedit = segment }
            } else if load.cmd == UInt32(LC_SYMTAB) {
                symtab = command.loadUnaligned(as: symtab_command.self)
            }
            guard load.cmdsize > 0 else { return nil }
            command += Int(load.cmdsize)
        }
        guard let linkedit, let symtab else { return nil }
        // __LINKEDIT's file offsets map to memory at its slid vmaddr.
        let base = UInt(bitPattern: slide) &+ UInt(linkedit.vmaddr) &- UInt(linkedit.fileoff)
        guard let linkeditBase = UnsafeRawPointer(bitPattern: base) else { return nil }
        return find(name, symtab: symtab, base: linkeditBase, slide: slide)
    }

    private static func find(_ name: String, symtab: symtab_command, base: UnsafeRawPointer, slide: Int) -> UnsafeMutableRawPointer? {
        let symbols = base + Int(symtab.symoff)
        let strings = (base + Int(symtab.stroff)).assumingMemoryBound(to: CChar.self)
        let wanted = Array(name.utf8CString)  // includes the terminating NUL
        for index in 0..<Int(symtab.nsyms) {
            let entry = (symbols + index * MemoryLayout<nlist_64>.stride).loadUnaligned(as: nlist_64.self)
            let offset = Int(entry.n_un.n_strx)
            // Bounded compare: only a match if the whole name plus its NUL fits in the table.
            guard entry.n_value != 0, offset + wanted.count <= Int(symtab.strsize),
                  memcmp(strings + offset, wanted, wanted.count) == 0
            else { continue }
            return UnsafeMutableRawPointer(bitPattern: UInt(entry.n_value) &+ UInt(bitPattern: slide))
        }
        return nil
    }

    private static func segmentName(_ segment: segment_command_64) -> String {
        withUnsafeBytes(of: segment.segname) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
