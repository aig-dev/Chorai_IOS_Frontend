import Combine
import Foundation

@usableFromInline
enum MergePollDelayJitter {
    @usableFromInline
    static let productionFactorRange = 0.85...1.15

    @usableFromInline
    static func applying(to delay: UInt64, factor: Double) -> UInt64 {
        precondition(productionFactorRange.contains(factor))
        guard delay > 0 else { return 0 }
        return UInt64((Double(delay) * factor).rounded())
    }
}

public enum MergeSessionPhase: Equatable, Sendable {
    case idle
    case checkingAvailability
    case selection
    case creating
    case weaving(MergeJobStatus)
    case loadingArtifact
    case ready
    case committing
    case paused(CoreMergeError)
    case failed(CoreMergeError)
    case cancelling
    case cancelled
    case completed(assetID: String?)
}

public enum MergeNotFoundResource: Equatable, Sendable {
    case jobStatus
    case artifact
}

@MainActor
public final class MergeSessionStore: ObservableObject {
    @Published public private(set) var anchor: MergeSource
    @Published public private(set) var selectedSources: [MergeSource]
    @Published public private(set) var capabilities: [MergeCapability] = []
    @Published public private(set) var job: MergeJob?
    @Published public private(set) var artifact: MergeArtifact?
    @Published public private(set) var artifactDraft: MergeArtifactDraftSnapshot?
    @Published public private(set) var artifactDraftSyncState: MergeDraftSyncState = .clean
    @Published public private(set) var artifactActionError: CoreMergeError?
    @Published public private(set) var notFoundResource: MergeNotFoundResource?
    @Published public private(set) var phase: MergeSessionPhase = .idle
    @Published public var titleOverride = ""
    @Published public private(set) var isOperationInFlight = false
    private(set) var createResponseCount = 0
    private(set) var statusResponseCount = 0
    private(set) var cancelledStatusResponseDiscardCount = 0

    public var canCreate: Bool {
        !isLifetimeInvalidated
            && phase == .selection
            && isMergeAvailable
            && selectedSources.count >= 2
            && !isOperationInFlight
    }

    public var isMergeAvailable: Bool {
        capabilities.contains {
            $0.isEnabled && $0.outputKind == .document
        }
    }

    public var activeSnapshot: MergeSessionSnapshot? {
        snapshot
    }

    public var canCancelCanonicalJob: Bool {
        canonicalJobIDForCancellation != nil
    }

    public var isTitleOverrideLocked: Bool {
        snapshot?.commitRequest != nil
    }

    private let actorID: String
    private let service: any CoreMergeServing
    private let persistence: any MergeSessionPersisting
    private let sleeper: any MergeSleeping
    private let pollingGate: MergePollingGate?
    private let resumePersistedSession: Bool
    private let idempotencyKey: () -> String
    private let pollDelaysNanoseconds: [UInt64]
    private let pollDelayJitter: (UInt64) -> UInt64
    private let maxPollAttempts: Int

    private var snapshot: MergeSessionSnapshot?
    private var operationTask: Task<Void, Never>?
    private var draftDebounceTask: Task<Void, Never>?
    private var activeDraftSaveTask: Task<MergeArtifact, Error>?
    private var activeDraftSaveToken: UUID?
    private var conflictServerArtifact: MergeArtifact?
    private var draftLifetimeGeneration = 0
    private var pendingSaveWasAttempted = false
    private var isNetworkAvailable = true
    private var hasStarted = false
    private var isLifetimeInvalidated = false

    private static let artifactDraftDebounceNanoseconds: UInt64 = 600_000_000

    public init(
        actorID: String,
        anchor: MergeSource,
        service: any CoreMergeServing,
        persistence: any MergeSessionPersisting,
        sleeper: any MergeSleeping = SystemMergeSleeper(),
        pollingGate: MergePollingGate? = nil,
        resumePersistedSession: Bool = true,
        idempotencyKey: @escaping () -> String = {
            "ios-merge-\(UUID().uuidString)"
        },
        pollDelaysNanoseconds: [UInt64] = [
            500_000_000,
            750_000_000,
            1_000_000_000,
            1_500_000_000,
            2_000_000_000
        ],
        pollDelayJitter: @escaping (UInt64) -> UInt64 = { delay in
            MergePollDelayJitter.applying(
                to: delay,
                factor: Double.random(
                    in: MergePollDelayJitter.productionFactorRange
                )
            )
        },
        // About 356 seconds with the default backoff: enough for the frozen
        // three-provider Merge routes when every provider uses its 90s bound.
        maxPollAttempts: Int = 180
    ) {
        self.actorID = actorID
        self.anchor = anchor
        self.selectedSources = [anchor]
        self.service = service
        self.persistence = persistence
        self.sleeper = sleeper
        self.pollingGate = pollingGate
        self.resumePersistedSession = resumePersistedSession
        self.idempotencyKey = idempotencyKey
        self.pollDelaysNanoseconds = pollDelaysNanoseconds
        self.pollDelayJitter = pollDelayJitter
        self.maxPollAttempts = max(0, maxPollAttempts)
    }

    public func start() {
        guard !isLifetimeInvalidated, !hasStarted else { return }
        hasStarted = true

        if resumePersistedSession,
           let restored = persistence.snapshot(actorID: actorID) {
            restore(restored)
            if let committedAssetID = restored.committedAssetID {
                phase = .completed(assetID: committedAssetID)
                return
            }
            if restored.lastStatus == .failed {
                phase = .failed(.server(code: nil))
                return
            }
            if let jobID = restored.jobID {
                phase = restored.lastStatus == .committing
                    ? .committing
                    : .weaving(restored.lastStatus ?? .created)
                launch { store in
                    await store.reconcile(jobID: jobID)
                }
            } else {
                phase = .creating
                launch { store in
                    await store.submitCreate(restored.createRequest)
                }
            }
            return
        }

        phase = .checkingAvailability
        launch { store in
            await store.checkAvailability()
        }
    }

    public func toggleSelection(_ source: MergeSource) {
        guard
            !isLifetimeInvalidated,
            phase == .selection,
            source.assetID != anchor.assetID
        else {
            return
        }

        if let index = selectedSources.firstIndex(
            where: { $0.assetID == source.assetID }
        ) {
            selectedSources.remove(at: index)
        } else {
            selectedSources.append(source)
        }
        selectedSources = MergeSourceOrdering.ordered(
            anchor: anchor,
            companions: Array(selectedSources.dropFirst())
        )
    }

    public func create() {
        guard canCreate else { return }

        let orderedSources = MergeSourceOrdering.ordered(
            anchor: anchor,
            companions: Array(selectedSources.dropFirst())
        )
        selectedSources = orderedSources
        let request = MergeCreateRequest(
            sources: orderedSources,
            capability: "auto",
            idempotencyKey: idempotencyKey(),
            context: [
                "client": .string("ios"),
                "surface": .string("merge_lifecycle")
            ]
        )
        let value = MergeSessionSnapshot(
            actorID: actorID,
            anchorAssetID: anchor.assetID,
            anchorPreview: anchor.preview,
            createRequest: request,
            selectedCapability: nil,
            jobID: nil,
            lastStatus: nil,
            artifactID: nil,
            commitRequest: nil,
            committedAssetID: nil
        )
        snapshot = value
        persistence.save(value)
        phase = .creating
        launch { store in
            await store.submitCreate(request)
        }
    }

    public func retry() {
        guard !isLifetimeInvalidated, !isOperationInFlight else { return }
        notFoundResource = nil

        guard let snapshot else {
            phase = .checkingAvailability
            launch { store in
                await store.checkAvailability()
            }
            return
        }

        if snapshot.lastStatus == .failed {
            retryGeneration()
            return
        }

        let shouldReplayCommit = snapshot.lastStatus == .artifactReady
            || snapshot.lastStatus == .committedCard
        if let commitRequest = snapshot.commitRequest, shouldReplayCommit {
            phase = .committing
            launch { store in
                await store.submitRecoveredCommit(
                    jobID: snapshot.jobID ?? "",
                    request: commitRequest,
                    reconcileConflict: true
                )
            }
            return
        }

        if let jobID = snapshot.jobID {
            phase = snapshot.lastStatus == .committing
                ? .committing
                : .weaving(snapshot.lastStatus ?? .created)
            launch { store in
                await store.reconcile(jobID: jobID)
            }
        } else {
            phase = .creating
            launch { store in
                await store.submitCreate(snapshot.createRequest)
            }
        }
    }

    public func cancel() {
        guard
            !isLifetimeInvalidated,
            let jobID = canonicalJobIDForCancellation
        else {
            return
        }

        notFoundResource = nil
        phase = .cancelling
        launch { store in
            await store.submitCancel(jobID: jobID)
        }
    }

    public func discardArtifact() {
        guard
            !isLifetimeInvalidated,
            !isOperationInFlight,
            phase == .ready,
            artifact != nil,
            let job,
            job.status.canCancel,
            snapshot != nil
        else {
            return
        }

        artifactActionError = nil
        phase = .cancelling
        launch { store in
            await store.submitArtifactDiscard(jobID: job.jobID)
        }
    }

    public func updateArtifactDraft(
        documentJSON: Data,
        preservationManifest: Data
    ) {
        guard
            !isLifetimeInvalidated,
            phase == .ready,
            var current = artifactDraft,
            current.documentJSON != documentJSON
                || current.preservationManifest != preservationManifest
        else {
            return
        }

        current = enqueueDraftMutation(
            current: current,
            documentJSON: documentJSON,
            tags: current.tags,
            preservationManifest: preservationManifest
        )
        persistArtifactDraft(current, invalidatingCommitRequest: true)
        scheduleDraftSynchronizationIfEligible()
    }

    public func updateArtifactTags(_ tags: [String]) {
        let normalized = CardEditingTag.normalize(tags)
        guard
            !isLifetimeInvalidated,
            phase == .ready,
            var current = artifactDraft,
            current.tags != normalized
        else {
            return
        }

        current = enqueueDraftMutation(
            current: current,
            documentJSON: current.documentJSON,
            tags: normalized,
            preservationManifest: current.preservationManifest
        )
        persistArtifactDraft(current, invalidatingCommitRequest: true)
        scheduleDraftSynchronizationIfEligible()
    }

    public func flushArtifactDraft() async throws -> MergeArtifact {
        draftDebounceTask?.cancel()
        draftDebounceTask = nil
        return try await synchronizeArtifactDraft()
    }

    public func resolveArtifactConflict(
        _ resolution: MergeArtifactConflictResolution
    ) async {
        guard
            !isLifetimeInvalidated,
            case .conflict = artifactDraftSyncState,
            let serverArtifact = conflictServerArtifact,
            let current = artifactDraft
        else {
            return
        }

        switch resolution {
        case .reloadServer:
            adoptServerArtifact(serverArtifact)
        case .keepMine:
            let pending = MergePendingArtifactSave(
                idempotencyKey: idempotencyKey(),
                baseRevision: serverArtifact.latestRevision,
                baseDocumentHash: serverArtifact.latestHash,
                documentJSON: current.documentJSON,
                tags: current.tags
            )
            let rebased = MergeArtifactDraftSnapshot(
                baseRevision: serverArtifact.latestRevision,
                baseDocumentHash: serverArtifact.latestHash,
                documentJSON: current.documentJSON,
                tags: current.tags,
                rate: serverArtifact.presentation.rate,
                preservationManifest: current.preservationManifest,
                pendingSave: pending
            )
            artifact = serverArtifact
            conflictServerArtifact = nil
            pendingSaveWasAttempted = false
            artifactDraftSyncState = isNetworkAvailable
                ? .dirty
                : .unsynced(.offline)
            persistArtifactDraft(rebased, invalidatingCommitRequest: true)
            guard isNetworkAvailable else { return }
            do {
                _ = try await flushArtifactDraft()
            } catch {
                return
            }
        }
    }

    public func setNetworkAvailable(_ isAvailable: Bool) {
        guard !isLifetimeInvalidated else { return }
        isNetworkAvailable = isAvailable

        guard artifactDraft?.pendingSave != nil else { return }
        if isAvailable {
            if activeDraftSaveTask == nil {
                artifactDraftSyncState = .dirty
            }
            scheduleDraftSynchronization(afterDebounce: false)
        } else {
            draftDebounceTask?.cancel()
            draftDebounceTask = nil
            artifactDraftSyncState = .unsynced(.offline)
        }
    }

    public func commit() {
        guard
            !isLifetimeInvalidated,
            !isOperationInFlight,
            phase == .ready,
            let job,
            job.status.canCommit,
            snapshot != nil
        else {
            return
        }

        artifactActionError = nil
        launch { store in
            await store.flushAndSubmitCommit(jobID: job.jobID)
        }
    }

    public func retryGeneration() {
        let canReplaceMissingJob: Bool
        if case .paused(.notFound) = phase,
           notFoundResource == .jobStatus {
            canReplaceMissingJob = true
        } else {
            canReplaceMissingJob = false
        }
        guard
            !isLifetimeInvalidated,
            !isOperationInFlight,
            let current = snapshot,
            current.lastStatus == .failed || canReplaceMissingJob
        else {
            return
        }

        let request = MergeCreateRequest(
            sources: current.createRequest.sources,
            capability: current.createRequest.capability,
            idempotencyKey: idempotencyKey(),
            context: current.createRequest.context
        )
        let replacement = MergeSessionSnapshot(
            actorID: current.actorID,
            anchorAssetID: current.anchorAssetID,
            anchorPreview: current.anchorPreview,
            createRequest: request,
            selectedCapability: nil,
            jobID: nil,
            lastStatus: nil,
            artifactID: nil,
            commitRequest: nil,
            committedAssetID: nil
        )
        snapshot = replacement
        persistence.save(replacement)
        selectedSources = request.sources
        job = nil
        artifact = nil
        artifactDraft = nil
        artifactDraftSyncState = .clean
        conflictServerArtifact = nil
        cancelDraftWork()
        artifactActionError = nil
        notFoundResource = nil
        titleOverride = ""
        phase = .creating
        launch { store in
            await store.submitCreate(request)
        }
    }

    public func suspend(reason: CoreMergeError? = nil) {
        operationTask?.cancel()
        operationTask = nil
        isOperationInFlight = false
        if let reason, snapshot != nil, !isTerminalPresentation {
            phase = .paused(reason)
        }
    }

    public func resume() {
        guard
            !isLifetimeInvalidated,
            snapshot != nil,
            !isOperationInFlight
        else {
            return
        }
        retry()
    }

    @available(*, deprecated, message: "Use suspend(reason:) for presentation suspension.")
    public func stop() {
        suspend(reason: .interrupted)
    }

    public func acknowledgeCompletion() {
        guard
            !isLifetimeInvalidated,
            case .completed = phase,
            snapshot != nil
        else {
            return
        }
        persistence.remove(actorID: actorID)
        snapshot = nil
        artifactDraft = nil
        artifactDraftSyncState = .clean
        cancelDraftWork()
    }

    func invalidateLifetime() {
        guard !isLifetimeInvalidated else { return }
        isLifetimeInvalidated = true
        draftLifetimeGeneration += 1
        cancelDraftWork()
        operationTask?.cancel()
        operationTask = nil
        isOperationInFlight = false
    }

    private var isTerminalPresentation: Bool {
        switch phase {
        case .cancelled, .completed:
            return true
        default:
            return false
        }
    }

    private var canonicalJobIDForCancellation: String? {
        guard
            let snapshot,
            let jobID = snapshot.jobID,
            !jobID.isEmpty,
            notFoundResource != .jobStatus
        else {
            return nil
        }
        if let lastStatus = snapshot.lastStatus, !lastStatus.canCancel {
            return nil
        }

        switch phase {
        case .paused(.offline):
            return nil
        case .weaving, .loadingArtifact, .ready, .paused, .failed:
            return jobID
        default:
            return nil
        }
    }

    private var shouldAcceptAsyncResult: Bool {
        !isLifetimeInvalidated && !Task.isCancelled
    }

    private func restore(_ restored: MergeSessionSnapshot) {
        snapshot = restored
        artifactDraft = restored.artifactDraft
        if restored.artifactDraft?.pendingSave != nil {
            artifactDraftSyncState = isNetworkAvailable
                ? .dirty
                : .unsynced(.offline)
            pendingSaveWasAttempted = true
        } else {
            artifactDraftSyncState = .clean
            pendingSaveWasAttempted = false
        }
        selectedSources = restored.createRequest.sources
        if let restoredAnchor = restored.createRequest.sources.first(
            where: { $0.assetID == restored.anchorAssetID }
        ) {
            anchor = restoredAnchor
        } else {
            anchor = MergeSource(
                assetID: restored.anchorAssetID,
                versionID: nil,
                preview: restored.anchorPreview
            )
        }
    }

    private func checkAvailability() async {
        do {
            let result = try await service.capabilities()
            guard shouldAcceptAsyncResult else { return }
            capabilities = result
            if isMergeAvailable {
                phase = .selection
            } else {
                phase = .failed(.unavailable(code: "merge_disabled"))
            }
        } catch {
            guard shouldAcceptAsyncResult else { return }
            notFoundResource = nil
            phase = .paused(coreError(from: error))
        }
    }

    private func submitCreate(_ request: MergeCreateRequest) async {
        do {
            let created = try await service.createJob(request)
            createResponseCount += 1
            guard shouldAcceptAsyncResult else { return }
            await driveLifecycle(from: created)
        } catch {
            guard shouldAcceptAsyncResult else { return }
            notFoundResource = nil
            phase = .paused(coreError(from: error))
        }
    }

    private func reconcile(jobID: String) async {
        do {
            let current = try await fetchJob(id: jobID)
            guard shouldAcceptAsyncResult else {
                cancelledStatusResponseDiscardCount += 1
                return
            }
            await driveLifecycle(from: current)
        } catch {
            guard shouldAcceptAsyncResult else { return }
            let mapped = coreError(from: error)
            notFoundResource = mapped == .notFound ? .jobStatus : nil
            phase = .paused(mapped)
        }
    }

    private func submitCancel(jobID: String) async {
        do {
            let cancelled = try await service.cancel(jobID: jobID)
            guard shouldAcceptAsyncResult else { return }
            await driveLifecycle(from: cancelled)
        } catch {
            guard shouldAcceptAsyncResult else { return }
            do {
                let current = try await fetchJob(id: jobID)
                guard shouldAcceptAsyncResult else { return }
                await driveLifecycle(from: current)
            } catch {
                guard shouldAcceptAsyncResult else { return }
                let mapped = coreError(from: error)
                notFoundResource = mapped == .notFound ? .jobStatus : nil
                phase = .paused(mapped)
            }
        }
    }

    private func submitArtifactDiscard(jobID: String) async {
        do {
            let cancelled = try await service.cancel(jobID: jobID)
            guard shouldAcceptAsyncResult else { return }
            if cancelled.status == .cancelled {
                finishArtifactDiscard()
            } else {
                await driveLifecycle(from: cancelled)
            }
        } catch {
            guard shouldAcceptAsyncResult else { return }
            let discardError = coreError(from: error)
            do {
                let current = try await fetchJob(id: jobID)
                guard shouldAcceptAsyncResult else { return }
                await driveLifecycle(from: current)
                if phase == .ready {
                    artifactActionError = discardError
                }
            } catch {
                guard shouldAcceptAsyncResult else { return }
                notFoundResource = nil
                artifactActionError = discardError
                phase = .ready
            }
        }
    }

    private func finishArtifactDiscard() {
        draftLifetimeGeneration += 1
        cancelDraftWork()
        persistence.remove(actorID: actorID)
        snapshot = nil
        job = nil
        artifact = nil
        artifactDraft = nil
        artifactDraftSyncState = .clean
        conflictServerArtifact = nil
        artifactActionError = nil
        phase = .cancelled
    }

    private func enqueueDraftMutation(
        current: MergeArtifactDraftSnapshot,
        documentJSON: Data,
        tags: [String],
        preservationManifest: Data
    ) -> MergeArtifactDraftSnapshot {
        let pending: MergePendingArtifactSave
        if let existing = current.pendingSave,
           !pendingSaveWasAttempted,
           activeDraftSaveTask == nil,
           conflictServerArtifact == nil {
            pending = MergePendingArtifactSave(
                idempotencyKey: existing.idempotencyKey,
                baseRevision: existing.baseRevision,
                baseDocumentHash: existing.baseDocumentHash,
                documentJSON: documentJSON,
                tags: tags
            )
        } else if let existing = current.pendingSave {
            pending = existing
        } else {
            pendingSaveWasAttempted = false
            pending = MergePendingArtifactSave(
                idempotencyKey: idempotencyKey(),
                baseRevision: current.baseRevision,
                baseDocumentHash: current.baseDocumentHash,
                documentJSON: documentJSON,
                tags: tags
            )
        }

        switch artifactDraftSyncState {
        case .conflict:
            break
        case .unsynced where pendingSaveWasAttempted:
            break
        default:
            if !isNetworkAvailable {
                artifactDraftSyncState = .unsynced(.offline)
            } else if activeDraftSaveTask != nil {
                artifactDraftSyncState = .saving
            } else {
                artifactDraftSyncState = .dirty
            }
        }

        return MergeArtifactDraftSnapshot(
            baseRevision: current.baseRevision,
            baseDocumentHash: current.baseDocumentHash,
            documentJSON: documentJSON,
            tags: tags,
            rate: current.rate,
            preservationManifest: preservationManifest,
            pendingSave: pending
        )
    }

    private func persistArtifactDraft(
        _ draft: MergeArtifactDraftSnapshot,
        invalidatingCommitRequest: Bool = false
    ) {
        artifactDraft = draft
        guard var value = snapshot,
              value.jobID != nil else {
            return
        }
        value.artifactDraft = draft
        if invalidatingCommitRequest {
            value.commitRequest = nil
        }
        snapshot = value
        persistence.save(value)
    }

    private func scheduleDraftSynchronizationIfEligible() {
        guard case .dirty = artifactDraftSyncState else { return }
        scheduleDraftSynchronization(afterDebounce: true)
    }

    private func scheduleDraftSynchronization(afterDebounce: Bool) {
        guard
            !isLifetimeInvalidated,
            isNetworkAvailable,
            artifactDraft?.pendingSave != nil
        else {
            return
        }

        draftDebounceTask?.cancel()
        let generation = draftLifetimeGeneration
        draftDebounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                if afterDebounce {
                    try await self.sleeper.sleep(
                        nanoseconds: Self.artifactDraftDebounceNanoseconds
                    )
                }
                try Task.checkCancellation()
                guard generation == self.draftLifetimeGeneration else { return }
                _ = try await self.synchronizeArtifactDraft()
            } catch {
                return
            }
        }
    }

    private func synchronizeArtifactDraft() async throws -> MergeArtifact {
        while true {
            guard !isLifetimeInvalidated,
                  let jobID = snapshot?.jobID,
                  !jobID.isEmpty,
                  let currentArtifact = artifact,
                  let draft = artifactDraft else {
                throw CoreMergeError.interrupted
            }
            if case .conflict = artifactDraftSyncState {
                throw CoreMergeError.conflict(code: "artifact_draft_conflict")
            }
            guard let pending = draft.pendingSave else {
                return currentArtifact
            }
            guard isNetworkAvailable else {
                artifactDraftSyncState = .unsynced(.offline)
                throw CoreMergeError.offline
            }

            let saved = try await executeDraftSave(
                jobID: jobID,
                pending: pending
            )
            guard artifactDraft?.pendingSave != nil else {
                return saved
            }
        }
    }

    private func executeDraftSave(
        jobID: String,
        pending: MergePendingArtifactSave
    ) async throws -> MergeArtifact {
        if let activeDraftSaveTask,
           let activeDraftSaveToken {
            defer { clearActiveDraftSave(ifMatching: activeDraftSaveToken) }
            return try await activeDraftSaveTask.value
        }

        pendingSaveWasAttempted = true
        artifactDraftSyncState = .saving
        let saveToken = UUID()
        let generation = draftLifetimeGeneration
        activeDraftSaveToken = saveToken
        let task = Task { @MainActor [weak self] () throws -> MergeArtifact in
            guard let self else { throw CoreMergeError.interrupted }
            return try await self.performDraftSave(
                jobID: jobID,
                pending: pending,
                saveToken: saveToken,
                generation: generation
            )
        }
        activeDraftSaveTask = task
        defer { clearActiveDraftSave(ifMatching: saveToken) }
        return try await task.value
    }

    private func clearActiveDraftSave(ifMatching saveToken: UUID) {
        guard activeDraftSaveToken == saveToken else { return }
        activeDraftSaveTask = nil
        activeDraftSaveToken = nil
    }

    private func performDraftSave(
        jobID: String,
        pending: MergePendingArtifactSave,
        saveToken: UUID,
        generation: Int
    ) async throws -> MergeArtifact {
        let request = MergeArtifactSaveRequest(
            baseRevision: pending.baseRevision,
            baseHash: pending.baseDocumentHash,
            idempotencyKey: pending.idempotencyKey,
            documentJSON: pending.documentJSON,
            tags: pending.tags
        )

        do {
            let result = try await service.saveArtifact(
                jobID: jobID,
                request: request
            )
            guard shouldAcceptDraftResult(
                jobID: jobID,
                pending: pending,
                saveToken: saveToken,
                generation: generation
            ) else {
                throw CoreMergeError.interrupted
            }
            return try applyDraftSaveResult(
                result,
                jobID: jobID,
                pending: pending
            )
        } catch {
            let mapped = coreError(from: error)
            guard shouldAcceptDraftResult(
                jobID: jobID,
                pending: pending,
                saveToken: saveToken,
                generation: generation
            ) else {
                throw CoreMergeError.interrupted
            }
            if case .conflict = mapped {
                return try await reconcileArtifactSaveConflict(
                    jobID: jobID,
                    pending: pending,
                    saveToken: saveToken,
                    generation: generation
                )
            }
            artifactDraftSyncState = .unsynced(draftFailure(from: mapped))
            throw mapped
        }
    }

    private func applyDraftSaveResult(
        _ result: MergeArtifactSaveResult,
        jobID: String,
        pending: MergePendingArtifactSave
    ) throws -> MergeArtifact {
        guard let previousArtifact = artifact,
              previousArtifact.jobID == jobID,
              result.artifactID == previousArtifact.artifactID,
              result.revision > pending.baseRevision,
              !result.documentHash.isEmpty,
              !result.presentationHash.isEmpty,
              let current = artifactDraft,
              current.pendingSave == pending else {
            throw CoreMergeError.decoding
        }

        let acknowledged = MergeArtifact(
            artifactID: result.artifactID,
            jobID: jobID,
            capabilityID: previousArtifact.capabilityID,
            outputKind: previousArtifact.outputKind,
            document: previousArtifact.document,
            fragments: previousArtifact.fragments,
            metadata: previousArtifact.metadata,
            latestRevision: result.revision,
            latestHash: result.documentHash,
            documentJSON: pending.documentJSON,
            presentationHash: result.presentationHash,
            presentation: result.presentation
        )
        artifact = acknowledged

        let hasNewerMutation = current.documentJSON != pending.documentJSON
            || current.tags != pending.tags
        let nextTags = hasNewerMutation
            ? current.tags
            : CardEditingTag.normalize(result.presentation.tags)
        let nextPending: MergePendingArtifactSave?
        if hasNewerMutation {
            nextPending = MergePendingArtifactSave(
                idempotencyKey: idempotencyKey(),
                baseRevision: result.revision,
                baseDocumentHash: result.documentHash,
                documentJSON: current.documentJSON,
                tags: current.tags
            )
            pendingSaveWasAttempted = false
        } else {
            nextPending = nil
            pendingSaveWasAttempted = false
        }
        let updated = MergeArtifactDraftSnapshot(
            baseRevision: result.revision,
            baseDocumentHash: result.documentHash,
            documentJSON: current.documentJSON,
            tags: nextTags,
            rate: result.presentation.rate,
            preservationManifest: current.preservationManifest,
            pendingSave: nextPending
        )
        conflictServerArtifact = nil
        artifactDraftSyncState = nextPending == nil ? .clean : .dirty
        persistArtifactDraft(updated)
        return acknowledged
    }

    private func reconcileArtifactSaveConflict(
        jobID: String,
        pending: MergePendingArtifactSave,
        saveToken: UUID,
        generation: Int
    ) async throws -> MergeArtifact {
        let hadLocalChanges: Bool
        if let draft = artifactDraft, let acknowledged = artifact {
            hadLocalChanges = draft.documentJSON != acknowledged.documentJSON
                || draft.tags != CardEditingTag.normalize(acknowledged.presentation.tags)
        } else {
            hadLocalChanges = true
        }

        do {
            let latest = try await service.artifact(jobID: jobID)
            guard latest.jobID == jobID,
                  shouldAcceptDraftResult(
                    jobID: jobID,
                    pending: pending,
                    saveToken: saveToken,
                    generation: generation
                  ) else {
                throw CoreMergeError.interrupted
            }
            if hadLocalChanges {
                conflictServerArtifact = latest
                artifactDraftSyncState = .conflict(
                    MergeArtifactConflict(
                        serverRevision: latest.latestRevision,
                        serverDocumentHash: latest.latestHash
                    )
                )
                throw CoreMergeError.conflict(code: "artifact_draft_conflict")
            }
            adoptServerArtifact(latest)
            return latest
        } catch {
            let mapped = coreError(from: error)
            if case .conflict = artifactDraftSyncState {
                throw mapped
            }
            artifactDraftSyncState = .unsynced(draftFailure(from: mapped))
            throw mapped
        }
    }

    private func adoptServerArtifact(_ serverArtifact: MergeArtifact) {
        artifact = serverArtifact
        let clean = makeCleanDraft(from: serverArtifact)
        conflictServerArtifact = nil
        pendingSaveWasAttempted = false
        artifactDraftSyncState = .clean
        persistArtifactDraft(clean, invalidatingCommitRequest: true)
    }

    private func makeCleanDraft(
        from artifact: MergeArtifact
    ) -> MergeArtifactDraftSnapshot {
        let preservationManifest = (try? MergeArtifactEditorCodec.decode(
            cardDocumentJSON: artifact.documentJSON
        ).preservationManifest) ?? Data()
        return MergeArtifactDraftSnapshot(
            baseRevision: artifact.latestRevision,
            baseDocumentHash: artifact.latestHash,
            documentJSON: artifact.documentJSON,
            tags: CardEditingTag.normalize(artifact.presentation.tags),
            rate: artifact.presentation.rate,
            preservationManifest: preservationManifest,
            pendingSave: nil
        )
    }

    private func shouldAcceptDraftResult(
        jobID: String,
        pending: MergePendingArtifactSave,
        saveToken: UUID,
        generation: Int
    ) -> Bool {
        !isLifetimeInvalidated
            && !Task.isCancelled
            && generation == draftLifetimeGeneration
            && activeDraftSaveToken == saveToken
            && snapshot?.jobID == jobID
            && artifactDraft?.pendingSave == pending
    }

    private func draftFailure(from error: CoreMergeError) -> MergeDraftFailure {
        switch error {
        case .offline:
            return .offline
        case .timeout:
            return .timeout
        case .unavailable(let code):
            return .unavailable(code: code)
        case .validation(let code):
            return .validation(code: code)
        case .server(let code):
            return .server(code: code)
        case .unauthorized:
            return .unknown(code: "unauthorized")
        case .forbidden:
            return .unknown(code: "forbidden")
        case .notFound:
            return .unknown(code: "not_found")
        case .conflict(let code):
            return .unknown(code: code)
        case .interrupted:
            return .unknown(code: "interrupted")
        case .artifactNotReady:
            return .unknown(code: "artifact_not_ready")
        case .cancelled:
            return .unknown(code: "cancelled")
        case .decoding:
            return .validation(code: "invalid_artifact_save_response")
        case .unknown(let code):
            return .unknown(code: code)
        }
    }

    private func cancelDraftWork() {
        draftDebounceTask?.cancel()
        draftDebounceTask = nil
        activeDraftSaveTask?.cancel()
        activeDraftSaveTask = nil
        activeDraftSaveToken = nil
        pendingSaveWasAttempted = false
    }

    private func flushAndSubmitCommit(jobID: String) async {
        do {
            let savedArtifact: MergeArtifact
            while true {
                let candidate = try await flushArtifactDraft()
                guard shouldAcceptAsyncResult,
                      snapshot?.jobID == jobID else {
                    return
                }
                guard artifactDraft?.pendingSave == nil,
                      artifactDraftSyncState == .clean,
                      artifact?.latestRevision == candidate.latestRevision,
                      artifact?.latestHash == candidate.latestHash else {
                    continue
                }
                savedArtifact = candidate
                break
            }
            guard var value = snapshot,
                  value.jobID == jobID else { return }

            let request: MergeCommitRequest
            if let existing = value.commitRequest {
                switch (existing.revision, existing.artifactHash) {
                case (.some, .some):
                    request = existing
                case (nil, nil):
                    request = MergeCommitRequest(
                        idempotencyKey: existing.idempotencyKey,
                        revision: savedArtifact.latestRevision,
                        artifactHash: savedArtifact.latestHash,
                        target: existing.target
                    )
                default:
                    throw CoreMergeError.decoding
                }
            } else {
                request = MergeCommitRequest(
                    idempotencyKey: idempotencyKey(),
                    revision: savedArtifact.latestRevision,
                    artifactHash: savedArtifact.latestHash,
                    target: .newCard(spaceID: nil, titleOverride: nil)
                )
            }
            value.commitRequest = request
            snapshot = value
            persistence.save(value)
            phase = .committing
            await submitCommit(
                jobID: jobID,
                request: request,
                reconcileConflict: true
            )
        } catch {
            guard shouldAcceptAsyncResult else { return }
            artifactActionError = coreError(from: error)
            phase = .ready
        }
    }

    private func submitRecoveredCommit(
        jobID: String,
        request: MergeCommitRequest,
        reconcileConflict: Bool
    ) async {
        do {
            switch (request.revision, request.artifactHash) {
            case (.some, .some):
                await submitCommit(
                    jobID: jobID,
                    request: request,
                    reconcileConflict: reconcileConflict
                )
                return
            case (nil, nil):
                break
            default:
                throw CoreMergeError.decoding
            }

            let selectedArtifact: MergeArtifact
            if let artifact, artifact.jobID == jobID {
                selectedArtifact = artifact
            } else {
                selectedArtifact = try await service.artifact(jobID: jobID)
            }
            guard shouldAcceptAsyncResult,
                  selectedArtifact.jobID == jobID,
                  !selectedArtifact.latestHash.isEmpty,
                  var value = snapshot,
                  value.jobID == jobID else {
                throw CoreMergeError.decoding
            }
            let migrated = MergeCommitRequest(
                idempotencyKey: request.idempotencyKey,
                revision: selectedArtifact.latestRevision,
                artifactHash: selectedArtifact.latestHash,
                target: request.target
            )
            artifact = selectedArtifact
            value.commitRequest = migrated
            snapshot = value
            persistence.save(value)
            await submitCommit(
                jobID: jobID,
                request: migrated,
                reconcileConflict: reconcileConflict
            )
        } catch {
            guard shouldAcceptAsyncResult else { return }
            let mapped = coreError(from: error)
            if artifact != nil {
                artifactActionError = mapped
                phase = .ready
            } else {
                notFoundResource = mapped == .notFound ? .artifact : nil
                phase = .paused(mapped)
            }
        }
    }

    private func submitCommit(
        jobID: String,
        request: MergeCommitRequest,
        reconcileConflict: Bool
    ) async {
        guard !jobID.isEmpty else {
            phase = .failed(.decoding)
            return
        }

        do {
            let result = try await service.commit(
                jobID: jobID,
                request: request
            )
            guard shouldAcceptAsyncResult else { return }
            recordCommitResult(result)
        } catch {
            guard shouldAcceptAsyncResult else { return }
            let mapped = coreError(from: error)
            if case .conflict = mapped, reconcileConflict {
                await reconcile(jobID: jobID)
            } else {
                if artifact != nil {
                    artifactActionError = mapped
                    phase = .ready
                } else {
                    notFoundResource = nil
                    phase = .paused(mapped)
                }
            }
        }
    }

    private func driveLifecycle(from initialJob: MergeJob) async {
        var current = initialJob
        var pollCount = 0

        while shouldAcceptAsyncResult {
            record(current)

            switch current.status {
            case .created, .snapshotReady, .planned, .generating:
                phase = .weaving(current.status)
            case .committing:
                phase = .committing
            case .artifactReady:
                await loadArtifact(jobID: current.jobID)
                return
            case .committedCard:
                if let committedAssetID = snapshot?.committedAssetID {
                    phase = .completed(assetID: committedAssetID)
                } else if let commitRequest = snapshot?.commitRequest {
                    await submitRecoveredCommit(
                        jobID: current.jobID,
                        request: commitRequest,
                        reconcileConflict: false
                    )
                } else {
                    notFoundResource = nil
                    phase = .paused(.decoding)
                }
                return
            case .committedBlock:
                phase = .completed(assetID: nil)
                return
            case .failed:
                notFoundResource = nil
                phase = .failed(.server(code: current.errorCode))
                return
            case .cancelled:
                persistence.remove(actorID: actorID)
                snapshot = nil
                phase = .cancelled
                return
            case .unknown(let value):
                notFoundResource = nil
                phase = .paused(.unknown(code: value))
                return
            }

            guard pollCount < maxPollAttempts else {
                notFoundResource = nil
                phase = .paused(.timeout)
                return
            }

            do {
                try await sleeper.sleep(
                    nanoseconds: pollDelay(at: pollCount)
                )
                try Task.checkCancellation()
                current = try await fetchJob(id: current.jobID)
                pollCount += 1
            } catch is CancellationError {
                return
            } catch {
                guard shouldAcceptAsyncResult else { return }
                let mapped = coreError(from: error)
                notFoundResource = mapped == .notFound ? .jobStatus : nil
                phase = .paused(mapped)
                return
            }
        }
    }

    private func loadArtifact(jobID: String) async {
        phase = .loadingArtifact
        do {
            let loaded = try await service.artifact(jobID: jobID)
            guard shouldAcceptAsyncResult else { return }
            guard loaded.jobID == jobID else {
                notFoundResource = nil
                phase = .failed(.decoding)
                return
            }
            artifact = loaded
            artifactActionError = nil
            // Merge vNext documents are titleless and the wire commit seals only
            // the artifact revision/hash. Do not revive legacy title overrides.
            titleOverride = ""
            if var value = snapshot {
                value.artifactID = loaded.artifactID
                let restoredDraft = value.artifactDraft
                if let restoredDraft,
                   restoredDraft.pendingSave != nil {
                    artifactDraft = restoredDraft
                    pendingSaveWasAttempted = true
                    artifactDraftSyncState = isNetworkAvailable
                        ? .dirty
                        : .unsynced(.offline)
                } else if let restoredDraft,
                          restoredDraft.baseRevision == loaded.latestRevision,
                          restoredDraft.baseDocumentHash == loaded.latestHash {
                    artifactDraft = restoredDraft
                    pendingSaveWasAttempted = false
                    artifactDraftSyncState = .clean
                } else {
                    artifactDraft = makeCleanDraft(from: loaded)
                    pendingSaveWasAttempted = false
                    artifactDraftSyncState = .clean
                }
                value.artifactDraft = artifactDraft
                snapshot = value
                persistence.save(value)
            }
            phase = .ready
            if artifactDraft?.pendingSave != nil, isNetworkAvailable {
                scheduleDraftSynchronization(afterDebounce: false)
            }
        } catch {
            guard shouldAcceptAsyncResult else { return }
            let mapped = coreError(from: error)
            notFoundResource = mapped == .notFound ? .artifact : nil
            phase = mapped == .decoding
                ? .failed(mapped)
                : .paused(mapped)
        }
    }

    private func recordCommitResult(_ result: MergeCommitResult) {
        guard
            result.targetType == "new_card",
            let assetID = result.assetID,
            !assetID.isEmpty,
            var value = snapshot
        else {
            let error = CoreMergeError.server(
                code: result.errorCode ?? "commit_result_incomplete"
            )
            if artifact != nil {
                artifactActionError = error
                phase = .ready
            } else {
                notFoundResource = nil
                phase = .paused(error)
            }
            return
        }

        value.committedAssetID = assetID
        value.lastStatus = .committedCard
        snapshot = value
        persistence.save(value)
        phase = .completed(assetID: assetID)
    }

    private func record(_ current: MergeJob) {
        notFoundResource = nil
        job = current
        guard var value = snapshot else { return }
        value.jobID = current.jobID
        value.lastStatus = current.status
        value.selectedCapability = current.selectedCapability
        value.artifactID = current.artifactID ?? value.artifactID
        snapshot = value
        persistence.save(value)
    }

    private func pollDelay(at index: Int) -> UInt64 {
        guard !pollDelaysNanoseconds.isEmpty else { return 0 }
        let delay = pollDelaysNanoseconds[
            min(index, pollDelaysNanoseconds.count - 1)
        ]
        return pollDelayJitter(delay)
    }

    private func fetchJob(id: String) async throws -> MergeJob {
        let result: MergeJob
        guard let pollingGate else {
            result = try await service.job(id: id)
            statusResponseCount += 1
            return result
        }
        result = try await pollingGate.perform { [service] in
            try await service.job(id: id)
        }
        statusResponseCount += 1
        return result
    }

    private func coreError(from error: Error) -> CoreMergeError {
        if let error = error as? CoreMergeError {
            return error
        }
        if error is CancellationError {
            return .interrupted
        }
        return .unknown(code: nil)
    }

    private func launch(
        _ operation: @escaping @MainActor (MergeSessionStore) async -> Void
    ) {
        guard !isLifetimeInvalidated else { return }
        operationTask?.cancel()
        isOperationInFlight = true
        operationTask = Task { [weak self] in
            guard let self, !self.isLifetimeInvalidated else { return }
            await operation(self)
            if self.shouldAcceptAsyncResult {
                self.isOperationInFlight = false
            }
        }
    }
}
