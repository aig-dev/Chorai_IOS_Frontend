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

    private var sourceCancellable: AnyCancellable?
    private var triggerCancellable: AnyCancellable?
    private var replayCancellable: AnyCancellable?
    private var replaySourceCancellable: AnyCancellable?

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
                phase = .reconciling
                isInteractionLocked = true
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
                    self.restoreAfterTriggerFailure(
                        rollback: rollback,
                        pending: pending,
                        source: source,
                        error: error
                    )
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
        pendingTrigger = nil
        isInteractionLocked = false
        phase = replayedResults.isEmpty ? .empty : .loaded
        persistCurrentState()
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
