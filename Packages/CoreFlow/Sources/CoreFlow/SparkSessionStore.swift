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

    public var canUndoSave: Bool {
        undoEntry?.createdFavorite == true
    }

    public var undoAssetID: String? {
        canUndoSave ? undoEntry?.result.id : nil
    }

    public var savedAssetID: String? {
        guard case .saved(let assetID) = notice else {
            return nil
        }
        return assetID
    }

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

    private struct UndoEntry {
        let result: SparkResult
        let originalIndex: Int
        let postSaveIndex: Int
        let createdFavorite: Bool
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
    private var undoEntry: UndoEntry?

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

    public func saveCurrent() {
        guard
            !isInteractionLocked,
            let result = currentResult,
            let sparkActivityID = activeActivityID
        else {
            return
        }

        let entry = UndoEntry(
            result: result,
            originalIndex: visibleIndex,
            postSaveIndex: visibleIndex + 1,
            createdFavorite: !result.card.isFavorited
        )
        undoEntry = nil
        notice = nil
        visibleIndex = entry.postSaveIndex
        phase = currentResult == nil ? .empty : .loaded
        isInteractionLocked = true
        persistCurrentState()

        var receivedValue = false
        interactionCancellable = service.favorite(
            assetID: result.id,
            sparkActivityID: sparkActivityID
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                guard let self else { return }
                self.isInteractionLocked = false
                if case .failure = completion {
                    self.visibleIndex = entry.originalIndex
                    self.phase = .loaded
                    self.notice = .saveFailed
                    self.undoEntry = nil
                    self.persistCurrentState()
                } else if !receivedValue {
                    self.visibleIndex = entry.originalIndex
                    self.phase = .loaded
                    self.notice = .saveFailed
                    self.undoEntry = nil
                    self.persistCurrentState()
                } else {
                    self.prefetchIfNeeded()
                }
            },
            receiveValue: { [weak self] in
                guard let self else { return }
                receivedValue = true
                self.undoEntry = entry
                self.notice = .saved(assetID: result.id)
            }
        )
    }

    public func undoLastSave() {
        guard
            !isInteractionLocked,
            let entry = undoEntry,
            entry.createdFavorite
        else {
            return
        }

        undoEntry = nil
        notice = nil
        visibleIndex = entry.originalIndex
        phase = .loaded
        isInteractionLocked = true
        persistCurrentState()

        var receivedValue = false
        interactionCancellable = service.unfavorite(assetID: entry.result.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self else { return }
                    self.isInteractionLocked = false
                    if case .failure = completion {
                        self.visibleIndex = entry.postSaveIndex
                        self.phase = self.currentResult == nil ? .empty : .loaded
                        self.undoEntry = entry
                        self.notice = .undoFailed
                    } else if !receivedValue {
                        self.visibleIndex = entry.postSaveIndex
                        self.phase = self.currentResult == nil ? .empty : .loaded
                        self.undoEntry = entry
                        self.notice = .undoFailed
                    }
                    self.persistCurrentState()
                },
                receiveValue: { _ in
                    receivedValue = true
                }
            )
    }

    public func expireUndo(assetID: String) {
        guard undoEntry?.result.id == assetID else {
            return
        }
        undoEntry = nil
        if notice == .saved(assetID: assetID) {
            notice = nil
        }
    }

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
        if let pendingTrigger {
            guard !isInteractionLocked else { return }
            reconcilePendingTrigger(
                pendingTrigger,
                rollback: nil,
                source: lastFailedSourceCard
            )
            return
        }

        guard
            !isInteractionLocked,
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
                    if Self.isAmbiguousTriggerError(error) {
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
        rollback: TriggerRollback
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
        results = page.orderedResults
        visibleIndex = 0
        activeActivityID = page.activityID
        resetMoreState(sourceAssetID: page.sourceAssetID)
        undoEntry = nil
        pendingTrigger = nil
        lastFailedTrigger = nil
        lastFailedSourceCard = nil
        isInteractionLocked = false
        phase = results.isEmpty ? .empty : .loaded
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
        let token = beginOperation()
        var receivedPage = false

        replayCancellable = service.activityResults(activityID: activityID)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self, self.isCurrentOperation(token) else {
                        return
                    }
                    if case .failure(let error) = completion {
                        self.failReplay(error)
                    } else if !receivedPage {
                        self.failReplay(.decoding)
                    }
                },
                receiveValue: { [weak self] page in
                    guard let self, self.isCurrentOperation(token) else {
                        return
                    }
                    receivedPage = true
                    guard page.activityID == activityID else {
                        self.failReplay(.decoding)
                        return
                    }
                    self.loadReplaySource(
                        page: page,
                        savedNode: savedNode,
                        token: token
                    )
                }
            )
    }

    private func loadReplaySource(
        page: SparkActivityPage,
        savedNode: SparkChainNode,
        token: Int
    ) {
        var receivedCard = false
        replaySourceCancellable = service.card(assetID: page.sourceAssetID)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self, self.isCurrentOperation(token) else {
                        return
                    }
                    if case .failure(let error) = completion {
                        self.failReplay(error)
                    } else if !receivedCard {
                        self.failReplay(.decoding)
                    }
                },
                receiveValue: { [weak self] card in
                    guard let self, self.isCurrentOperation(token) else {
                        return
                    }
                    receivedCard = true
                    self.applyReplay(
                        page: page,
                        source: card,
                        savedNode: savedNode
                    )
                }
            )
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

        let replayedResults = page.orderedResults
        sourceCard = source
        results = replayedResults
        visibleIndex = replayedResults.isEmpty
            ? 0
            : min(savedNode.visibleIndex, replayedResults.count - 1)
        activeActivityID = page.activityID
        resetMoreState(sourceAssetID: page.sourceAssetID)
        undoEntry = nil
        pendingTrigger = nil
        isInteractionLocked = false
        phase = replayedResults.isEmpty ? .empty : .loaded
        persistCurrentState()
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

    private func resetMoreState(sourceAssetID: String) {
        moreCancellable?.cancel()
        moreCancellable = nil
        nextCursor = nil
        seenAssetIDs = Set(results.map(\.id))
        seenAssetIDs.insert(sourceAssetID)
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
                if case .failure = completion, self.undoEntry == nil {
                    self.notice = .moreFailed
                } else if !receivedPage, self.undoEntry == nil {
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
        case .offline, .timeout:
            return "Couldn't confirm this Spark."
        case .decoding, .server, .unknown:
            return "Couldn't continue this Spark."
        }
    }
}
