import Foundation

public struct PendingInvitationCode: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let actorID: String
    public let code: String
    public let needsRetry: Bool

    public init(actorID: String, code: String, needsRetry: Bool) {
        self.init(
            schemaVersion: Self.currentSchemaVersion,
            actorID: actorID,
            code: code,
            needsRetry: needsRetry
        )
    }

    public init(
        schemaVersion: Int,
        actorID: String,
        code: String,
        needsRetry: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.actorID = actorID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        self.needsRetry = needsRetry
    }
}

public protocol PendingInvitationCodePersisting: Sendable {
    func pending(actorID: String) -> PendingInvitationCode?
    func save(_ pending: PendingInvitationCode)
    func remove(actorID: String)
}

public final class UserDefaultsPendingInvitationCodeStore:
    PendingInvitationCodePersisting,
    @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "chorai.invitation.pending.v1"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func pending(actorID: String) -> PendingInvitationCode? {
        guard let actorID = normalized(actorID) else { return nil }
        let storageKey = key(actorID: actorID)
        guard let data = defaults.data(forKey: storageKey) else { return nil }

        guard let value = try? JSONDecoder().decode(
            PendingInvitationCode.self,
            from: data
        ),
        value.schemaVersion == PendingInvitationCode.currentSchemaVersion,
        value.actorID == actorID,
        InvitationCode.normalized(value.code) != nil else {
            defaults.removeObject(forKey: storageKey)
            return nil
        }
        return value
    }

    public func save(_ pending: PendingInvitationCode) {
        guard let actorID = normalized(pending.actorID),
              let code = InvitationCode.normalized(pending.code) else {
            return
        }
        let value = PendingInvitationCode(
            actorID: actorID,
            code: code,
            needsRetry: pending.needsRetry
        )
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key(actorID: actorID))
    }

    public func remove(actorID: String) {
        guard let actorID = normalized(actorID) else { return }
        defaults.removeObject(forKey: key(actorID: actorID))
    }

    private func key(actorID: String) -> String {
        "\(keyPrefix).\(actorID)"
    }

    private func normalized(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
