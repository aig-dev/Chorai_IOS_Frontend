import Foundation

public enum CommunityNotificationKind: String, Equatable, Sendable, Codable {
    case follow
    case like
    case comment
    case system
    case legacy

    public var category: NotificationFilter {
        switch self {
        case .follow, .like, .comment:
            return .activity
        case .system, .legacy:
            return .system
        }
    }
}

public enum CommunityNotificationTarget: Equatable, Sendable, Codable {
    case actor(String)
    case asset(String)
    case legacy
}

public struct NotificationSourceActor: Equatable, Sendable, Codable {
    public let actorID: String
    public let username: String
    public let avatarURL: String?

    public init(actorID: String, username: String, avatarURL: String?) {
        self.actorID = actorID
        self.username = username
        self.avatarURL = avatarURL
    }
}

public struct CommunityNotification: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let kind: CommunityNotificationKind
    public let displayText: String
    public let sourceActor: NotificationSourceActor?
    public let target: CommunityNotificationTarget
    public var isRead: Bool
    public let createdAt: Date

    public init(
        id: String,
        kind: CommunityNotificationKind,
        displayText: String,
        sourceActor: NotificationSourceActor?,
        target: CommunityNotificationTarget,
        isRead: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.displayText = displayText
        self.sourceActor = kind.category == .system ? nil : sourceActor
        self.target = kind.category == .system ? .legacy : target
        self.isRead = isRead
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case displayText
        case sourceActor
        case target
        case isRead
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            kind: try container.decode(
                CommunityNotificationKind.self,
                forKey: .kind
            ),
            displayText: try container.decode(
                String.self,
                forKey: .displayText
            ),
            sourceActor: try container.decodeIfPresent(
                NotificationSourceActor.self,
                forKey: .sourceActor
            ),
            target: try container.decode(
                CommunityNotificationTarget.self,
                forKey: .target
            ),
            isRead: try container.decode(Bool.self, forKey: .isRead),
            createdAt: try container.decode(Date.self, forKey: .createdAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(displayText, forKey: .displayText)
        try container.encodeIfPresent(sourceActor, forKey: .sourceActor)
        try container.encode(target, forKey: .target)
        try container.encode(isRead, forKey: .isRead)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

public struct NotificationPage: Equatable, Sendable {
    public let items: [CommunityNotification]
    public let page: Int
    public let perPage: Int
    public let total: Int
    public let unreadCount: Int

    public init(
        items: [CommunityNotification],
        page: Int,
        perPage: Int,
        total: Int,
        unreadCount: Int
    ) {
        self.items = items
        self.page = page
        self.perPage = perPage
        self.total = total
        self.unreadCount = unreadCount
    }
}

public enum NotificationFilter: String, CaseIterable, Equatable, Sendable, Codable {
    case all
    case unread
    case activity
    case system
}

public enum NotificationInboxOperation: Equatable, Sendable {
    case load
    case loadMore
    case markRead(id: String)
    case markAllRead
}

public enum NotificationInboxError: Error, Equatable, Sendable {
    case invalidActor
    case contract(code: String)
    case unauthorized
    case forbidden
    case notFound
    case transport(code: String)
}

public enum NotificationInboxPhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case empty
    case loadingMore
    case failed(
        operation: NotificationInboxOperation,
        error: NotificationInboxError
    )
}

public struct NotificationActionFailure: Equatable, Sendable {
    public let operation: NotificationInboxOperation
    public let error: NotificationInboxError

    public init(
        operation: NotificationInboxOperation,
        error: NotificationInboxError
    ) {
        self.operation = operation
        self.error = error
    }
}
