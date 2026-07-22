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
    private let maximumEmptyPageHops = 8
    private var nextRefreshToken: String?
    private var seenAssetIDs: Set<String> = []
    private var emptyPageHopCount = 0
    private var isLoadingPage = false
    private var pageCancellable: AnyCancellable?
    private var interactionCancellable: AnyCancellable?

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

    public func toggleFavoriteCurrent(
        onFavoriteSucceeded: ((String) -> Void)? = nil
    ) {
        guard
            !isInteractionLocked,
            let card = cards.first,
            !card.isOwner
        else { return }

        notice = nil
        let nextIsFavorited = !card.isFavorited
        let nextFavoriteCount = nextIsFavorited
            ? card.favoriteCount + 1
            : max(0, card.favoriteCount - 1)
        let optimisticCard = card.replacingFavorite(
            isFavorited: nextIsFavorited,
            favoriteCount: nextFavoriteCount
        )
        cards[0] = optimisticCard
        isInteractionLocked = true

        let mutation = nextIsFavorited
            ? service.favorite(assetID: card.id)
            : service.unfavorite(assetID: card.id)
        interactionCancellable = mutation
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self else { return }

                    self.isInteractionLocked = false
                    guard case .failure = completion else { return }

                    self.cards = self.cards.map { current in
                        current.id == card.id ? card : current
                    }
                    self.notice = .favoriteFailed
                },
                receiveValue: { _ in
                    guard nextIsFavorited else { return }
                    onFavoriteSucceeded?(card.id)
                }
            )
    }

    public func applyLikeState(_ state: CardLikeState) {
        cards = cards.map { card in
            card.id == state.cardID
                ? card.replacingLike(with: state)
                : card
        }
    }

    private func requestPage(reset: Bool) {
        guard !isLoadingPage else { return }

        if reset {
            cards = []
            seenAssetIDs = []
            nextRefreshToken = nil
            emptyPageHopCount = 0
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
                        return
                    }

                    if self.cards.isEmpty,
                       self.nextRefreshToken != nil,
                       self.emptyPageHopCount < self.maximumEmptyPageHops {
                        self.emptyPageHopCount += 1
                        self.requestPage(reset: false)
                    } else {
                        self.phase = self.cards.isEmpty ? .empty : .loaded
                    }
                },
                receiveValue: { [weak self] page in
                    guard let self else { return }

                    for card in page.cards
                    where self.seenAssetIDs.insert(card.id).inserted {
                        self.cards.append(card)
                    }
                    self.nextRefreshToken = page.nextRefreshToken
                    if !self.cards.isEmpty {
                        self.emptyPageHopCount = 0
                    }
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
