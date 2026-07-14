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

    func createLink(_ link: CardEditingLink) async throws
    func deleteLink(_ link: CardEditingLink) async throws

    func replaceBackground(
        cardID: String,
        image: CardEditingImage
    ) async throws -> String

    func removeBackground(cardID: String) async throws
}
