import CryptoKit
import Foundation

public enum NotePrivacyError: LocalizedError, Equatable {
    case invalidResponse, invalidCommand, pendingCommand, stalePolicy, idempotencyConflict
    case admission(String), outcomeUnknown, rejected(Int, String)

    public var errorDescription: String? {
        switch self {
        case .stalePolicy: "The audience changed. Open the note audience and choose again."
        case .idempotencyConflict: "The server could not match the original command. Its request has been retained."
        case .pendingCommand, .outcomeUnknown: "Open the note audience to check and retry the previous change."
        case .invalidResponse, .invalidCommand, .rejected: "The audience change could not be verified."
        case .admission: "Sign in to an account with access to this note."
        }
    }
}

public struct NotePrivacyPolicy: Equatable, Sendable {
    public enum Audience: String, Codable, Sendable {
        case PUBLIC, PRIVATE, COMMUNITY, WORKSPACE
        public var isPublic: Bool { self == .PUBLIC || self == .COMMUNITY }
    }
    public let assetID: String
    public let audience: Audience
    public let spaceID: String?
    public let token: String
}

public struct NotePrivacyCommand: Codable, Equatable, Sendable {
    public let version: Int
    public let action: String
    public let path: String
    public let scope: NoteStoreScope
    public let assetID: String
    public let requestID: UUID
    public let base: String
    public let desired: NotePrivacyPolicy.Audience
    public let bytes: Data
}

public enum NotePrivacyWire {
    public static func validID(_ id: String) -> Bool {
        id.range(of: #"\A[A-Za-z0-9_-]{1,64}\z"#, options: .regularExpression) != nil
    }
    static func validToken(_ token: String) -> Bool {
        token.range(of: #"\Avp1\.[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]\z"#, options: .regularExpression) != nil
    }
    private static func nullableID(_ field: Any?) throws -> String? {
        if field is NSNull { return nil }
        guard let id = field as? String, validID(id) else { throw NotePrivacyError.invalidResponse }
        return id
    }

    public static func decode(status: Int, data: Data, assetID: String,
                              command: NotePrivacyCommand? = nil) throws -> NotePrivacyPolicy {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = root["success"] as? NSNumber, CFGetTypeID(success) == CFBooleanGetTypeID()
        else { throw NotePrivacyError.invalidResponse }
        guard status == 200, success.boolValue else {
            guard !success.boolValue else { throw NotePrivacyError.invalidResponse }
            if let code = root["error_code"] as? String { throw NotePrivacyError.admission(code) }
            guard let error = root["error"] as? [String: String], let reason = error["reason"],
                  let code = error["code"], error["message"] != nil else { throw NotePrivacyError.invalidResponse }
            switch (status, code, reason) {
            case (409, "stale_policy", "stale_policy"): throw NotePrivacyError.stalePolicy
            case (409, "idempotency_conflict", "idempotency_conflict"): throw NotePrivacyError.idempotencyConflict
            case (503, "action_outcome_unknown", "action_outcome_unknown"): throw NotePrivacyError.outcomeUnknown
            default: throw NotePrivacyError.rejected(status, reason)
            }
        }
        guard Set(root.keys).isSubset(of: ["success", "data", "meta"]), root["meta"] == nil || root["meta"] is [String: Any],
              let payload = root["data"] as? [String: Any],
              Set(payload.keys) == (command == nil ? ["current_policy"] : ["current_policy", "visibility_receipt"]),
              let policy = payload["current_policy"] as? [String: Any],
              Set(policy.keys) == ["asset_id", "visibility", "space_id", "policy_token"],
              validID(assetID), policy["asset_id"] as? String == assetID,
              let value = policy["visibility"] as? String, let audience = NotePrivacyPolicy.Audience(rawValue: value),
              let token = policy["policy_token"] as? String, validToken(token) else { throw NotePrivacyError.invalidResponse }
        let current = try NotePrivacyPolicy(assetID: assetID, audience: audience, spaceID: nullableID(policy["space_id"]), token: token)
        if let command {
            guard command.assetID == assetID, let receipt = payload["visibility_receipt"] as? [String: Any],
                  Set(receipt.keys) == ["action", "client_request_id", "actor_id", "asset_id", "requested_visibility",
                      "requested_space_id", "base_policy_token", "result_policy_token", "activity_id", "action_log_id"],
                  receipt["action"] as? String == "SET_VISIBILITY",
                  receipt["client_request_id"] as? String == command.requestID.uuidString,
                  receipt["actor_id"] as? String == command.scope.actorID,
                  receipt["asset_id"] as? String == assetID,
                  receipt["requested_visibility"] as? String == command.desired.rawValue,
                  receipt["requested_space_id"] is NSNull, receipt["base_policy_token"] as? String == command.base,
                  let result = receipt["result_policy_token"] as? String, validToken(result), result != command.base,
                  (result != token || audience == command.desired),
                  let activity = receipt["activity_id"] as? String, validID(activity),
                  let log = receipt["action_log_id"] as? String, validID(log) else { throw NotePrivacyError.invalidResponse }
        }
        return current
    }
}

/// A slot belongs to the canonical server asset, including cards outside the local Library.
public actor NotePrivacyJournal {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }

    private func file(_ scope: NoteStoreScope, _ assetID: String) throws -> URL {
        guard NotePrivacyWire.validID(assetID), NotePrivacyWire.validID(scope.actorID),
              !scope.environmentID.isEmpty, scope.environmentID.utf8.count <= 2048 else { throw NotePrivacyError.invalidCommand }
        let key = try JSONEncoder().encode([scope.environmentID, scope.actorID, assetID])
        return directory.appendingPathComponent(SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined())
    }

    private func body(_ base: String, _ desired: NotePrivacyPolicy.Audience) throws -> Data {
        guard NotePrivacyWire.validToken(base), desired == .PUBLIC || desired == .PRIVATE else { throw NotePrivacyError.invalidCommand }
        return try JSONSerialization.data(withJSONObject: ["base_policy_token": base, "visibility": desired.rawValue], options: [.sortedKeys])
    }

    public func pending(scope: NoteStoreScope, assetID: String) throws -> NotePrivacyCommand? {
        let url = try file(scope, assetID)
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard let size, (1...8192).contains(size) else { throw NotePrivacyError.invalidCommand }
            let saved = try JSONDecoder().decode(NotePrivacyCommand.self, from: Data(contentsOf: url))
            guard saved.version == 1, saved.action == "SET_VISIBILITY", validPath(saved.path),
                  saved.scope == scope, saved.assetID == assetID,
                  saved.bytes == (try body(saved.base, saved.desired)) else { throw NotePrivacyError.invalidCommand }
            return saved
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    private func validPath(_ path: String) -> Bool {
        path.utf8.count <= 256 && path.range(of: #"\A/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\z"#, options: .regularExpression) != nil
    }

    public func begin(scope: NoteStoreScope, path: String, observed: NotePrivacyPolicy, desired: NotePrivacyPolicy.Audience, requestID: UUID = UUID()) throws -> NotePrivacyCommand {
        let url = try file(scope, observed.assetID)
        guard validPath(path) else { throw NotePrivacyError.invalidCommand }
        let command = try NotePrivacyCommand(version: 1, action: "SET_VISIBILITY", path: path, scope: scope, assetID: observed.assetID, requestID: requestID, base: observed.token,
            desired: desired, bytes: body(observed.token, desired))
        if let retained = try pending(scope: scope, assetID: observed.assetID) {
            guard retained == command else { throw NotePrivacyError.pendingCommand }
            return retained
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(command).write(to: url, options: .atomic)
        guard try pending(scope: scope, assetID: observed.assetID) == command else { throw NotePrivacyError.invalidCommand }
        return command
    }

    public func settle(_ command: NotePrivacyCommand) throws {
        guard try pending(scope: command.scope, assetID: command.assetID) == command else { throw NotePrivacyError.invalidCommand }
        try FileManager.default.removeItem(at: file(command.scope, command.assetID))
    }
}

public struct NotePrivacyObservation: Equatable, Sendable {
    public let scope: NoteStoreScope
    public let decisionID = UUID()
    public let session: UInt64
    public let policy: NotePrivacyPolicy
    public let pending: NotePrivacyCommand?

    public init(scope: NoteStoreScope, session: UInt64, policy: NotePrivacyPolicy, pending: NotePrivacyCommand?) {
        self.scope = scope
        self.session = session
        self.policy = policy
        self.pending = pending
    }
}
