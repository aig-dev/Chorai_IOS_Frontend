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

    private let service: any CoreCardLikeServing
    private let onCommit: @MainActor (CardLikeState) -> Void
    private var operationTask: Task<Void, Never>?
    private var requestID = UUID()

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
        operationTask?.cancel()
        requestID = UUID()
        self.state = state
        phase = .ready
    }

    public func applyCommitted(_ state: CardLikeState) {
        guard state.cardID == self.state.cardID, !isMutating else { return }
        self.state = state
        phase = .ready
    }

    public func toggle() {
        guard !isMutating, !state.cardID.isEmpty else { return }
        let committed = state
        let target = !committed.isLiked
        let currentRequest = UUID()
        requestID = currentRequest
        phase = .mutating(targetLiked: target)
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.setLiked(
                    cardID: committed.cardID,
                    liked: target
                )
                guard !Task.isCancelled,
                      requestID == currentRequest,
                      state.cardID == committed.cardID else {
                    return
                }
                let count = max(
                    0,
                    committed.likeCount + (target ? 1 : -1)
                )
                let next = CardLikeState(
                    cardID: committed.cardID,
                    isLiked: target,
                    likeCount: count
                )
                state = next
                phase = .ready
                onCommit(next)
            } catch {
                guard !Task.isCancelled, requestID == currentRequest else {
                    return
                }
                phase = .failed(
                    (error as? CardLikeError)
                        ?? .transport(code: "card_like_request_failed")
                )
            }
        }
    }
}
