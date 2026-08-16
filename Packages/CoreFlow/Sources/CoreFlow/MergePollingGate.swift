public actor MergePollingGate {
    private struct Waiter {
        let sequence: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var availablePermits: Int
    private var waiters: [Waiter] = []
    private var nextWaiterSequence = 0
    private let waiterDidResume: (@Sendable (Int) -> Void)?
    var waitingRequestCount: Int { waiters.count }

    public init(maxConcurrentRequests: Int = 4) {
        precondition(maxConcurrentRequests > 0)
        availablePermits = maxConcurrentRequests
        waiterDidResume = nil
    }

    init(
        maxConcurrentRequests: Int,
        waiterDidResume: @escaping @Sendable (Int) -> Void
    ) {
        precondition(maxConcurrentRequests > 0)
        availablePermits = maxConcurrentRequests
        self.waiterDidResume = waiterDidResume
    }

    public func perform<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(
                Waiter(
                    sequence: nextWaiterSequence,
                    continuation: continuation
                )
            )
            nextWaiterSequence += 1
        }
    }

    private func release() {
        if waiters.isEmpty {
            availablePermits += 1
        } else {
            let waiter = waiters.removeFirst()
            waiterDidResume?(waiter.sequence)
            waiter.continuation.resume()
        }
    }
}
