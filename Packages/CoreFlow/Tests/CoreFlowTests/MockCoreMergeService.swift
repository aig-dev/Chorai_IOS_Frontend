import Foundation
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

    func snapshot(actorID: String) -> MergeSessionSnapshot? {
        values[actorID]
    }

    func save(_ snapshot: MergeSessionSnapshot) {
        values[snapshot.actorID] = snapshot
        saves.append(snapshot)
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
