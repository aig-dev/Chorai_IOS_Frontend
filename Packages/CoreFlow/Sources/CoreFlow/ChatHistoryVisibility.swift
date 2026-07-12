import Foundation

public protocol ChatHistoryCutoffPersisting: Sendable {
    func cutoff(actorID: String) -> Date?
    func saveCutoff(_ date: Date, actorID: String)
}

public final class UserDefaultsChatHistoryCutoffPersistence:
    ChatHistoryCutoffPersisting,
    @unchecked Sendable
{
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "chorai.chat-history.cutoff"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func cutoff(actorID: String) -> Date? {
        guard let value = defaults.string(forKey: key(actorID)) else { return nil }
        return Self.parse(value)
    }

    public func saveCutoff(_ date: Date, actorID: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        defaults.set(formatter.string(from: date), forKey: key(actorID))
    }

    private func key(_ actorID: String) -> String {
        "\(keyPrefix).\(actorID)"
    }

    private static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

public struct ChatHistoryVisibility: Sendable {
    private let persistence: any ChatHistoryCutoffPersisting

    public init(
        persistence: any ChatHistoryCutoffPersisting =
            UserDefaultsChatHistoryCutoffPersistence()
    ) {
        self.persistence = persistence
    }

    public func clear(actorID: String, at date: Date) {
        persistence.saveCutoff(date, actorID: actorID)
    }

    public func isVisible(timestamp: Date?, actorID: String) -> Bool {
        guard let cutoff = persistence.cutoff(actorID: actorID) else { return true }
        guard let timestamp else { return false }
        return timestamp > cutoff
    }

    public func isVisible(timestampString: String?, actorID: String) -> Bool {
        isVisible(timestamp: Self.parseTimestamp(timestampString), actorID: actorID)
    }

    public static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}
