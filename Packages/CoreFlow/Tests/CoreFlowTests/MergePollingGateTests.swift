import XCTest
@testable import CoreFlow

final class MergePollingGateTests: XCTestCase {
    func testPollingGateNeverRunsMoreThanFourRequests() async {
        let gate = MergePollingGate(maxConcurrentRequests: 4)
        let tracker = ConcurrentRequestTracker()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    _ = try? await gate.perform {
                        await tracker.enter()
                        try await Task.sleep(nanoseconds: 5_000_000)
                        await tracker.leave()
                        return true
                    }
                }
            }
        }

        let maximum = await tracker.maximum
        XCTAssertEqual(maximum, 4)
    }

    func testPollingGateReleasesPermitWhenOperationThrows() async throws {
        let gate = MergePollingGate(maxConcurrentRequests: 1)

        do {
            _ = try await gate.perform { () async throws -> Bool in
                throw PollingGateTestError.expected
            }
            XCTFail("Expected the gated operation to throw")
        } catch PollingGateTestError.expected {
            // The next operation proves defer returned the permit.
        }

        let value = try await gate.perform { true }
        XCTAssertTrue(value)
    }

    func testCancelledWaiterReturnsItsPermitWithoutRunningOperation() async throws {
        let resumedWaiters = LockedPollingGateSequenceLog()
        let gate = MergePollingGate(
            maxConcurrentRequests: 1,
            waiterDidResume: { resumedWaiters.append($0) }
        )
        let blocker = PollingGateBlocker()
        let execution = PollingGateExecutionLog()
        let first = Task {
            try await gate.perform {
                await execution.append("first")
                await blocker.wait()
                return true
            }
        }
        await blocker.waitUntilEntered()

        let cancelled = Task {
            try await gate.perform {
                await execution.append("cancelled")
                return true
            }
        }
        await waitForGateWaiters(gate, count: 1)
        cancelled.cancel()
        let third = Task {
            try await gate.perform {
                await execution.append("third")
                return true
            }
        }
        await waitForGateWaiters(gate, count: 2)

        let eventsBeforeRelease = await execution.events
        XCTAssertEqual(eventsBeforeRelease, ["first"])

        await blocker.resume()
        _ = try await first.value
        do {
            _ = try await cancelled.value
            XCTFail("Expected the queued operation to observe cancellation")
        } catch is CancellationError {
            // Expected after this FIFO waiter acquires its permit.
        }
        let thirdValue = try await third.value
        let finalEvents = await execution.events
        XCTAssertTrue(thirdValue)
        XCTAssertEqual(finalEvents, ["first", "third"])
        XCTAssertEqual(resumedWaiters.values, [0, 1])
    }
}

private enum PollingGateTestError: Error {
    case expected
}

private final class LockedPollingGateSequenceLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int] = []

    var values: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Int) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private actor ConcurrentRequestTracker {
    private var current = 0
    private(set) var maximum = 0

    func enter() {
        current += 1
        maximum = max(maximum, current)
    }

    func leave() {
        current -= 1
    }
}

private actor PollingGateBlocker {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entered = false

    func wait() async {
        entered = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilEntered() async {
        while !entered {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private actor PollingGateExecutionLog {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}

private func waitForGateWaiters(
    _ gate: MergePollingGate,
    count: Int,
    timeoutIterations: Int = 500
) async {
    for _ in 0..<timeoutIterations {
        if await gate.waitingRequestCount == count { return }
        await Task.yield()
    }
    XCTFail("Timed out waiting for \(count) queued polling requests")
}
