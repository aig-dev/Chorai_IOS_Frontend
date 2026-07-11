public protocol CoreCommunityProfileServing: Sendable {
    func profile(actorID: String) async throws -> CommunityProfile
    func setFollowing(actorID: String, following: Bool) async throws
    func followList(
        actorID: String,
        kind: FollowListKind,
        cursor: String?,
        limit: Int
    ) async throws -> FollowListPage
    func blockedActors(
        cursor: String?,
        limit: Int
    ) async throws -> BlockedActorPage
    func block(actorID: String) async throws
    func unblock(actorID: String) async throws
}
