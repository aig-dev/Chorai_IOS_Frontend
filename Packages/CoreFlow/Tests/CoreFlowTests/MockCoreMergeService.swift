import Foundation
import XCTest
@testable import CoreFlow

actor MockCoreMergeService: CoreMergeServing {
    private(set) var capabilityCallCount = 0
    private(set) var createCalls: [MergeCreateRequest] = []
    private(set) var jobCalls: [String] = []
    private(set) var artifactCalls: [String] = []
    private(set) var saveCalls: [(jobID: String, request: MergeArtifactSaveRequest)] = []
    private(set) var cancelCalls: [String] = []
    private(set) var commitCalls: [(jobID: String, request: MergeCommitRequest)] = []

    private var capabilityResults: [Result<[MergeCapability], CoreMergeError>] = []
    private var createResults: [Result<MergeJob, CoreMergeError>] = []
    private var jobResults: [Result<MergeJob, CoreMergeError>] = []
    private var artifactResults: [Result<MergeArtifact, CoreMergeError>] = []
    private var saveResults: [Result<MergeArtifactSaveResult, CoreMergeError>] = []
    private var cancelResults: [Result<MergeJob, CoreMergeError>] = []
    private var commitResults: [Result<MergeCommitResult, CoreMergeError>] = []
    private var jobResultsByID: [String: [Result<MergeJob, CoreMergeError>]] = [:]
    private var artifactResultsByJobID: [String: [Result<MergeArtifact, CoreMergeError>]] = [:]
    private var saveResultsByJobID: [String: [Result<MergeArtifactSaveResult, CoreMergeError>]] = [:]
    private var cancelResultsByJobID: [String: [Result<MergeJob, CoreMergeError>]] = [:]
    private var commitResultsByJobID: [String: [Result<MergeCommitResult, CoreMergeError>]] = [:]
    private var controlledCreatesByKey: [String: [ControlledMergeCreateResponse]] = [:]
    private var controlledJobsByID: [String: [ControlledMergeJobResponse]] = [:]
    private var createObserver: (@Sendable (MergeCreateRequest) -> Void)?
    private var cancelObserver: (@Sendable (String) -> Void)?
    private var commitObserver: (@Sendable (String, MergeCommitRequest) -> Void)?

    func setCreateObserver(
        _ observer: @escaping @Sendable (MergeCreateRequest) -> Void
    ) {
        createObserver = observer
    }

    func setCancelObserver(_ observer: @escaping @Sendable (String) -> Void) {
        cancelObserver = observer
    }

    func setCommitObserver(
        _ observer: @escaping @Sendable (String, MergeCommitRequest) -> Void
    ) {
        commitObserver = observer
    }

    func enqueueCapabilities(_ result: Result<[MergeCapability], CoreMergeError>) {
        capabilityResults.append(result)
    }

    func enqueueCreate(_ result: Result<MergeJob, CoreMergeError>) {
        createResults.append(result)
    }

    func enqueueControlledCreate(
        idempotencyKey: String,
        _ result: Result<MergeJob, CoreMergeError>
    ) -> ControlledMergeCreateResponse {
        let response = ControlledMergeCreateResponse(result: result)
        controlledCreatesByKey[idempotencyKey, default: []].append(response)
        return response
    }

    func enqueueJob(_ result: Result<MergeJob, CoreMergeError>) {
        jobResults.append(result)
    }

    func enqueueJob(
        id: String,
        _ result: Result<MergeJob, CoreMergeError>
    ) {
        jobResultsByID[id, default: []].append(result)
    }

    func enqueueArtifact(_ result: Result<MergeArtifact, CoreMergeError>) {
        artifactResults.append(result)
    }

    func enqueueArtifact(
        jobID: String,
        _ result: Result<MergeArtifact, CoreMergeError>
    ) {
        artifactResultsByJobID[jobID, default: []].append(result)
    }

    func enqueueSave(_ result: Result<MergeArtifactSaveResult, CoreMergeError>) {
        saveResults.append(result)
    }

    func enqueueSave(
        jobID: String,
        _ result: Result<MergeArtifactSaveResult, CoreMergeError>
    ) {
        saveResultsByJobID[jobID, default: []].append(result)
    }

    func enqueueCancel(_ result: Result<MergeJob, CoreMergeError>) {
        cancelResults.append(result)
    }

    func enqueueCancel(
        jobID: String,
        _ result: Result<MergeJob, CoreMergeError>
    ) {
        cancelResultsByJobID[jobID, default: []].append(result)
    }

    func enqueueCommit(_ result: Result<MergeCommitResult, CoreMergeError>) {
        commitResults.append(result)
    }

    func enqueueCommit(
        jobID: String,
        _ result: Result<MergeCommitResult, CoreMergeError>
    ) {
        commitResultsByJobID[jobID, default: []].append(result)
    }

    func enqueueControlledJob(
        id: String,
        _ result: Result<MergeJob, CoreMergeError>
    ) -> ControlledMergeJobResponse {
        let response = ControlledMergeJobResponse(result: result)
        controlledJobsByID[id, default: []].append(response)
        return response
    }

    func capabilities() async throws -> [MergeCapability] {
        capabilityCallCount += 1
        return try dequeue(&capabilityResults).get()
    }

    func createJob(_ request: MergeCreateRequest) async throws -> MergeJob {
        createCalls.append(request)
        createObserver?(request)
        if var responses = controlledCreatesByKey[request.idempotencyKey],
           !responses.isEmpty {
            let response = responses.removeFirst()
            controlledCreatesByKey[request.idempotencyKey] = responses
            return try await response.resolve()
        }
        return try dequeue(&createResults).get()
    }

    func job(id: String) async throws -> MergeJob {
        jobCalls.append(id)
        if var responses = controlledJobsByID[id], !responses.isEmpty {
            let response = responses.removeFirst()
            controlledJobsByID[id] = responses
            return try await response.resolve()
        }
        if let result = dequeue(id: id, from: &jobResultsByID) {
            return try result.get()
        }
        return try dequeue(&jobResults).get()
    }

    func artifact(jobID: String) async throws -> MergeArtifact {
        artifactCalls.append(jobID)
        if let result = dequeue(id: jobID, from: &artifactResultsByJobID) {
            return try result.get()
        }
        return try dequeue(&artifactResults).get()
    }

    func saveArtifact(
        jobID: String,
        request: MergeArtifactSaveRequest
    ) async throws -> MergeArtifactSaveResult {
        saveCalls.append((jobID, request))
        if let result = dequeue(id: jobID, from: &saveResultsByJobID) {
            return try result.get()
        }
        return try dequeue(&saveResults).get()
    }

    func cancel(jobID: String) async throws -> MergeJob {
        cancelCalls.append(jobID)
        cancelObserver?(jobID)
        if let result = dequeue(id: jobID, from: &cancelResultsByJobID) {
            return try result.get()
        }
        return try dequeue(&cancelResults).get()
    }

    func commit(
        jobID: String,
        request: MergeCommitRequest
    ) async throws -> MergeCommitResult {
        commitCalls.append((jobID, request))
        commitObserver?(jobID, request)
        if let result = dequeue(id: jobID, from: &commitResultsByJobID) {
            return try result.get()
        }
        return try dequeue(&commitResults).get()
    }

    private func dequeue<Value>(
        id: String,
        from values: inout [String: [Result<Value, CoreMergeError>]]
    ) -> Result<Value, CoreMergeError>? {
        guard var queue = values[id], !queue.isEmpty else { return nil }
        let result = queue.removeFirst()
        values[id] = queue
        return result
    }

    private func dequeue<Value>(
        _ values: inout [Result<Value, CoreMergeError>]
    ) -> Result<Value, CoreMergeError> {
        precondition(!values.isEmpty, "A mock Merge result must be enqueued")
        return values.removeFirst()
    }
}

actor ControlledMergeCreateResponse {
    private let result: Result<MergeJob, CoreMergeError>
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    init(result: Result<MergeJob, CoreMergeError>) {
        self.result = result
    }

    func resolve() async throws -> MergeJob {
        isWaiting = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return try result.get()
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

actor ControlledMergeJobResponse {
    private let result: Result<MergeJob, CoreMergeError>
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    init(result: Result<MergeJob, CoreMergeError>) {
        self.result = result
    }

    func resolve() async throws -> MergeJob {
        isWaiting = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return try result.get()
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

final class InMemoryMergeSessionPersistence: MergeSessionPersisting {
    private var values: [String: MergeSessionSnapshot] = [:]
    private(set) var saves: [MergeSessionSnapshot] = []
    private(set) var removals: [String] = []
    var onSave: ((MergeSessionSnapshot) -> Void)?
    var onRemove: ((String) -> Void)?

    func snapshot(actorID: String) -> MergeSessionSnapshot? {
        values[actorID]
    }

    func save(_ snapshot: MergeSessionSnapshot) {
        values[snapshot.actorID] = snapshot
        saves.append(snapshot)
        onSave?(snapshot)
    }

    func remove(actorID: String) {
        values[actorID] = nil
        removals.append(actorID)
        onRemove?(actorID)
    }

    func resumeMetadata(actorID: String) -> MergeResumeMetadata? {
        guard let snapshot = values[actorID] else {
            return nil
        }
        return MergeResumeMetadata(
            actorID: snapshot.actorID,
            anchorAssetID: snapshot.anchorAssetID,
            anchorPreview: snapshot.anchorPreview,
            sourceCount: snapshot.createRequest.sources.count,
            jobID: snapshot.jobID,
            status: snapshot.lastStatus,
            committedAssetID: snapshot.committedAssetID
        )
    }

    func seed(_ snapshot: MergeSessionSnapshot) {
        values[snapshot.actorID] = snapshot
    }
}

final class LockedMergeEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ event: String) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}

actor ImmediateMergeSleeper: MergeSleeping {
    private(set) var calls: [UInt64] = []

    func sleep(nanoseconds: UInt64) async throws {
        calls.append(nanoseconds)
        try Task.checkCancellation()
    }
}

actor ControlledMergeSleeper: MergeSleeping {
    private(set) var calls: [UInt64] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var pendingCount: Int { continuations.count }

    func sleep(nanoseconds: UInt64) async throws {
        calls.append(nanoseconds)
        try Task.checkCancellation()
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        try Task.checkCancellation()
    }

    func resumeNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

func makeMergeSource(
    _ assetID: String,
    preview: String? = nil
) -> MergeSource {
    MergeSource(
        assetID: assetID,
        versionID: nil,
        preview: preview ?? assetID
    )
}

func makeMergeCapability(
    id: String = "structured_text",
    enabled: Bool = true,
    outputKind: MergeCapabilityOutputKind = .document
) -> MergeCapability {
    MergeCapability(
        capabilityID: id,
        displayName: "Structured text",
        outputKind: outputKind,
        blockExport: true,
        slotCommit: false,
        isEnabled: enabled,
        rolloutStage: "ga"
    )
}

func makeMergeJob(
    id: String = "job_1",
    status: MergeJobStatus,
    artifactID: String? = nil,
    errorCode: String? = nil
) -> MergeJob {
    MergeJob(
        jobID: id,
        status: status,
        capability: "auto",
        selectedCapability: "structured_text",
        planScore: 0.9,
        artifactID: artifactID,
        latestCommit: nil,
        failureStage: status == .failed ? "generation" : nil,
        errorCode: errorCode,
        failureReason: nil
    )
}

func makeMergeArtifact(
    jobID: String = "job_1",
    artifactID: String = "artifact_1"
) -> MergeArtifact {
    let documentJSON = Data(
        #"{"blocks":[{"content":[{"text":"Merged body","type":"text"}],"id":"block_1","type":"paragraph"}],"meta":{},"schemaVersion":"card_doc.v1"}"#.utf8
    )
    return MergeArtifact(
        artifactID: artifactID,
        jobID: jobID,
        capabilityID: "structured_text",
        outputKind: .document,
        document: MergeDocument(
            schemaVersion: "1.0",
            title: "Merged title",
            subtitle: nil,
            blocks: [
                MergeBlock(
                    id: "block_1",
                    type: "paragraph",
                    content: [
                        MergeInline(
                            type: "text",
                            text: "Merged body",
                            properties: [:]
                        )
                    ],
                    properties: [:],
                    children: []
                )
            ],
            metadata: [:]
        ),
        fragments: [],
        metadata: [:],
        latestRevision: 1,
        latestHash: "sha256:artifact-document-1",
        documentJSON: documentJSON,
        presentationHash: "sha256:artifact-presentation-1",
        presentation: MergeArtifactPresentation(
            schemaVersion: "merge_artifact_presentation.v1",
            tags: [],
            rate: 1
        )
    )
}

func makeMergeCommitResult(
    assetID: String? = "ast_committed",
    errorCode: String? = nil
) -> MergeCommitResult {
    MergeCommitResult(
        commitID: "commit_1",
        status: "COMMITTED",
        targetType: "new_card",
        assetID: assetID,
        versionID: assetID == nil ? nil : "ver_committed",
        activityID: assetID == nil ? nil : "activity_1",
        logID: nil,
        errorCode: errorCode,
        backgroundMediaReference: nil
    )
}

func makeMergeSnapshot(
    actorID: String = "actor_1",
    anchorID: String = "ast_anchor",
    jobID: String? = nil,
    status: MergeJobStatus? = nil,
    createKey: String = "create-existing"
) -> MergeSessionSnapshot {
    let sources = [
        makeMergeSource(anchorID, preview: "Anchor"),
        makeMergeSource("ast_companion", preview: "Companion")
    ]
    return MergeSessionSnapshot(
        actorID: actorID,
        anchorAssetID: anchorID,
        anchorPreview: "Anchor",
        createRequest: MergeCreateRequest(
            sources: sources,
            capability: "auto",
            idempotencyKey: createKey,
            context: ["client": .string("ios")]
        ),
        selectedCapability: nil,
        jobID: jobID,
        lastStatus: status,
        artifactID: nil,
        commitRequest: nil,
        committedAssetID: nil
    )
}

func makeMergeTaskRecord(
    jobID: String,
    status: MergeJobStatus,
    operationID: String? = nil,
    createdAt: TimeInterval = 100
) -> MergeTaskRecord {
    MergeTaskRecord(
        operationID: operationID ?? "op_\(jobID)",
        snapshot: makeMergeSnapshot(
            jobID: jobID,
            status: status,
            createKey: "create_\(jobID)"
        ),
        createdAt: Date(timeIntervalSince1970: createdAt),
        updatedAt: Date(timeIntervalSince1970: createdAt),
        replacesJobID: nil
    )
}

func waitForControlledJob(
    _ response: ControlledMergeJobResponse,
    timeoutIterations: Int = 500
) async {
    for _ in 0..<timeoutIterations {
        if await response.isWaiting { return }
        await Task.yield()
    }
    XCTFail("Timed out waiting for controlled Merge GET")
}

func waitForControlledCreate(
    _ response: ControlledMergeCreateResponse,
    timeoutIterations: Int = 500
) async {
    for _ in 0..<timeoutIterations {
        if await response.isWaiting { return }
        await Task.yield()
    }
    XCTFail("Timed out waiting for controlled Merge create")
}

@MainActor
func waitForMergeStore(
    timeoutIterations: Int = 500,
    _ predicate: @escaping () -> Bool
) async {
    for _ in 0..<timeoutIterations {
        if predicate() { return }
        await Task.yield()
    }
    XCTFail("Timed out waiting for Merge store state")
}
