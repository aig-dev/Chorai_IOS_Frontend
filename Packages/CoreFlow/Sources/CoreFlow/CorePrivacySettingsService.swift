import Foundation

public protocol CorePrivacySettingsServing: Sendable {
    func privacySettings(actorID: String) async throws -> PrivacySettings
    func updatePrivacySetting(
        actorID: String,
        setting: PrivacySetting,
        enabled: Bool
    ) async throws -> PrivacySettings
}
