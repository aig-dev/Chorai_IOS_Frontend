import Foundation

public struct ChatSendAttempt: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case awaitingFirstReceipt
        case outcomeUnknown
        case rejected
    }

    public let actorID: String
    public let conversationID: String
    public let requestID: UUID
    public let content: String
    public let referencedAssetID: String?
    public private(set) var state: State

    public init(actorID: String, conversationID: String, requestID: UUID = UUID(),
                content: String, referencedAssetID: String? = nil) {
        self.actorID = actorID
        self.conversationID = conversationID
        self.requestID = requestID
        self.content = content
        self.referencedAssetID = referencedAssetID
        self.state = .awaitingFirstReceipt
    }

    /// Matches Go strings.TrimSpace (Unicode White_Space), including retaining
    /// U+200B, which Foundation's whitespacesAndNewlines would incorrectly trim.
    public var normalizedContent: String {
        let leading = content.unicodeScalars.drop(while: { $0.properties.isWhitespace })
        let trailing = leading.reversed().drop(while: { $0.properties.isWhitespace })
        return String(String.UnicodeScalarView(trailing.reversed()))
    }

    public func uncertain() -> Self {
        var copy = self
        copy.state = .outcomeUnknown
        return copy
    }

    public func isSameSend(as other: Self) -> Bool {
        var left = self
        var right = other
        left.state = .awaitingFirstReceipt
        right.state = .awaitingFirstReceipt
        return left == right
    }

    public func rejected() -> Self {
        var copy = self
        copy.state = .rejected
        return copy
    }
}

public enum ChatSendPersistenceError: Error {
    case invalidRecord
    case recordChanged
    case writeFailed
}

@MainActor
public protocol ChatSendAttemptPersisting {
    func load(actorID: String, conversationID: String) throws -> ChatSendAttempt?
    func save(_ attempt: ChatSendAttempt, replacing expected: ChatSendAttempt?) throws
    func remove(_ expected: ChatSendAttempt) throws
}

/// Owns only a requested send, scoped by the caller's API origin and actor.
/// All operations are synchronous on MainActor, including compare-and-replace.
@MainActor
public final class UserDefaultsChatSendAttemptStore: ChatSendAttemptPersisting {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func load(actorID: String, conversationID: String) throws -> ChatSendAttempt? {
        let key = try key(actorID: actorID, conversationID: conversationID)
        guard let raw = defaults.object(forKey: key) else { return nil }
        guard let data = raw as? Data, data.count <= 16_384 else {
            throw ChatSendPersistenceError.invalidRecord
        }
        let attempt = try JSONDecoder().decode(ChatSendAttempt.self, from: data)
        try validate(attempt)
        guard attempt.actorID == actorID, attempt.conversationID == conversationID else {
            throw ChatSendPersistenceError.invalidRecord
        }
        return attempt
    }

    public func save(_ attempt: ChatSendAttempt, replacing expected: ChatSendAttempt?) throws {
        try validate(attempt)
        let current = try load(actorID: attempt.actorID, conversationID: attempt.conversationID)
        guard current == expected else { throw ChatSendPersistenceError.recordChanged }
        if let expected {
            guard expected.actorID == attempt.actorID,
                  expected.conversationID == attempt.conversationID else {
                throw ChatSendPersistenceError.invalidRecord
            }
            switch expected.state {
            case .awaitingFirstReceipt:
                guard attempt == expected.rejected() || attempt == expected.uncertain() else {
                    throw ChatSendPersistenceError.invalidRecord
                }
            case .outcomeUnknown:
                // A later rejection cannot prove that an earlier attempt did not commit.
                guard attempt == expected else { throw ChatSendPersistenceError.invalidRecord }
            case .rejected:
                guard attempt.state == .awaitingFirstReceipt else {
                    throw ChatSendPersistenceError.invalidRecord
                }
            }
        } else if attempt.state != .awaitingFirstReceipt {
            throw ChatSendPersistenceError.invalidRecord
        }
        let key = try key(actorID: attempt.actorID, conversationID: attempt.conversationID)
        let data = try JSONEncoder().encode(attempt)
        guard data.count <= 16_384 else { throw ChatSendPersistenceError.invalidRecord }
        defaults.set(data, forKey: key)
        guard defaults.synchronize(), defaults.data(forKey: key) == data else {
            throw ChatSendPersistenceError.writeFailed
        }
    }

    public func remove(_ expected: ChatSendAttempt) throws {
        let current = try load(actorID: expected.actorID, conversationID: expected.conversationID)
        guard current == nil || current?.isSameSend(as: expected) == true else {
            throw ChatSendPersistenceError.recordChanged
        }
        let key = try key(actorID: expected.actorID, conversationID: expected.conversationID)
        defaults.removeObject(forKey: key)
        guard defaults.synchronize(), defaults.object(forKey: key) == nil else {
            throw ChatSendPersistenceError.writeFailed
        }
    }

    private func key(actorID: String, conversationID: String) throws -> String {
        for value in [actorID, conversationID] {
            guard value.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else {
                throw ChatSendPersistenceError.invalidRecord
            }
        }
        return "\(keyPrefix).\(actorID).\(conversationID)"
    }

    private func validate(_ attempt: ChatSendAttempt) throws {
        _ = try key(actorID: attempt.actorID, conversationID: attempt.conversationID)
        guard attempt.content.unicodeScalars.count <= 1_000,
              !attempt.normalizedContent.isEmpty,
              attempt.normalizedContent.utf8.count <= 1_000,
              attempt.requestID.uuidString != "00000000-0000-0000-0000-000000000000" else {
            throw ChatSendPersistenceError.invalidRecord
        }
        if let reference = attempt.referencedAssetID {
            guard reference.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else {
                throw ChatSendPersistenceError.invalidRecord
            }
        }
    }
}
