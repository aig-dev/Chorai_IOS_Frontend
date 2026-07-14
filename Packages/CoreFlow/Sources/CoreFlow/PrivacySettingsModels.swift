import Foundation

public enum PrivacySetting: String, CaseIterable, Equatable, Hashable, Sendable {
    case showEmail = "show_email"
    case showPhone = "show_phone"
    case showLocation = "show_location"
    case showBirthday = "show_birthday"
    case allowFollow = "allow_follow"
    case showFollowLists = "show_follow_lists"
}

public struct PrivacySettings: Equatable, Sendable {
    public var showEmail: Bool
    public var showPhone: Bool
    public var showLocation: Bool
    public var showBirthday: Bool
    public var allowFollow: Bool
    public var showFollowLists: Bool

    public init(
        showEmail: Bool,
        showPhone: Bool,
        showLocation: Bool,
        showBirthday: Bool,
        allowFollow: Bool,
        showFollowLists: Bool
    ) {
        self.showEmail = showEmail
        self.showPhone = showPhone
        self.showLocation = showLocation
        self.showBirthday = showBirthday
        self.allowFollow = allowFollow
        self.showFollowLists = showFollowLists
    }

    public func value(for setting: PrivacySetting) -> Bool {
        switch setting {
        case .showEmail: showEmail
        case .showPhone: showPhone
        case .showLocation: showLocation
        case .showBirthday: showBirthday
        case .allowFollow: allowFollow
        case .showFollowLists: showFollowLists
        }
    }

    public func setting(_ setting: PrivacySetting, to enabled: Bool) -> Self {
        var result = self
        switch setting {
        case .showEmail: result.showEmail = enabled
        case .showPhone: result.showPhone = enabled
        case .showLocation: result.showLocation = enabled
        case .showBirthday: result.showBirthday = enabled
        case .allowFollow: result.allowFollow = enabled
        case .showFollowLists: result.showFollowLists = enabled
        }
        return result
    }
}

public enum PrivacySettingsError: Error, Equatable, Sendable {
    case invalidActor
    case unauthorized
    case contract(code: String)
    case requestFailed(message: String?)
}

public enum PrivacySettingsPhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed(PrivacySettingsError)
}

public struct PrivacyUpdateIntent: Equatable, Sendable {
    public let setting: PrivacySetting
    public let enabled: Bool

    public init(setting: PrivacySetting, enabled: Bool) {
        self.setting = setting
        self.enabled = enabled
    }
}
