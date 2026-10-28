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

    func applicationDidFinishLaunching(_ notification: Notification) {
        signalSources = NativeDock.installSignalHandlers()
        Task { await NativeDock.hide() }

        let workspace = Workspace(model: model)
        let modes = ModeController(model: model, workspace: workspace)
        let actions = DockActions(
            open: { [weak workspace] tile in workspace?.open(tile) },
            pill: { [weak modes] id in modes?.pillPressed(id) },
            stay: { [weak modes] in modes?.stay() }
        )
        let panel = DockPanel(contentView: DockHostingView(model: model, actions: actions))
        let menuBar = MenuBar(controller: modes, themes: ThemeMenu())
        let themeWatcher = ShellThemeWatcher { [model] theme in model.setShellTheme(theme) }
        themeWatcher.start()
        self.themeWatcher = themeWatcher
        modes.onChange = { [weak menuBar] in menuBar?.update() }
        modes.start()
        self.workspace = workspace
        self.modes = modes
        self.menuBar = menuBar
        self.panel = panel

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenChanged() }
        }
        followCanvasSize()
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
