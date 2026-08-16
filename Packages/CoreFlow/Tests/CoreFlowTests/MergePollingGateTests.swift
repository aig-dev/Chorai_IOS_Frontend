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
        let gate = MergePollingGate(maxConcurrentRequests: 1)
        let blocker = PollingGateBlocker()
        let execution = PollingGateExecutionFlag()
        let first = Task {
            try await gate.perform {
                await blocker.wait()
                return true
            }
        }
        await blocker.waitUntilEntered()

        let cancelled = Task {
            try await gate.perform {
                await execution.markExecuted()
                return true
            }
        }
        for _ in 0..<10 { await Task.yield() }
        cancelled.cancel()
        let third = Task {
            try await gate.perform { true }
        }

        await blocker.resume()
        _ = try await first.value
        do {
            _ = try await cancelled.value
            XCTFail("Expected the queued operation to observe cancellation")
        } catch is CancellationError {
            // Expected after this FIFO waiter acquires its permit.
        }
        let thirdValue = try await third.value
        let didExecute = await execution.didExecute
        XCTAssertTrue(thirdValue)
        XCTAssertFalse(didExecute)
    }
}

private enum PollingGateTestError: Error {
    case expected
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

private actor PollingGateExecutionFlag {
    private(set) var didExecute = false

    func markExecuted() {
        didExecute = true
    }
}
