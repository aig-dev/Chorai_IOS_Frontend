import Foundation
import XCTest
@testable import CoreFlow

actor MockCoreMergeService: CoreMergeServing {
    private(set) var capabilityCallCount = 0
    private(set) var createCalls: [MergeCreateRequest] = []
    private(set) var jobCalls: [String] = []
    private(set) var artifactCalls: [String] = []
    private(set) var cancelCalls: [String] = []
    private(set) var commitCalls: [(jobID: String, request: MergeCommitRequest)] = []

    private var capabilityResults: [Result<[MergeCapability], CoreMergeError>] = []
    private var createResults: [Result<MergeJob, CoreMergeError>] = []
    private var jobResults: [Result<MergeJob, CoreMergeError>] = []
    private var artifactResults: [Result<MergeArtifact, CoreMergeError>] = []
    private var cancelResults: [Result<MergeJob, CoreMergeError>] = []
    private var commitResults: [Result<MergeCommitResult, CoreMergeError>] = []
    private var createObserver: (@Sendable (MergeCreateRequest) -> Void)?

    func setCreateObserver(
        _ observer: @escaping @Sendable (MergeCreateRequest) -> Void
    ) {
        createObserver = observer
    }

    func enqueueCapabilities(_ result: Result<[MergeCapability], CoreMergeError>) {
        capabilityResults.append(result)
    }

    func enqueueCreate(_ result: Result<MergeJob, CoreMergeError>) {
        createResults.append(result)
    }

    func enqueueJob(_ result: Result<MergeJob, CoreMergeError>) {
        jobResults.append(result)
    }

    func enqueueArtifact(_ result: Result<MergeArtifact, CoreMergeError>) {
        artifactResults.append(result)
    }

    func enqueueCancel(_ result: Result<MergeJob, CoreMergeError>) {
        cancelResults.append(result)
    }

    func enqueueCommit(_ result: Result<MergeCommitResult, CoreMergeError>) {
        commitResults.append(result)
    }

    func capabilities() async throws -> [MergeCapability] {
        capabilityCallCount += 1
        return try dequeue(&capabilityResults).get()
    }

    func createJob(_ request: MergeCreateRequest) async throws -> MergeJob {
        createCalls.append(request)
        createObserver?(request)
        return try dequeue(&createResults).get()
    }

    func job(id: String) async throws -> MergeJob {
        jobCalls.append(id)
        return try dequeue(&jobResults).get()
    }

    func artifact(jobID: String) async throws -> MergeArtifact {
        artifactCalls.append(jobID)
        return try dequeue(&artifactResults).get()
    }

    func cancel(jobID: String) async throws -> MergeJob {
        cancelCalls.append(jobID)
        return try dequeue(&cancelResults).get()
    }

    func commit(
        jobID: String,
        request: MergeCommitRequest
    ) async throws -> MergeCommitResult {
        commitCalls.append((jobID, request))
        return try dequeue(&commitResults).get()
    }

    private func dequeue<Value>(
        _ values: inout [Result<Value, CoreMergeError>]
    ) -> Result<Value, CoreMergeError> {
        precondition(!values.isEmpty, "A mock Merge result must be enqueued")
        return values.removeFirst()
    }
}

final class InMemoryMergeSessionPersistence: MergeSessionPersisting {
    private var values: [String: MergeSessionSnapshot] = [:]
    private(set) var saves: [MergeSessionSnapshot] = []
    private(set) var removals: [String] = []
    var onSave: ((MergeSessionSnapshot) -> Void)?

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
    MergeArtifact(
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
        metadata: [:]
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
