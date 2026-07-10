import Combine
import Foundation

@MainActor
public final class FlowDeckStore: ObservableObject {
    @Published public private(set) var cards: [FlowCard] = []
    @Published public private(set) var phase: FlowDeckPhase = .idle
    @Published public private(set) var isInteractionLocked = false
    @Published public private(set) var notice: FlowNotice?

    public var currentCard: FlowCard? { cards.first }
    public var nextCard: FlowCard? { cards.dropFirst().first }

    private let service: CoreFlowServing
    private let pageSize: Int
    private var nextRefreshToken: String?
    private var seenAssetIDs: Set<String> = []
    private var isLoadingPage = false
    private var pageCancellable: AnyCancellable?

    public init(service: CoreFlowServing, pageSize: Int = 20) {
        self.service = service
        self.pageSize = pageSize
    }

    public func loadInitialIfNeeded() {
        guard phase == .idle else { return }
        requestPage(reset: true)
    }

    public func refresh() {
        requestPage(reset: true)
    }

    public func dismissCurrent() {
        guard !isInteractionLocked, !cards.isEmpty else { return }

        cards.removeFirst()
        updatePhaseAfterAdvance()
        prefetchIfNeeded()
    }

    private func requestPage(reset: Bool) {
        guard !isLoadingPage else { return }

        if reset {
            cards = []
            seenAssetIDs = []
            nextRefreshToken = nil
        } else if nextRefreshToken == nil {
            updatePhaseAfterAdvance()
            return
        }

        isLoadingPage = true
        if cards.isEmpty {
            phase = .loading
        }

        let requestedToken = reset ? nil : nextRefreshToken
        pageCancellable = service.recommendedCards(limit: pageSize, refreshToken: requestedToken)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self else { return }

                    self.isLoadingPage = false
                    if case .failure = completion {
                        self.phase = self.cards.isEmpty
                            ? .failed("Couldn't load your flow.")
                            : .loaded
                    }
                },
                receiveValue: { [weak self] page in
                    guard let self else { return }

                    for card in page.cards
                    where self.seenAssetIDs.insert(card.id).inserted {
                        self.cards.append(card)
                    }
                    self.nextRefreshToken = page.nextRefreshToken
                    self.phase = self.cards.isEmpty ? .empty : .loaded
                }
            )
    }

    private func prefetchIfNeeded() {
        guard cards.count <= 2, nextRefreshToken != nil else { return }
        requestPage(reset: false)
    }

    private func updatePhaseAfterAdvance() {
        phase = cards.isEmpty
            ? (nextRefreshToken == nil ? .empty : .loading)
            : .loaded
    }
}
