import Combine
import Foundation

public enum ContextualGuideTipID: String, CaseIterable, Codable, Hashable, Sendable {
    case libraryCreate
    case flowCard
    case flowSpark
    case sparkResume
    case sparkFavorite
    case libraryMergeEntry
    case mergeAction
    case mergeResume

    public var copy: String {
        switch self {
        case .libraryCreate:
            return "Tap + to capture your first note."
        case .flowCard:
            return "Swipe this card to continue."
        case .flowSpark:
            return "Tap Spark to continue from this card."
        case .sparkResume:
            return "Tap Spark to return to your results."
        case .sparkFavorite:
            return "Favorite a result to keep it."
        case .libraryMergeEntry:
            return "Open a note's menu to start Merge."
        case .mergeAction:
            return "Merge two related notes."
        case .mergeResume:
            return "Resume Merge to finish your note."
        }
    }

    public var storageKey: String {
        "\(rawValue).v1"
    }

    public var accessibilityIdentifier: String {
        switch self {
        case .libraryCreate:
            return "library"
        case .flowCard:
            return "flow-card"
        case .flowSpark:
            return "flow-spark"
        case .sparkResume:
            return "spark-resume"
        case .sparkFavorite:
            return "spark-favorite"
        case .libraryMergeEntry:
            return "library-merge-entry"
        case .mergeAction:
            return "merge"
        case .mergeResume:
            return "merge-resume"
        }
    }

    public func matches(onboardingState: String?) -> Bool {
        switch self {
        case .libraryCreate:
            return onboardingState == "elicit_signal"
        case .flowCard:
            return onboardingState == "product_curator_intro"
                || onboardingState == "product_explore_card"
        case .flowSpark:
            return onboardingState == "product_spark_intro"
        case .sparkResume:
            return onboardingState == "product_spark_results"
                || onboardingState == "product_save_material"
        case .sparkFavorite:
            return onboardingState == "product_spark_results"
                || onboardingState == "product_save_material"
        case .libraryMergeEntry:
            return onboardingState == "product_merge_intro"
        case .mergeAction:
            return onboardingState == "product_merge_intro"
        case .mergeResume:
            return onboardingState == "product_merge_preview"
        }
    }
}

public enum ContextualGuideTipOutcome: String, Codable, Equatable, Sendable {
    case dismissed
    case completed
}

public protocol ContextualGuideTipPersisting {
    func outcome(
        actorID: String,
        sessionID: String?,
        tip: ContextualGuideTipID
    ) -> ContextualGuideTipOutcome?
    func save(
        _ outcome: ContextualGuideTipOutcome,
        actorID: String,
        sessionID: String?,
        tip: ContextualGuideTipID
    )
}

public final class UserDefaultsContextualGuideTipPersistence:
    ContextualGuideTipPersisting {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "chorai.onboarding.contextual-tip"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func outcome(
        actorID: String,
        sessionID: String?,
        tip: ContextualGuideTipID
    ) -> ContextualGuideTipOutcome? {
        guard let rawValue = defaults.string(
            forKey: key(actorID: actorID, sessionID: sessionID, tip: tip)
        ) else {
            return nil
        }
        return ContextualGuideTipOutcome(rawValue: rawValue)
    }

    public func save(
        _ outcome: ContextualGuideTipOutcome,
        actorID: String,
        sessionID: String?,
        tip: ContextualGuideTipID
    ) {
        defaults.set(
            outcome.rawValue,
            forKey: key(actorID: actorID, sessionID: sessionID, tip: tip)
        )
    }

    private func key(
        actorID: String,
        sessionID: String?,
        tip: ContextualGuideTipID
    ) -> String {
        if let sessionID {
            return "\(keyPrefix).\(actorID).\(sessionID).\(tip.storageKey)"
        }
        return "\(keyPrefix).\(actorID).\(tip.storageKey)"
    }
}

@MainActor
public final class ContextualGuideTipStore: ObservableObject {
    @Published public private(set) var actorID: String?
    @Published public private(set) var sessionID: String?
    @Published public private(set) var outcomes:
        [ContextualGuideTipID: ContextualGuideTipOutcome] = [:]

    private let persistence: ContextualGuideTipPersisting

    public init(persistence: ContextualGuideTipPersisting) {
        self.persistence = persistence
    }

    public func load(actorID: String) {
        load(actorID: actorID, sessionID: nil)
    }

    public func load(actorID: String, sessionID: String) {
        let normalizedActorID = actorID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedSessionID = sessionID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedActorID.isEmpty,
              !normalizedSessionID.isEmpty else {
            reset()
            return
        }

        self.actorID = normalizedActorID
        self.sessionID = normalizedSessionID
        outcomes = Dictionary(
            uniqueKeysWithValues: ContextualGuideTipID.allCases.compactMap { tip in
                persistence.outcome(
                    actorID: normalizedActorID,
                    sessionID: normalizedSessionID,
                    tip: tip
                )
                    .map { (tip, $0) }
            }
        )
    }

    private func load(actorID: String, sessionID: String?) {
        let normalizedActorID = actorID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedActorID.isEmpty else {
            reset()
            return
        }

        self.actorID = normalizedActorID
        self.sessionID = sessionID
        outcomes = Dictionary(
            uniqueKeysWithValues: ContextualGuideTipID.allCases.compactMap { tip in
                persistence.outcome(
                    actorID: normalizedActorID,
                    sessionID: sessionID,
                    tip: tip
                )
                .map { (tip, $0) }
            }
        )
    }

    public func reset() {
        actorID = nil
        sessionID = nil
        outcomes = [:]
    }

    public func outcome(
        for tip: ContextualGuideTipID
    ) -> ContextualGuideTipOutcome? {
        outcomes[tip]
    }

    public func isVisible(
        _ tip: ContextualGuideTipID,
        onboardingState: String?,
        targetIsVisible: Bool
    ) -> Bool {
        actorID != nil
            && targetIsVisible
            && tip.matches(onboardingState: onboardingState)
            && outcomes[tip] == nil
    }

    public func dismiss(
        _ tip: ContextualGuideTipID,
        onboardingState: String?,
        targetIsVisible: Bool
    ) {
        guard isEligible(
            tip,
            onboardingState: onboardingState,
            targetIsVisible: targetIsVisible
        ) else {
            return
        }
        guard outcomes[tip] != .completed else { return }
        record(.dismissed, for: tip)
    }

    public func complete(
        _ tip: ContextualGuideTipID,
        onboardingState: String?,
        targetIsVisible: Bool
    ) {
        guard isEligible(
            tip,
            onboardingState: onboardingState,
            targetIsVisible: targetIsVisible
        ) else {
            return
        }
        record(.completed, for: tip)
    }

    private func isEligible(
        _ tip: ContextualGuideTipID,
        onboardingState: String?,
        targetIsVisible: Bool
    ) -> Bool {
        actorID != nil
            && targetIsVisible
            && tip.matches(onboardingState: onboardingState)
    }

    private func record(
        _ outcome: ContextualGuideTipOutcome,
        for tip: ContextualGuideTipID
    ) {
        guard let actorID else { return }
        outcomes[tip] = outcome
        persistence.save(
            outcome,
            actorID: actorID,
            sessionID: sessionID,
            tip: tip
        )
    }
}
