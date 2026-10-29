import AppKit
import FocusDockCore

/// Owns the mode state machine and runs its side effects: dock tiles, AeroSpace workspace,
/// Focus shortcut, persisted mode, menu bar. Every mode change goes through `update`.
@MainActor
final class ModeController {
    private static let savedModeKey = "activeMode"

    private let model: DockModel
    private let workspace: Workspace
    private let store = ConfigStore<ModesConfig>.modes()
    private let aerospace = AeroSpace()
    private let focus = FocusSwitcher()
    private var machine: ModeMachine
    private var tracker = FocusTracker.initial
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
            config = ConfigStore<ModesConfig>.defaultConfig()
        }
        machine = ModeMachine(config: config, restoredModeID: UserDefaults.standard.string(forKey: Self.savedModeKey))
    }

    func start() {
        aerospace.onStatusChange = { [weak self] in self?.publish() }
        aerospace.startEvents { [weak self] event in await self?.handle(event) }
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

    /// What is wrong with modes.json while the last good config stays in use.
    var configProblems: [ConfigProblem] { configError?.items ?? [] }

    /// Menu warnings other than config problems, most important first.
    var warnings: [String] {
        var lines: [String] = []
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
        tracker = tracker.withJump(nil)
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

    /// Switches the dock, AeroSpace and Focus to `mode`; if the user had jumped to a window
    /// of this mode, lands on that window.
    private func activate(_ mode: Mode) {
        UserDefaults.standard.set(mode.id, forKey: Self.savedModeKey)
        workspace.show(mode)
        let jump = tracker.jump?.modeID == mode.id ? tracker.jump : nil
        // Set before any suspension, so a focus event already in flight is read as an echo.
        tracker = tracker.withJump(nil).expecting(mode.workspace)
        Task {
            await switchWorkspace(to: mode.workspace)
            if let jump {
                _ = await aerospace.perform(["focus", "--window-id", String(jump.windowId)], affectsStatus: false)
            }
            await focus.apply(mode)
        }
    }

    /// Runs a workspace switch the tracker already expects; a failed switch sends no echo.
    private func switchWorkspace(to name: String) async {
        if !(await aerospace.perform(["workspace", name])) { tracker = tracker.commandFailed() }
    }

    private func handle(_ event: AeroSpaceEvent) async {
        switch event {
        case .windowDetected(let window):
            guard let move = WindowRouting.moveArguments(for: window, config: machine.config, currentModeID: machine.activeModeID) else { return }
            _ = await aerospace.perform(move, affectsStatus: false)
        case .focusChanged(let focusEvent):
            let outcome = FocusFollow.handle(focusEvent, machine: machine, tracker: tracker, now: Date())
            tracker = outcome.tracker
            update(outcome.machine)
            guard let bounce = outcome.bounceTo else { return }
            NSLog("FocusDock: jump to %@ while in %@; back to %@", focusEvent.workspace, machine.activeModeID, bounce)
            await switchWorkspace(to: bounce)
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
            NSLog("FocusDock: reloaded %@", ConfigFiles.modes.path)
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
