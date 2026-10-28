import Foundation

/// One `aerospace subscribe focus-changed` JSON line, e.g.
/// `{"_event":"focus-changed","windowId":28218,"workspace":"M"}` (windowId absent on an empty workspace).
public struct FocusChanged: Decodable, Equatable, Sendable {
    public let windowId: UInt32?
    public let workspace: String

    public init(windowId: UInt32?, workspace: String) {
        self.windowId = windowId
        self.workspace = workspace
    }
}

/// The subscription events FocusDock reacts to.
public enum AeroSpaceEvent: Equatable, Sendable {
    case windowDetected(WindowDetected)
    case focusChanged(FocusChanged)

    public static let subscribeArguments = ["subscribe", "window-detected", "focus-changed"]

    public static func parse(line: String) -> AeroSpaceEvent? {
        let data = Data(line.utf8)
        guard let header = try? JSONDecoder().decode(EventHeader.self, from: data) else { return nil }
        switch header.event {
        case "window-detected": return (try? JSONDecoder().decode(WindowDetected.self, from: data)).map(Self.windowDetected)
        case "focus-changed": return (try? JSONDecoder().decode(FocusChanged.self, from: data)).map(Self.focusChanged)
        default: return nil
        }
    }
}

struct EventHeader: Decodable {
    let event: String
    enum CodingKeys: String, CodingKey { case event = "_event" }
}

/// The window the user jumped to in another mode's workspace; focused when that mode activates.
public struct JumpTarget: Equatable, Sendable {
    public let modeID: String
    public let windowId: UInt32
}

/// What FocusDock knows about AeroSpace focus between events.
public struct FocusTracker: Equatable, Sendable {
    /// Workspace FocusDock itself asked AeroSpace for. Focus events for any other workspace that
    /// arrive before it are echoes of the state before FocusDock's command, so they are ignored.
    public let expectedWorkspace: String?
    /// The workspace of the last focus event.
    public let focusedWorkspace: String?
    public let jump: JumpTarget?

    public static let initial = FocusTracker(expectedWorkspace: nil, focusedWorkspace: nil, jump: nil)

    /// Call before FocusDock switches to `workspace`. Switching to the focused workspace
    /// produces no event, so it sets no token.
    public func expecting(_ workspace: String) -> FocusTracker {
        let token = workspace == focusedWorkspace ? nil : workspace
        return FocusTracker(expectedWorkspace: token, focusedWorkspace: focusedWorkspace, jump: jump)
    }

    /// The switch command failed, so no echo will come.
    public func commandFailed() -> FocusTracker {
        FocusTracker(expectedWorkspace: nil, focusedWorkspace: focusedWorkspace, jump: jump)
    }

    public func withJump(_ jump: JumpTarget?) -> FocusTracker {
        FocusTracker(expectedWorkspace: expectedWorkspace, focusedWorkspace: focusedWorkspace, jump: jump)
    }

    func seeing(_ workspace: String, expected: String?) -> FocusTracker {
        FocusTracker(expectedWorkspace: expected, focusedWorkspace: workspace, jump: jump)
    }
}

/// Jumping to a window in another mode's workspace is a request to switch to that mode: the
/// countdown starts and the user is bounced back to the active mode's workspace until it ends.
public enum FocusFollow {
    public struct Outcome: Equatable, Sendable {
        public let machine: ModeMachine
        public let tracker: FocusTracker
        /// Workspace to switch back to; the tracker already expects it.
        public let bounceTo: String?
    }

    public static func handle(_ event: FocusChanged, machine: ModeMachine, tracker: FocusTracker, now: Date) -> Outcome {
        let active = machine.activeMode
        let target = machine.config.modes.first { $0.workspace == event.workspace }
        // A windowless focus is no jump (AeroSpace reports one when the last window of a
        // workspace closes, after the next app's focus), but AeroSpace has left the active
        // mode's workspace, so put it back; this is what keeps mode and workspace equal.
        if event.windowId == nil, target != nil, event.workspace != active.workspace {
            let back = tracker.seeing(event.workspace, expected: nil).expecting(active.workspace)
            return Outcome(machine: machine, tracker: back, bounceTo: active.workspace)
        }
        if let expected = tracker.expectedWorkspace {
            let token = event.workspace == expected ? nil : expected
            return Outcome(machine: machine, tracker: tracker.seeing(event.workspace, expected: token), bounceTo: nil)
        }
        let seen = tracker.seeing(event.workspace, expected: nil)
        guard let windowId = event.windowId, let target, target.id != active.id else {
            return Outcome(machine: machine, tracker: seen, bounceTo: nil)
        }
        let next = machine.pendingTarget == target.id ? machine : machine.request(target.id, now: now)
        if next.activeModeID == target.id {
            return Outcome(machine: next, tracker: seen.withJump(nil), bounceTo: nil)
        }
        let tracker = seen.withJump(JumpTarget(modeID: target.id, windowId: windowId)).expecting(active.workspace)
        return Outcome(machine: next, tracker: tracker, bounceTo: active.workspace)
    }
}
