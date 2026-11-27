import Combine
import CoreFlow
import Foundation

struct SharePreviewWireResponse: Codable {
    let noteId: String
    let noteVersionId: String
    let artifactKind: String
    let artifact: ShareArtifactWire
    let actions: ShareActionsWire
}

struct ShareArtifactWire: Codable {
    let id: String
    let kind: String
    let imageUrl: String
    let contentType: String
    let width: Int
    let height: Int
    let status: String
}

struct ShareActionsWire: Codable {
    let canDownload: Bool
    let canNativeShare: Bool
    let canCopyLink: Bool
    let canShareToX: Bool
}

struct SharePinWireResponse: Codable {
    let noteId: String
    let noteVersionId: String
    let artifactId: String
    let artifactKind: String
}

struct NetworkCoreShareService: CoreShareServing, Sendable {
    private let network: NetworkManager
    private let resolveLocalCardID: @MainActor @Sendable (String) -> String?
    private let isCurrentSession: @MainActor @Sendable () -> Bool

    @MainActor
    init(
        network: NetworkManager = .shared,
        resolveLocalCardID: @escaping @MainActor @Sendable (String) -> String? = {
            LocalNotesController.shared.cloudAssetID(for: $0)
        }
    ) {
        self.network = network
        self.resolveLocalCardID = resolveLocalCardID
        self.isCurrentSession = network.captureSessionCheck()
    }

    func preview(cardID: String) async throws -> ShareCardPreview {
        do {
            let response = try await firstValue(cardID: cardID) { serverCardID in
                network.getSharePreview(cardId: serverCardID)
            }
            guard response.artifact.status == "ready",
                  response.artifact.contentType == "image/png",
                  !response.artifact.id.isEmpty else {
                throw CoreShareError.invalidResponse(
                    code: "share_artifact_not_ready"
                )
            }
            return ShareCardPreview(
                noteID: response.noteId,
                noteVersionID: response.noteVersionId,
                artifactKind: response.artifactKind,
                artifact: ShareArtifact(
                    id: response.artifact.id,
                    kind: response.artifact.kind,
                    imageURL: response.artifact.imageUrl,
                    contentType: response.artifact.contentType,
                    width: response.artifact.width,
                    height: response.artifact.height,
                    status: response.artifact.status
                ),
                actions: ShareActions(
                    canDownload: response.actions.canDownload,
                    canNativeShare: response.actions.canNativeShare,
                    canCopyLink: response.actions.canCopyLink,
                    canShareToX: response.actions.canShareToX
                )
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    func artifactImage(
        cardID: String,
        artifactID: String
    ) async throws -> Data {
        do {
            let data = try await firstValue(cardID: cardID) { serverCardID in
                network.getShareArtifactImage(
                    cardId: serverCardID,
                    artifactId: artifactID
                )
            }
            guard !data.isEmpty else {
                throw CoreShareError.invalidResponse(
                    code: "share_image_empty"
                )
            }
            return data
        } catch {
            throw Self.mapError(error)
        }
    }

    func pinArtifact(
        cardID: String,
        artifactID: String
    ) async throws -> ShareArtifactPin {
        do {
            let response = try await firstValue(cardID: cardID) { serverCardID in
                network.pinShareArtifact(
                    cardId: serverCardID,
                    artifactId: artifactID
                )
            }
            return ShareArtifactPin(
                noteID: response.noteId,
                noteVersionID: response.noteVersionId,
                artifactID: response.artifactId,
                artifactKind: response.artifactKind
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    @MainActor
    private func requestCardID(_ cardID: String) throws -> String {
        guard cardID.hasPrefix("local-note:") else { return cardID }
        guard let serverID = resolveLocalCardID(cardID),
              !serverID.isEmpty, !serverID.hasPrefix("local-note:") else {
            throw CoreShareError.transport(code: "note_not_yet_synced")
        }
        return serverID
    }

    @MainActor
    private func firstValue<Output: Sendable>(
        cardID: String,
        publisher: @MainActor @Sendable (String) -> AnyPublisher<Output, NetworkError>
    ) async throws -> Output {
        try Task.checkCancellation()
        guard isCurrentSession() else { throw NetworkError.unauthorized }
        let serverCardID = try requestCardID(cardID)
        guard isCurrentSession() else { throw NetworkError.unauthorized }
        // Resolve and create the eager request in one MainActor turn, before any suspension.
        do {
            guard let value = try await NetworkManager.firstValue(publisher(serverCardID)) else {
                throw NetworkError.noData
            }
            try Task.checkCancellation()
            guard isCurrentSession() else { throw NetworkError.unauthorized }
            return value
        } catch {
            try Task.checkCancellation()
            guard isCurrentSession() else { throw NetworkError.unauthorized }
            throw error
        }
    }

    private static func mapError(_ error: Error) -> CoreShareError {
        if let shareError = error as? CoreShareError {
            return shareError
        }
        guard let networkError = error as? NetworkError else {
            return .transport(code: "share_unknown")
        }

        switch networkError {
        case .decodingError:
            return .invalidResponse(code: "share_decoding")
        case .api(_, let code, _, _):
            return .transport(code: code?.lowercased() ?? "share_api")
        case .unauthorized:
            return .transport(code: "share_unauthorized")
        case .forbidden:
            return .transport(code: "share_forbidden")
        case .notFound:
            return .transport(code: "share_not_found")
        case .timeout:
            return .transport(code: "share_timeout")
        case .networkError:
            return .transport(code: "share_offline")
        case .invalidURL:
            return .transport(code: "share_invalid_url")
        case .noData:
            return .transport(code: "share_no_data")
        case .encodingError:
            return .transport(code: "share_encoding")
        case .serverError(let statusCode, _):
            return .transport(code: "share_server_\(statusCode)")
        case .unknown:
            return .transport(code: "share_unknown")
        }
    }
}
