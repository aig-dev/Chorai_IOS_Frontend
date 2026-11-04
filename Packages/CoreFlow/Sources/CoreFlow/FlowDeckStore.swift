import Combine
import Foundation

@MainActor
public final class FlowDeckStore: ObservableObject {
    @Published public private(set) var cards: [FlowCard] = []
    @Published public private(set) var phase: FlowDeckPhase = .idle
    @Published public private(set) var isInteractionLocked = false
    @Published public private(set) var notice: FlowNotice?

    @Published public private(set) var history: [FlowCard] = []
    @Published public private(set) var historyIndex: Int?
    @Published public private(set) var undoCollectionCardID: String?

    public var browsingCards: [FlowCard] { history + cards }
    public var isRevisiting: Bool { historyIndex != nil }
    public var canGoBack: Bool { (historyIndex ?? history.count) > 0 }
    public var currentCard: FlowCard? {
        if let historyIndex, history.indices.contains(historyIndex) { return history[historyIndex] }
        return cards.first
    }
    public var nextCard: FlowCard? {
        if let historyIndex { return history.indices.contains(historyIndex + 1) ? history[historyIndex + 1] : cards.first }
        return cards.dropFirst().first
    }
    public var remainingCount: Int { cards.count + (historyIndex.map { history.count - $0 } ?? 0) }
    public var canLoadMore: Bool { nextRefreshToken != nil }


    private let service: CoreFlowServing
    private let pageSize: Int
    private let onFavoriteCommitted: (CardFavoriteState) -> Void
    private let maximumEmptyPageHops = 8
    private var nextRefreshToken: String?
    private var seenAssetIDs: Set<String> = []
    private var emptyPageHopCount = 0
    private var isLoadingPage = false
    private var pageCancellable: AnyCancellable?
    private var interactionCancellable: AnyCancellable?
    private var pendingFavoriteBaseline: CardFavoriteState?

    public init(service: CoreFlowServing, pageSize: Int = 20, onFavoriteCommitted: @escaping (CardFavoriteState) -> Void = { _ in }) {
        self.service = service
        self.pageSize = pageSize
        self.onFavoriteCommitted = onFavoriteCommitted
    }

    public func loadInitialIfNeeded() {
        guard phase == .idle else { return }
        requestPage(reset: true)
    }

    public func refresh() {
        guard !isInteractionLocked else { return }
        requestPage(reset: true)
    }

    public func dismissCurrent() {
        guard !isInteractionLocked, currentCard != nil else { return }
        notice = nil
        if let index = historyIndex {
            historyIndex = index + 1 < history.count ? index + 1 : nil
        } else if !cards.isEmpty {
            history.append(cards.removeFirst())
        }
        updatePhaseAfterAdvance()
        prefetchIfNeeded()
    }

    public func previous() {
        guard !isInteractionLocked, canGoBack else { return }
        notice = nil
        historyIndex = (historyIndex ?? history.count) - 1
        phase = .loaded
    }

    public func resumeExploring() {
        guard !isInteractionLocked else { return }
        historyIndex = nil
        notice = nil
        updatePhaseAfterAdvance()
        prefetchIfNeeded()
    }

    public func revisitHistory(at index: Int) {
        guard !isInteractionLocked, history.indices.contains(index) else { return }
        historyIndex = index
        notice = nil
        phase = .loaded
    }

    public func loadMoreIfNeeded(visibleCardID: String) {
        guard cards.suffix(3).contains(where: { $0.id == visibleCardID }) else { return }
        requestPage(reset: false)
    }

    public func toggleFavoriteCurrent(onFavoriteSucceeded: ((String) -> Void)? = nil) {
        guard let card = currentCard else { return }
        toggleFavorite(assetID: card.id, onFavoriteSucceeded: onFavoriteSucceeded)
    }

    public func toggleFavorite(assetID: String, onFavoriteSucceeded: ((String) -> Void)? = nil) {
        guard let card = browsingCards.first(where: { $0.id == assetID }) else { return }
        mutateFavorite(card: card, isFavorited: !card.isFavorited) { [weak self] in
            if self?.undoCollectionCardID == assetID { self?.undoCollectionCardID = nil }
            if !card.isFavorited { onFavoriteSucceeded?(assetID) }
        }
    }

    /// A right swipe collects idempotently. Advancing waits for a real success.
    public func collectAndAdvanceCurrent(
        onFavoriteSucceeded: ((String) -> Void)? = nil,
        onAdvanced: ((String) -> Void)? = nil
    ) {
        guard !isInteractionLocked, let card = currentCard else { return }
        if card.isFavorited || card.isOwner {
            undoCollectionCardID = nil
            dismissCurrent()
            onAdvanced?(card.id)
            return
        }
        mutateFavorite(card: card, isFavorited: true) { [weak self] in
            guard let self else { return }
            self.undoCollectionCardID = card.id
            onFavoriteSucceeded?(card.id)
            guard self.currentCard?.id == card.id else { return }
            self.dismissCurrent()
            onAdvanced?(card.id)
        }
    }

    public func undoLastCollection() {
        guard let id = undoCollectionCardID,
              let card = browsingCards.first(where: { $0.id == id }),
              card.isFavorited else { return }
        mutateFavorite(card: card, isFavorited: false) { [weak self] in
            self?.undoCollectionCardID = nil
        }
    }

    /// Ends transient feedback without changing the confirmed collection or deck.
    public func dismissCollectionUndo(for cardID: String) {
        guard !isInteractionLocked, undoCollectionCardID == cardID else { return }
        undoCollectionCardID = nil
    }

    public func applyLikeState(_ state: CardLikeState) {
        updateCard(state.cardID) { $0.replacingLike(with: state) }
    }

    public func applyFavoriteState(_ state: CardFavoriteState) {
        updateCard(state.cardID) { card in
            let delta = card.isFavorited == state.isFavorited ? 0 : (state.isFavorited ? 1 : -1)
            return card.replacingFavorite(
                isFavorited: state.isFavorited,
                favoriteCount: max(0, state.favoriteCount ?? (card.favoriteCount + delta))
            )
        }
        if pendingFavoriteBaseline?.cardID == state.cardID,
           let card = browsingCards.first(where: { $0.id == state.cardID }) {
            // A successful mutation elsewhere is now the rollback source of truth.
            pendingFavoriteBaseline = .init(cardID: card.id, isFavorited: card.isFavorited, favoriteCount: card.favoriteCount)
        }
        if !state.isFavorited, undoCollectionCardID == state.cardID { undoCollectionCardID = nil }
    }

    private func mutateFavorite(card: FlowCard, isFavorited: Bool, onSuccess: @escaping () -> Void) {
        guard !isInteractionLocked, !card.isOwner else { return }
        notice = nil
        pendingFavoriteBaseline = .init(cardID: card.id, isFavorited: card.isFavorited, favoriteCount: card.favoriteCount)
        let count = max(0, card.favoriteCount + (isFavorited ? 1 : -1))
        updateCard(card.id) { $0.replacingFavorite(isFavorited: isFavorited, favoriteCount: count) }
        isInteractionLocked = true
        var receivedSuccess = false
        let mutation = isFavorited ? service.favorite(assetID: card.id) : service.unfavorite(assetID: card.id)
        interactionCancellable = mutation
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self else { return }
                let baseline = self.pendingFavoriteBaseline
                    ?? .init(cardID: card.id, isFavorited: card.isFavorited, favoriteCount: card.favoriteCount)
                self.pendingFavoriteBaseline = nil
                self.isInteractionLocked = false
                if case .finished = completion, receivedSuccess {
                    let delta = baseline.isFavorited == isFavorited ? 0 : (isFavorited ? 1 : -1)
                    let committed = CardFavoriteState(cardID: card.id, isFavorited: isFavorited, favoriteCount: max(0, (baseline.favoriteCount ?? card.favoriteCount) + delta))
                    self.applyFavoriteState(committed)
                    self.onFavoriteCommitted(committed)
                    onSuccess()
                } else {
                    // Keep successful updates from other surfaces and concurrent likes.
                    self.updateCard(card.id) {
                        $0.replacingFavorite(isFavorited: baseline.isFavorited, favoriteCount: baseline.favoriteCount ?? card.favoriteCount)
                    }
                    self.notice = .favoriteFailed
                }
            }, receiveValue: { _ in receivedSuccess = true })
    }

    private func updateCard(_ id: String, transform: (FlowCard) -> FlowCard) {
        cards = cards.map { $0.id == id ? transform($0) : $0 }
        history = history.map { $0.id == id ? transform($0) : $0 }
    }

    private func requestPage(reset: Bool) {
        guard !isLoadingPage else { return }

        if reset {
            cards = []
            history = []
            historyIndex = nil
            undoCollectionCardID = nil
            seenAssetIDs = []
            nextRefreshToken = nil
            emptyPageHopCount = 0
        } else if nextRefreshToken == nil {
            updatePhaseAfterAdvance()
            return
        }

        isLoadingPage = true
        if currentCard == nil {
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
                        self.phase = self.currentCard == nil
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
                        self.phase = self.currentCard == nil ? .empty : .loaded
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
        phase = currentCard == nil
            ? (nextRefreshToken == nil ? .empty : .loading)
            : .loaded
    }
}
