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
    private var hasStarted = false
    private var isLifetimeInvalidated = false

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
            !isLifetimeInvalidated,
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

    public func commit() {
        guard
            !isLifetimeInvalidated,
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
    }

    func invalidateLifetime() {
        guard !isLifetimeInvalidated else { return }
        isLifetimeInvalidated = true
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

    private var shouldAcceptAsyncResult: Bool {
        !isLifetimeInvalidated && !Task.isCancelled
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
        persistence.remove(actorID: actorID)
        snapshot = nil
        job = nil
        artifact = nil
        artifactActionError = nil
        phase = .cancelled
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
                    await submitCommit(
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
                snapshot = value
                persistence.save(value)
            }
            phase = .ready
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
