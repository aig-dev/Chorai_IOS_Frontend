import Foundation

public struct CommunityProfile: Equatable, Sendable {
    public let actorID: String
    public let username: String
    public let avatarURL: String?
    public let bio: String?
    public let followerCount: Int
    public let followingCount: Int
    public let isFollowing: Bool

    public init(
        actorID: String,
        username: String,
        avatarURL: String?,
        bio: String?,
        followerCount: Int,
        followingCount: Int,
        isFollowing: Bool
    ) {
        self.actorID = actorID
        self.username = username
        self.avatarURL = avatarURL
        self.bio = bio
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.isFollowing = isFollowing
    }
}

public enum FollowListKind: String, Equatable, Sendable {
    case followers
    case following
}

public struct CommunityActor: Equatable, Identifiable, Sendable {
    public var id: String { actorID }

    public let actorID: String
    public let username: String
    public let avatarURL: String?
    public let bio: String?
    public let followerCount: Int
    public let followingCount: Int
    public let isFollowing: Bool

    public init(
        actorID: String,
        username: String,
        avatarURL: String?,
        bio: String?,
        followerCount: Int,
        followingCount: Int,
        isFollowing: Bool
    ) {
        self.actorID = actorID
        self.username = username
        self.avatarURL = avatarURL
        self.bio = bio
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.isFollowing = isFollowing
    }
}

public struct FollowListPage: Equatable, Sendable {
    public let items: [CommunityActor]
    public let nextCursor: String?
    public let hasMore: Bool

    public init(
        items: [CommunityActor],
        nextCursor: String?,
        hasMore: Bool
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

public struct BlockedActor: Equatable, Identifiable, Sendable {
    public var id: String { actorID }

    public let actorID: String
    public let username: String
    public let avatarURL: String?
    public let bio: String?
    public let blockedAt: String

    public init(
        actorID: String,
        username: String,
        avatarURL: String?,
        bio: String?,
        blockedAt: String
    ) {
        self.actorID = actorID
        self.username = username
        self.avatarURL = avatarURL
        self.bio = bio
        self.blockedAt = blockedAt
    }
}

public struct BlockedActorPage: Equatable, Sendable {
    public let items: [BlockedActor]
    public let nextCursor: String?
    public let hasMore: Bool

    public init(
        items: [BlockedActor],
        nextCursor: String?,
        hasMore: Bool
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

public enum CommunitySocialError: Error, Equatable, Sendable {
    case invalidActor
    case forbidden
    case notFound
    case transport(code: String)
}

public enum CommunityProfileOperation: Equatable, Sendable {
    case load
    case follow
    case block
}

public enum CommunityProfilePhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case mutatingFollow(targetFollowing: Bool)
    case blocking
    case blocked
    case failed(
        operation: CommunityProfileOperation,
        error: CommunitySocialError
    )
}
