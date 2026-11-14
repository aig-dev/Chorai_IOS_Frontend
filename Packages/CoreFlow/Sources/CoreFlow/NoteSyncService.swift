import Foundation

public struct NoteSyncManifest: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let assetID: String
        public let syncToken: String
        public let lifecycle: NoteLifecycle
        public init(assetID: String, syncToken: String, lifecycle: NoteLifecycle) {
            self.assetID = assetID; self.syncToken = syncToken; self.lifecycle = lifecycle
        }
        enum CodingKeys: String, CodingKey { case assetID = "asset_id", syncToken = "sync_token", lifecycle }
    }
    public let protocolVersion: Int
    public let complete: Bool
    public let notes: [Entry]
    public init(protocolVersion: Int, complete: Bool, notes: [Entry]) {
        self.protocolVersion = protocolVersion; self.complete = complete; self.notes = notes
    }
    enum CodingKeys: String, CodingKey { case protocolVersion = "protocol_version", complete, notes }
    public var isReady: Bool {
        (protocolVersion == 1 || protocolVersion == 2 || protocolVersion == 3) && complete && notes.count <= 100_000
            && notes.allSatisfy { !$0.assetID.isEmpty && !$0.syncToken.isEmpty }
            && Set(notes.map(\.assetID)).count == notes.count
    }
}

public struct NoteSyncUploadReceipt: Codable, Equatable, Sendable {
    public let mediaRef: String
    public let sha256: String
    public let mimeType: String
    public let byteCount: Int
    public init(mediaRef: String, sha256: String, mimeType: String, byteCount: Int) {
        self.mediaRef = mediaRef; self.sha256 = sha256; self.mimeType = mimeType; self.byteCount = byteCount
    }
    enum CodingKeys: String, CodingKey { case mediaRef = "media_ref", sha256, mimeType = "mime", byteCount = "size_bytes" }
}

public struct NoteSyncDownloadedAttachment: Sendable {
    public let data: Data
    public let filename: String
    public let mimeType: String
    public init(data: Data, filename: String, mimeType: String) { self.data = data; self.filename = filename; self.mimeType = mimeType }
}

/// The app adapter binds both the URL environment and authenticated actor to
/// this immutable scope. It must reject credentials belonging to another actor.
public protocol NoteSyncServing: Sendable {
    var scope: NoteStoreScope { get }
    /// Nil IDs request the most recent active notes. A nil response means this server only supports individual details.
    func readPage(assetIDs: [String]?) async throws -> [NoteRemoteSnapshot]?
    func manifest() async throws -> NoteSyncManifest
    func detail(assetID: String) async throws -> NoteRemoteSnapshot
    func send(_ operation: NotePendingOperation) async throws -> NoteSyncReceipt
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment
}

public extension NoteSyncServing {
    func readPage(assetIDs: [String]?) async throws -> [NoteRemoteSnapshot]? { nil }
}

public enum NoteSyncFailure: Error, Equatable, Sendable {
    case transient(retryAfter: TimeInterval?)
    case authenticationRequired, accountRestricted, permissionDenied, authorityRevoked, notFound
    case staleVersion, idempotencyConflict, preconditionRequired, notReady
    case unsupportedDocument, mediaExpired, invalidResponse, validation
}

public enum NoteSyncStatus: Equatable, Sendable {
    case paused, idle, synchronizing, waitingForNetwork, needsLogin, accessRevoked, notReady, localFailure
}
