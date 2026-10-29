import Synchronization

/// Mutable state shared with `@Sendable` fakes; a class so closures capture a reference, not a noncopyable Mutex.
final class Shared<Value: Sendable>: Sendable {
    let state: Mutex<Value>
    init(_ value: Value) { state = Mutex(value) }
}
