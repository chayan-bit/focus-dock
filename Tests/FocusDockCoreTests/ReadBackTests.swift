import Foundation
import Synchronization
import Testing
@testable import FocusDockCore

struct ReadBackTests {
    @Test func matchesOnTheFirstRead() async {
        let reads = Shared(0)
        let matched = await ReadBack.poll(true, timeout: .seconds(1)) {
            reads.state.withLock { $0 += 1 }
            return true
        }
        #expect(matched)
        #expect(reads.state.withLock { $0 } == 1)
    }

    @Test func keepsPollingUntilTheValueAppears() async {
        let reads = Shared(0)
        let matched = await ReadBack.poll(3, timeout: .seconds(5), interval: .milliseconds(1)) {
            reads.state.withLock { count in
                count += 1
                return count
            }
        }
        #expect(matched)
        #expect(reads.state.withLock { $0 } == 3)
    }

    @Test func nilReadsKeepPolling() async {
        let reads = Shared(0)
        let matched = await ReadBack.poll("on", timeout: .seconds(5), interval: .milliseconds(1)) {
            reads.state.withLock { count in
                count += 1
                return count < 3 ? nil : "on"
            }
        }
        #expect(matched)
    }

    @Test func givesUpAfterTheTimeout() async {
        let clock = ContinuousClock()
        let start = clock.now
        let matched = await ReadBack.poll(true, timeout: .milliseconds(50), interval: .milliseconds(5)) { false }
        let elapsed = clock.now - start
        #expect(!matched)
        #expect(elapsed >= .milliseconds(50))
        #expect(elapsed < .seconds(2))
    }

    @Test func zeroTimeoutStillReadsOnce() async {
        #expect(await ReadBack.poll(1, timeout: .zero) { 1 })
        #expect(!(await ReadBack.poll(1, timeout: .zero) { 2 }))
    }
}

/// Mutable state shared with `@Sendable` fakes; a class so closures capture a reference, not a noncopyable Mutex.
final class Shared<Value: Sendable>: Sendable {
    let state: Mutex<Value>
    init(_ value: Value) { state = Mutex(value) }
}
