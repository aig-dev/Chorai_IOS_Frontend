import Foundation

public protocol CoreShareServing: Sendable {
    func preview(cardID: String) async throws -> ShareCardPreview
    func artifactImage(cardID: String, artifactID: String) async throws -> Data
    func pinArtifact(cardID: String, artifactID: String) async throws -> ShareArtifactPin
}
