import AppKit
import FocusDockCore
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = DockModel(tileSize: Workspace.currentTileSize())
    private var workspace: Workspace?
    private var panel: DockPanel?
    private var signalSources: [DispatchSourceSignal] = []
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        signalSources = NativeDock.installSignalHandlers()
        Task { await NativeDock.hide() }

        let workspace = Workspace(model: model)
        let hostingView = DockHostingView(model: model) { [weak workspace] tile in workspace?.open(tile) }
        let panel = DockPanel(contentView: hostingView)
        self.workspace = workspace
        self.panel = panel

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenChanged() }
        }
        followCanvasSize()
    }

    func applicationWillTerminate(_ notification: Notification) {
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
