import Combine
import CoreFlow
import Foundation

struct NetworkCommunityProfileService: CoreCommunityProfileServing, Sendable {
    private let network: NetworkManager

    @MainActor
    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func profile(actorID: String) async throws -> CommunityProfile {
        let response = try await firstValue(
            network.getUserProfile(
                actorId: actorID,
                presentsError: false
            )
        )
        guard response.success else {
            throw CommunitySocialError.transport(code: "profile_rejected")
        }
        return CommunityProfile(
            actorID: response.data.id,
            username: response.data.username,
            avatarURL: response.data.avatar,
            bio: response.data.bio,
            followerCount: response.data.followersCount ?? 0,
            followingCount: response.data.followingCount ?? 0,
            isFollowing: response.data.isFollowing ?? false
        )
    }

    func setFollowing(actorID: String, following: Bool) async throws {
        if following {
            let response = try await firstValue(
                network.followUser(
                    targetActorId: actorID,
                    presentsError: false
                )
            )
            guard response.success else {
                throw CommunitySocialError.transport(code: "follow_rejected")
            }
        } else {
            let response = try await firstValue(
                network.unfollowUser(
                    targetActorId: actorID,
                    presentsError: false
                )
            )
            guard response.success else {
                throw CommunitySocialError.transport(code: "unfollow_rejected")
            }
        }
    }

    func followList(
        actorID: String,
        kind: FollowListKind,
        cursor: String?,
        limit: Int
    ) async throws -> FollowListPage {
        let response: FollowListResponse
        switch kind {
        case .followers:
            response = try await firstValue(network.getFollowersList(
                actorId: actorID,
                cursor: cursor,
                limit: limit,
                presentsError: false
            ))
        case .following:
            response = try await firstValue(network.getFollowingList(
                actorId: actorID,
                cursor: cursor,
                limit: limit,
                presentsError: false
            ))
        }
        guard response.success else {
            throw CommunitySocialError.transport(code: "follow_list_rejected")
        }
        return FollowListPage(
            items: response.data.map {
                CommunityActor(
                    actorID: $0.id,
                    username: $0.username,
                    avatarURL: $0.avatar,
                    bio: $0.bio,
                    followerCount: $0.followersCount ?? 0,
                    followingCount: $0.followingCount ?? 0,
                    isFollowing: $0.isFollowing ?? false
                )
            },
            nextCursor: response.nextCursor,
            hasMore: response.hasMore
        )
    }

    func blockedActors(
        cursor: String?,
        limit: Int
    ) async throws -> BlockedActorPage {
        let response = try await firstValue(
            network.getBlockedActors(
                cursor: cursor,
                limit: limit,
                presentsError: false
            )
        )
        guard response.success else {
            throw CommunitySocialError.transport(code: "block_list_rejected")
        }
        return BlockedActorPage(
            items: response.data.items.map {
                BlockedActor(
                    actorID: $0.actorID,
                    username: $0.username,
                    avatarURL: $0.avatarURL,
                    bio: $0.bio,
                    blockedAt: $0.blockedAt
                )
            },
            nextCursor: response.data.nextCursor,
            hasMore: response.data.hasMore
        )
    }

    func block(actorID: String) async throws {
        let response = try await firstValue(
            network.blockUser(
                blockedActorId: actorID,
                presentsError: false
            )
        )
        guard response.success else {
            throw CommunitySocialError.transport(code: "block_rejected")
        }
    }

    func unblock(actorID: String) async throws {
        let response = try await firstValue(
            network.unblockUser(
                blockedActorId: actorID,
                presentsError: false
            )
        )
        guard response.success else {
            throw CommunitySocialError.transport(code: "unblock_rejected")
        }
    }

    @MainActor
    private func firstValue<T: Sendable>(
        _ publisher: @autoclosure @MainActor @Sendable () -> AnyPublisher<T, NetworkError>
    ) async throws -> T {
        do {
            guard let value = try await NetworkManager.firstValue(publisher()) else {
                throw CommunitySocialError.transport(code: "empty_response")
            }
            return value
        } catch let error as CommunitySocialError {
            throw error
        } catch let error as NetworkError {
            throw error.communitySocialError
        } catch {
            throw CommunitySocialError.transport(code: "unknown")
        }
    }
}

private extension NetworkError {
    var communitySocialError: CommunitySocialError {
        switch self {
        case .forbidden:
            .forbidden
        case .notFound:
            .notFound
        case .api(let status, let code, _, _):
            switch status {
            case 403: .forbidden
            case 404: .notFound
            default: .transport(code: code ?? "api_\(status)")
            }
        case .unauthorized:
            .transport(code: "unauthorized")
        case .invalidURL:
            .transport(code: "invalid_url")
        case .noData:
            .transport(code: "no_data")
        case .decodingError:
            .transport(code: "decoding")
        case .encodingError:
            .transport(code: "encoding")
        case .serverError(let status, _):
            .transport(code: "server_\(status)")
        case .networkError:
            .transport(code: "network")
        case .timeout:
            .transport(code: "timeout")
        case .unknown:
            .transport(code: "unknown")
        }
    }
}
