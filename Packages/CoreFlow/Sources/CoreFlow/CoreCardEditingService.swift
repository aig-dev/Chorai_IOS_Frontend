import Foundation

public protocol CoreCardEditingServing: Sendable {
    func create(
        draft: CardEditingDraft,
        createRequestID: String
    ) async throws -> CardEditingSnapshot

    func update(
        cardID: String,
        draft: CardEditingDraft
    ) async throws -> CardEditingSnapshot

    func createLink(_ link: CardEditingLink) async throws -> CardEditingLink
    func deleteLink(_ link: CardEditingLink) async throws
    func fetchLinks(cardID: String) async throws -> [CardEditingLink]

    func uploadInlineImage(
        _ image: CardEditingImage
    ) async throws -> CardEditingInlineImageUpload

    func replaceBackground(
        cardID: String,
        image: CardEditingImage
    ) async throws -> String

    func removeBackground(cardID: String) async throws
}
