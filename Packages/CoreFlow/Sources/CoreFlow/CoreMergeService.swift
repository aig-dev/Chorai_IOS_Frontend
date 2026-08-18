import Foundation

public protocol CoreMergeServing: Sendable {
    func capabilities() async throws -> [MergeCapability]
    func createJob(_ request: MergeCreateRequest) async throws -> MergeJob
    func job(id: String) async throws -> MergeJob
    func artifact(jobID: String) async throws -> MergeArtifact
    func saveArtifact(
        jobID: String,
        request: MergeArtifactSaveRequest
    ) async throws -> MergeArtifactSaveResult
    func cancel(jobID: String) async throws -> MergeJob
    func commit(
        jobID: String,
        request: MergeCommitRequest
    ) async throws -> MergeCommitResult
}

public extension CoreMergeServing {
    func saveArtifact(
        jobID: String,
        request: MergeArtifactSaveRequest
    ) async throws -> MergeArtifactSaveResult {
        throw CoreMergeError.unavailable(code: "artifact_save_unavailable")
    }
}

public protocol MergeSleeping: Sendable {
    func sleep(nanoseconds: UInt64) async throws
}

public struct SystemMergeSleeper: MergeSleeping {
    public init() {}

    public func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}
