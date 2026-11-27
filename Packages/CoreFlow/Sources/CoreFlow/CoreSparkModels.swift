import Foundation

public enum SparkBucket: String, Codable, CaseIterable, Sendable {
    case related
    case angles
    case keywords
}

public struct SparkResult: Identifiable, Equatable, Sendable {
    public var id: String { card.id }
    public let card: FlowCard
    public let bucket: SparkBucket
    public let score: Double
    public let resultID: String?

    public init(
        card: FlowCard,
        bucket: SparkBucket,
        score: Double,
        resultID: String?
    ) {
        self.card = card
        self.bucket = bucket
        self.score = score
        self.resultID = resultID
    }
}

public struct SparkActivityPage: Equatable, Sendable {
    public let activityID: String
    public let parentActivityID: String?
    public let rootActivityID: String
    public let chainDepth: Int
    public let sourceAssetID: String
    public let groups: [SparkBucket: [SparkResult]]
    public let createdAt: Date?

    public var orderedResults: [SparkResult] {
        SparkResultOrdering.flatten(groups: groups)
    }

    public init(
        activityID: String,
        parentActivityID: String?,
        rootActivityID: String,
        chainDepth: Int,
        sourceAssetID: String,
        groups: [SparkBucket: [SparkResult]],
        createdAt: Date?
    ) {
        self.activityID = activityID
        self.parentActivityID = parentActivityID
        self.rootActivityID = rootActivityID
        self.chainDepth = chainDepth
        self.sourceAssetID = sourceAssetID
        self.groups = groups
        self.createdAt = createdAt
    }
}

public struct SparkHistoryEntry: Equatable, Sendable {
    public let activityID: String
    public let parentActivityID: String?
    public let sourceAssetID: String
    public let rootActivityID: String
    public let chainDepth: Int
    public let createdAt: Date

    public init(
        activityID: String,
        parentActivityID: String?,
        sourceAssetID: String,
        rootActivityID: String,
        chainDepth: Int,
        createdAt: Date
    ) {
        self.activityID = activityID
        self.parentActivityID = parentActivityID
        self.sourceAssetID = sourceAssetID
        self.rootActivityID = rootActivityID
        self.chainDepth = chainDepth
        self.createdAt = createdAt
    }
}

public struct SparkMorePage: Equatable, Sendable {
    public let results: [SparkResult]
    public let nextCursor: String?
    public let round: Int
    public let sourceAssetID: String

    public init(
        results: [SparkResult],
        nextCursor: String?,
        round: Int,
        sourceAssetID: String
    ) {
        self.results = results
        self.nextCursor = nextCursor
        self.round = round
        self.sourceAssetID = sourceAssetID
    }
}

public enum SparkResultOrdering {
    public static func flatten(
        groups: [SparkBucket: [SparkResult]]
    ) -> [SparkResult] {
        var seenAssetIDs = Set<String>()
        return SparkBucket.allCases
            .flatMap { groups[$0] ?? [] }
            .filter { seenAssetIDs.insert($0.id).inserted }
    }
}

public enum CoreSparkError: Error, Equatable, Sendable {
    case unauthorized
    case forbidden
    case notFound
    case insufficientCredit
    case maximumDepth
    case retrievalUnavailable
    case resultsUnavailable(activityID: String, rootActivityID: String, chainDepth: Int)
    case offline
    case timeout
    case decoding
    case server
    case unknown
}

public enum SparkSessionPhase: Equatable, Sendable {
    case idle
    case loadingSource
    case triggering
    case reconciling
    case loaded
    case replaying
    case empty
    case failed(String)
}

public enum SparkNotice: Equatable, Sendable {
    case saveFailed
    case moreFailed
}

public struct SparkChainNode: Codable, Equatable, Identifiable, Sendable {
    public var id: String { activityID }
    public let sourceAssetID: String
    public let sourcePreview: String
    public let activityID: String
    public let parentActivityID: String?
    public let rootActivityID: String
    public let chainDepth: Int
    public var visibleIndex: Int

    public init(
        sourceAssetID: String,
        sourcePreview: String,
        activityID: String,
        parentActivityID: String?,
        rootActivityID: String,
        chainDepth: Int,
        visibleIndex: Int
    ) {
        self.sourceAssetID = sourceAssetID
        self.sourcePreview = sourcePreview
        self.activityID = activityID
        self.parentActivityID = parentActivityID
        self.rootActivityID = rootActivityID
        self.chainDepth = chainDepth
        self.visibleIndex = visibleIndex
    }
}

public struct PendingSparkTrigger: Codable, Equatable, Sendable {
    public let sourceAssetID: String
    public let sourcePreview: String
    public let parentActivityID: String?
    public let startedAt: Date
    public let priorActivityID: String?
    public let priorVisibleIndex: Int

    public init(
        sourceAssetID: String,
        sourcePreview: String,
        parentActivityID: String?,
        startedAt: Date,
        priorActivityID: String?,
        priorVisibleIndex: Int
    ) {
        self.sourceAssetID = sourceAssetID
        self.sourcePreview = sourcePreview
        self.parentActivityID = parentActivityID
        self.startedAt = startedAt
        self.priorActivityID = priorActivityID
        self.priorVisibleIndex = priorVisibleIndex
    }
}

public struct SparkSessionSnapshot: Codable, Equatable, Sendable {
    public let actorID: String
    public let rootSourceAssetID: String
    public var nodes: [SparkChainNode]
    public var activeActivityID: String?
    public var pendingTrigger: PendingSparkTrigger?
    public var didShowUpwardCue: Bool

    public init(
        actorID: String,
        rootSourceAssetID: String,
        nodes: [SparkChainNode],
        activeActivityID: String?,
        pendingTrigger: PendingSparkTrigger?,
        didShowUpwardCue: Bool
    ) {
        self.actorID = actorID
        self.rootSourceAssetID = rootSourceAssetID
        self.nodes = nodes
        self.activeActivityID = activeActivityID
        self.pendingTrigger = pendingTrigger
        self.didShowUpwardCue = didShowUpwardCue
    }
}

public enum SparkGestureDecision: Equatable, Sendable {
    case next
    case cancel
}

public enum SparkGestureResolver {
    public static func resolve(
        translationX: Double,
        translationY: Double,
        predictedEndX: Double,
        predictedEndY: Double,
        translationThreshold: Double = 88,
        predictionThreshold: Double = 132,
        dominanceRatio: Double = 1.25
    ) -> SparkGestureDecision {
        let horizontalMagnitude = max(abs(translationX), abs(predictedEndX))
        let verticalMagnitude = max(abs(translationY), abs(predictedEndY))

        if horizontalMagnitude >= verticalMagnitude * dominanceRatio {
            if abs(translationX) >= translationThreshold {
                return .next
            }
            if abs(predictedEndX) >= predictionThreshold {
                return .next
            }
            return .cancel
        }

        return .cancel
    }
}
