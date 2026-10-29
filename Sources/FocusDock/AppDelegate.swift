import AppKit
import FocusDockCore
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = DockModel(tileSize: Workspace.currentTileSize())
    private var workspace: Workspace?
    private var modes: ModeController?
    private var menuBar: MenuBar?
    private var panel: DockPanel?
    private var signalSources: [DispatchSourceSignal] = []
    private var screenObserver: NSObjectProtocol?
    private var themeWatcher: ShellThemeWatcher?
    private var hostingView: DockHostingView?
    private var permissions: PermissionMonitor?
    private var actions: ActionRegistry?
    private var shellStore: ConfigStore<ShellConfig>?
    /// The last `shell.jsonc` load's problems; the last good motion stays applied meanwhile.
    private var shellError: ConfigError?

    func applicationDidFinishLaunching(_ notification: Notification) {
        signalSources = NativeDock.installSignalHandlers()
        // Watchdog, stale-ledger replay, then hide; the awaits run off the main thread.
        Task { await NativeDock.launch() }

        // Once per launch: the OS does not gain or lose private symbols while we run.
        let resolved = SymbolTable.resolved(CapabilityRegistry.catalog)
        let permissions = PermissionMonitor()
        let actions = ActionRegistry { CapabilityRegistry(resolved: resolved, granted: permissions.granted) }
        let workspace = Workspace(model: model)
        // Loads modes.json, creating ~/.config/focusdock, so the shell store's directory watch can arm.
        let modes = ModeController(model: model, workspace: workspace)
        let engine = ThemeSystem.engine()
        AppActions.register(in: actions, controller: modes, permissions: permissions, engine: engine)
        let dockActions = DockActions(
            open: { [weak workspace] tile in workspace?.open(tile) },
            pill: { [weak modes] id in modes?.pillPressed(id) },
            stay: { [weak modes] in modes?.stay() }
        )
        let hostingView = DockHostingView(model: model, actions: dockActions)
        let panel = DockPanel(contentView: hostingView)
        let menuBar = MenuBar(
            controller: modes, themes: ThemeMenu(engine: engine, actions: actions),
            capabilities: CapabilitiesMenu(resolved: resolved, monitor: permissions, actions: actions),
            actions: actions, shellProblems: { [weak self] in self?.shellError?.items ?? [] }
        )
        let themeWatcher = ShellThemeWatcher { [model] theme in model.setShellTheme(theme) }
        themeWatcher.start()
        self.themeWatcher = themeWatcher
        modes.onChange = { [weak menuBar] in menuBar?.update() }
        modes.start()
        self.workspace = workspace
        self.modes = modes
        self.menuBar = menuBar
        self.panel = panel
        self.hostingView = hostingView
        self.permissions = permissions
        self.actions = actions
        startShellConfig()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenChanged() }
        }
        followCanvasSize()
    }

    /// Created after the modes store (see above); a missing `shell.jsonc` means defaults.
    private func startShellConfig() {
        let store = ConfigStore<ShellConfig>.shell()
        shellStore = store
        reloadShell()
        store.watch { [weak self] in self?.reloadShell() }
    }

    private func reloadShell() {
        guard let shellStore else { return }
        switch shellStore.load() {
        case .success(let config):
            shellError = nil
            hostingView?.setMotion(config.motion)
            workspace?.motion = config.motion
        case .failure(let error):
            shellError = error
            NSLog("FocusDock: keeping the last good %@: %@", ShellConfig.fileName, error.description)
        }
        menuBar?.update()
    }

    func applicationWillTerminate(_ notification: Notification) {
        modes?.stop()
        // Restores only if the state file exists, so this is also right mid-launch.
        NativeDock.restore(NativeDock.keeper())
    }

    private func screenChanged() {
        model.setTileSize(Workspace.currentTileSize())
        panel?.place(canvasSize: model.layout.canvasSize)
    }

    /// Re-centres the panel whenever the tile list or tile size changes its width.
    private func followCanvasSize() {
        let model = model
        Task { [weak self] in
            for await size in Observations({ model.layout.canvasSize }) {
                self?.panel?.place(canvasSize: size)
            }
        }
    }
}
