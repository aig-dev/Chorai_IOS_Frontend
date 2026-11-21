import Combine
import CoreFlow
import Foundation

#if DEBUG
private actor CardEditingCreateResponseLossFault {
    static let shared = CardEditingCreateResponseLossFault()

    private var consumedRequestIDs = Set<String>()

    func shouldLoseResponse(
        draft: CardEditingDraft,
        createRequestID: String
    ) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CHORAI_UI_TEST"] == "1",
              let token = environment[
                  "CHORAI_UI_TEST_CARD_CREATE_RESPONSE_LOSS_TOKEN"
              ]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty,
              draft.content.contains(token),
              consumedRequestIDs.insert(createRequestID).inserted else {
            return false
        }
        return true
    }
}
#endif

struct NetworkCoreCardEditingService: CoreCardEditingServing, Sendable {
    private let network: NetworkManager

    @MainActor
    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func create(
        draft: CardEditingDraft,
        createRequestID: String
    ) async throws -> CardEditingSnapshot {
        do {
            let response = try await firstValue(
                network.createCard(
                    CreateCardRequest(
                        title: draft.title,
                        content: draft.content,
                        contentJSON: draft.contentJSON,
                        editorAtmosphere: draft.editorAtmosphere,
                        tags: draft.tags,
                        isPublic: draft.isPublic
                    ),
                    idempotencyKey: createRequestID
                )
            )
            guard response.success else {
                throw CardEditingError.transport(code: "card_create_rejected")
            }
#if DEBUG
            if await CardEditingCreateResponseLossFault.shared.shouldLoseResponse(
                draft: draft,
                createRequestID: createRequestID
            ) {
                throw CardEditingError.transport(
                    code: "ui_test_card_create_response_lost"
                )
            }
#endif
            return snapshot(from: response.data)
        } catch {
            throw Self.mapError(error)
        }
    }

    func update(
        cardID: String,
        draft: CardEditingDraft
    ) async throws -> CardEditingSnapshot {
        do {
            let response = try await firstValue(
                network.updateCardForEditing(
                    cardId: cardID,
                    title: draft.title,
                    content: draft.content,
                    contentJSON: draft.contentJSON,
                    editorAtmosphere: draft.editorAtmosphere,
                    tags: draft.tags,
                    isPublic: draft.isPublic
                )
            )
            guard response.success else {
                throw CardEditingError.transport(code: "card_save_rejected")
            }
            return snapshot(from: response.data)
        } catch {
            throw Self.mapError(error)
        }
    }

    func createLink(_ link: CardEditingLink) async throws -> CardEditingLink {
        do {
            let response = try await network.createCardLink(
                cardId: link.sourceCardID, reques: LinkRequest(linkedCardId: link.targetCardID), presentsError: false
            )
            guard response.success else {
                throw CardEditingError.transport(code: "card_link_rejected")
            }
            return CardEditingLink(sourceCardID: response.data.cardId, targetCardID: response.data.linkedCardId,
                title: link.title, noteLinkID: response.data.linkId, previewHTML: link.previewHTML,
                authorName: link.authorName, authorAvatarURL: link.authorAvatarURL)
        } catch {
            throw Self.mapError(error)
        }
    }

    func deleteLink(_ link: CardEditingLink) async throws {
        do {
            guard let noteLinkID = link.noteLinkID, !noteLinkID.isEmpty else {
                throw CardEditingError.transport(code: "card_link_identity_missing")
            }
            let response = try await network.deleteCardLink(
                cardId: link.sourceCardID, linkedCardId: link.targetCardID, noteLinkID: noteLinkID
            )
            guard response.success, response.data?.removed == true else {
                throw CardEditingError.transport(code: "card_unlink_rejected")
            }
        } catch {
            throw Self.mapError(error)
        }
    }

    func fetchLinks(cardID: String) async throws -> [CardEditingLink] {
        do {
            let response = try await firstValue(
                network.getCardLinks(cardId: cardID)
            )
            guard response.success else {
                throw CardEditingError.transport(
                    code: "card_links_fetch_rejected"
                )
            }
            return (
                response.data.outgoingLinks + response.data.incomingLinks
            ).map { item in
                CardEditingLink(
                    sourceCardID: item.sourceAssetId,
                    targetCardID: item.targetAssetId,
                    title: item.title ?? "Related note",
                    noteLinkID: item.linkId,
                    previewHTML: item.content,
                    authorName: item.author?.userName,
                    authorAvatarURL: item.author?.avatar
                )
            }
        } catch {
            throw Self.mapError(error)
        }
    }

    func uploadInlineImage(
        _ image: CardEditingImage
    ) async throws -> CardEditingInlineImageUpload {
        do {
            let upload = try await firstValue(
                network.uploadCardMedia(
                    data: image.data,
                    filename: image.filename,
                    mimeType: image.mimeType
                )
            )
            guard upload.success else {
                throw CardEditingError.transport(
                    code: "card_inline_image_upload_rejected"
                )
            }
            guard let uploaded = upload.data else {
                throw CardEditingError.transport(
                    code: "card_inline_image_response_missing"
                )
            }
            let mediaRef = uploaded.mediaRef.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !mediaRef.isEmpty else {
                throw CardEditingError.transport(
                    code: "card_inline_image_media_ref_missing"
                )
            }
            let publicURL = uploaded.publicURL.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard let url = CardEditingMediaURLResolver.resolve(
                publicURL,
                canonicalizeRelativePath: APIConfiguration.resourceURLString
            ) else {
                throw CardEditingError.transport(
                    code: "card_inline_image_url_missing"
                )
            }
            return CardEditingInlineImageUpload(
                mediaRef: mediaRef,
                url: url
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    func replaceBackground(
        cardID: String,
        image: CardEditingImage
    ) async throws -> String {
        do {
            let upload = try await firstValue(
                network.uploadCardMedia(
                    data: image.data,
                    filename: image.filename,
                    mimeType: image.mimeType
                )
            )
            guard let uploaded = upload.data, !uploaded.mediaRef.isEmpty else {
                throw CardEditingError.transport(code: "card_media_ref_missing")
            }
            let response = try await firstValue(
                network.updateCardBackground(
                    cardId: cardID,
                    mediaRef: uploaded.mediaRef
                )
            )
            guard response.success else {
                throw CardEditingError.transport(code: "card_background_rejected")
            }
            return response.data.backgroundMediaRef ?? uploaded.mediaRef
        } catch {
            throw Self.mapError(error)
        }
    }

    func removeBackground(cardID: String) async throws {
        do {
            let response = try await firstValue(
                network.clearCardBackground(cardId: cardID)
            )
            guard response.success else {
                throw CardEditingError.transport(code: "card_background_clear_rejected")
            }
        } catch {
            throw Self.mapError(error)
        }
    }

    private func snapshot(from card: CreateCardData) -> CardEditingSnapshot {
        CardEditingSnapshot(
            id: card.id,
            title: card.title,
            content: card.content,
            contentJSON: card.contentJSON,
            editorAtmosphere: card.editorAtmosphere ?? "none",
            tags: card.tags,
            isPublic: card.isPublic,
            backgroundMediaRef: card.backgroundMediaRef
        )
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

    private static func mapError(_ error: Error) -> CardEditingError {
        if let editingError = error as? CardEditingError {
            return editingError
        }
        guard let networkError = error as? NetworkError else {
            return .transport(code: "card_editing_unknown")
        }
        switch networkError {
        case .api(_, let code, _):
            return .transport(code: code?.lowercased() ?? "card_editing_api")
        case .unauthorized:
            return .transport(code: "card_editing_unauthorized")
        case .forbidden:
            return .transport(code: "card_editing_forbidden")
        case .notFound:
            return .transport(code: "card_editing_not_found")
        case .timeout:
            return .transport(code: "card_editing_timeout")
        case .networkError:
            return .transport(code: "card_editing_offline")
        case .decodingError:
            return .transport(code: "card_editing_decoding")
        case .invalidURL:
            return .transport(code: "card_editing_invalid_url")
        case .noData:
            return .transport(code: "card_editing_no_data")
        case .encodingError:
            return .transport(code: "card_editing_encoding")
        case .serverError(let statusCode, _):
            return .transport(code: "card_editing_server_\(statusCode)")
        case .unknown:
            return .transport(code: "card_editing_unknown")
        }
    }
}
