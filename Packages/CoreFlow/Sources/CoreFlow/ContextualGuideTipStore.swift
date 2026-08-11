import Combine
import Foundation

public enum ContextualGuideTipID: String, CaseIterable, Codable, Hashable, Sendable {
    case libraryCreate
    case flowSpark
    case sparkFavorite
    case mergeAction

    public var copy: String {
        switch self {
        case .libraryCreate:
            return "Tap + to capture your first note."
        case .flowSpark:
            return "Tap Spark to continue from this card."
        case .sparkFavorite:
            return "Favorite a result to keep it."
        case .mergeAction:
            return "Merge two related notes."
        }
    }

    public var storageKey: String {
        "\(rawValue).v1"
    }

    public var accessibilityIdentifier: String {
        switch self {
        case .libraryCreate:
            return "library"
        case .flowSpark:
            return "flow-spark"
        case .sparkFavorite:
            return "spark-favorite"
        case .mergeAction:
            return "merge"
        }
    }

    public func matches(onboardingState: String?) -> Bool {
        switch self {
        case .libraryCreate:
            return onboardingState == "elicit_signal"
        case .flowSpark:
            return onboardingState == "product_spark_intro"
        case .sparkFavorite:
            return onboardingState == "product_spark_results"
                || onboardingState == "product_save_material"
        case .mergeAction:
            return onboardingState == "product_merge_intro"
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
        tip: ContextualGuideTipID
    ) -> ContextualGuideTipOutcome?
    func save(
        _ outcome: ContextualGuideTipOutcome,
        actorID: String,
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
        tip: ContextualGuideTipID
    ) -> ContextualGuideTipOutcome? {
        guard let rawValue = defaults.string(forKey: key(actorID: actorID, tip: tip)) else {
            return nil
        }
        return ContextualGuideTipOutcome(rawValue: rawValue)
    }

    public func save(
        _ outcome: ContextualGuideTipOutcome,
        actorID: String,
        tip: ContextualGuideTipID
    ) {
        defaults.set(
            outcome.rawValue,
            forKey: key(actorID: actorID, tip: tip)
        )
    }

    private func key(actorID: String, tip: ContextualGuideTipID) -> String {
        "\(keyPrefix).\(actorID).\(tip.storageKey)"
    }
}

@MainActor
public final class ContextualGuideTipStore: ObservableObject {
    @Published public private(set) var actorID: String?
    @Published public private(set) var outcomes:
        [ContextualGuideTipID: ContextualGuideTipOutcome] = [:]

    private let persistence: ContextualGuideTipPersisting

    public init(persistence: ContextualGuideTipPersisting) {
        self.persistence = persistence
    }

    public func load(actorID: String) {
        let normalizedActorID = actorID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedActorID.isEmpty else {
            reset()
            return
        }

        self.actorID = normalizedActorID
        outcomes = Dictionary(
            uniqueKeysWithValues: ContextualGuideTipID.allCases.compactMap { tip in
                persistence.outcome(actorID: normalizedActorID, tip: tip)
                    .map { (tip, $0) }
            }
        )
    }

    public func reset() {
        actorID = nil
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
        persistence.save(outcome, actorID: actorID, tip: tip)
    }
}
