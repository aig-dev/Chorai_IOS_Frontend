import Foundation

public enum ChatHistoryCutoffRecord: Equatable, Sendable {
    case missing
    case valid(Date)
    case corrupt
}

public protocol ChatHistoryCutoffPersisting: Sendable {
    func cutoffRecord(actorID: String) -> ChatHistoryCutoffRecord
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

    public func cutoffRecord(actorID: String) -> ChatHistoryCutoffRecord {
        guard let value = defaults.object(forKey: key(actorID)) else {
            return .missing
        }
        if let seconds = value as? Double, seconds.isFinite {
            return .valid(Date(timeIntervalSince1970: seconds))
        }
        if let legacy = value as? String, let date = Self.parse(legacy) {
            return .valid(date)
        }
        return .corrupt
    }

    public func saveCutoff(_ date: Date, actorID: String) {
        defaults.set(date.timeIntervalSince1970, forKey: key(actorID))
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
        switch persistence.cutoffRecord(actorID: actorID) {
        case .missing:
            true
        case .corrupt:
            false
        case let .valid(cutoff):
            timestamp.map { $0 > cutoff } ?? false
        }
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
