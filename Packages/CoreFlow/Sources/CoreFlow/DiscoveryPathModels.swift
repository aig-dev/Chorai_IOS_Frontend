import Foundation

public struct DiscoveryPathCard: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String?
    public let content: String
    public let tags: [String]
    public let createdAt: String
    public let authorActorID: String?
    public let authorName: String
    public let avatarURL: String?
    public let rate: Int

    public init(
        id: String,
        title: String?,
        content: String,
        tags: [String],
        createdAt: String,
        authorActorID: String?,
        authorName: String,
        avatarURL: String?,
        rate: Int
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.tags = tags
        self.createdAt = createdAt
        self.authorActorID = authorActorID
        self.authorName = authorName
        self.avatarURL = avatarURL
        self.rate = rate
    }
}

public struct DiscoveryPathNode: Identifiable, Equatable, Sendable {
    public let card: DiscoveryPathCard
    public let versionID: String
    public let activityID: String
    public let depth: Int

    public var id: String { card.id }

    public init(
        card: DiscoveryPathCard,
        versionID: String,
        activityID: String,
        depth: Int
    ) {
        self.card = card
        self.versionID = versionID
        self.activityID = activityID
        self.depth = depth
    }
}

public struct DiscoveryPathSnapshot: Equatable, Sendable {
    public let collected: DiscoveryPathCard
    public let ancestors: [DiscoveryPathNode]
    public let pathLength: Int

    public init(
        collected: DiscoveryPathCard,
        nodes: [DiscoveryPathNode],
        pathLength: Int
    ) {
        self.collected = collected
        self.pathLength = max(0, pathLength)

        var seen = Set<String>()
        self.ancestors = nodes
            .filter { $0.card.id != collected.id }
            .sorted {
                if $0.depth == $1.depth { return $0.card.id < $1.card.id }
                return $0.depth > $1.depth
            }
            .filter { seen.insert($0.card.id).inserted }
    }
}

public enum DiscoveryPathError: Error, Equatable, Sendable {
    case invalidCard
    case unauthorized
    case forbidden
    case requestFailed(message: String?)
}

public enum DiscoveryPathPhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case empty
    case failed(DiscoveryPathError)
}
