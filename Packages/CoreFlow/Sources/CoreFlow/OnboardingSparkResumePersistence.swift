import Foundation

public struct OnboardingSparkResumeMetadata: Codable, Equatable, Sendable {
    public let actorID: String
    public let sessionID: String
    public let rootSourceAssetID: String

    public init(
        actorID: String,
        sessionID: String,
        rootSourceAssetID: String
    ) {
        self.actorID = actorID
        self.sessionID = sessionID
        self.rootSourceAssetID = rootSourceAssetID
    }
}

public protocol OnboardingSparkResumePersisting {
    func metadata(
        actorID: String,
        sessionID: String
    ) -> OnboardingSparkResumeMetadata?

    func save(_ metadata: OnboardingSparkResumeMetadata)

    func remove(actorID: String, sessionID: String)
}

public final class UserDefaultsOnboardingSparkResumeStore:
    OnboardingSparkResumePersisting
{
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "chorai.onboarding.spark.resume"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func metadata(
        actorID: String,
        sessionID: String
    ) -> OnboardingSparkResumeMetadata? {
        let storageKey = key(actorID: actorID, sessionID: sessionID)
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }
        do {
            let metadata = try JSONDecoder().decode(
                OnboardingSparkResumeMetadata.self,
                from: data
            )
            guard metadata.actorID == actorID,
                  metadata.sessionID == sessionID,
                  !metadata.rootSourceAssetID
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty else {
                defaults.removeObject(forKey: storageKey)
                return nil
            }
            return metadata
        } catch {
            defaults.removeObject(forKey: storageKey)
            return nil
        }
    }

    public func save(_ metadata: OnboardingSparkResumeMetadata) {
        guard let data = try? JSONEncoder().encode(metadata) else {
            return
        }
        defaults.set(
            data,
            forKey: key(
                actorID: metadata.actorID,
                sessionID: metadata.sessionID
            )
        )
    }

    public func remove(actorID: String, sessionID: String) {
        defaults.removeObject(forKey: key(actorID: actorID, sessionID: sessionID))
    }

    private func key(actorID: String, sessionID: String) -> String {
        "\(keyPrefix).\(actorID).\(sessionID)"
    }
}
