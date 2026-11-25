import Foundation

public struct NoteStoreScope: Codable, Equatable, Hashable, Sendable {
    public let actorID: String
    public let environmentID: String

    public init(actorID: String, environmentID: String) {
        self.actorID = actorID
        self.environmentID = environmentID
    }
}

/// The complete body payload. Presentation and cloud-only metadata are intentionally absent.
public struct OfflineNoteBody: Codable, Equatable, Sendable {
    public let title: String?
    public let content: String
    public let contentJSON: String?
    public let tags: [String]

    public init(title: String? = nil, content: String, contentJSON: String? = nil, tags: [String] = []) {
        self.title = title
        self.content = content
        self.contentJSON = contentJSON
        self.tags = tags
    }

    public init(draft: CardEditingDraft) {
        self.init(title: draft.title, content: draft.content, contentJSON: draft.contentJSON, tags: draft.tags)
    }
}

public enum NoteLifecycle: String, Codable, Sendable {
    case active, trashed
}

public struct NoteLocalAttachment: Codable, Equatable, Sendable {
    public let uploadID: String
    public let relativePath: String
    public let originalFilename: String
    public let mimeType: String
    public let sha256: String
    public let byteCount: Int
    public internal(set) var mediaRef: String?
    public internal(set) var uploadAttemptCount: Int?
    public internal(set) var nextUploadAttemptAt: Date?
}

public struct NotePendingOperation: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case create, update, delete, restore }
    public let operationID: String
    public let kind: Kind
    public let serverAssetID: String?
    public let bodyRevision: Int64?
    public let lifecycle: NoteLifecycle
    public let baseSyncToken: String?
    public let requestBody: Data
    public let attachments: [NoteLocalAttachment]
    public internal(set) var attemptCount: Int = 0
    public internal(set) var nextAttemptAt: Date?

    public init(
        operationID: String, kind: Kind, serverAssetID: String?, bodyRevision: Int64?,
        lifecycle: NoteLifecycle, baseSyncToken: String?, requestBody: Data,
        attachments: [NoteLocalAttachment] = []
    ) {
        self.operationID = operationID
        self.kind = kind
        self.serverAssetID = serverAssetID
        self.bodyRevision = bodyRevision
        self.lifecycle = lifecycle
        self.baseSyncToken = baseSyncToken
        self.requestBody = requestBody
        self.attachments = attachments
    }
}

public struct NoteSyncReceipt: Codable, Equatable, Sendable {
    public let operationID: String
    public let assetID: String
    public let syncToken: String
    public let noteDocumentVersionID: String?
    public let lifecycle: NoteLifecycle

    public init(operationID: String, assetID: String, syncToken: String, noteDocumentVersionID: String?, lifecycle: NoteLifecycle) {
        self.operationID = operationID
        self.assetID = assetID
        self.syncToken = syncToken
        self.noteDocumentVersionID = noteDocumentVersionID
        self.lifecycle = lifecycle
    }

    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case assetID = "asset_id"
        case syncToken = "sync_token"
        case noteDocumentVersionID = "note_document_version_id"
        case lifecycle
    }
}

public struct NoteRemoteSnapshot: Codable, Equatable, Sendable {
    public let assetID: String
    public let syncToken: String
    public let body: OfflineNoteBody
    public let lifecycle: NoteLifecycle
    public let isPublic: Bool
    public let editorAtmosphere: String
    public let backgroundMediaRef: String?
    public let backgroundRevision: Int64?
    public let isPinned: Bool?
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        assetID: String, syncToken: String, body: OfflineNoteBody, lifecycle: NoteLifecycle,
        isPublic: Bool, editorAtmosphere: String = "none", backgroundMediaRef: String? = nil, backgroundRevision: Int64? = nil, isPinned: Bool? = nil,
        createdAt: Date? = nil, updatedAt: Date? = nil
    ) {
        self.assetID = assetID
        self.syncToken = syncToken
        self.body = body
        self.lifecycle = lifecycle
        self.isPublic = isPublic
        self.editorAtmosphere = editorAtmosphere
        self.backgroundMediaRef = backgroundMediaRef
        self.backgroundRevision = backgroundRevision
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct OfflineNote: Codable, Equatable, Identifiable, Sendable {
    static func mostRecentFirst(_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.updatedAt == rhs.updatedAt ? lhs.localID < rhs.localID : lhs.updatedAt > rhs.updatedAt
    }

    public var id: String { localID }
    public let localID: String
    public internal(set) var serverAssetID: String?
    public internal(set) var body: OfflineNoteBody
    public internal(set) var bodyRevision: Int64 = 1
    public internal(set) var acknowledgedBodyRevision: Int64 = 0
    public internal(set) var desiredLifecycle: NoteLifecycle = .active
    public internal(set) var confirmedLifecycle: NoteLifecycle?
    public internal(set) var baseSyncToken: String?
    public internal(set) var generation: Int64 = 1
    public internal(set) var pendingOperation: NotePendingOperation?
    public internal(set) var pendingPurge: NotePurgeWriteAttempt?
    public internal(set) var remoteSnapshot: NoteRemoteSnapshot?
    public internal(set) var syncIssue: String?
    public internal(set) var attachments: [NoteLocalAttachment] = []
    public internal(set) var isPublic = false
    public internal(set) var editorAtmosphere = "none"
    public internal(set) var backgroundMediaRef: String?
    public internal(set) var backgroundRevision: Int64?

    /// Order confirmed presentation independently of the body sync token.
    @discardableResult
    mutating func acceptBackground(ref: String?, revision: Int64?) -> Bool {
        if let revision, !(0...NoteBackgroundCommand.maxRevision).contains(revision) { return false }
        if let known = backgroundRevision {
            guard let revision, revision >= known else { return false }
            if revision == known { return ref == backgroundMediaRef }
        }
        backgroundMediaRef = ref
        backgroundRevision = revision
        return true
    }
    public internal(set) var isPinned: Bool?
    public let createdAt: Date
    public internal(set) var updatedAt: Date

    public var hasUnacknowledgedBody: Bool { bodyRevision != acknowledgedBodyRevision }
    public var isSynchronized: Bool {
        serverAssetID != nil && baseSyncToken != nil && !hasUnacknowledgedBody
            && confirmedLifecycle == desiredLifecycle && pendingOperation == nil && pendingPurge == nil
            && remoteSnapshot == nil && syncIssue == nil
    }

    init(localID: String, body: OfflineNoteBody, now: Date = Date()) {
        self.localID = localID
        self.body = body
        self.createdAt = now
        self.updatedAt = now
    }
}

public enum NoteLocalStoreError: Error, Equatable, Sendable {
    case invalidScope, invalidIdentity, noteNotFound, duplicateIdentity, closed
    case corruptRecord, unsupportedStoreVersion, staleGeneration
    case pendingOperationExists, invalidOperation, invalidReceipt
    case invalidAttachment, attachmentMismatch
}
