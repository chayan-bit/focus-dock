// The capability catalog: every row of SHELL-SPEC 3.1 plus the native Dock SPI, with the
// private symbols from `Spikes/Sources/SpikeKit/Runtime.m`. Images are dyld install names,
// which is what `_dyld_get_image_name` reports for the local-symbol walk.

private enum Image {
    static let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
    static let coreGraphics = "/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics"
    static let applicationServices = "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/ApplicationServices"
    static let displayServices = "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/A/DisplayServices"
    static let coreBrightness = "/System/Library/PrivateFrameworks/CoreBrightness.framework/Versions/A/CoreBrightness"
    static let ioBluetooth = "/System/Library/Frameworks/IOBluetooth.framework/Versions/A/IOBluetooth"
    static let login = "/System/Library/PrivateFrameworks/login.framework/Versions/A/login"
}

extension SymbolRef {
    private static func sky(_ name: String) -> SymbolRef { SymbolRef(image: Image.skyLight, name: name, kind: .function) }
    private static func cgs(_ name: String) -> SymbolRef { SymbolRef(image: Image.coreGraphics, name: name, kind: .function) }

    public static let mainConnectionID = sky("SLSMainConnectionID")
    public static let copyManagedDisplaySpaces = sky("SLSCopyManagedDisplaySpaces")
    public static let getActiveSpace = sky("SLSGetActiveSpace")
    public static let copySpacesForWindows = sky("SLSCopySpacesForWindows")
    public static let moveWindowsToManagedSpace = sky("SLSMoveWindowsToManagedSpace")
    public static let bridgedMoveOperation = SymbolRef(
        image: Image.skyLight, name: "SLSBridgedMoveWindowsToManagedSpaceOperation", kind: .objcClass)
    /// A C++ static (`dlsym` cannot see it); the class is in the macOS 15 SDK, but this
    /// function's symtab entry was only verified on 27 (spike S1).
    public static let performBridgedOperation = SymbolRef(
        image: Image.skyLight,
        name: "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation",
        kind: .localSymbol, minimumOS: 27)
    public static let registerNotifyProc = sky("SLSRegisterNotifyProc")
    public static let requestNotificationsForWindows = sky("SLSRequestNotificationsForWindows")
    public static let transactionCreate = sky("SLSTransactionCreate")
    public static let transactionOrderWindow = sky("SLSTransactionOrderWindow")
    public static let transactionCommit = sky("SLSTransactionCommit")
    public static let getAppearanceTheme = sky("SLSGetAppearanceThemeLegacy")
    public static let setAppearanceTheme = sky("SLSSetAppearanceThemeLegacy")

    public static let getMenuBarAutohide = cgs("CGSGetMenuBarAutohideEnabled")
    public static let setMenuBarAutohide = cgs("CGSSetMenuBarAutohideEnabled")
    public static let isSymbolicHotKeyEnabled = cgs("CGSIsSymbolicHotKeyEnabled")
    public static let setSymbolicHotKeyEnabled = cgs("CGSSetSymbolicHotKeyEnabled")

    public static let coreDockSendNotification = SymbolRef(
        image: Image.applicationServices, name: "CoreDockSendNotification", kind: .function)
    public static let coreDockGetAutoHide = SymbolRef(
        image: Image.applicationServices, name: "CoreDockGetAutoHideEnabled", kind: .function)
    public static let coreDockSetAutoHide = SymbolRef(
        image: Image.applicationServices, name: "CoreDockSetAutoHideEnabled", kind: .function)

    public static let getBrightness = SymbolRef(
        image: Image.displayServices, name: "DisplayServicesGetBrightness", kind: .function)
    public static let setBrightness = SymbolRef(
        image: Image.displayServices, name: "DisplayServicesSetBrightness", kind: .function)
    public static let setBrightnessSmooth = SymbolRef(
        image: Image.displayServices, name: "DisplayServicesSetBrightnessSmooth", kind: .function)
    public static let blueLightClient = SymbolRef(image: Image.coreBrightness, name: "CBBlueLightClient", kind: .objcClass)
    public static let trueToneClient = SymbolRef(image: Image.coreBrightness, name: "CBTrueToneClient", kind: .objcClass)
    public static let getBluetoothPower = SymbolRef(
        image: Image.ioBluetooth, name: "IOBluetoothPreferenceGetControllerPowerState", kind: .function)
    public static let setBluetoothPower = SymbolRef(
        image: Image.ioBluetooth, name: "IOBluetoothPreferenceSetControllerPowerState", kind: .function)
    public static let lockScreen = SymbolRef(image: Image.login, name: "SACLockScreenImmediate", kind: .function)
}

extension CapabilityRegistry {
    /// Getters ride along with their setters so every change can be read back.
    public static let catalog: [Capability] = [
        Capability(id: "spaces.list", symbols: [.mainConnectionID, .copyManagedDisplaySpaces, .getActiveSpace],
                   permissions: [], summary: "List Spaces"),
        Capability(id: "spaces.switch", symbols: [], permissions: [.accessibility], summary: "Switch Spaces with the native slide"),
        Capability(id: "spaces.jump", symbols: [], permissions: [.accessibility], summary: "Jump to a Space instantly"),
        Capability(id: "window.moveToSpace",
                   symbols: [.mainConnectionID, .bridgedMoveOperation, .performBridgedOperation,
                             .moveWindowsToManagedSpace, .copySpacesForWindows],
                   permissions: [], summary: "Move windows between Spaces"),
        Capability(id: "window.frames", symbols: [], permissions: [.accessibility], summary: "Move, resize and focus windows"),
        Capability(id: "window.events", symbols: [.mainConnectionID, .registerNotifyProc, .requestNotificationsForWindows],
                   permissions: [.accessibility], summary: "Window events"),
        Capability(id: "borders",
                   symbols: [.mainConnectionID, .transactionCreate, .transactionOrderWindow, .transactionCommit],
                   permissions: [], summary: "Window borders"),
        Capability(id: "window.animate", symbols: [], permissions: [.screenRecording, .accessibility],
                   summary: "Animate other apps' windows"),
        Capability(id: "motion", symbols: [], permissions: [], summary: "Animate FocusDock's own surfaces"),
        Capability(id: "bar", symbols: [], permissions: [], summary: "Bar"),
        Capability(id: "bar.appMenus", symbols: [], permissions: [.accessibility], summary: "App menus in the bar"),
        Capability(id: "bar.statusItems", symbols: [], permissions: [.screenRecording, .accessibility],
                   summary: "Status items in the bar"),
        Capability(id: "menuBar.autohide", symbols: [.getMenuBarAutohide, .setMenuBarAutohide],
                   permissions: [], summary: "Hide Apple's menu bar"),
        Capability(id: "notifications.silence", symbols: [], permissions: [], summary: "Silence notifications per mode"),
        Capability(id: "notifications.read", symbols: [], permissions: [.fullDiskAccess, .accessibility],
                   summary: "Read notifications"),
        Capability(id: "audio", symbols: [], permissions: [], summary: "Volume, mute and output"),
        Capability(id: "display.brightness", symbols: [.getBrightness, .setBrightness, .setBrightnessSmooth],
                   permissions: [], summary: "Built-in display brightness"),
        Capability(id: "display.nightShift", symbols: [.blueLightClient], permissions: [], summary: "Night Shift"),
        Capability(id: "display.trueTone", symbols: [.trueToneClient], permissions: [], summary: "True Tone"),
        Capability(id: "wifi", symbols: [], permissions: [], summary: "Wi-Fi"),
        Capability(id: "wifi.name", symbols: [], permissions: [.location], summary: "Wi-Fi network name"),
        Capability(id: "bluetooth.power", symbols: [.getBluetoothPower, .setBluetoothPower],
                   permissions: [], summary: "Bluetooth power"),
        // shortcut: the Focus status grant is not a Permission case yet; add it when the Focus widget lands.
        Capability(id: "focus.state", symbols: [], permissions: [], summary: "Focus state"),
        Capability(id: "appearance", symbols: [.getAppearanceTheme, .setAppearanceTheme],
                   permissions: [], summary: "Dark and light appearance"),
        Capability(id: "accent", symbols: [], permissions: [], summary: "Accent colour"),
        Capability(id: "wallpaper", symbols: [], permissions: [], summary: "Wallpaper"),
        Capability(id: "input.leader", symbols: [], permissions: [], summary: "Leader key"),
        Capability(id: "input.hyper", symbols: [], permissions: [.accessibility], summary: "Hyper chords"),
        Capability(id: "switcher", symbols: [.isSymbolicHotKeyEnabled, .setSymbolicHotKeyEnabled],
                   permissions: [.screenRecording], summary: "Cmd-Tab switcher"),
        Capability(id: "overview", symbols: [], permissions: [.screenRecording], summary: "Overview"),
        Capability(id: "missionControl", symbols: [.coreDockSendNotification], permissions: [],
                   summary: "Mission Control and Show Desktop"),
        Capability(id: "lock", symbols: [.lockScreen], permissions: [], summary: "Lock the screen"),
        Capability(id: "fleet", symbols: [], permissions: [], summary: "Fleet view"),
        Capability(id: "agent", symbols: [], permissions: [], summary: "Agent console"),
        Capability(id: "dock.autohide", symbols: [.coreDockGetAutoHide, .coreDockSetAutoHide],
                   permissions: [], summary: "Hide the system Dock"),
    ]
}
