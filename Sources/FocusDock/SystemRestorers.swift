import FocusDockCore

/// Every restorer the ledger replays, one per key a setter records (SHELL-SPEC 4.3). A key with
/// no restorer here (its SPI is missing) stays in the ledger for a later replay.
enum SystemRestorers {
    static func all() -> [Restorer] {
        NativeDock.keeper()?.restorers ?? []
    }
}
