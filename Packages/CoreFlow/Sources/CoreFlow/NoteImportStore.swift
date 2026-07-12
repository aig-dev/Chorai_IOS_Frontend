import Combine
import Foundation

@MainActor
public final class NoteImportStore: ObservableObject {
    public static let pollIntervalNanoseconds: UInt64 = 3_000_000_000
    public static let reconciliationLimit = 50

    @Published public private(set) var actorID: String?
    @Published public private(set) var selectedFiles: [NoteImportFile] = []
    @Published public private(set) var clientRequestID: String?
    @Published public private(set) var receipt: NoteImportReceipt?
    @Published public private(set) var detail: NoteImportJobDetail?
    @Published public private(set) var phase: NoteImportPhase = .idle

    private let service: any CoreNoteImportServing
    private let persistence: any NoteImportRequestIDPersisting
    private let sleeper: any NoteImportSleeping
    private let requestID: @Sendable () -> String

    private var generation = UUID()
    private var operationTask: Task<Void, Never>?
    private var operationID: UUID?

    public init(
        service: any CoreNoteImportServing,
        persistence: any NoteImportRequestIDPersisting,
        sleeper: any NoteImportSleeping = SystemNoteImportSleeper(),
        requestID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.service = service
        self.persistence = persistence
        self.sleeper = sleeper
        self.requestID = requestID
    }

    deinit {
        operationTask?.cancel()
    }

    public func load(actorID rawActorID: String) async {
        invalidateOperation()
        selectedFiles = []
        clientRequestID = nil
        receipt = nil
        detail = nil

        let normalized = rawActorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            actorID = nil
            phase = .failed(.contract(code: "invalid_actor"))
            return
        }

        actorID = normalized
        phase = .loading
        let scope = generation
        let persistedRequestID = persistence.load(actorID: normalized)
        clientRequestID = persistedRequestID

        do {
            let summaries = try await service.jobs(limit: Self.reconciliationLimit)
            guard isCurrent(actorID: normalized, generation: scope) else { return }

            if let persistedRequestID {
                guard let exact = summaries.first(where: {
                    $0.clientRequestID == persistedRequestID
                }) else {
                    phase = .ambiguous
                    return
                }
                await loadAndDrive(
                    jobID: exact.jobID,
                    actorID: normalized,
                    generation: scope
                )
                return
            }

            if let active = summaries
                .filter({ !$0.isSettled && $0.clientRequestID != nil })
                .max(by: { $0.createdAt < $1.createdAt }),
               let restoredRequestID = active.clientRequestID {
                clientRequestID = restoredRequestID
                persistence.save(restoredRequestID, actorID: normalized)
                await loadAndDrive(
                    jobID: active.jobID,
                    actorID: normalized,
                    generation: scope
                )
            } else {
                phase = .ready
            }
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(actorID: normalized, generation: scope) else { return }
            phase = .failed(Self.map(error))
        }
    }

    public func select(_ files: [NoteImportFile]) {
        guard operationTask == nil else { return }
        if phase == .terminal {
            clientRequestID = nil
            receipt = nil
            detail = nil
            phase = .ready
        }
        selectedFiles = files
    }

    public func start() {
        guard operationTask == nil, let actorID else { return }
        guard let selectionError = Self.validate(selectedFiles) else {
            beginSubmission(actorID: actorID)
            return
        }
        phase = .invalidSelection(selectionError)
    }

    public func retry() {
        guard operationTask == nil,
              let actorID,
              let stableRequestID = clientRequestID,
              phase == .ambiguous || Self.isFailure(phase),
              Self.validate(selectedFiles) == nil else {
            return
        }

        phase = .reconciling
        let scope = generation
        let operationID = UUID()
        self.operationID = operationID
        operationTask = Task { [weak self] in
            guard let self else { return }
            await self.reconcileBeforeRetry(
                actorID: actorID,
                requestID: stableRequestID,
                generation: scope
            )
            self.finishOperation(generation: scope, operationID: operationID)
        }
    }

    public func cancel() {
        guard let actorID,
              let jobID = detail?.jobID ?? receipt?.jobID,
              phase != .terminal else {
            return
        }

        operationTask?.cancel()
        generation = UUID()
        phase = .cancelling
        let scope = generation
        let operationID = UUID()
        self.operationID = operationID
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.cancel(id: jobID)
            } catch is CancellationError {
                return
            } catch {
                // Cancellation may have reached the server even when its response did not.
                // The actor-scoped detail route is the canonical outcome.
            }
            guard self.isCurrent(actorID: actorID, generation: scope) else { return }
            do {
                let canonical = try await self.service.job(id: jobID)
                guard self.isCurrent(actorID: actorID, generation: scope) else { return }
                await self.drive(
                    canonical,
                    actorID: actorID,
                    generation: scope
                )
            } catch is CancellationError {
                return
            } catch {
                guard self.isCurrent(actorID: actorID, generation: scope) else { return }
                self.phase = .failed(Self.map(error))
            }
            self.finishOperation(generation: scope, operationID: operationID)
        }
    }

    public func stop() {
        invalidateOperation()
        if phase == .submitting || phase == .reconciling || phase == .polling || phase == .cancelling {
            phase = clientRequestID == nil ? .ready : .ambiguous
        }
    }

    private func beginSubmission(actorID: String) {
        let stableRequestID: String
        if let existing = clientRequestID {
            stableRequestID = existing
        } else {
            stableRequestID = requestID()
            clientRequestID = stableRequestID
            persistence.save(stableRequestID, actorID: actorID)
        }

        phase = .submitting
        let files = selectedFiles
        let scope = generation
        let operationID = UUID()
        self.operationID = operationID
        let service = self.service
        operationTask = Task { [weak self] in
            do {
                let created = try await service.enqueue(
                    files: files,
                    clientRequestID: stableRequestID
                )
                guard let self,
                      self.isCurrent(actorID: actorID, generation: scope) else {
                    return
                }
                await self.acceptCreatedReceipt(
                    created,
                    actorID: actorID,
                    requestID: stableRequestID,
                    generation: scope
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.isCurrent(actorID: actorID, generation: scope) else {
                    return
                }
                await self.acceptSubmissionFailure(
                    error,
                    actorID: actorID,
                    requestID: stableRequestID,
                    generation: scope
                )
            }
            self?.finishOperation(generation: scope, operationID: operationID)
        }
    }

    private func acceptCreatedReceipt(
        _ created: NoteImportReceipt,
        actorID: String,
        requestID: String,
        generation: UUID
    ) async {
        guard created.clientRequestID == requestID else {
            phase = .failed(.contract(code: "client_request_id_mismatch"))
            return
        }
        receipt = created
        await loadAndDrive(
            jobID: created.jobID,
            actorID: actorID,
            generation: generation
        )
    }

    private func acceptSubmissionFailure(
        _ error: Error,
        actorID: String,
        requestID: String,
        generation: UUID
    ) async {
        let mapped = Self.map(error)
        if case .ambiguous = mapped {
            phase = .reconciling
            await reconcileOnly(
                actorID: actorID,
                requestID: requestID,
                generation: generation
            )
        } else {
            phase = .failed(mapped)
        }
    }

    private func submit(
        files: [NoteImportFile],
        actorID: String,
        requestID: String,
        generation: UUID
    ) async {
        do {
            let created = try await service.enqueue(
                files: files,
                clientRequestID: requestID
            )
            guard isCurrent(actorID: actorID, generation: generation) else { return }
            await acceptCreatedReceipt(
                created,
                actorID: actorID,
                requestID: requestID,
                generation: generation
            )
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(actorID: actorID, generation: generation) else { return }
            await acceptSubmissionFailure(
                error,
                actorID: actorID,
                requestID: requestID,
                generation: generation
            )
        }
    }

    private func reconcileBeforeRetry(
        actorID: String,
        requestID: String,
        generation: UUID
    ) async {
        do {
            let summaries = try await service.jobs(limit: Self.reconciliationLimit)
            guard isCurrent(actorID: actorID, generation: generation) else { return }
            if let exact = summaries.first(where: { $0.clientRequestID == requestID }) {
                await loadAndDrive(
                    jobID: exact.jobID,
                    actorID: actorID,
                    generation: generation
                )
            } else {
                await submit(
                    files: selectedFiles,
                    actorID: actorID,
                    requestID: requestID,
                    generation: generation
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(actorID: actorID, generation: generation) else { return }
            phase = .failed(Self.map(error))
        }
    }

    private func reconcileOnly(
        actorID: String,
        requestID: String,
        generation: UUID
    ) async {
        do {
            let summaries = try await service.jobs(limit: Self.reconciliationLimit)
            guard isCurrent(actorID: actorID, generation: generation) else { return }
            guard let exact = summaries.first(where: {
                $0.clientRequestID == requestID
            }) else {
                phase = .ambiguous
                return
            }
            await loadAndDrive(
                jobID: exact.jobID,
                actorID: actorID,
                generation: generation
            )
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(actorID: actorID, generation: generation) else { return }
            phase = .failed(Self.map(error))
        }
    }

    private func loadAndDrive(
        jobID: String,
        actorID: String,
        generation: UUID
    ) async {
        do {
            let canonical = try await service.job(id: jobID)
            guard isCurrent(actorID: actorID, generation: generation) else { return }
            guard canonical.jobID == jobID else {
                phase = .failed(.contract(code: "job_id_mismatch"))
                return
            }
            if let expected = clientRequestID,
               canonical.clientRequestID != expected {
                phase = .failed(.contract(code: "client_request_id_mismatch"))
                return
            }
            await drive(
                canonical,
                actorID: actorID,
                generation: generation
            )
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(actorID: actorID, generation: generation) else { return }
            phase = .failed(Self.map(error))
        }
    }

    private func drive(
        _ initial: NoteImportJobDetail,
        actorID: String,
        generation: UUID
    ) async {
        guard isCurrent(actorID: actorID, generation: generation) else { return }
        detail = initial
        if initial.isSettled {
            phase = .terminal
            persistence.clear(actorID: actorID)
            return
        }

        phase = .polling
        schedulePoll(
            jobID: initial.jobID,
            actorID: actorID,
            generation: generation
        )
    }

    private func schedulePoll(
        jobID: String,
        actorID: String,
        generation: UUID
    ) {
        let operationID = UUID()
        self.operationID = operationID
        let sleeper = self.sleeper
        let service = self.service
        operationTask = Task { [weak self] in
            let result: Result<NoteImportJobDetail, Error>
            do {
                try await sleeper.sleep(nanoseconds: Self.pollIntervalNanoseconds)
                try Task.checkCancellation()
                result = .success(try await service.job(id: jobID))
            } catch {
                result = .failure(error)
            }

            guard let self,
                  self.isCurrent(actorID: actorID, generation: generation) else {
                return
            }
            switch result {
            case .success(let next):
                guard next.jobID == jobID else {
                    self.phase = .failed(.contract(code: "job_id_mismatch"))
                    self.finishOperation(
                        generation: generation,
                        operationID: operationID
                    )
                    return
                }
                await self.drive(
                    next,
                    actorID: actorID,
                    generation: generation
                )
            case .failure(let error):
                if error is CancellationError { return }
                self.phase = .failed(Self.map(error))
            }
            self.finishOperation(
                generation: generation,
                operationID: operationID
            )
        }
    }

    private func invalidateOperation() {
        generation = UUID()
        operationTask?.cancel()
        operationTask = nil
        operationID = nil
    }

    private func finishOperation(generation scope: UUID, operationID: UUID) {
        guard generation == scope, self.operationID == operationID else { return }
        operationTask = nil
        self.operationID = nil
    }

    private func isCurrent(actorID: String, generation: UUID) -> Bool {
        !Task.isCancelled && self.actorID == actorID && self.generation == generation
    }

    private static func validate(_ files: [NoteImportFile]) -> NoteImportSelectionError? {
        guard !files.isEmpty else { return .noFiles }
        for file in files {
            guard let canonical = file.canonicalFormat,
                  canonical == file.format else {
                return .unsupportedFormat(filename: file.filename)
            }
            guard file.byteCount > 0 else {
                return .emptyFile(filename: file.filename)
            }
        }
        return nil
    }

    private static func map(_ error: Error) -> NoteImportServiceError {
        if let typed = error as? NoteImportServiceError {
            return typed
        }
        return .requestFailed(code: nil)
    }

    private static func isFailure(_ phase: NoteImportPhase) -> Bool {
        if case .failed = phase { return true }
        return false
    }
}
