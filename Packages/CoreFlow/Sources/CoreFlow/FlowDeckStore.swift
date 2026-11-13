import Combine
import Foundation

@MainActor
public final class FlowDeckStore: ObservableObject {
    @Published public private(set) var cards: [FlowCard] = []
    @Published public private(set) var phase: FlowDeckPhase = .idle
    @Published public private(set) var failedFavoriteIDs: Set<String> = []

    @Published public private(set) var history: [FlowCard] = []
    @Published public private(set) var historyIndex: Int?

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
    private struct PendingFavorite {
        var baseline: CardFavoriteState
        let target: Bool
        var cancellable: AnyCancellable?
    }
    private var pendingFavorites: [String: PendingFavorite] = [:]

    public func isFavoritePending(_ cardID: String) -> Bool {
        pendingFavorites[cardID] != nil
    }

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
        guard pendingFavorites.isEmpty else { return }
        requestPage(reset: true)
    }

    public func dismissCurrent() {
        guard currentCard != nil else { return }
        if let index = historyIndex {
            historyIndex = index + 1 < history.count ? index + 1 : nil
        } else if !cards.isEmpty {
            history.append(cards.removeFirst())
        }
        updatePhaseAfterAdvance()
        prefetchIfNeeded()
    }

    public func previous() {
        guard canGoBack else { return }
        historyIndex = (historyIndex ?? history.count) - 1
        phase = .loaded
    }

    public func resumeExploring() {
        historyIndex = nil
        updatePhaseAfterAdvance()
        prefetchIfNeeded()
    }

    public func revisitHistory(at index: Int) {
        guard history.indices.contains(index) else { return }
        historyIndex = index
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
        guard let card = browsingCards.first(where: { $0.id == assetID }),
              !card.isOwner, !isFavoritePending(assetID) else { return }

        failedFavoriteIDs.remove(assetID)
        let target = !card.isFavorited
        let baseline = card.favoriteState
        pendingFavorites[assetID] = PendingFavorite(baseline: baseline, target: target)
        displayFavorite(baseline.settingFavorite(target))

        var receivedSuccess = false
        let mutation = target ? service.favorite(assetID: assetID) : service.unfavorite(assetID: assetID)
        pendingFavorites[assetID]?.cancellable = mutation
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self, let pending = pendingFavorites.removeValue(forKey: assetID) else { return }
                if case .finished = completion, receivedSuccess {
                    let committed = pending.baseline.settingFavorite(target)
                    applyFavoriteState(committed)
                    onFavoriteCommitted(committed)
                    if target { onFavoriteSucceeded?(assetID) }
                } else {
                    displayFavorite(pending.baseline)
                    if pending.baseline.isFavorited != target { failedFavoriteIDs.insert(assetID) }
                }
            }, receiveValue: { _ in receivedSuccess = true })
    }

    public func applyLikeState(_ state: CardLikeState) {
        updateCard(state.cardID) { $0.replacingLike(with: state) }
    }

    public func applyFavoriteState(_ state: CardFavoriteState) {
        guard let card = browsingCards.first(where: { $0.id == state.cardID }) else { return }
        let baseline = pendingFavorites[card.id]?.baseline ?? card.favoriteState
        let confirmed = baseline.settingFavorite(state.isFavorited, count: state.favoriteCount)
        if let target = pendingFavorites[card.id]?.target {
            pendingFavorites[card.id]?.baseline = confirmed
            displayFavorite(confirmed.settingFavorite(target))
        } else {
            displayFavorite(confirmed)
        }
        failedFavoriteIDs.remove(card.id)
    }

    private func displayFavorite(_ state: CardFavoriteState) {
        updateCard(state.cardID) {
            $0.replacingFavorite(isFavorited: state.isFavorited, favoriteCount: state.favoriteCount ?? $0.favoriteCount)
        }
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
            failedFavoriteIDs.removeAll()
            historyIndex = nil
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

private extension FlowCard {
    var favoriteState: CardFavoriteState {
        CardFavoriteState(cardID: id, isFavorited: isFavorited, favoriteCount: favoriteCount)
    }
}

private extension CardFavoriteState {
    func settingFavorite(_ target: Bool, count: Int? = nil) -> CardFavoriteState {
        let delta = isFavorited == target ? 0 : (target ? 1 : -1)
        return CardFavoriteState(cardID: cardID, isFavorited: target,
                                 favoriteCount: max(0, count ?? ((favoriteCount ?? 0) + delta)))
    }
}
