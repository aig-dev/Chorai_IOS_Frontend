import Combine
import Foundation

@MainActor
public final class SparkSessionStore: ObservableObject {
    @Published public private(set) var sourceCard: FlowCard?
    @Published public private(set) var results: [SparkResult] = []
    @Published public private(set) var visibleIndex = 0
    @Published public private(set) var chain: [SparkChainNode] = []
    @Published public private(set) var activeActivityID: String?
    @Published public private(set) var phase: SparkSessionPhase = .idle
    @Published public private(set) var notice: SparkNotice?
    @Published public private(set) var isInteractionLocked = false
    @Published public private(set) var didShowUpwardCue = false
    @Published public private(set) var isMoreExhausted = false
    @Published public private(set) var ownedCardActionRefresh: OwnedCardActionRefresh?
    @Published public private(set) var ownedCardRefreshFailure: String?
    @Published public private(set) var isRefreshingOwnedCard = false

    public var currentResult: SparkResult? {
        guard results.indices.contains(visibleIndex) else {
            return nil
        }
        return results[visibleIndex]
    }

    public var nextResult: SparkResult? {
        let nextIndex = visibleIndex + 1
        guard results.indices.contains(nextIndex) else {
            return nil
        }
        return results[nextIndex]
    }

    private struct TriggerRollback {
        let sourceCard: FlowCard?
        let results: [SparkResult]
        let visibleIndex: Int
        let chain: [SparkChainNode]
        let activeActivityID: String?
        let didShowUpwardCue: Bool
    }

    private let actorID: String
    private let rootSourceAssetID: String
    private let service: CoreSparkServing
    private let persistence: SparkSessionPersisting
    private let now: () -> Date

    private var operationToken = 0
    private var pendingTrigger: PendingSparkTrigger?
    private var lastFailedTrigger: PendingSparkTrigger?
    private var lastFailedSourceCard: FlowCard?
    private var lastFailedReplayActivityID: String?
    private var nextCursor: String?
    private var seenAssetIDs = Set<String>()
    private var hasRequestedMore = false
    private var consecutiveEmptyMorePages = 0
    private var isLoadingMore = false

    private var sourceCancellable: AnyCancellable?
    private var triggerCancellable: AnyCancellable?
    private var replayCancellable: AnyCancellable?
    private var replaySourceCancellable: AnyCancellable?
    private var historyCancellable: AnyCancellable?
    private var moreCancellable: AnyCancellable?
    private var interactionCancellable: AnyCancellable?
    private var ownedCardRefreshCancellable: AnyCancellable?
    private var ownedCardRefreshGeneration = 0

    public init(
        actorID: String,
        rootSourceAssetID: String,
        service: CoreSparkServing,
        persistence: SparkSessionPersisting,
        now: @escaping () -> Date = Date.init
    ) {
        self.actorID = actorID
        self.rootSourceAssetID = rootSourceAssetID
        self.service = service
        self.persistence = persistence
        self.now = now
    }

    public func start() {
        guard phase == .idle else {
            return
        }

        if let snapshot = persistence.snapshot(
            actorID: actorID,
            rootSourceAssetID: rootSourceAssetID
        ) {
            chain = snapshot.nodes
            activeActivityID = snapshot.activeActivityID
            pendingTrigger = snapshot.pendingTrigger
            didShowUpwardCue = snapshot.didShowUpwardCue

            if let pending = snapshot.pendingTrigger {
                lastFailedTrigger = pending
                reconcilePendingTrigger(
                    pending,
                    rollback: nil,
                    source: nil
                )
                return
            }

            if let activityID = snapshot.activeActivityID {
                replay(activityID: activityID)
                return
            }
        }

        loadRootSource()
    }

    public func advance() {
        guard !isInteractionLocked, currentResult != nil else {
            return
        }

        visibleIndex += 1
        phase = currentResult == nil ? .empty : .loaded
        persistCurrentState()
        prefetchIfNeeded()
    }

    public func previous() {
        guard !isInteractionLocked,
              visibleIndex > 0,
              results.indices.contains(visibleIndex - 1) else { return }
        visibleIndex -= 1
        phase = .loaded
        persistCurrentState()
    }

    public func toggleFavoriteCurrent(
        onFavoriteMutationSucceeded: ((String, Bool, Int) -> Void)? = nil,
        onFavoriteSucceeded: ((String) -> Void)? = nil
    ) {
        guard
            !isInteractionLocked,
            let result = currentResult,
            let sparkActivityID = activeActivityID,
            !result.card.isOwner
        else {
            return
        }

        notice = nil
        let nextIsFavorited = !result.card.isFavorited
        let nextFavoriteCount = nextIsFavorited
            ? result.card.favoriteCount + 1
            : max(0, result.card.favoriteCount - 1)
        let optimisticResult = SparkResult(
            card: result.card.replacingFavorite(
                isFavorited: nextIsFavorited,
                favoriteCount: nextFavoriteCount
            ),
            bucket: result.bucket,
            score: result.score,
            resultID: result.resultID
        )
        results[visibleIndex] = optimisticResult
        isInteractionLocked = true
        persistCurrentState()

        var receivedValue = false
        let mutation = nextIsFavorited
            ? service.favorite(
                assetID: result.id,
                sparkActivityID: sparkActivityID
            )
            : service.unfavorite(assetID: result.id)
        interactionCancellable = mutation
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                guard let self else { return }
                self.isInteractionLocked = false
                switch completion {
                case .failure:
                    self.restoreFavoriteMutation(result)
                case .finished where !receivedValue:
                    self.restoreFavoriteMutation(result)
                case .finished:
                    onFavoriteMutationSucceeded?(result.id, nextIsFavorited, nextFavoriteCount)
                    if nextIsFavorited {
                        onFavoriteSucceeded?(result.id)
                    }
                }
            },
            receiveValue: {
                receivedValue = true
            }
        )
    }

    private func restoreFavoriteMutation(_ result: SparkResult) {
        if let index = results.firstIndex(where: { $0.id == result.id }) {
            results[index] = result
        }
        notice = .saveFailed
        persistCurrentState()
    }

    public func applyFavoriteState(_ state: CardFavoriteState) {
        results = results.map { result in
            guard result.card.id == state.cardID else { return result }
            let count = state.favoriteCount ?? max(0, result.card.favoriteCount + (
                result.card.isFavorited == state.isFavorited ? 0 : (state.isFavorited ? 1 : -1)
            ))
            return SparkResult(
                card: result.card.replacingFavorite(isFavorited: state.isFavorited, favoriteCount: count),
                bucket: result.bucket,
                score: result.score,
                resultID: result.resultID
            )
        }
        persistCurrentState()
    }

    public func applyLikeState(_ state: CardLikeState) {
        results = results.map { result in
            guard result.id == state.cardID else { return result }
            return SparkResult(
                card: result.card.replacingLike(with: state),
                bucket: result.bucket,
                score: result.score,
                resultID: result.resultID
            )
        }
    }

    /// Applies a completed owner action to the visible session, without issuing
    /// another request or changing the user's current surviving result.
    public func applyOwnedCardAction(_ commit: OwnedCardActionCommit) {
        let ownedCards = results.map(\.card) + [sourceCard].compactMap { $0 }
        guard ownedCards.contains(where: { $0.id == commit.cardID && $0.isOwner }) else { return }
        let visibleID = currentResult?.id
        switch commit {
        case .removed(let cardID):
            results.removeAll { $0.id == cardID }
            if sourceCard?.id == cardID { sourceCard = nil }
            if let visibleID, let index = results.firstIndex(where: { $0.id == visibleID }) {
                visibleIndex = index
            } else {
                visibleIndex = max(0, min(visibleIndex, results.count - 1))
            }
            if phase == .loaded && results.isEmpty { phase = .empty }
        case .visibility, .pin:
            sourceCard = sourceCard?.applyingOwnedAction(commit)
            results = results.map { result in
                SparkResult(
                    card: result.card.applyingOwnedAction(commit),
                    bucket: result.bucket, score: result.score, resultID: result.resultID
                )
            }
        }
        persistCurrentState()
    }

    /// An explicit return from the editor authorizes a fresh read to supersede
    /// this surface's previous write receipt. Ordinary replay reads do not do so.
    public func refreshOwnedCardAfterEditing(cardID: String) {
        let visibleCards = results.map(\.card) + [sourceCard].compactMap { $0 }
        guard visibleCards.contains(where: { $0.id == cardID && $0.isOwner }) else { return }
        ownedCardRefreshGeneration += 1
        let generation = ownedCardRefreshGeneration
        ownedCardRefreshFailure = nil
        isRefreshingOwnedCard = true
        var receivedCard = false
        ownedCardRefreshCancellable = service.card(assetID: cardID)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self, self.ownedCardRefreshGeneration == generation else { return }
                self.isRefreshingOwnedCard = false
                if case .failure = completion {
                    self.ownedCardRefreshFailure = cardID
                } else if !receivedCard {
                    self.ownedCardRefreshFailure = cardID
                }
            }, receiveValue: { [weak self] card in
                guard let self, self.ownedCardRefreshGeneration == generation else { return }
                guard card.id == cardID, card.isOwner else { return }
                receivedCard = true
                if self.sourceCard?.id == cardID { self.sourceCard = card }
                self.results = self.results.map { result in
                    guard result.id == cardID else { return result }
                    return SparkResult(card: card, bucket: result.bucket, score: result.score, resultID: result.resultID)
                }
                self.chain = self.chain.map { node in
                    guard node.sourceAssetID == cardID else { return node }
                    return SparkChainNode(
                        sourceAssetID: node.sourceAssetID, sourcePreview: Self.preview(for: card),
                        activityID: node.activityID, parentActivityID: node.parentActivityID,
                        rootActivityID: node.rootActivityID, chainDepth: node.chainDepth,
                        visibleIndex: node.visibleIndex
                    )
                }
                self.ownedCardActionRefresh = OwnedCardActionRefresh(snapshot: OwnedCardActionSnapshot(
                    cardID: card.id, isOwned: card.isOwner, isPublic: card.isPublic,
                    isPinned: card.isPinned, pinnedAt: card.pinnedAt
                ))
                self.persistCurrentState()
            })
    }

    public func dismissOwnedCardRefreshFailure() { ownedCardRefreshFailure = nil }

    public func sparkCurrentDeeper() {
        guard
            !isInteractionLocked,
            phase == .loaded,
            let source = currentResult?.card,
            let parentActivityID = activeActivityID
        else {
            return
        }

        beginTrigger(
            source: source,
            parentActivityID: parentActivityID
        )
    }

    public func retryTrigger() {
        guard !isInteractionLocked else {
            return
        }

        if let pendingTrigger {
            reconcilePendingTrigger(
                pendingTrigger,
                rollback: nil,
                source: lastFailedSourceCard
            )
            return
        }

        if let activityID = lastFailedReplayActivityID {
            replay(activityID: activityID)
            return
        }

        if chain.isEmpty, sourceCard == nil {
            loadRootSource()
            return
        }

        guard
            let pending = lastFailedTrigger,
            let source = lastFailedSourceCard,
            pending.sourceAssetID == source.id
        else {
            return
        }

        beginTrigger(
            source: source,
            parentActivityID: pending.parentActivityID
        )
    }

    public func selectNode(activityID: String) {
        guard
            !isInteractionLocked,
            activityID != activeActivityID,
            chain.contains(where: { $0.activityID == activityID })
        else {
            return
        }

        replay(activityID: activityID)
    }

    public func dismissUpwardCue() {
        guard !didShowUpwardCue else {
            return
        }
        didShowUpwardCue = true
        persistCurrentState()
    }

    private func loadRootSource() {
        phase = .loadingSource
        isInteractionLocked = true
        notice = nil
        let token = beginOperation()
        var receivedCard = false

        sourceCancellable = service.card(assetID: rootSourceAssetID)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self, self.isCurrentOperation(token) else {
                        return
                    }
                    if case .failure(let error) = completion {
                        self.failRootLoad(error)
                    } else if !receivedCard {
                        self.failRootLoad(.decoding)
                    }
                },
                receiveValue: { [weak self] card in
                    guard let self, self.isCurrentOperation(token) else {
                        return
                    }
                    receivedCard = true
                    self.sourceCard = card
                    self.beginTrigger(source: card, parentActivityID: nil)
                }
            )
    }

    private func beginTrigger(
        source: FlowCard,
        parentActivityID: String?
    ) {
        let rollback = TriggerRollback(
            sourceCard: sourceCard,
            results: results,
            visibleIndex: visibleIndex,
            chain: chain,
            activeActivityID: activeActivityID,
            didShowUpwardCue: didShowUpwardCue
        )
        let pending = PendingSparkTrigger(
            sourceAssetID: source.id,
            sourcePreview: Self.preview(for: source),
            parentActivityID: parentActivityID,
            startedAt: now(),
            priorActivityID: activeActivityID,
            priorVisibleIndex: visibleIndex
        )

        pendingTrigger = pending
        lastFailedTrigger = nil
        lastFailedSourceCard = nil
        phase = .triggering
        isInteractionLocked = true
        notice = nil
        persistCurrentState()

        let token = beginOperation()
        var receivedPage = false
        triggerCancellable = service.trigger(
            sourceAssetID: source.id,
            parentActivityID: parentActivityID
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                guard let self, self.isCurrentOperation(token) else {
                    return
                }
                if case .failure(let error) = completion {
                    if case .resultsUnavailable(let activityID, let rootActivityID, let depth) = error {
                        let acknowledged = SparkActivityPage(
                            activityID: activityID,
                            parentActivityID: parentActivityID,
                            rootActivityID: rootActivityID,
                            chainDepth: depth,
                            sourceAssetID: source.id,
                            groups: [:],
                            createdAt: nil
                        )
                        if self.isValid(
                            page: acknowledged, sourceAssetID: source.id,
                            parentActivityID: parentActivityID, rollback: rollback
                        ) {
                            self.applyTriggeredPage(
                                acknowledged, source: source,
                                parentActivityID: parentActivityID, rollback: rollback,
                                resultLoadFailed: true
                            )
                        } else {
                            self.restoreAfterTriggerFailure(
                                rollback: rollback, pending: pending, source: source, error: .decoding
                            )
                        }
                    } else if Self.isAmbiguousTriggerError(error) {
                        self.reconcilePendingTrigger(
                            pending,
                            rollback: rollback,
                            source: source
                        )
                    } else {
                        self.restoreAfterTriggerFailure(
                            rollback: rollback,
                            pending: pending,
                            source: source,
                            error: error
                        )
                    }
                } else if !receivedPage {
                    self.restoreAfterTriggerFailure(
                        rollback: rollback,
                        pending: pending,
                        source: source,
                        error: .decoding
                    )
                }
            },
            receiveValue: { [weak self] page in
                guard let self, self.isCurrentOperation(token) else {
                    return
                }
                receivedPage = true
                guard self.isValid(
                    page: page,
                    sourceAssetID: source.id,
                    parentActivityID: parentActivityID,
                    rollback: rollback
                ) else {
                    self.restoreAfterTriggerFailure(
                        rollback: rollback,
                        pending: pending,
                        source: source,
                        error: .decoding,
                        message: "Couldn't continue this Spark."
                    )
                    return
                }
                self.applyTriggeredPage(
                    page,
                    source: source,
                    parentActivityID: parentActivityID,
                    rollback: rollback
                )
            }
        )
    }

    private func isValid(
        page: SparkActivityPage,
        sourceAssetID: String,
        parentActivityID: String?,
        rollback: TriggerRollback
    ) -> Bool {
        guard
            !page.activityID.isEmpty,
            page.sourceAssetID == sourceAssetID,
            page.parentActivityID == parentActivityID
        else {
            return false
        }

        guard let parentActivityID else {
            return page.rootActivityID == page.activityID && page.chainDepth == 0
        }
        guard
            let parent = rollback.chain.first(where: {
                $0.activityID == parentActivityID
            })
        else {
            return false
        }
        return page.rootActivityID == parent.rootActivityID
            && page.chainDepth == parent.chainDepth + 1
    }

    private func applyTriggeredPage(
        _ page: SparkActivityPage,
        source: FlowCard,
        parentActivityID: String?,
        rollback: TriggerRollback,
        resultLoadFailed: Bool = false
    ) {
        let node = SparkChainNode(
            sourceAssetID: page.sourceAssetID,
            sourcePreview: Self.preview(for: source),
            activityID: page.activityID,
            parentActivityID: page.parentActivityID,
            rootActivityID: page.rootActivityID,
            chainDepth: page.chainDepth,
            visibleIndex: 0
        )

        if let parentActivityID,
           let parentIndex = rollback.chain.firstIndex(where: {
               $0.activityID == parentActivityID
           }) {
            chain = Array(rollback.chain.prefix(through: parentIndex)) + [node]
            didShowUpwardCue = true
        } else {
            chain = [node]
        }

        sourceCard = source
        results = filteredResults(from: page)
        visibleIndex = 0
        activeActivityID = page.activityID
        resetMoreState(
            sourceAssetID: page.sourceAssetID,
            activityID: page.activityID
        )
        pendingTrigger = nil
        lastFailedTrigger = nil
        lastFailedSourceCard = nil
        lastFailedReplayActivityID = resultLoadFailed ? page.activityID : nil
        isInteractionLocked = false
        phase = resultLoadFailed
            ? .failed("Spark completed, but its results couldn't load.")
            : results.isEmpty ? .empty : .loaded
        persistCurrentState()
    }

    private func restoreAfterTriggerFailure(
        rollback: TriggerRollback,
        pending: PendingSparkTrigger,
        source: FlowCard,
        error: CoreSparkError,
        message: String? = nil
    ) {
        sourceCard = rollback.sourceCard ?? source
        results = rollback.results
        visibleIndex = rollback.visibleIndex
        chain = rollback.chain
        activeActivityID = rollback.activeActivityID
        didShowUpwardCue = rollback.didShowUpwardCue
        pendingTrigger = nil
        lastFailedTrigger = pending
        lastFailedSourceCard = source
        isInteractionLocked = false
        phase = .failed(message ?? Self.message(for: error))
        persistCurrentState()
    }

    private func replay(activityID: String) {
        guard let savedNode = chain.first(where: {
            $0.activityID == activityID
        }) else {
            phase = .failed("This Spark can no longer be restored.")
            return
        }

        phase = .replaying
        isInteractionLocked = true
        notice = nil
        lastFailedReplayActivityID = activityID
        let token = beginOperation()
        var receivedPage = false

        replayCancellable = service.activityResults(activityID: activityID)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self else {
                        return
                    }
                    guard self.isCurrentOperation(token) else {
                        return
                    }
                    if case .failure(let error) = completion {
                        self.failReplay(error)
                    } else if !receivedPage {
                        self.failReplay(.decoding)
                    }
                },
                receiveValue: { [weak self] page in
                    guard let self else {
                        return
                    }
                    guard self.isCurrentOperation(token) else {
                        return
                    }
                    receivedPage = true
                    guard page.activityID == activityID else {
                        self.failReplay(.decoding)
                        return
                    }
                    self.applyReplay(
                        page: page,
                        source: Self.restoredSource(
                            page: page,
                            savedNode: savedNode
                        ),
                        savedNode: savedNode
                    )
                    self.refreshReplaySource(
                        page: page,
                        token: token
                    )
                }
            )
    }

    private func refreshReplaySource(
        page: SparkActivityPage,
        token: Int
    ) {
        replaySourceCancellable = service.card(assetID: page.sourceAssetID)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] card in
                    guard let self else {
                        return
                    }
                    guard self.isCurrentOperation(token) else {
                        return
                    }
                    self.applyRefreshedReplaySource(card, page: page)
                }
            )
    }

    private func applyRefreshedReplaySource(
        _ source: FlowCard,
        page: SparkActivityPage
    ) {
        guard activeActivityID == page.activityID else {
            return
        }

        sourceCard = source
        if let index = chain.firstIndex(where: {
            $0.activityID == page.activityID
        }) {
            let node = chain[index]
            chain[index] = SparkChainNode(
                sourceAssetID: page.sourceAssetID,
                sourcePreview: Self.preview(for: source),
                activityID: page.activityID,
                parentActivityID: page.parentActivityID,
                rootActivityID: page.rootActivityID,
                chainDepth: page.chainDepth,
                visibleIndex: node.visibleIndex
            )
        }
        persistCurrentState()
    }

    private func applyReplay(
        page: SparkActivityPage,
        source: FlowCard,
        savedNode: SparkChainNode
    ) {
        let updatedNode = SparkChainNode(
            sourceAssetID: page.sourceAssetID,
            sourcePreview: Self.preview(for: source),
            activityID: page.activityID,
            parentActivityID: page.parentActivityID,
            rootActivityID: page.rootActivityID,
            chainDepth: page.chainDepth,
            visibleIndex: savedNode.visibleIndex
        )
        if let index = chain.firstIndex(where: {
            $0.activityID == page.activityID
        }) {
            chain[index] = updatedNode
        } else {
            chain.append(updatedNode)
        }

        let replayedResults = filteredResults(from: page)
        sourceCard = source
        results = replayedResults
        visibleIndex = replayedResults.isEmpty
            ? 0
            : min(savedNode.visibleIndex, replayedResults.count - 1)
        activeActivityID = page.activityID
        resetMoreState(
            sourceAssetID: page.sourceAssetID,
            activityID: page.activityID
        )
        pendingTrigger = nil
        lastFailedReplayActivityID = nil
        isInteractionLocked = false
        phase = replayedResults.isEmpty ? .empty : .loaded
        persistCurrentState()
    }

    private func filteredResults(from page: SparkActivityPage) -> [SparkResult] {
        let excludedSourceAssetIDs = sourceAssetIDs(
            through: page.activityID,
            fallback: page.sourceAssetID
        )
        return page.orderedResults.filter {
            !excludedSourceAssetIDs.contains($0.id)
        }
    }

    private func sourceAssetIDs(
        through activityID: String,
        fallback sourceAssetID: String
    ) -> Set<String> {
        var sourceAssetIDs = Set([sourceAssetID])
        guard let activityIndex = chain.firstIndex(where: {
            $0.activityID == activityID
        }) else {
            return sourceAssetIDs
        }
        sourceAssetIDs.formUnion(
            chain[...activityIndex].map(\.sourceAssetID)
        )
        return sourceAssetIDs
    }

    private static func restoredSource(
        page: SparkActivityPage,
        savedNode: SparkChainNode
    ) -> FlowCard {
        FlowCard(
            id: page.sourceAssetID,
            title: nil,
            content: savedNode.sourcePreview,
            contentHash: nil,
            tags: [],
            isPublic: true,
            createdAt: "",
            updatedAt: "",
            favoriteCount: 0,
            likeCount: 0,
            commentCount: 0,
            rate: 0,
            isFavorited: false,
            isLiked: false,
            isPinned: false,
            pinnedAt: nil,
            author: nil
        )
    }

    private func reconcilePendingTrigger(
        _ pending: PendingSparkTrigger,
        rollback: TriggerRollback?,
        source: FlowCard?
    ) {
        pendingTrigger = pending
        lastFailedTrigger = pending
        lastFailedSourceCard = source
        phase = .reconciling
        isInteractionLocked = true
        persistCurrentState()

        let token = beginOperation()
        var receivedHistory = false
        historyCancellable = service.history(
            sourceAssetID: pending.sourceAssetID,
            limit: 20
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                guard let self, self.isCurrentOperation(token) else {
                    return
                }
                if case .failure = completion {
                    self.isInteractionLocked = false
                    self.phase = .failed("Couldn't check this Spark.")
                    self.persistCurrentState()
                } else if !receivedHistory {
                    self.isInteractionLocked = false
                    self.phase = .failed("Couldn't check this Spark.")
                    self.persistCurrentState()
                }
            },
            receiveValue: { [weak self] entries in
                guard let self, self.isCurrentOperation(token) else {
                    return
                }
                receivedHistory = true
                let earliestMatch = pending.startedAt.addingTimeInterval(-2)
                let match = entries
                    .filter {
                        $0.sourceAssetID == pending.sourceAssetID
                            && $0.parentActivityID == pending.parentActivityID
                            && $0.createdAt >= earliestMatch
                    }
                    .max(by: { $0.createdAt < $1.createdAt })

                if let match {
                    self.recover(
                        match: match,
                        pending: pending,
                        rollback: rollback,
                        source: source
                    )
                } else {
                    self.confirmNoHistoryMatch(
                        pending: pending,
                        rollback: rollback,
                        source: source
                    )
                }
            }
        )
    }

    private func recover(
        match: SparkHistoryEntry,
        pending: PendingSparkTrigger,
        rollback: TriggerRollback?,
        source: FlowCard?
    ) {
        let recoveredNode = SparkChainNode(
            sourceAssetID: match.sourceAssetID,
            sourcePreview: pending.sourcePreview,
            activityID: match.activityID,
            parentActivityID: match.parentActivityID,
            rootActivityID: match.rootActivityID,
            chainDepth: match.chainDepth,
            visibleIndex: 0
        )
        let baseChain = rollback?.chain ?? chain
        if let parentActivityID = pending.parentActivityID,
           let parentIndex = baseChain.firstIndex(where: {
               $0.activityID == parentActivityID
           }) {
            chain = Array(baseChain.prefix(through: parentIndex)) + [recoveredNode]
            didShowUpwardCue = true
        } else {
            chain = [recoveredNode]
        }

        sourceCard = source ?? rollback?.sourceCard ?? sourceCard
        results = rollback?.results ?? results
        visibleIndex = 0
        activeActivityID = match.activityID
        pendingTrigger = nil
        lastFailedTrigger = nil
        lastFailedSourceCard = nil
        persistCurrentState()
        replay(activityID: match.activityID)
    }

    private func confirmNoHistoryMatch(
        pending: PendingSparkTrigger,
        rollback: TriggerRollback?,
        source: FlowCard?
    ) {
        pendingTrigger = nil
        lastFailedTrigger = pending
        lastFailedSourceCard = source
        if let rollback {
            sourceCard = rollback.sourceCard ?? source
            results = rollback.results
            visibleIndex = rollback.visibleIndex
            chain = rollback.chain
            activeActivityID = rollback.activeActivityID
            didShowUpwardCue = rollback.didShowUpwardCue
        }
        isInteractionLocked = false
        phase = .failed("Couldn't confirm this Spark.")
        persistCurrentState()

        if source == nil {
            loadSourceForConfirmedRetry(pending: pending)
        }
    }

    private func loadSourceForConfirmedRetry(
        pending: PendingSparkTrigger
    ) {
        sourceCancellable = service.card(assetID: pending.sourceAssetID)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] card in
                    self?.lastFailedSourceCard = card
                }
            )
    }

    private func resetMoreState(
        sourceAssetID: String,
        activityID: String
    ) {
        moreCancellable?.cancel()
        moreCancellable = nil
        nextCursor = nil
        seenAssetIDs = Set(results.map(\.id))
        seenAssetIDs.formUnion(
            sourceAssetIDs(
                through: activityID,
                fallback: sourceAssetID
            )
        )
        hasRequestedMore = false
        consecutiveEmptyMorePages = 0
        isLoadingMore = false
        isMoreExhausted = false
    }

    private func prefetchIfNeeded() {
        guard
            !isLoadingMore,
            !isMoreExhausted,
            let sourceAssetID = sourceCard?.id,
            let activityID = activeActivityID,
            max(0, results.count - visibleIndex) <= 2,
            !hasRequestedMore || nextCursor != nil
        else {
            return
        }

        isLoadingMore = true
        let requestedCursor = nextCursor
        var receivedPage = false
        let publisher = service.more(
            sourceAssetID: sourceAssetID,
            cursor: requestedCursor,
            limit: 20
        )
        moreCancellable = publisher
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                guard let self, self.activeActivityID == activityID else {
                    return
                }
                self.isLoadingMore = false
                if case .failure = completion {
                    self.notice = .moreFailed
                } else if !receivedPage {
                    self.notice = .moreFailed
                }
            },
            receiveValue: { [weak self] page in
                guard
                    let self,
                    self.activeActivityID == activityID,
                    page.sourceAssetID == sourceAssetID
                else {
                    return
                }
                receivedPage = true
                self.hasRequestedMore = true
                let additions = page.results.filter {
                    self.seenAssetIDs.insert($0.id).inserted
                }
                self.results.append(contentsOf: additions)
                self.nextCursor = page.nextCursor.flatMap {
                    $0.isEmpty ? nil : $0
                }
                self.consecutiveEmptyMorePages = additions.isEmpty
                    ? self.consecutiveEmptyMorePages + 1
                    : 0
                self.isMoreExhausted = self.nextCursor == nil
                    || self.consecutiveEmptyMorePages >= 2
                self.isLoadingMore = false
                if self.currentResult != nil {
                    self.phase = .loaded
                } else if !self.isMoreExhausted {
                    DispatchQueue.main.async { [weak self] in
                        self?.prefetchIfNeeded()
                    }
                }
            }
        )
    }

    private func failReplay(_ error: CoreSparkError) {
        isInteractionLocked = false
        if error == .forbidden || error == .notFound || error == .decoding {
            persistence.remove(
                actorID: actorID,
                rootSourceAssetID: rootSourceAssetID
            )
            chain = []
            activeActivityID = nil
            pendingTrigger = nil
            results = []
            visibleIndex = 0
            lastFailedReplayActivityID = nil
            phase = .failed("This Spark can no longer be restored.")
            return
        }
        phase = .failed("Couldn't restore this Spark.")
    }

    private func failRootLoad(_ error: CoreSparkError) {
        isInteractionLocked = false
        phase = .failed(Self.message(for: error))
    }

    private func beginOperation() -> Int {
        operationToken += 1
        return operationToken
    }

    private func isCurrentOperation(_ token: Int) -> Bool {
        token == operationToken
    }

    private func persistCurrentState() {
        guard
            !chain.isEmpty
                || activeActivityID != nil
                || pendingTrigger != nil
        else {
            persistence.remove(
                actorID: actorID,
                rootSourceAssetID: rootSourceAssetID
            )
            return
        }

        var persistedChain = chain
        if let activeActivityID,
           let index = persistedChain.firstIndex(where: {
               $0.activityID == activeActivityID
           }) {
            persistedChain[index].visibleIndex = visibleIndex
            chain = persistedChain
        }

        persistence.save(
            SparkSessionSnapshot(
                actorID: actorID,
                rootSourceAssetID: rootSourceAssetID,
                nodes: persistedChain,
                activeActivityID: activeActivityID,
                pendingTrigger: pendingTrigger,
                didShowUpwardCue: didShowUpwardCue
            )
        )
    }

    private static func preview(for card: FlowCard) -> String {
        let normalized = card.content
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(80))
    }

    private static func isAmbiguousTriggerError(
        _ error: CoreSparkError
    ) -> Bool {
        error == .offline || error == .timeout || error == .unknown
    }

    private static func message(for error: CoreSparkError) -> String {
        switch error {
        case .unauthorized:
            return "Your session expired."
        case .forbidden:
            return "This card isn't available."
        case .notFound:
            return "This Spark is no longer available."
        case .insufficientCredit:
            return "Not enough credit for this Spark."
        case .maximumDepth:
            return "This Spark has reached its limit."
        case .retrievalUnavailable:
            return "Spark is unavailable right now."
        case .resultsUnavailable:
            return "Spark completed, but its results couldn't load."
        case .offline, .timeout:
            return "Couldn't confirm this Spark."
        case .decoding, .server, .unknown:
            return "Couldn't continue this Spark."
        }
    }
}
