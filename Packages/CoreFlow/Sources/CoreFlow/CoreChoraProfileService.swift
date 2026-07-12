import Foundation

public protocol CoreChoraProfileServing: Sendable {
    func identity(humanActorID: String) async throws -> ChoraIdentity
    func growth(agentActorID: String) async throws -> ChoraGrowthSnapshot?
    func updateDisplayName(agentActorID: String, displayName: String) async throws
    func updatePreferredAddress(
        humanActorID: String,
        value: String?
    ) async throws
    func updateAvatar(agentActorID: String, avatar: ChoraAvatarDraft) async throws
}
