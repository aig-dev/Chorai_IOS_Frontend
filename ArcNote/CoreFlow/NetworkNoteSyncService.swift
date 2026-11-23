import CoreFlow
import CryptoKit
import Foundation

struct NetworkNoteSyncService: NoteSyncServing, Sendable {
    let scope: NoteStoreScope

    func readPage(assetIDs: [String]?) async throws -> [NoteRemoteSnapshot]? {
        var path = "/api/cards/sync-page"
        if let assetIDs {
            try assetIDs.forEach(validateServerID)
            path += "?ids=" + assetIDs.joined(separator: ",")
        }
        do {
            let bytes = try await NetworkManager.shared.noteSyncRequest(scope: scope, path: path, method: .get)
            return try NoteSyncHTTP.snapshots(from: bytes, actorID: scope.actorID)
        } catch NoteSyncFailure.notFound {
            return nil
        }
    }

    func manifest() async throws -> NoteSyncManifest {
        let bytes = try await NetworkManager.shared.noteSyncRequest(scope: scope, path: "/api/cards/sync-manifest", method: .get)
        let manifest = try NoteSyncHTTP.payload(NoteSyncManifest.self, from: bytes)
        guard manifest.protocolVersion == 2 || manifest.protocolVersion == 3 else { throw NoteSyncFailure.notReady }
        return manifest
    }

    func detail(assetID: String) async throws -> NoteRemoteSnapshot {
        try validateServerID(assetID)
        let bytes = try await NetworkManager.shared.noteSyncRequest(scope: scope, path: "/api/cards/\(assetID)?sync=1", method: .get)
        return try NoteSyncHTTP.snapshot(from: bytes, actorID: scope.actorID)
    }

    func send(_ operation: NotePendingOperation) async throws -> NoteSyncReceipt {
        let path: String
        let method: NoteSyncHTTPMethod
        switch operation.kind {
        case .create: path = "/api/cards"; method = .post
        case .update, .delete, .restore:
            guard let assetID = operation.serverAssetID else { throw NoteSyncFailure.invalidResponse }
            try validateServerID(assetID)
            switch operation.kind {
            case .restore: path = "/api/cards/trash/\(assetID)/restore"; method = .post
            case .delete: path = "/api/cards/\(assetID)"; method = .delete
            default: path = "/api/cards/\(assetID)"; method = .put
            }
        }
        let bytes = try await NetworkManager.shared.noteSyncRequest(scope: scope, path: path, method: method, body: operation.requestBody, operationID: operation.operationID)
        return try NoteSyncHTTP.receipt(from: bytes)
    }

    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt {
        let bytes = try await NetworkManager.shared.noteSyncUpload(scope: scope, attachment: attachment, data: data)
        return try NoteSyncHTTP.payload(NoteSyncUploadReceipt.self, from: bytes)
    }

    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment {
        try validateServerID(assetID); try validateServerID(mediaRef)
        struct Media: Decodable {
            let assetID: String; let mediaRef: String; let url: String; let sha256: String; let mime: String; let size: Int
            enum CodingKeys: String, CodingKey { case assetID = "asset_id", mediaRef = "media_ref", url = "public_url", sha256, mime, size = "size_bytes" }
        }
        let metadata = try await NetworkManager.shared.noteSyncRequest(scope: scope, path: "/api/v1/media/\(mediaRef)?asset_id=\(assetID)", method: .get)
        let media = try NoteSyncHTTP.payload(Media.self, from: metadata)
        guard media.assetID == assetID, media.mediaRef == mediaRef, media.size > 0, media.size <= 25 * 1024 * 1024,
              let url = URL(string: APIConfiguration.resourceURLString(media.url)),
              ["https", "http"].contains(url.scheme), url.host != nil, url.user == nil, url.password == nil else { throw NoteSyncFailure.invalidResponse }
        let bytes = try await NetworkManager.shared.noteSyncDownload(scope: scope, url: url)
        guard bytes.count == media.size, SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == media.sha256 else { throw NoteSyncFailure.invalidResponse }
        return NoteSyncDownloadedAttachment(data: bytes, filename: mediaRef, mimeType: media.mime)
    }

    private func validateServerID(_ id: String) throws {
        guard id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { throw NoteSyncFailure.invalidResponse }
    }
}

enum NoteSyncHTTPMethod: String { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }
