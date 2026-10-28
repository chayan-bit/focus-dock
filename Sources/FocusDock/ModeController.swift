import AppKit
import FocusDockCore

/// Owns the mode state machine and runs its side effects: dock tiles, AeroSpace workspace,
/// Focus shortcut, persisted mode, menu bar. Every mode change goes through `update`.
@MainActor
final class ModeController {
    private static let savedModeKey = "activeMode"

    private let model: DockModel
    private let workspace: Workspace
    private let store = ConfigStore()
    private let aerospace = AeroSpace()
    private let focus = FocusSwitcher()
    private var machine: ModeMachine
    private var configError: ConfigError?
    private var tickTask: Task<Void, Never>?
    /// Called after every state, countdown or warning change (the menu bar listens).
    var onChange: (() -> Void)?

    init(model: DockModel, workspace: Workspace) {
        self.model = model
        self.workspace = workspace
        let loaded = store.load()
        let config: ModesConfig
        switch loaded {
        case .success(let valid): config = valid
        case .failure(let error):
            configError = error
            config = ConfigStore.defaultConfig()
        }
        machine = ModeMachine(config: config, restoredModeID: UserDefaults.standard.string(forKey: Self.savedModeKey))
    }

    func start() {
        aerospace.onStatusChange = { [weak self] in self?.publish() }
        aerospace.startRouting { [weak self] window in
            guard let self else { return nil }
            return WindowRouting.moveArguments(for: window, config: self.machine.config, currentModeID: self.machine.activeModeID)
        }
        store.watch { [weak self] in self?.reload() }
        activate(machine.activeMode)
        refreshFocus(applyAfter: true)
    }

    func stop() {
        tickTask?.cancel()
        aerospace.stop()
    }

    var config: ModesConfig { machine.config }
    var state: ModeState { machine.state }
    var activeMode: Mode { machine.activeMode }

    func remainingSeconds() -> Int? { machine.remainingSeconds(now: Date()) }

    /// Menu warnings, most important first.
    var warnings: [String] {
        var lines = configError.map { ["modes.json is invalid; keeping the last good config:"] + $0.problems } ?? []
        if case .unavailable(let reason) = aerospace.status { lines.append("AeroSpace unavailable (\(reason))") }
        return lines + focus.warnings
    }

    // MARK: Input

    /// A dock pill: pressing the pending target shortens the wait, any other pill requests it.
    func pillPressed(_ id: String) {
        NSLog("FocusDock: pill %@ pressed", id)
        let now = Date()
        update(machine.pendingTarget == id ? machine.press(id, now: now) : machine.request(id, now: now))
    }

    func request(_ id: String) {
        NSLog("FocusDock: %@ requested from the menu", id)
        update(machine.request(id, now: Date()))
    }

    func stay() {
        NSLog("FocusDock: Stay pressed")
        update(machine.stay())
    }

    // MARK: State

    private func update(_ next: ModeMachine) {
        let previous = machine
        machine = next
        if next.state != previous.state { NSLog("FocusDock: mode state %@", String(describing: next.state)) }
        if next.activeModeID != previous.activeModeID {
            activate(next.activeMode)
        } else if next.activeMode != previous.activeMode {
            workspace.show(next.activeMode)
        }
        scheduleTick()
        publish()
    }

    private func activate(_ mode: Mode) {
        UserDefaults.standard.set(mode.id, forKey: Self.savedModeKey)
        workspace.show(mode)
        Task {
            await aerospace.focus(workspace: mode.workspace)
            await focus.apply(mode)
        }
    }

    private func publish() {
        model.setModes(machine.config.modes, state: machine.state, countdown: remainingSeconds())
        onChange?()
    }

    /// Wakes just after each whole second of the countdown, and at the deadline.
    private func scheduleTick() {
        tickTask?.cancel()
        guard case .pending(_, _, let deadline) = machine.state else { return }
        let left = deadline.timeIntervalSinceNow
        let untilNextSecond = left - left.rounded(.down)
        tickTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds((untilNextSecond > 0 ? untilNextSecond : 1) + 0.002))
            guard !Task.isCancelled, let self else { return }
            self.update(self.machine.tick(now: Date()))
        }
    }

    private func reload() {
        switch store.load() {
        case .success(let config):
            configError = nil
            NSLog("FocusDock: reloaded %@", ConfigStore.file.path)
            update(machine.reloaded(with: config))
            refreshFocus(applyAfter: false)
        case .failure(let error):
            configError = error
            NSLog("FocusDock: keeping the last good config: %@", error.description)
            publish()
        }
    }

    private func refreshFocus(applyAfter: Bool) {
        let config = machine.config
        Task {
            await focus.refresh(for: config)
            if applyAfter { await focus.apply(machine.activeMode) }
            publish()
        }
    }
}
