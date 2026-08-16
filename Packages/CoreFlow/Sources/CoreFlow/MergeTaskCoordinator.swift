import Combine
import Foundation

public enum MergeTaskVisualState: String, Equatable, Sendable {
    case working, complete, committing, recovering, failed
}

public struct MergeTaskSummary: Identifiable, Equatable, Sendable {
    public var id: String { jobID }
    public let jobID: String
    public let sourceCount: Int
    public let createdAt: Date
    public let visualState: MergeTaskVisualState

    public init(
        jobID: String,
        sourceCount: Int,
        createdAt: Date,
        visualState: MergeTaskVisualState
    ) {
        self.jobID = jobID
        self.sourceCount = sourceCount
        self.createdAt = createdAt
        self.visualState = visualState
    }
}

public enum MergeTaskPresentation: Equatable, Sendable {
    case progress(jobID: String)
    case preview(jobID: String)
    case failure(jobID: String)
}

public struct MergeCommittedCardIntent: Equatable, Sendable {
    public let jobID: String
    public let assetID: String
}

@MainActor
public struct MergeDraftSession {
    public let operationID: String
    public let store: MergeSessionStore
    let persistence: MergeTaskSessionPersistence
    let generation: Int
}

@MainActor
public final class MergeTaskCoordinator: ObservableObject {
    @Published public private(set) var summaries: [MergeTaskSummary] = []
    @Published public private(set) var presentation: MergeTaskPresentation?
    @Published public private(set) var committedCardIntent: MergeCommittedCardIntent?
    @Published public private(set) var completionEventJobID: String?

    private struct Runtime {
        let operationID: String
        let store: MergeSessionStore
        let persistence: MergeTaskSessionPersistence
    }

    private struct DraftOwnership {
        let actorID: String
        let generation: Int
        let store: MergeSessionStore
        let persistence: MergeTaskSessionPersistence
    }

    private let service: any CoreMergeServing
    private let persistence: any MergeTaskCollectionPersisting
    private let sleeper: any MergeSleeping
    private let pollingGate: MergePollingGate
    private let idempotencyKey: () -> String
    private let operationID: () -> String
    private let now: () -> Date

    private var actorID: String?
    private var draftsByOperationID: [String: DraftOwnership] = [:]
    private var runtimesByOperationID: [String: Runtime] = [:]
    private var jobToOperationID: [String: String] = [:]
    private var subscriptionsByOperationID: [String: Set<AnyCancellable>] = [:]
    private var completionObservedJobIDs: Set<String> = []
    private var committedIntentObservedJobIDs: Set<String> = []
    private var committedIntentQueue: [MergeCommittedCardIntent] = []
    private var isNetworkAvailable = true
    private var isApplicationActive = true
    private var generation = 0

    public init(
        service: any CoreMergeServing,
        persistence: any MergeTaskCollectionPersisting,
        sleeper: any MergeSleeping = SystemMergeSleeper(),
        pollingGate: MergePollingGate = MergePollingGate(
            maxConcurrentRequests: 4
        ),
        idempotencyKey: @escaping () -> String = {
            "ios-merge-\(UUID().uuidString)"
        },
        operationID: @escaping () -> String = { UUID().uuidString },
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.persistence = persistence
        self.sleeper = sleeper
        self.pollingGate = pollingGate
        self.idempotencyKey = idempotencyKey
        self.operationID = operationID
        self.now = now
    }

    public func activate(actorID: String) {
        clearRuntimeState()
        generation += 1
        self.actorID = actorID

        let collection = persistence.collection(actorID: actorID)
        completionObservedJobIDs = Set(
            collection.tasks.compactMap { jobID, record in
                record.snapshot.lastStatus == .artifactReady ? jobID : nil
            }
        )

        var recordsByOperationID: [String: (MergeTaskRecord, String?)] = [:]
        for (jobID, record) in collection.tasks {
            recordsByOperationID[record.operationID] = (record, jobID)
        }
        for record in collection.pendingCreations.values {
            recordsByOperationID[record.operationID] = (
                record,
                record.replacesJobID
            )
        }

        let records = recordsByOperationID.values.sorted {
            if $0.0.createdAt == $1.0.createdAt {
                return $0.0.operationID < $1.0.operationID
            }
            return $0.0.createdAt < $1.0.createdAt
        }
        for (record, initialJobID) in records {
            let scopedPersistence = MergeTaskSessionPersistence(
                actorID: actorID,
                operationID: record.operationID,
                initialJobID: initialJobID,
                store: persistence,
                now: now
            )
            let store = makeStore(
                actorID: actorID,
                anchor: anchor(from: record.snapshot),
                persistence: scopedPersistence,
                resumePersistedSession: true
            )
            register(
                operationID: record.operationID,
                store: store,
                persistence: scopedPersistence
            )
            store.start()
            suspendIfNeeded(store)
        }
        refreshState()
    }

    public func deactivate() {
        clearRuntimeState()
        generation += 1
        actorID = nil
    }

    public func makeDraft(anchor: MergeSource) -> MergeDraftSession {
        guard let actorID else {
            preconditionFailure("MergeTaskCoordinator must be activated before making a draft")
        }
        let operationID = operationID()
        precondition(!operationID.isEmpty, "Merge operation IDs must not be empty")
        precondition(
            draftsByOperationID[operationID] == nil
                && runtimesByOperationID[operationID] == nil,
            "Merge operation IDs must be unique within an activation"
        )
        let scopedPersistence = MergeTaskSessionPersistence(
            actorID: actorID,
            operationID: operationID,
            store: persistence,
            now: now
        )
        let store = makeStore(
            actorID: actorID,
            anchor: anchor,
            persistence: scopedPersistence,
            resumePersistedSession: false
        )
        draftsByOperationID[operationID] = DraftOwnership(
            actorID: actorID,
            generation: generation,
            store: store,
            persistence: scopedPersistence
        )
        let draft = MergeDraftSession(
            operationID: operationID,
            store: store,
            persistence: scopedPersistence,
            generation: generation
        )
        return draft
    }

    @discardableResult
    public func adopt(_ draft: MergeDraftSession) -> String? {
        guard
            let actorID,
            draft.generation == generation,
            draft.persistence.actorID == actorID,
            let ownership = draftsByOperationID[draft.operationID],
            ownership.actorID == actorID,
            ownership.generation == generation,
            ownership.store === draft.store,
            ownership.persistence === draft.persistence,
            runtimesByOperationID[draft.operationID] == nil,
            let snapshot = draft.store.activeSnapshot,
            let jobID = snapshot.jobID?.nonEmpty
        else {
            return nil
        }

        draft.persistence.save(snapshot)
        let collection = persistence.collection(actorID: actorID)
        guard
            let record = collection.tasks[jobID],
            record.operationID == draft.operationID,
            record.snapshot.jobID == jobID
        else {
            return nil
        }

        draftsByOperationID[draft.operationID] = nil
        register(
            operationID: draft.operationID,
            store: draft.store,
            persistence: draft.persistence
        )
        jobToOperationID[jobID] = draft.operationID
        suspendIfNeeded(draft.store)
        return jobID
    }

    public func session(jobID: String) -> MergeSessionStore? {
        guard let operationID = jobToOperationID[jobID] else { return nil }
        return runtimesByOperationID[operationID]?.store
    }

    public func summary(jobID: String) -> MergeTaskSummary? {
        summaries.first { $0.jobID == jobID }
    }

    public func present(jobID: String) {
        refreshState()
        guard let summary = summary(jobID: jobID) else { return }
        presentation = presentation(for: summary)
    }

    public func minimize() {
        presentation = nil
    }

    public func setNetworkAvailable(_ isAvailable: Bool) {
        guard isNetworkAvailable != isAvailable else { return }
        isNetworkAvailable = isAvailable
        for runtime in runtimesByOperationID.values {
            if isAvailable, isApplicationActive {
                runtime.store.resume()
            } else if !isAvailable {
                runtime.store.suspend(reason: .offline)
            }
        }
        refreshState()
    }

    public func setApplicationActive(_ isActive: Bool) {
        guard isApplicationActive != isActive else { return }
        isApplicationActive = isActive
        for runtime in runtimesByOperationID.values {
            if isActive, isNetworkAvailable {
                runtime.store.resume()
            } else if !isActive {
                runtime.store.suspend(reason: nil)
            }
        }
        refreshState()
    }

    public func removeFailed(jobID: String) {
        guard
            summary(jobID: jobID)?.visualState == .failed,
            let operationID = jobToOperationID[jobID],
            let runtime = runtimesByOperationID[operationID],
            let actorID
        else {
            return
        }
        runtime.store.suspend(reason: nil)
        runtime.persistence.remove(actorID: actorID)
        if presentation?.jobID == jobID {
            presentation = nil
        }
        unregister(operationID: operationID)
        refreshState()
    }

    public func retryFailed(jobID: String) {
        guard
            summary(jobID: jobID)?.visualState == .failed,
            let store = session(jobID: jobID)
        else {
            return
        }
        store.retry()
        refreshState()
    }

    public func acknowledgeCommittedCardIntent(jobID: String) {
        guard
            committedIntentQueue.first?.jobID == jobID,
            let operationID = jobToOperationID[jobID],
            let runtime = runtimesByOperationID[operationID]
        else {
            return
        }

        runtime.store.acknowledgeCompletion()
        committedIntentQueue.removeFirst()
        committedCardIntent = nil
        if presentation?.jobID == jobID {
            presentation = nil
        }
        unregister(operationID: operationID)
        refreshState()

        let expectedGeneration = generation
        Task { @MainActor [weak self] in
            await Task.yield()
            guard self?.generation == expectedGeneration else { return }
            self?.committedCardIntent = self?.committedIntentQueue.first
        }
    }

    private func makeStore(
        actorID: String,
        anchor: MergeSource,
        persistence: MergeTaskSessionPersistence,
        resumePersistedSession: Bool
    ) -> MergeSessionStore {
        MergeSessionStore(
            actorID: actorID,
            anchor: anchor,
            service: service,
            persistence: persistence,
            sleeper: sleeper,
            pollingGate: pollingGate,
            resumePersistedSession: resumePersistedSession,
            idempotencyKey: idempotencyKey
        )
    }

    private func register(
        operationID: String,
        store: MergeSessionStore,
        persistence: MergeTaskSessionPersistence
    ) {
        let runtime = Runtime(
            operationID: operationID,
            store: store,
            persistence: persistence
        )
        runtimesByOperationID[operationID] = runtime

        let expectedGeneration = generation
        var subscriptions = Set<AnyCancellable>()
        Publishers.CombineLatest3(store.$phase, store.$job, store.$artifact)
            .sink { [weak self] _, _, _ in
                guard self?.generation == expectedGeneration else { return }
                self?.scheduleRefresh(operationID: operationID)
            }
            .store(in: &subscriptions)
        subscriptionsByOperationID[operationID] = subscriptions
    }

    private func unregister(operationID: String) {
        subscriptionsByOperationID[operationID] = nil
        runtimesByOperationID[operationID]?.store.invalidateLifetime()
        runtimesByOperationID[operationID] = nil
        jobToOperationID = jobToOperationID.filter { $0.value != operationID }
    }

    private func scheduleRefresh(operationID: String?) {
        guard let operationID else { return }
        let expectedGeneration = generation
        Task { @MainActor [weak self] in
            await Task.yield()
            guard
                let self,
                self.generation == expectedGeneration,
                self.runtimesByOperationID[operationID] != nil
            else {
                return
            }
            self.refreshState(
                prioritizedOperationID: operationID,
                shouldObserveEvents: true
            )
        }
    }

    private func refreshState(
        prioritizedOperationID: String? = nil,
        shouldObserveEvents: Bool = false
    ) {
        guard let actorID else {
            summaries = []
            return
        }

        let collection = persistence.collection(actorID: actorID)
        let previousJobToOperationID = jobToOperationID
        let presentedOperationID = presentation.flatMap {
            previousJobToOperationID[$0.jobID]
        }
        var acceptedByOperationID: [String: (String, MergeTaskRecord)] = [:]
        for (jobID, record) in collection.tasks {
            acceptedByOperationID[record.operationID] = (jobID, record)
        }

        var nextJobToOperationID: [String: String] = [:]
        var visibleByOperationID: [String: MergeTaskSummary] = [:]
        var terminalCancelledOperationIDs: [String] = []

        var operationIDs = runtimesByOperationID.keys.sorted()
        if let prioritizedOperationID,
           let index = operationIDs.firstIndex(of: prioritizedOperationID) {
            operationIDs.remove(at: index)
            operationIDs.insert(prioritizedOperationID, at: 0)
        }

        for operationID in operationIDs {
            guard let runtime = runtimesByOperationID[operationID] else {
                continue
            }
            if runtime.store.phase == .cancelled {
                terminalCancelledOperationIDs.append(operationID)
                continue
            }

            if let pending = collection.pendingCreations[operationID],
               let retainedJobID = pending.replacesJobID,
               let retained = collection.tasks[retainedJobID] {
                nextJobToOperationID[retainedJobID] = operationID
                visibleByOperationID[operationID] = MergeTaskSummary(
                    jobID: retainedJobID,
                    sourceCount: pending.snapshot.createRequest.sources.count,
                    createdAt: retained.createdAt,
                    visualState: .recovering
                )
                continue
            }

            guard let (jobID, record) = acceptedByOperationID[operationID] else {
                continue
            }
            nextJobToOperationID[jobID] = operationID
            if shouldObserveEvents, operationID == prioritizedOperationID {
                observeEvents(jobID: jobID, store: runtime.store)
            }
            guard let visualState = visualState(for: runtime.store.phase) else {
                continue
            }
            visibleByOperationID[operationID] = MergeTaskSummary(
                jobID: jobID,
                sourceCount: record.snapshot.createRequest.sources.count,
                createdAt: record.createdAt,
                visualState: visualState
            )
        }

        jobToOperationID = nextJobToOperationID
        summaries = visibleByOperationID.values.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.jobID > $1.jobID
            }
            return $0.createdAt > $1.createdAt
        }

        if let presentedOperationID,
           let summary = visibleByOperationID[presentedOperationID] {
            switch presentation {
            case .progress:
                presentation = summary.visualState == .complete
                    ? .preview(jobID: summary.jobID)
                    : presentation(for: summary)
            case .preview:
                presentation = .preview(jobID: summary.jobID)
            case .failure:
                presentation = presentation(for: summary)
            case nil:
                break
            }
        }

        for operationID in terminalCancelledOperationIDs {
            if let jobID = previousJobToOperationID.first(
                where: { $0.value == operationID }
            )?.key, presentation?.jobID == jobID {
                presentation = nil
            }
            unregister(operationID: operationID)
        }
    }

    private func observeEvents(jobID: String, store: MergeSessionStore) {
        switch store.phase {
        case .ready:
            if isApplicationActive,
               completionObservedJobIDs.insert(jobID).inserted {
                completionEventJobID = jobID
            }
        case .completed(let assetID):
            guard
                let assetID = assetID?.nonEmpty,
                committedIntentObservedJobIDs.insert(jobID).inserted
            else {
                return
            }
            committedIntentQueue.append(
                MergeCommittedCardIntent(jobID: jobID, assetID: assetID)
            )
            if committedCardIntent == nil {
                committedCardIntent = committedIntentQueue.first
            }
        default:
            break
        }
    }

    private func visualState(
        for phase: MergeSessionPhase
    ) -> MergeTaskVisualState? {
        switch phase {
        case .ready:
            return .complete
        case .committing:
            return .committing
        case .paused(.notFound), .failed:
            return .failed
        case .completed(let assetID):
            return assetID?.nonEmpty == nil ? .failed : nil
        case .paused:
            return .recovering
        case .cancelled:
            return nil
        case .idle, .checkingAvailability, .selection, .creating,
             .weaving, .loadingArtifact, .cancelling:
            return .working
        }
    }

    private func presentation(
        for summary: MergeTaskSummary
    ) -> MergeTaskPresentation {
        switch summary.visualState {
        case .complete:
            return .preview(jobID: summary.jobID)
        case .failed:
            return .failure(jobID: summary.jobID)
        case .working, .committing, .recovering:
            return .progress(jobID: summary.jobID)
        }
    }

    private func suspendIfNeeded(_ store: MergeSessionStore) {
        if !isNetworkAvailable {
            store.suspend(reason: .offline)
        } else if !isApplicationActive {
            store.suspend(reason: nil)
        }
    }

    private func anchor(from snapshot: MergeSessionSnapshot) -> MergeSource {
        snapshot.createRequest.sources.first {
            $0.assetID == snapshot.anchorAssetID
        } ?? MergeSource(
            assetID: snapshot.anchorAssetID,
            versionID: nil,
            preview: snapshot.anchorPreview
        )
    }

    private func clearRuntimeState() {
        for draft in draftsByOperationID.values {
            draft.store.invalidateLifetime()
        }
        for runtime in runtimesByOperationID.values {
            runtime.store.invalidateLifetime()
        }
        draftsByOperationID.removeAll()
        subscriptionsByOperationID.removeAll()
        runtimesByOperationID.removeAll()
        jobToOperationID.removeAll()
        completionObservedJobIDs.removeAll()
        committedIntentObservedJobIDs.removeAll()
        committedIntentQueue.removeAll()
        summaries = []
        presentation = nil
        committedCardIntent = nil
        completionEventJobID = nil
    }
}

private extension MergeTaskPresentation {
    var jobID: String {
        switch self {
        case .progress(let jobID), .preview(let jobID), .failure(let jobID):
            return jobID
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
