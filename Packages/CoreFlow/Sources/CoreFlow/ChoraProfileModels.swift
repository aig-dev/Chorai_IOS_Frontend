import Foundation

public struct ChoraIdentity: Codable, Equatable, Sendable {
    public let humanActorID: String
    public let agentActorID: String
    public let displayName: String
    public let avatarURL: String?
    public let preferredAddress: String?

    public init(
        humanActorID: String,
        agentActorID: String,
        displayName: String,
        avatarURL: String?,
        preferredAddress: String?
    ) {
        self.humanActorID = humanActorID
        self.agentActorID = agentActorID
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.preferredAddress = preferredAddress
    }
}

public struct ChoraAvatarDraft: Equatable, Sendable {
    public let data: Data
    public let filename: String
    public let mimeType: String

    public init(data: Data, filename: String, mimeType: String) {
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
    }
}

public enum KnownChoraGrowthStage: Int, CaseIterable, Codable, Sendable {
    case initial = 0
    case trace = 1
    case thread = 2
    case weave = 3
    case coThink = 4
    case secondVoice = 5

    public var displayName: String {
        switch self {
        case .initial: "Initial"
        case .trace: "Trace"
        case .thread: "Thread"
        case .weave: "Weave"
        case .coThink: "Co-Think"
        case .secondVoice: "Second Voice"
        }
    }
}

public struct ChoraGrowthStage: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public var knownValue: KnownChoraGrowthStage? {
        KnownChoraGrowthStage(rawValue: rawValue)
    }

    public var displayName: String? {
        knownValue?.displayName
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum KnownChoraGrowthDimension: String, CaseIterable, Codable, Sendable {
    case curiosity
    case insight
    case creativity
    case empathy
    case judgment
    case resonance

    public var displayName: String {
        rawValue.capitalized
    }
}

public struct ChoraGrowthDimension: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var knownValue: KnownChoraGrowthDimension? {
        KnownChoraGrowthDimension(rawValue: rawValue)
    }

    public var displayName: String? {
        knownValue?.displayName
    }

    public static let curiosity = Self(rawValue: "curiosity")
    public static let insight = Self(rawValue: "insight")
    public static let creativity = Self(rawValue: "creativity")
    public static let empathy = Self(rawValue: "empathy")
    public static let judgment = Self(rawValue: "judgment")
    public static let resonance = Self(rawValue: "resonance")

    public static let canonicalRenderOrder: [Self] = [
        .curiosity,
        .insight,
        .creativity,
        .empathy,
        .judgment,
        .resonance
    ]

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ChoraGrowthDimensionValue: Codable, Equatable, Sendable {
    public let dimension: ChoraGrowthDimension
    public let value: Double

    public init(dimension: ChoraGrowthDimension, value: Double) {
        self.dimension = dimension
        self.value = value
    }

    public var displayValue: Double? {
        guard dimension.knownValue != nil,
              value.isFinite,
              (0...12).contains(value) else {
            return nil
        }
        return value
    }
}

public struct ChoraGrowthSnapshot: Codable, Equatable, Sendable {
    public let version: String
    public let committedStage: ChoraGrowthStage
    public let dimensions: [ChoraGrowthDimensionValue]
    public let computedAt: Date

    public init(
        version: String,
        committedStage: ChoraGrowthStage,
        dimensions: [ChoraGrowthDimensionValue],
        computedAt: Date
    ) {
        self.version = version
        self.committedStage = committedStage
        self.dimensions = dimensions
        self.computedAt = computedAt
    }

    public var canonicalDisplayValues: [ChoraGrowthDimensionValue] {
        ChoraGrowthDimension.canonicalRenderOrder.compactMap { dimension in
            dimensions.first { value in
                value.dimension == dimension && value.displayValue != nil
            }
        }
    }
}

public enum ChoraProfileField: Hashable, Sendable {
    case displayName
    case preferredAddress
    case avatar
}

public enum ChoraProfileError: Error, Equatable, Sendable {
    case invalidHumanActor
    case humanActorMismatch
    case missingAgentActor
    case humanActorUsedAsAgent
    case agentActorChanged
    case requestFailed
}

public enum ChoraProfilePhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed(ChoraProfileError)
}

public enum ChoraGrowthPhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case unavailable(ChoraGrowthUnavailableReason)
}

public enum ChoraGrowthUnavailableReason: Equatable, Sendable {
    case noSnapshot
    case requestFailed(ChoraProfileError)
}
