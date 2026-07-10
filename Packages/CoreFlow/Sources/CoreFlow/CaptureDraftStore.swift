import Foundation

public protocol CaptureDraftPersisting {
    func text(for actorID: String) -> String
    func save(_ text: String, for actorID: String)
    func remove(for actorID: String)
}

public final class UserDefaultsCaptureDraftStore: CaptureDraftPersisting {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "chorai.quick-capture"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func text(for actorID: String) -> String {
        defaults.string(forKey: key(for: actorID)) ?? ""
    }

    public func save(_ text: String, for actorID: String) {
        defaults.set(text, forKey: key(for: actorID))
    }

    public func remove(for actorID: String) {
        defaults.removeObject(forKey: key(for: actorID))
    }

    private func key(for actorID: String) -> String {
        "\(keyPrefix).\(actorID)"
    }
}
