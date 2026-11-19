import Foundation

/// Exactly one drain task enters the worker. The applied watermark advances only
/// after MainActor delivery, so persistence waits for applied body revisions.
@MainActor
final class BlockNoteBridgeMailbox {
    let generation = UUID()
    private let worker: BlockNoteBridgeWorker
    private var apply: ((BlockNotePreparedOutput) -> Void)?
    private var queue: [(sequence: UInt64, input: BlockNoteBridgeInput)?] = []
    private var head = 0
    private var submitted: UInt64 = 0
    private var applied: UInt64 = 0
    private var sealed = false
    private var drainTask: Task<Void, Never>?
    private var waiters: [(watermark: UInt64, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var pendingCount = 0
    private(set) var pendingBytes = 0
    private(set) var peakPendingCount = 0
    private(set) var peakPendingBytes = 0

    init(worker: BlockNoteBridgeWorker, apply: @escaping (BlockNotePreparedOutput) -> Void) {
        self.worker = worker
        self.apply = apply
    }

    @discardableResult
    func enqueue(_ input: BlockNoteBridgeInput) -> UInt64? {
        guard !sealed else { return nil }
        return append(input)
    }

    func close() {
        guard !sealed else { return }
        sealed = true
        append(.close)
    }

    func drainAcceptedEvents() async {
        let cutoff = submitted
        guard applied < cutoff else { return }
        await withCheckedContinuation { waiters.append((cutoff, $0)) }
    }

    @discardableResult
    private func append(_ input: BlockNoteBridgeInput) -> UInt64 {
        submitted &+= 1
        queue.append((submitted, input))
        pendingCount += 1
        pendingBytes += input.estimatedBytes
        peakPendingCount = max(peakPendingCount, pendingCount)
        peakPendingBytes = max(peakPendingBytes, pendingBytes)
        if drainTask == nil {
            drainTask = Task { @MainActor in
                while self.head < self.queue.count {
                    guard let item = self.queue[self.head] else { break }
                    self.queue[self.head] = nil // release waiting payload storage immediately
                    self.head += 1
                    let result = await self.worker.apply(item.input)
                    self.apply?(result)
                    self.applied = item.sequence
                    self.pendingCount -= 1
                    self.pendingBytes -= item.input.estimatedBytes
                    if case .close = item.input { self.apply = nil }
                    let completed = self.waiters.filter { $0.watermark <= self.applied }
                    self.waiters.removeAll { $0.watermark <= self.applied }
                    completed.forEach { $0.continuation.resume() }
                }
                self.queue.removeAll()
                self.head = 0
                self.drainTask = nil
            }
        }
        return submitted
    }
}
