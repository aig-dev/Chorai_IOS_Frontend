import Combine
import Foundation

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

@MainActor
public final class MergeSessionStore: ObservableObject {
    @Published public private(set) var anchor: MergeSource
    @Published public private(set) var selectedSources: [MergeSource]
    @Published public private(set) var capabilities: [MergeCapability] = []
    @Published public private(set) var job: MergeJob?
    @Published public private(set) var artifact: MergeArtifact?
    @Published public private(set) var artifactActionError: CoreMergeError?
    @Published public private(set) var phase: MergeSessionPhase = .idle
    @Published public var titleOverride = ""
    @Published public private(set) var isOperationInFlight = false

    public var canCreate: Bool {
        phase == .selection
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

    public var isTitleOverrideLocked: Bool {
        snapshot?.commitRequest != nil
    }

    private let actorID: String
    private let service: any CoreMergeServing
    private let persistence: any MergeSessionPersisting
    private let sleeper: any MergeSleeping
    private let resumePersistedSession: Bool
    private let idempotencyKey: () -> String
    private let pollDelaysNanoseconds: [UInt64]
    private let maxPollAttempts: Int

    private var snapshot: MergeSessionSnapshot?
    private var operationTask: Task<Void, Never>?
    private var hasStarted = false

    public init(
        actorID: String,
        anchor: MergeSource,
        service: any CoreMergeServing,
        persistence: any MergeSessionPersisting,
        sleeper: any MergeSleeping = SystemMergeSleeper(),
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
        self.resumePersistedSession = resumePersistedSession
        self.idempotencyKey = idempotencyKey
        self.pollDelaysNanoseconds = pollDelaysNanoseconds
        self.maxPollAttempts = max(0, maxPollAttempts)
    }

    public func start() {
        guard !hasStarted else { return }
        hasStarted = true

        if resumePersistedSession,
           let restored = persistence.snapshot(actorID: actorID) {
            restore(restored)
            if let committedAssetID = restored.committedAssetID {
                phase = .completed(assetID: committedAssetID)
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
        guard phase == .selection, source.assetID != anchor.assetID else {
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
        guard !isOperationInFlight else { return }

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
                await store.submitCommit(
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
            !isOperationInFlight,
            let job,
            job.status.canCancel,
            snapshot != nil
        else {
            return
        }

        phase = .cancelling
        launch { store in
            await store.submitCancel(jobID: job.jobID)
        }
    }

    public func discardArtifact() {
        guard
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

    public func commit() {
        guard
            !isOperationInFlight,
            phase == .ready,
            let job,
            job.status.canCommit,
            var value = snapshot
        else {
            return
        }

        artifactActionError = nil

        let request: MergeCommitRequest
        if let existing = value.commitRequest {
            request = existing
        } else {
            request = MergeCommitRequest(
                idempotencyKey: idempotencyKey(),
                target: .newCard(
                    spaceID: nil,
                    titleOverride: nil
                )
            )
            value.commitRequest = request
            snapshot = value
            persistence.save(value)
        }

        phase = .committing
        launch { store in
            await store.submitCommit(
                jobID: job.jobID,
                request: request,
                reconcileConflict: true
            )
        }
    }

    public func retryGeneration() {
        guard
            !isOperationInFlight,
            let current = snapshot,
            current.lastStatus == .failed
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
        artifactActionError = nil
        titleOverride = ""
        phase = .creating
        launch { store in
            await store.submitCreate(request)
        }
    }

    public func stop() {
        operationTask?.cancel()
        operationTask = nil
        isOperationInFlight = false
        if snapshot != nil, !isTerminalPresentation {
            phase = .paused(.interrupted)
        }
    }

    public func acknowledgeCompletion() {
        guard case .completed = phase, snapshot != nil else { return }
        persistence.remove(actorID: actorID)
        snapshot = nil
    }

    private var isTerminalPresentation: Bool {
        switch phase {
        case .cancelled, .completed:
            return true
        default:
            return false
        }
    }

    private func restore(_ restored: MergeSessionSnapshot) {
        snapshot = restored
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
            guard !Task.isCancelled else { return }
            capabilities = result
            if isMergeAvailable {
                phase = .selection
            } else {
                phase = .failed(.unavailable(code: "merge_disabled"))
            }
        } catch {
            guard !Task.isCancelled else { return }
            phase = .paused(coreError(from: error))
        }
    }

    private func submitCreate(_ request: MergeCreateRequest) async {
        do {
            let created = try await service.createJob(request)
            guard !Task.isCancelled else { return }
            await driveLifecycle(from: created)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .paused(coreError(from: error))
        }
    }

    private func reconcile(jobID: String) async {
        do {
            let current = try await service.job(id: jobID)
            guard !Task.isCancelled else { return }
            await driveLifecycle(from: current)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .paused(coreError(from: error))
        }
    }

    private func submitCancel(jobID: String) async {
        do {
            let cancelled = try await service.cancel(jobID: jobID)
            guard !Task.isCancelled else { return }
            await driveLifecycle(from: cancelled)
        } catch {
            guard !Task.isCancelled else { return }
            do {
                let current = try await service.job(id: jobID)
                guard !Task.isCancelled else { return }
                await driveLifecycle(from: current)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .paused(coreError(from: error))
            }
        }
    }

    private func submitArtifactDiscard(jobID: String) async {
        do {
            let cancelled = try await service.cancel(jobID: jobID)
            guard !Task.isCancelled else { return }
            if cancelled.status == .cancelled {
                resetToSelectionAfterDiscard()
            } else {
                await driveLifecycle(from: cancelled)
            }
        } catch {
            guard !Task.isCancelled else { return }
            let discardError = coreError(from: error)
            do {
                let current = try await service.job(id: jobID)
                guard !Task.isCancelled else { return }
                await driveLifecycle(from: current)
                if phase == .ready {
                    artifactActionError = discardError
                }
            } catch {
                guard !Task.isCancelled else { return }
                artifactActionError = discardError
                phase = .ready
            }
        }
    }

    private func resetToSelectionAfterDiscard() {
        persistence.remove(actorID: actorID)
        snapshot = nil
        job = nil
        artifact = nil
        artifactActionError = nil
        selectedSources = [anchor]
        titleOverride = ""
        phase = .selection
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
            guard !Task.isCancelled else { return }
            recordCommitResult(result)
        } catch {
            guard !Task.isCancelled else { return }
            let mapped = coreError(from: error)
            if case .conflict = mapped, reconcileConflict {
                await reconcile(jobID: jobID)
            } else {
                if artifact != nil {
                    artifactActionError = mapped
                    phase = .ready
                } else {
                    phase = .paused(mapped)
                }
            }
        }
    }

    private func driveLifecycle(from initialJob: MergeJob) async {
        var current = initialJob
        var pollCount = 0

        while !Task.isCancelled {
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
                    await submitCommit(
                        jobID: current.jobID,
                        request: commitRequest,
                        reconcileConflict: false
                    )
                } else {
                    phase = .paused(.decoding)
                }
                return
            case .committedBlock:
                phase = .completed(assetID: nil)
                return
            case .failed:
                phase = .failed(.server(code: current.errorCode))
                return
            case .cancelled:
                persistence.remove(actorID: actorID)
                snapshot = nil
                phase = .cancelled
                return
            case .unknown(let value):
                phase = .paused(.unknown(code: value))
                return
            }

            guard pollCount < maxPollAttempts else {
                phase = .paused(.timeout)
                return
            }

            do {
                try await sleeper.sleep(
                    nanoseconds: pollDelay(at: pollCount)
                )
                try Task.checkCancellation()
                current = try await service.job(id: current.jobID)
                pollCount += 1
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                phase = .paused(coreError(from: error))
                return
            }
        }
    }

    private func loadArtifact(jobID: String) async {
        phase = .loadingArtifact
        do {
            let loaded = try await service.artifact(jobID: jobID)
            guard !Task.isCancelled else { return }
            guard loaded.jobID == jobID else {
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
                snapshot = value
                persistence.save(value)
            }
            phase = .ready
        } catch {
            guard !Task.isCancelled else { return }
            let mapped = coreError(from: error)
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
        return pollDelaysNanoseconds[min(index, pollDelaysNanoseconds.count - 1)]
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
        operationTask?.cancel()
        isOperationInFlight = true
        operationTask = Task { [weak self] in
            guard let self else { return }
            await operation(self)
            if !Task.isCancelled {
                self.isOperationInFlight = false
            }
        }
    }
}
