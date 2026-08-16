public actor MergePollingGate {
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(maxConcurrentRequests: Int = 4) {
        precondition(maxConcurrentRequests > 0)
        availablePermits = maxConcurrentRequests
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
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            availablePermits += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
