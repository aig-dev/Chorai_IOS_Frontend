import Foundation

public struct MergePendingArtifactSave: Codable, Equatable, Sendable {
    public let idempotencyKey: String
    public let baseRevision: Int
    public let baseDocumentHash: String
    public let documentJSON: Data
    public let tags: [String]

    public init(
        idempotencyKey: String,
        baseRevision: Int,
        baseDocumentHash: String,
        documentJSON: Data,
        tags: [String]
    ) {
        self.idempotencyKey = idempotencyKey
        self.baseRevision = baseRevision
        self.baseDocumentHash = baseDocumentHash
        self.documentJSON = documentJSON
        self.tags = tags
    }
}

public struct MergeArtifactDraftValidationRejection: Codable, Equatable, Sendable {
    public let idempotencyKey: String
    public let code: String?

    public init(idempotencyKey: String, code: String?) {
        self.idempotencyKey = idempotencyKey
        self.code = code
    }
}

public struct MergeArtifactDraftSnapshot: Codable, Equatable, Sendable {
    public let baseRevision: Int
    public let baseDocumentHash: String
    public let documentJSON: Data
    public let tags: [String]
    public let rate: Int
    public let preservationManifest: Data
    public let pendingSave: MergePendingArtifactSave?
    public let validationRejection: MergeArtifactDraftValidationRejection?

    public init(
        baseRevision: Int,
        baseDocumentHash: String,
        documentJSON: Data,
        tags: [String],
        rate: Int,
        preservationManifest: Data,
        pendingSave: MergePendingArtifactSave?,
        validationRejection: MergeArtifactDraftValidationRejection? = nil
    ) {
        self.baseRevision = baseRevision
        self.baseDocumentHash = baseDocumentHash
        self.documentJSON = documentJSON
        self.tags = tags
        self.rate = rate
        self.preservationManifest = preservationManifest
        self.pendingSave = pendingSave
        self.validationRejection = validationRejection
    }
}

public enum MergeDraftFailure: Equatable, Sendable {
    case offline
    case timeout
    case unavailable(code: String?)
    case validation(code: String?)
    case server(code: String?)
    case unknown(code: String?)
}

public struct MergeArtifactConflict: Equatable, Sendable {
    public let serverRevision: Int
    public let serverDocumentHash: String

    public init(serverRevision: Int, serverDocumentHash: String) {
        self.serverRevision = serverRevision
        self.serverDocumentHash = serverDocumentHash
    }
}

public enum MergeArtifactConflictResolution: Equatable, Sendable {
    case reloadServer
    case keepMine
}

public enum MergeDraftSyncState: Equatable, Sendable {
    case clean
    case dirty
    case saving
    case unsynced(MergeDraftFailure)
    case conflict(MergeArtifactConflict)
}
