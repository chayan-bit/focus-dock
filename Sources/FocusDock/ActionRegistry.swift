import Foundation
import FocusDockCore

/// The one place every trigger runs an action through: menu, hotkeys, CLI, command bar and
/// agent. Arguments and capability are checked against `ActionCatalog` before any handler runs.
@MainActor
final class ActionRegistry {
    enum Source: String {
        case menu, hotkey, cli, agent
    }

    typealias Handler = @MainActor ([String]) async throws -> Void

    private var handlers: [String: Handler] = [:]
    /// Read per call, so a permission granted since launch counts at once.
    private let capabilities: @MainActor () -> CapabilityRegistry

    init(capabilities: @escaping @MainActor () -> CapabilityRegistry) {
        self.capabilities = capabilities
    }

    func register(_ id: String, _ run: @escaping Handler) {
        handlers[id] = run
    }

    func perform(_ invocation: ActionInvocation, from source: Source) async -> Result<Void, ActionFailure> {
        NSLog("FocusDock: action %@ from %@", invocation.id, source.rawValue)
        let result = await run(invocation)
        if case .failure(let failure) = result {
            NSLog("FocusDock: action %@ failed: %@", invocation.id, failure.description)
        }
        return result
    }

    private func run(_ invocation: ActionInvocation) async -> Result<Void, ActionFailure> {
        if case .failure(let failure) = ActionCatalog.validate(invocation, capabilities: capabilities()) { return .failure(failure) }
        guard let handler = handlers[invocation.id] else { return .failure(.notRegistered(invocation.id)) }
        do {
            try await handler(invocation.arguments)
            return .success(())
        } catch let failure as ActionFailure {
            return .failure(failure)
        } catch {
            return .failure(.failed(String(describing: error)))
        }
    }
}
