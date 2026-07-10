import Foundation

public protocol OnboardingGuidePersisting {
    func pendingEvidence(
        actorID: String,
        sessionID: String
    ) -> [OnboardingGuideEvidence]
    func savePendingEvidence(
        _ evidence: [OnboardingGuideEvidence],
        actorID: String,
        sessionID: String
    )
    func recordedCardEvidence(
        actorID: String,
        sessionID: String
    ) -> OnboardingGuideEvidence?
    func saveRecordedCardEvidence(
        _ evidence: OnboardingGuideEvidence,
        actorID: String,
        sessionID: String
    )
    func clear(actorID: String, sessionID: String)
}

public final class UserDefaultsOnboardingGuidePersistence: OnboardingGuidePersisting {
    private let defaults: UserDefaults
    private let keyPrefix: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "chorai.onboarding.guide"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func pendingEvidence(
        actorID: String,
        sessionID: String
    ) -> [OnboardingGuideEvidence] {
        guard let data = defaults.data(forKey: pendingKey(actorID, sessionID)) else {
            return []
        }
        return (try? decoder.decode([OnboardingGuideEvidence].self, from: data)) ?? []
    }

    public func savePendingEvidence(
        _ evidence: [OnboardingGuideEvidence],
        actorID: String,
        sessionID: String
    ) {
        let key = pendingKey(actorID, sessionID)
        guard !evidence.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? encoder.encode(evidence) else { return }
        defaults.set(data, forKey: key)
    }

    public func recordedCardEvidence(
        actorID: String,
        sessionID: String
    ) -> OnboardingGuideEvidence? {
        guard let data = defaults.data(forKey: recordKey(actorID, sessionID)) else {
            return nil
        }
        return try? decoder.decode(OnboardingGuideEvidence.self, from: data)
    }

    public func saveRecordedCardEvidence(
        _ evidence: OnboardingGuideEvidence,
        actorID: String,
        sessionID: String
    ) {
        guard case .recordCreated = evidence,
              let data = try? encoder.encode(evidence) else {
            return
        }
        defaults.set(data, forKey: recordKey(actorID, sessionID))
    }

    public func clear(actorID: String, sessionID: String) {
        defaults.removeObject(forKey: pendingKey(actorID, sessionID))
        defaults.removeObject(forKey: recordKey(actorID, sessionID))
    }

    private func pendingKey(_ actorID: String, _ sessionID: String) -> String {
        "\(keyPrefix).\(actorID).\(sessionID).pending"
    }

    private func recordKey(_ actorID: String, _ sessionID: String) -> String {
        "\(keyPrefix).\(actorID).\(sessionID).record"
    }
}
