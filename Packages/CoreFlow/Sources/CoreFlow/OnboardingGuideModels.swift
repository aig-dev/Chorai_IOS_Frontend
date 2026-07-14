import Combine
import Foundation

public struct OnboardingStatusSnapshot: Codable, Equatable, Sendable {
    public let completed: Bool
    public let needsOnboarding: Bool
    public let latestSessionID: String?
    public let activeSessionID: String?
    public let status: String?
    public let state: String?

    public init(
        completed: Bool,
        needsOnboarding: Bool,
        latestSessionID: String?,
        activeSessionID: String?,
        status: String?,
        state: String?
    ) {
        self.completed = completed
        self.needsOnboarding = needsOnboarding
        self.latestSessionID = latestSessionID
        self.activeSessionID = activeSessionID
        self.status = status
        self.state = state
    }

    enum CodingKeys: String, CodingKey {
        case completed
        case needsOnboarding = "needs_onboarding"
        case latestSessionID = "latest_session_id"
        case activeSessionID = "active_session_id"
        case status, state
    }
}

public struct OnboardingGuideChoice: Codable, Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct OnboardingGuideScene: Codable, Equatable, Sendable {
    public let speaker: String
    public let text: String
    public let inputMode: String
    public let choices: [OnboardingGuideChoice]
    public let canSkip: Bool
    public let nextRoute: String?
    public let presentation: String?
    public let targetAnchor: String?
    public let placement: String?
    public let spotlight: Bool
    public let choraMode: String?

    public init(
        speaker: String,
        text: String,
        inputMode: String,
        choices: [OnboardingGuideChoice],
        canSkip: Bool,
        nextRoute: String?,
        presentation: String?,
        targetAnchor: String?,
        placement: String?,
        spotlight: Bool,
        choraMode: String?
    ) {
        self.speaker = speaker
        self.text = text
        self.inputMode = inputMode
        self.choices = choices
        self.canSkip = canSkip
        self.nextRoute = nextRoute
        self.presentation = presentation
        self.targetAnchor = targetAnchor
        self.placement = placement
        self.spotlight = spotlight
        self.choraMode = choraMode
    }

    enum CodingKeys: String, CodingKey {
        case speaker, text
        case inputMode = "input_mode"
        case choices
        case canSkip = "can_skip"
        case nextRoute = "next_route"
        case presentation
        case targetAnchor = "target_anchor"
        case placement, spotlight
        case choraMode = "chora_mode"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speaker = try container.decode(String.self, forKey: .speaker)
        text = try container.decode(String.self, forKey: .text)
        inputMode = try container.decode(String.self, forKey: .inputMode)
        choices = try container.decodeIfPresent(
            [OnboardingGuideChoice].self,
            forKey: .choices
        ) ?? []
        canSkip = try container.decodeIfPresent(Bool.self, forKey: .canSkip) ?? false
        nextRoute = try container.decodeIfPresent(String.self, forKey: .nextRoute)
        presentation = try container.decodeIfPresent(String.self, forKey: .presentation)
        targetAnchor = try container.decodeIfPresent(String.self, forKey: .targetAnchor)
        placement = try container.decodeIfPresent(String.self, forKey: .placement)
        spotlight = try container.decodeIfPresent(Bool.self, forKey: .spotlight) ?? false
        choraMode = try container.decodeIfPresent(String.self, forKey: .choraMode)
    }
}

public struct OnboardingGuideSession: Codable, Equatable, Sendable {
    public let sessionID: String
    public let flowKey: String
    public let flowVersion: Int
    public let status: String
    public let state: String
    public let scene: OnboardingGuideScene

    public init(
        sessionID: String,
        flowKey: String,
        flowVersion: Int,
        status: String,
        state: String,
        scene: OnboardingGuideScene
    ) {
        self.sessionID = sessionID
        self.flowKey = flowKey
        self.flowVersion = flowVersion
        self.status = status
        self.state = state
        self.scene = scene
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case flowKey = "flow_key"
        case flowVersion = "flow_version"
        case status, state, scene
    }
}

public enum OnboardingGuideInput: Equatable, Sendable {
    case text(String)
    case choice(String)
}

extension OnboardingGuideInput: Encodable {
    enum CodingKeys: String, CodingKey {
        case inputType = "input_type"
        case text
        case choiceID = "choice_id"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .inputType)
            try container.encode(text, forKey: .text)
        case .choice(let choiceID):
            try container.encode("choice", forKey: .inputType)
            try container.encode(choiceID, forKey: .choiceID)
        }
    }
}

public enum OnboardingGuideError: Error, Equatable, Sendable {
    case unauthorized
    case offline
    case timeout
    case decoding
    case server
    case unknown
}

public protocol OnboardingGuideServing {
    func status() -> AnyPublisher<OnboardingStatusSnapshot, OnboardingGuideError>
    func start(flowVersion: Int) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError>
    func current() -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError>
    func respond(
        sessionID: String,
        input: OnboardingGuideInput
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError>
    func complete(
        sessionID: String
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError>
    func skip(
        sessionID: String
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError>
}

public enum OnboardingGuideEvidence: Codable, Equatable, Sendable {
    case noteCreated(cardID: String, content: String)
    case deepenChoice(id: String)
    case flowViewed
    case flowCardSaved(assetID: String)
    case flowCardDismissed(assetID: String)
    case sparkStarted(assetID: String)
    case sparkResultsViewed(activityID: String)
    case sparkResultSaved(assetID: String)
    case mergeStarted(jobID: String)
    case mergeCommitted(assetID: String)
    case libraryViewed
}

public enum OnboardingGuidePhase: Equatable, Sendable {
    case idle
    case loading
    case active
    case completed
    case skipped
    case deferred(flowVersion: Int)
    case unavailable
}

public enum OnboardingGuidePrimaryTabDestination: Equatable, Sendable {
    case flow
    case library

    public static func forState(_ state: String) -> Self? {
        switch state {
        case "elicit_signal", "product_merge_intro", "product_library_intro":
            return .library
        case "product_curator_intro", "product_explore_card":
            return .flow
        default:
            return nil
        }
    }
}
