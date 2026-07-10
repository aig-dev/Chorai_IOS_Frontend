import Combine
import CoreFlow
import Foundation

struct NetworkCoreMergeService: CoreMergeServing, @unchecked Sendable {
    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func capabilities() async throws -> [MergeCapability] {
        do {
            let response = try await firstValue(network.listMergeCapabilities())
            return response.capabilities.map {
                MergeCapability(
                    capabilityID: $0.capabilityId,
                    displayName: $0.displayName ?? $0.capabilityId,
                    outputKind: MergeCapabilityOutputKind(
                        serverValue: $0.outputKind
                    ),
                    blockExport: $0.blockExport,
                    slotCommit: $0.slotCommit,
                    isEnabled: $0.enabled,
                    rolloutStage: $0.rolloutStage ?? ""
                )
            }
        } catch {
            throw Self.mapError(error)
        }
    }

    func createJob(_ request: MergeCreateRequest) async throws -> MergeJob {
        let wireRequest = MergeCardsRequest(
            sources: request.sources.map {
                MergeSourceRef(
                    assetId: $0.assetID,
                    versionId: $0.versionID
                )
            },
            capability: request.capability,
            idemKey: request.idempotencyKey,
            context: request.context
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
            return Self.mapArtifact(
                try await firstValue(network.getMergeArtifact(jobId: jobID))
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    func cancel(jobID: String) async throws -> MergeJob {
        do {
            return Self.mapJob(
                try await firstValue(network.cancelMergeJob(jobId: jobID))
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

        let wireRequest = CommitMergeJobRequest(
            idemKey: request.idempotencyKey,
            target: NewCardCommitTarget(
                spaceId: request.target.spaceID,
                titleOverride: request.target.titleOverride
            )
        )

        do {
            let response = try await firstValue(
                network.commitMergeJob(
                    jobId: jobID,
                    request: wireRequest
                )
            )
            return MergeCommitResult(
                commitID: response.commitId,
                status: response.status,
                targetType: response.targetType,
                assetID: response.assetId,
                versionID: response.versionId,
                activityID: response.activityId,
                logID: response.logId,
                errorCode: response.errorCode,
                backgroundMediaReference: response.backgroundMediaRef
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    private func firstValue<Output>(
        _ publisher: AnyPublisher<Output, NetworkError>
    ) async throws -> Output {
        var iterator = publisher.values.makeAsyncIterator()
        guard let value = try await iterator.next() else {
            throw NetworkError.noData
        }
        return value
    }

    private static func mapJob(_ response: MergeJobResponse) -> MergeJob {
        MergeJob(
            jobID: response.jobId,
            status: MergeJobStatus(serverValue: response.status),
            capability: response.capability,
            selectedCapability: response.selectedCap,
            planScore: response.planScore,
            artifactID: response.artifactId,
            latestCommit: response.latestCommit.map {
                MergeCommitSummary(
                    commitID: $0.commitId,
                    status: $0.status,
                    targetType: $0.targetType
                )
            },
            failureStage: response.failStage,
            errorCode: response.errorCode,
            failureReason: response.failureReason
        )
    }

    private static func mapArtifact(
        _ response: MergeArtifactResponse
    ) -> MergeArtifact {
        MergeArtifact(
            artifactID: response.artifactId,
            jobID: response.jobId,
            capabilityID: response.capabilityId,
            outputKind: MergeCapabilityOutputKind(
                serverValue: response.outputKind
            ),
            document: MergeDocument(
                schemaVersion: response.doc.schemaVersion,
                title: response.doc.title,
                subtitle: response.doc.subtitle,
                blocks: response.doc.blocks.map(mapBlock),
                metadata: response.doc.meta ?? [:]
            ),
            fragments: (response.fragments ?? []).map {
                MergeFragment(
                    fragmentID: $0.fragmentId,
                    schemaVersion: $0.schemaVersion,
                    blocks: $0.blocks.map(mapBlock),
                    insertMode: $0.insertMode,
                    metadata: $0.meta ?? [:]
                )
            },
            metadata: response.meta ?? [:]
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
        case .api(let statusCode, let code, let message):
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
