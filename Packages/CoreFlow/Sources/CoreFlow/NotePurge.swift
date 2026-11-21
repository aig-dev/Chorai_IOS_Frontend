import Foundation

public struct NotePurgeWriteAttempt: Codable, Equatable, Sendable {
    public let version: Int
    public let scope: NoteStoreScope
    public let assetID: String
    public let localID: String
    public let localGeneration: Int64
    public let baseSyncToken: String
    public let requestID: String
    public let requestBody: Data

    public init(scope: NoteStoreScope, assetID: String, localID: String,
                localGeneration: Int64, baseSyncToken: String) throws {
        guard validPurgeID(scope.actorID), validPurgeID(assetID), validPurgeID(localID), localGeneration > 0,
              !scope.environmentID.isEmpty, scope.environmentID.utf8.count <= 2_048,
              !baseSyncToken.isEmpty, baseSyncToken.utf8.count <= 2_048 else {
            throw NoteLocalStoreError.invalidOperation
        }
        self.version = 1; self.scope = scope; self.assetID = assetID; self.localID = localID
        self.localGeneration = localGeneration; self.baseSyncToken = baseSyncToken
        self.requestID = UUID().uuidString
        self.requestBody = try JSONEncoder().encode(["base_sync_token": baseSyncToken])
    }

    public func validate() throws {
        guard version == 1, validPurgeID(scope.actorID), validPurgeID(assetID), validPurgeID(localID), localGeneration > 0,
              !scope.environmentID.isEmpty, scope.environmentID.utf8.count <= 2_048,
              !baseSyncToken.isEmpty, baseSyncToken.utf8.count <= 2_048,
              UUID(uuidString: requestID) != nil, requestBody.count <= 4_096,
              (try? JSONDecoder().decode([String: String].self, from: requestBody)) == ["base_sync_token": baseSyncToken] else {
            throw NoteLocalStoreError.corruptRecord
        }
    }

    public static func isTerminalRejection(status: Int, reason: String) -> Bool {
        (status == 409 && ["stale_version", "note_authority_changed"].contains(reason))
            || (status == 403 && reason == "note_authority_revoked")
            || (status == 400 && reason == "invalid_sync_token")
            || (status == 428 && reason == "precondition_required")
            || (status == 404 && reason == "purge_target_absent")
    }
}

public struct NotePurgeWriteReceipt: Codable, Equatable, Sendable {
    public enum CleanupState: String, Codable, Sendable { case pending = "PENDING", complete = "COMPLETE" }
    public let assetID: String
    public let requestID: String
    public let state: String
    public let activityID: String
    public let actionLogID: String
    public let certificateID: String
    public let cleanupState: CleanupState

    public init(assetID: String, requestID: String, state: String, activityID: String,
                actionLogID: String, certificateID: String, cleanupState: CleanupState) {
        self.assetID = assetID; self.requestID = requestID; self.state = state
        self.activityID = activityID; self.actionLogID = actionLogID
        self.certificateID = certificateID; self.cleanupState = cleanupState
    }

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id", requestID = "request_id", state
        case activityID = "activity_id", actionLogID = "action_log_id"
        case certificateID = "certificate_id", cleanupState = "cleanup_state"
    }

    public func validate(for attempt: NotePurgeWriteAttempt) throws {
        try attempt.validate()
        guard assetID == attempt.assetID, requestID == attempt.requestID, state == "ERASED",
              validPurgeID(activityID), validPurgeID(actionLogID), validPurgeID(certificateID, limit: 96) else {
            throw NoteLocalStoreError.invalidReceipt
        }
    }
}

private func validPurgeID(_ value: String, limit: Int = 64) -> Bool {
    !value.isEmpty && value.utf8.count <= limit && value.utf8.allSatisfy {
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
    }
}
