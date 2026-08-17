import Foundation

public struct ChoraAvatarUpdate: Equatable, Sendable {
    public static let notification = Notification.Name(
        "com.chorai.chora-profile.avatar-updated"
    )

    public static let actorIDUserInfoKey = "actor_id"
    public static let avatarURLUserInfoKey = "avatar_url"

    public let actorID: String
    public let avatarURL: String

    public init?(actorID: String, avatarURL: String) {
        let normalizedActorID = actorID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedAvatarURL = avatarURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedActorID.isEmpty, !normalizedAvatarURL.isEmpty else {
            return nil
        }
        self.actorID = normalizedActorID
        self.avatarURL = normalizedAvatarURL
    }

    public init?(notification: Notification) {
        guard notification.name == Self.notification,
              let actorID = notification.userInfo?[Self.actorIDUserInfoKey] as? String,
              let avatarURL = notification.userInfo?[Self.avatarURLUserInfoKey] as? String else {
            return nil
        }
        self.init(actorID: actorID, avatarURL: avatarURL)
    }

    public func post() {
        NotificationCenter.default.post(
            name: Self.notification,
            object: nil,
            userInfo: [
                Self.actorIDUserInfoKey: actorID,
                Self.avatarURLUserInfoKey: avatarURL
            ]
        )
    }
}
