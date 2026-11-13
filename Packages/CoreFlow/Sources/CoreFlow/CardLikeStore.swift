import Combine
import Foundation

@MainActor
public final class CardLikeStore: ObservableObject {
    @Published public private(set) var state: CardLikeState
    @Published public private(set) var phase: CardLikePhase = .ready

    public var isMutating: Bool {
        if case .mutating = phase { return true }
        return false
    }

    private struct PendingLike {
        var baseline: CardLikeState
        let target: Bool
        let task: Task<Void, Never>

        var displayState: CardLikeState { baseline.settingLiked(target) }
    }

    private var pending: [String: PendingLike] = [:]
    private let service: any CoreCardLikeServing
    private let onCommit: @MainActor (CardLikeState) -> Void

    public init(
        state: CardLikeState,
        service: any CoreCardLikeServing,
        onCommit: @escaping @MainActor (CardLikeState) -> Void = { _ in }
    ) {
        self.state = state
        self.service = service
        self.onCommit = onCommit
    }

    public func hydrate(_ state: CardLikeState) {
        if let write = pending[state.cardID] {
            self.state = write.displayState
            phase = .mutating(targetLiked: write.target)
        } else {
            self.state = state
            phase = .ready
        }
    }

    public func applyCommitted(_ state: CardLikeState) {
        pending[state.cardID]?.baseline = state
        if self.state.cardID == state.cardID { hydrate(state) }
    }

    public func toggle() {
        let cardID = state.cardID
        guard !cardID.isEmpty, pending[cardID] == nil else { return }
        let target = !state.isLiked
        let task = Task { [weak self, service] in
            do {
                try Task.checkCancellation()
                try await service.setLiked(cardID: cardID, liked: target)
                guard let self, !Task.isCancelled, let write = pending.removeValue(forKey: cardID) else { return }
                let committed = write.displayState
                if state.cardID == cardID { hydrate(committed) }
                onCommit(committed)
            } catch {
                guard let self, !Task.isCancelled, let write = pending.removeValue(forKey: cardID),
                      state.cardID == cardID else { return }
                state = write.baseline
                phase = .failed((error as? CardLikeError) ?? .transport(code: "card_like_request_failed"))
            }
        }
        let write = PendingLike(baseline: state, target: target, task: task)
        pending[cardID] = write
        state = write.displayState
        phase = .mutating(targetLiked: target)
    }

    deinit {
        for write in pending.values { write.task.cancel() }
    }
}
