import Foundation

public enum ModeState: Equatable, Sendable {
    case active(String)
    /// Leaving `from` for `to`; `to` activates at `deadline` unless cancelled.
    case pending(from: String, to: String, deadline: Date)
}

/// The mode-switch state machine (SPEC 6). Pure: every transition takes the current time and
/// returns a new machine, so the caller owns the clock.
public struct ModeMachine: Equatable, Sendable {
    public let config: ModesConfig
    public let state: ModeState

    /// Starts in `restoredModeID` if the config still has it, else `initialMode`, else the first mode.
    public init(config: ModesConfig, restoredModeID: String?) {
        let id = restoredModeID.flatMap { config.mode($0)?.id } ?? config.fallbackModeID
        self.init(config: config, state: .active(id))
    }

    init(config: ModesConfig, state: ModeState) {
        self.config = config
        self.state = state
    }

    /// The mode whose apps the dock shows; while pending, still the mode being left.
    public var activeModeID: String {
        switch state {
        case .active(let id), .pending(let id, _, _): id
        }
    }

    public var activeMode: Mode { config.mode(activeModeID) ?? config.modes[0] }

    public var pendingTarget: String? {
        if case .pending(_, let to, _) = state { return to }
        return nil
    }

    /// Whole seconds left, rounded up, while pending.
    public func remainingSeconds(now: Date) -> Int? {
        guard case .pending(_, _, let deadline) = state else { return nil }
        return max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }

    /// Asks to switch to `target`. Asking for the pending target, or for the mode being left,
    /// cancels the switch; a zero delay switches at once.
    public func request(_ target: String, now: Date) -> ModeMachine {
        guard config.mode(target) != nil else { return self }
        switch state {
        case .active(let current) where current == target:
            return self
        case .pending(let from, let to, _) where to == target || from == target:
            return with(.active(from))
        default:
            let deadline = now.addingTimeInterval(activeMode.exit.delay(to: target))
            return with(.pending(from: activeModeID, to: target, deadline: deadline)).tick(now: now)
        }
    }

    /// Another press on the pending target shortens the wait, never past `now`.
    public func press(_ target: String, now: Date) -> ModeMachine {
        guard case .pending(let from, let to, let deadline) = state, to == target else {
            return request(target, now: now)
        }
        let shortened = max(now, deadline.addingTimeInterval(-activeMode.exit.perPressSeconds))
        return with(.pending(from: from, to: to, deadline: shortened)).tick(now: now)
    }

    public func stay() -> ModeMachine { with(.active(activeModeID)) }

    /// Activates the pending target once its deadline has passed.
    public func tick(now: Date) -> ModeMachine {
        guard case .pending(_, let to, let deadline) = state, deadline <= now else { return self }
        return with(.active(to))
    }

    /// Adopts a new config. A pending switch survives only if both its modes still exist;
    /// otherwise it is cancelled, landing on the mode being left if it still exists.
    public func reloaded(with newConfig: ModesConfig) -> ModeMachine {
        if case .pending(let from, let to, _) = state, newConfig.mode(from) != nil, newConfig.mode(to) != nil {
            return ModeMachine(config: newConfig, state: state)
        }
        return ModeMachine(config: newConfig, restoredModeID: activeModeID)
    }

    private func with(_ state: ModeState) -> ModeMachine { ModeMachine(config: config, state: state) }
}

public enum Countdown {
    /// `m:ss`, e.g. 10 -> "0:10", 75 -> "1:15".
    public static func format(seconds: Int) -> String {
        let clamped = max(0, seconds)
        return "\(clamped / 60):" + String(format: "%02d", clamped % 60)
    }
}
