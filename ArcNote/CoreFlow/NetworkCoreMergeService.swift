import Combine
import CoreFlow
import Foundation

struct NetworkCoreMergeService: CoreMergeServing, Sendable {
    private let network: NetworkManager

    @MainActor
    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func capabilities() async throws -> [MergeCapability] {
        [
            MergeCapability(
                capabilityID: "auto",
                displayName: "Merge",
                outputKind: .document,
                blockExport: false,
                slotCommit: false,
                isEnabled: true,
                rolloutStage: "server-job-contract"
            )
        ]
    }

    func createJob(_ request: MergeCreateRequest) async throws -> MergeJob {
        let sources = try request.sources.map {
            guard let versionID = $0.versionID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !versionID.isEmpty else {
                throw CoreMergeError.validation(
                    code: "source_version_required"
                )
            }
            return MergeSourceRef(
                assetId: $0.assetID,
                versionId: versionID
            )
        }
        let wireRequest = MergeCardsRequest(
            sources: sources,
            idemKey: request.idempotencyKey
        )

        do {
            return Self.mapJob(
                try await firstValue(network.createMergeJob(wireRequest))
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    func job(id: String) async throws -> MergeJob {
        do {
            return Self.mapJob(
                try await firstValue(network.getMergeJob(jobId: id))
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    func artifact(jobID: String) async throws -> MergeArtifact {
        do {
            return try Self.mapArtifact(
                try await firstValue(network.getMergeArtifact(jobId: jobID))
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    func saveArtifact(
        jobID: String,
        request: MergeArtifactSaveRequest
    ) async throws -> MergeArtifactSaveResult {
        let wireRequest: MergeArtifactSaveRequestDTO
        do {
            wireRequest = try MergeArtifactSaveRequestDTO(
                baseRevision: request.baseRevision,
                baseHash: request.baseHash,
                idemKey: request.idempotencyKey,
                documentJSON: request.documentJSON,
                tags: request.tags
            )
        } catch {
            throw CoreMergeError.validation(code: "invalid_artifact_document")
        }

        do {
            let encoding = try NetworkManager.mergeArtifactEncoding(wireRequest)
            let response = try await firstValue(
                network.saveMergeArtifact(
                    jobID: jobID,
                    encoding: encoding
                )
            )
            return MergeArtifactSaveResult(
                artifactID: response.artifactId,
                revision: response.revision,
                documentHash: response.docHash,
                presentationHash: response.presentationHash,
                presentation: response.presentation
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    func cancel(jobID: String) async throws -> MergeJob {
        do {
            return Self.mapJob(
                try await firstValue(
                    network.cancelMergeJob(
                        jobId: jobID,
                        request: CancelMergeJobRequest(
                            idemKey: "ios-merge-cancel-\(jobID)"
                        )
                    )
                )
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    func commit(
        jobID: String,
        request: MergeCommitRequest
    ) async throws -> MergeCommitResult {
        guard request.target.targetType == "new_card" else {
            throw CoreMergeError.validation(code: "unsupported_commit_target")
        }
        guard let revision = request.revision,
              let artifactHash = request.artifactHash else {
            throw CoreMergeError.validation(code: "commit_artifact_selection_required")
        }

        do {
            // The vNext API commits an immutable artifact revision. It does not
            // accept client-side title or space overrides at this boundary.
            let wireRequest = CommitMergeJobRequest(
                revision: revision,
                artifactHash: artifactHash,
                idemKey: request.idempotencyKey
            )
            let response = try await firstValue(
                network.commitMergeJob(
                    jobId: jobID,
                    request: wireRequest
                )
            )
            return MergeCommitResult(
                commitID: response.commitId,
                status: "COMMITTED",
                targetType: "new_card",
                assetID: response.noteAssetId,
                versionID: response.assetVersionId,
                activityID: response.activityId,
                logID: response.actionLogId,
                errorCode: nil,
                backgroundMediaReference: nil
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    @MainActor
    private func firstValue<Output: Sendable>(
        _ publisher: @autoclosure @MainActor @Sendable () -> AnyPublisher<Output, NetworkError>
    ) async throws -> Output {
        guard let value = try await NetworkManager.firstValue(publisher()) else {
            throw NetworkError.noData
        }
        return value
    }

    private static func mapJob(_ response: MergeJobResponse) -> MergeJob {
        MergeJob(
            jobID: response.jobId,
            status: MergeJobStatus(serverValue: response.status),
            capability: "auto",
            selectedCapability: response.route.isEmpty ? nil : response.route,
            planScore: nil,
            artifactID: response.artifactId.isEmpty ? nil : response.artifactId,
            latestCommit: nil,
            failureStage: nil,
            errorCode: nil,
            failureReason: nil
        )
    }

    private static func mapArtifact(
        _ response: MergeArtifactResponse
    ) throws -> MergeArtifact {
        MergeArtifact(
            artifactID: response.artifactID,
            jobID: response.jobID,
            capabilityID: response.route,
            outputKind: .document,
            document: MergeDocument(
                schemaVersion: response.document.schemaVersion,
                title: nil,
                subtitle: nil,
                blocks: response.document.blocks.map(mapBlock),
                metadata: response.document.meta
            ),
            fragments: [],
            metadata: [
                "route": .string(response.route),
                "surpriseKind": .string(response.surpriseKind),
                "sourceSnapshotHash": .string(response.sourceSnapshotHash),
                "latestRevision": .number(Double(response.latestRevision)),
                "latestHash": .string(response.latestHash),
                "sourceTray": .object(response.sourceTray),
                "alignment": .object(response.alignment)
            ],
            latestRevision: response.latestRevision,
            latestHash: response.latestHash,
            documentJSON: response.documentJSON,
            presentationHash: response.presentationHash,
            presentation: response.presentation
        )
    }

    private static func mapBlock(_ block: MergeBlockNodeDTO) -> MergeBlock {
        MergeBlock(
            id: block.id,
            type: block.type,
            content: (block.content ?? []).map(mapInline),
            properties: block.props ?? [:],
            children: (block.children ?? []).map(mapBlock)
        )
    }

    private static func mapInline(_ value: MergeJSONValue) -> MergeInline {
        switch value {
        case .object(let properties):
            return MergeInline(
                type: properties["type"]?.textValue,
                text: properties["text"]?.textValue,
                properties: properties
            )
        case .string(let text):
            return MergeInline(
                type: "text",
                text: text,
                properties: [:]
            )
        default:
            return MergeInline(
                type: nil,
                text: value.textValue,
                properties: ["value": value]
            )
        }
    }

    private static func mapError(_ error: Error) -> CoreMergeError {
        if let coreError = error as? CoreMergeError {
            return coreError
        }
        guard let networkError = error as? NetworkError else {
            return .unknown(code: nil)
        }

        switch networkError {
        case .api(let statusCode, let code, let message, _):
#if DEBUG
            if let message {
                print("Merge API error [\(code ?? "UNKNOWN")]: \(message)")
            }
#endif
            return classify(
                statusCode: statusCode,
                code: code,
                message: message
            )
        case .serverError(let statusCode, let message):
            return classify(
                statusCode: statusCode,
                code: nil,
                message: message
            )
        case .unauthorized:
            return .unauthorized
        case .forbidden:
            return .forbidden
        case .notFound:
            return .notFound
        case .timeout:
            return .timeout
        case .decodingError:
            return .decoding
        case .networkError(let underlying):
            if (underlying as? URLError)?.code == .timedOut {
                return .timeout
            }
            return .offline
        case .encodingError:
            return .validation(code: "client_encoding")
        case .invalidURL, .noData, .unknown:
            return .unknown(code: nil)
        }
    }

    private static func classify(
        statusCode: Int,
        code: String?,
        message: String?
    ) -> CoreMergeError {
        let normalizedCode = code?.uppercased()
        let normalizedMessage = message?.lowercased() ?? ""

        if statusCode == 401 || normalizedCode == "UNAUTHORIZED" {
            return .unauthorized
        }
        if statusCode == 403 || normalizedCode == "FORBIDDEN" {
            return .forbidden
        }
        if statusCode == 404
            || normalizedCode == "NOT_FOUND"
            || normalizedCode == "RESOURCE_NOT_FOUND" {
            return .notFound
        }
        if normalizedCode?.contains("CANCEL") == true {
            return .cancelled
        }
        if statusCode == 408 {
            return .timeout
        }
        if statusCode == 409,
           normalizedMessage.contains("artifact"),
           normalizedMessage.contains("ready") {
            return .artifactNotReady
        }
        if statusCode == 409 {
            return .conflict(code: normalizedCode)
        }
        if statusCode == 400 || statusCode == 422 {
            return .validation(code: normalizedCode)
        }
        if statusCode == 502 || statusCode == 503 || statusCode == 504 {
            return .unavailable(code: normalizedCode)
        }
        if statusCode >= 500 {
            return .server(code: normalizedCode)
        }
        return .unknown(code: normalizedCode)
    }
}
