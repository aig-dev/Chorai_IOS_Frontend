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

public enum MergeTaskFailureAction: Hashable, Sendable {
    case retry
    case cancel
    case remove
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

public enum MergeEditorTransitionState: Equatable, Sendable {
    case ready, draining, failed
}

@MainActor
public final class MergeTaskCoordinator: ObservableObject {
    @Published public private(set) var summaries: [MergeTaskSummary] = []
    @Published public private(set) var presentation: MergeTaskPresentation?
    @Published public private(set) var committedCardIntent: MergeCommittedCardIntent?
    @Published public private(set) var completionEventJobID: String?

    @Published public private(set) var transitionState: MergeEditorTransitionState = .ready

    private struct EditorDrain {
        let jobID: String
        let beginClosing: @MainActor () -> Void
        let drain: @MainActor () async -> Bool
    }
    private var editorDrains: [UUID: EditorDrain] = [:]
    @Published private var closingEditorIDs: Set<UUID> = []
    private var sealedEditorIDs: Set<UUID> = []
    private var requestedActorID: String?
    private var retirementTask: Task<Void, Never>?

    public var canStartDraft: Bool { transitionState == .ready && actorID != nil }

    public func isReady(for actorID: String?) -> Bool {
        transitionState == .ready && actorID != nil && self.actorID == actorID
    }

    public func registerEditorDrain(
        id: UUID, jobID: String,
        beginClosing: @escaping @MainActor () -> Void,
        drain: @escaping @MainActor () async -> Bool
    ) {
        editorDrains[id] = EditorDrain(jobID: jobID, beginClosing: beginClosing, drain: drain)
        closingEditorIDs.remove(id)
        if transitionState != .ready { sealEditor(id) }
    }

    public func unregisterEditorDrain(id: UUID) {
        // Retirement owns the registration until its drain has succeeded.
        guard transitionState == .ready else { return }
        editorDrains[id] = nil
        closingEditorIDs.remove(id)
        sealedEditorIDs.remove(id)
    }

    public func editorWillDisappear(id: UUID) {
        guard editorDrains[id] != nil else { return }
        closingEditorIDs.insert(id)
    }

    public func editorDrainFailed(id: UUID) {
        guard transitionState == .ready, editorDrains[id] != nil else { return }
        // Retain the original failed owner and use the existing explicit retry
        // transition. A fresh editor must never overwrite its unsaved body.
        beginRetirement()
        transitionState = .failed
    }

    private func isEditorClosing(jobID: String) -> Bool {
        closingEditorIDs.contains { editorDrains[$0]?.jobID == jobID }
    }

    public func retryEditorDrain() {
        guard transitionState == .failed else { return }
        transitionState = .draining
        startRetirement()
    }

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
    private let queueCommittedNote: @MainActor (String, String) throws -> Void
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
        now: @escaping () -> Date = Date.init,
        queueCommittedNote: @escaping @MainActor (String, String) throws -> Void = { _, _ in }
    ) {
        self.service = service
        self.persistence = persistence
        self.sleeper = sleeper
        self.pollingGate = pollingGate
        self.idempotencyKey = idempotencyKey
        self.operationID = operationID
        self.now = now
        self.queueCommittedNote = queueCommittedNote
    }

    @discardableResult
    public func synchronizeLifecycle(
        verifiedActorID: String?,
        isApplicationActive: Bool,
        isNetworkAvailable: Bool
    ) -> Bool {
        let didChange = requestedActorID != verifiedActorID
        if didChange || transitionState != .ready {
            self.isApplicationActive = isApplicationActive
            self.isNetworkAvailable = isNetworkAvailable
            requestActivation(verifiedActorID)
        } else {
            setApplicationActive(isApplicationActive)
            setNetworkAvailable(isNetworkAvailable)
        }
        return didChange
    }

    public func activate(actorID: String) { requestActivation(actorID, force: true) }

    public func deactivate() { requestActivation(nil) }

    private func requestActivation(_ target: String?, force: Bool = false) {
        requestedActorID = target
        guard transitionState == .ready else { return }
        guard force || actorID != target else { return }
        guard !editorDrains.isEmpty else {
            finishActivation(target)
            return
        }
        beginRetirement()
        startRetirement()
    }

    private func beginRetirement() {
        transitionState = .draining
        presentation = nil
        summaries = []
        committedCardIntent = nil
        completionEventJobID = nil
        for runtime in runtimesByOperationID.values { runtime.store.beginLocalEditorDrain() }
        for draft in draftsByOperationID.values { draft.store.beginLocalEditorDrain() }
        for id in Array(editorDrains.keys) { sealEditor(id) }
    }

    private func sealEditor(_ id: UUID) {
        guard sealedEditorIDs.insert(id).inserted else { return }
        editorDrains[id]?.beginClosing()
    }

    private func startRetirement() {
        guard retirementTask == nil else { return }
        retirementTask = Task { @MainActor in
            while let (id, editor) = self.editorDrains.first {
                guard await editor.drain() else {
                    self.retirementTask = nil
                    self.transitionState = .failed
                    return
                }
                self.editorDrains[id] = nil
                self.closingEditorIDs.remove(id)
                self.sealedEditorIDs.remove(id)
            }
            self.retirementTask = nil
            self.finishActivation(self.requestedActorID)
        }
    }

    private func finishActivation(_ target: String?) {
        clearRuntimeState()
        generation += 1
        actorID = target
        transitionState = .ready
        guard let actorID = target else { return }

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

    public func makeDraft(anchor: MergeSource) -> MergeDraftSession {
        guard transitionState == .ready, let actorID else {
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
        guard transitionState == .ready else { return nil }
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
        refreshState(
            prioritizedOperationID: draft.operationID,
            shouldObserveEvents: true
        )
        return jobID
    }

    public func abandon(_ draft: MergeDraftSession) {
        guard transitionState == .ready else { return }
        guard
            let actorID,
            draft.generation == generation,
            draft.persistence.actorID == actorID,
            let ownership = draftsByOperationID[draft.operationID],
            ownership.actorID == actorID,
            ownership.generation == generation,
            ownership.store === draft.store,
            ownership.persistence === draft.persistence,
            runtimesByOperationID[draft.operationID] == nil
        else {
            return
        }

        draftsByOperationID[draft.operationID] = nil
        if let snapshot = draft.store.activeSnapshot {
            register(
                operationID: draft.operationID,
                store: draft.store,
                persistence: draft.persistence
            )
            if let jobID = snapshot.jobID?.nonEmpty {
                jobToOperationID[jobID] = draft.operationID
            }
            suspendIfNeeded(draft.store)
            refreshState(
                prioritizedOperationID: draft.operationID,
                shouldObserveEvents: true
            )
            return
        }
        draft.store.invalidateLifetime()
        draft.persistence.remove(actorID: actorID)
        refreshState()
    }

    public func session(jobID: String) -> MergeSessionStore? {
        guard transitionState == .ready, !isEditorClosing(jobID: jobID),
              let operationID = jobToOperationID[jobID] else { return nil }
        return runtimesByOperationID[operationID]?.store
    }

    public func summary(jobID: String) -> MergeTaskSummary? {
        summaries.first { $0.jobID == jobID }
    }

    public func present(jobID: String) {
        guard transitionState == .ready, !isEditorClosing(jobID: jobID) else { return }
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
        guard transitionState == .ready else { return }
        for runtime in runtimesByOperationID.values {
            runtime.store.setNetworkAvailable(isAvailable)
            if runtime.store.phase == .ready {
                continue
            }
            if recoveryStrategy(for: runtime.store) == .replacement {
                runtime.store.suspend(reason: nil)
                continue
            }
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
        guard transitionState == .ready else { return }
        if !isActive {
            for editor in editorDrains.values {
                Task { @MainActor in _ = await editor.drain() }
            }
        }
        for runtime in runtimesByOperationID.values {
            if runtime.store.phase == .ready {
                continue
            }
            if recoveryStrategy(for: runtime.store) == .replacement {
                runtime.store.suspend(reason: nil)
                continue
            }
            if isActive, isNetworkAvailable {
                runtime.store.resume()
            } else if !isActive {
                runtime.store.suspend(reason: nil)
            }
        }
        refreshState()
    }

    public func removeFailed(jobID: String) {
        guard transitionState == .ready else { return }
        guard
            failureActions(jobID: jobID).contains(.remove),
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

    public func failureActions(jobID: String) -> Set<MergeTaskFailureAction> {
        guard let store = session(jobID: jobID) else { return [] }
        switch recoveryStrategy(for: store) {
        case .replacement:
            return [.retry, .remove]
        case .pendingCreation:
            return [.retry, .remove]
        case .sameOperation:
            if case .paused(.offline) = store.phase {
                return [.retry]
            }
            return store.canCancelCanonicalJob
                ? [.retry, .cancel]
                : [.retry]
        case .removeOnly:
            return [.remove]
        case .none:
            return []
        }
    }

    public func retryFailed(jobID: String) {
        guard transitionState == .ready else { return }
        guard
            failureActions(jobID: jobID).contains(.retry),
            let store = session(jobID: jobID)
        else {
            return
        }

        switch recoveryStrategy(for: store) {
        case .replacement:
            store.retryGeneration()
        case .pendingCreation, .sameOperation:
            store.retry()
        case .removeOnly, .none:
            return
        }

        if presentation?.jobID == jobID {
            presentation = .progress(jobID: jobID)
        }
        refreshState()
    }

    public func cancelFailed(jobID: String) {
        guard transitionState == .ready else { return }
        guard
            failureActions(jobID: jobID).contains(.cancel),
            let store = session(jobID: jobID)
        else {
            return
        }
        store.cancel()
        if presentation?.jobID == jobID {
            presentation = .progress(jobID: jobID)
        }
        refreshState()
    }

    private enum RecoveryStrategy {
        case replacement
        case pendingCreation
        case sameOperation
        case removeOnly
        case none
    }

    private func recoveryStrategy(
        for store: MergeSessionStore
    ) -> RecoveryStrategy {
        if let snapshot = store.activeSnapshot,
           snapshot.jobID?.nonEmpty == nil {
            return .pendingCreation
        }
        if store.activeSnapshot?.lastStatus == .failed {
            return .replacement
        }
        switch store.phase {
        case .paused(.notFound)
            where store.notFoundResource == .jobStatus:
            return .replacement
        case .failed where store.activeSnapshot?.lastStatus == .failed:
            return .replacement
        case .paused, .failed:
            return .sameOperation
        case .completed(let assetID) where assetID?.nonEmpty == nil:
            return .removeOnly
        default:
            return .none
        }
    }

    public func acknowledgeCommittedCardIntent(jobID: String) {
        guard transitionState == .ready else { return }
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
            queueCommittedNote: queueCommittedNote,
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
        guard transitionState == .ready, let actorID else {
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
        store.setNetworkAvailable(isNetworkAvailable)
        if store.phase == .ready {
            return
        }
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
