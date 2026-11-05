import Foundation

public enum NoteSyncPayload {
    /// M1 publishes only the text subset. The original document stays intact
    /// in the store when a block needs a later synchronization capability.
    public static func requireTextOnly(_ body: OfflineNoteBody) throws {
        try requireSupportedDocument(body, includeImages: false)
    }

    static func requireSupportedDocument(_ body: OfflineNoteBody, includeImages: Bool) throws {
        var supported: Set<String> = ["paragraph", "heading", "bulletListItem", "numberedListItem", "checkListItem", "quote", "codeBlock"]
        if includeImages { supported.insert("image") }
        func check(_ blocks: [[String: Any]]) throws {
            for block in blocks {
                guard let type = block["type"] as? String, supported.contains(type) else { throw NoteSyncFailure.unsupportedDocument }
                if let children = block["children"] as? [[String: Any]] { try check(children) }
            }
        }
        guard let blocks = try documentObject(body)["blocks"] as? [[String: Any]] else { throw NoteSyncFailure.unsupportedDocument }
        try check(blocks)
    }

    public static func localMediaRef(uploadID: String) -> String { "local-note-attachment:" + uploadID }

    /// The embedded editor inserts display URLs. Bind an app-local preview to
    /// an already retained attachment before acknowledging the local body.
    /// An unsupported document is kept verbatim; this is not a schema migration.
    static func retainingPreviewIdentities(body: OfflineNoteBody, attachments: [NoteLocalAttachment], assetID: String? = nil) throws -> OfflineNoteBody {
        guard let raw = body.contentJSON, let data = raw.data(using: .utf8),
              let original = try? JSONSerialization.jsonObject(with: data),
              let document = try? documentObject(body) else { return body }
        var changed = false
        let result = try transformImages(document) { props in
            var value = props
            for key in ["url", "src"] {
                guard let address = props[key] as? String, let url = URL(string: address), url.scheme?.lowercased() == NoteAttachmentFiles.previewScheme else { continue }
                let id = try NoteAttachmentFiles.previewUploadID(url)
                let localRef = localMediaRef(uploadID: id)
                let ref = value["mediaRef"] as? String ?? value["media_ref"] as? String
                if let ref, let assetID, id == NoteAttachmentFiles.downloadID(assetID: assetID, mediaRef: ref) { continue }
                guard let attachment = attachments.first(where: { $0.uploadID == id }) else { throw NoteLocalStoreError.invalidAttachment }
                guard ref == nil || ref == localRef || ref == attachment.mediaRef else { throw NoteLocalStoreError.invalidAttachment }
                if ref == nil { value["mediaRef"] = localRef; changed = true }
            }
            return value
        }
        guard changed else { return body }
        // The native editor emits a block array. Keep that shape locally while
        // binding its preview URLs to this note's already-persisted attachments.
        let output: Any
        if original is [Any] {
            guard let blocks = result["blocks"] else { throw NoteLocalStoreError.invalidAttachment }
            output = blocks
        } else { output = result }
        let encoded = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        return OfflineNoteBody(title: body.title, content: body.content, contentJSON: String(decoding: encoded, as: UTF8.self), tags: body.tags)
    }

    static func imageReferences(_ body: OfflineNoteBody) throws -> Set<String> {
        var refs = Set<String>()
        _ = try transformImages(documentObject(body)) { props in
            if let ref = props["mediaRef"] as? String ?? props["media_ref"] as? String { refs.insert(ref) }
            return props
        }
        return refs
    }

    public static func hasUndownloadedImages(_ note: OfflineNote) -> Bool {
        let refs = (try? imageReferences(note.body)) ?? []
        return refs.contains { ref in
            !note.attachments.contains { localMediaRef(uploadID: $0.uploadID) == ref || $0.mediaRef == ref }
        }
    }

    public static func operation(for note: OfflineNote, operationID: String) throws -> NotePendingOperation? {
        if let pending = note.pendingOperation { return pending }
        let kind: NotePendingOperation.Kind
        if note.serverAssetID == nil {
            guard note.desiredLifecycle == .active else { return nil }
            // Retaining an image may create this placeholder before the editor
            // has inserted its reference. Only a saved body may publish it.
            guard note.bodyRevision > 1 || note.body != OfflineNoteBody(content: "") else { return nil }
            kind = .create
        } else if note.desiredLifecycle != note.confirmedLifecycle {
            kind = note.desiredLifecycle == .trashed ? .delete : .restore
        } else {
            guard note.desiredLifecycle == .active && note.hasUnacknowledgedBody else { return nil }
            kind = .update
        }
        var payload: [String: Any] = [:]
        let bodyOperation = kind == .create || kind == .update
        let attachments = bodyOperation ? try referencedAttachments(body: note.body, attachments: note.attachments) : []
        if bodyOperation {
            let document = try remoteDocument(body: note.body, attachments: attachments, assetID: note.serverAssetID)
            payload = ["content": try remoteContent(note.body.content, attachments: attachments), "content_json": document, "tags": note.body.tags]
            if let title = note.body.title { payload["title"] = title }
            if kind == .create { payload["is_public"] = false }
        }
        if kind != .create {
            guard let token = note.baseSyncToken, !token.isEmpty else { throw NoteSyncFailure.invalidResponse }
            payload["base_sync_token"] = token
        }
        let references = bodyOperation ? try imageReferences(note.body) : []
        // Downloaded images already have cloud authority. They are not new
        // uploads and must never enter an expired-upload recovery request.
        let uploads = attachments.filter { references.contains(localMediaRef(uploadID: $0.uploadID)) }
        return NotePendingOperation(operationID: operationID, kind: kind, serverAssetID: note.serverAssetID,
            bodyRevision: bodyOperation ? note.bodyRevision : nil, lifecycle: note.desiredLifecycle,
            baseSyncToken: note.baseSyncToken, requestBody: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            attachments: uploads)
    }

    /// Retained files can outlive a removed block or an earlier frozen request.
    /// Only current image occurrences authorize a new upload or recovery set.
    static func referencedAttachments(body: OfflineNoteBody, attachments: [NoteLocalAttachment]) throws -> [NoteLocalAttachment] {
        var references = Set<String>()
        _ = try transformImages(documentObject(body)) { props in
            if let ref = props["mediaRef"] as? String ?? props["media_ref"] as? String { references.insert(ref) }
            return props
        }
        let used = attachments.filter {
            references.contains(localMediaRef(uploadID: $0.uploadID)) || $0.mediaRef.map(references.contains) == true
        }
        let available = Set(used.map { localMediaRef(uploadID: $0.uploadID) })
        guard references.filter({ $0.hasPrefix("local-note-attachment:") }).allSatisfy(available.contains) else {
            throw NoteLocalStoreError.invalidAttachment
        }
        return used
    }

    /// Rewrite only local image references. Unknown structure/fields survive
    /// intact and are either accepted or explicitly rejected by the server.
    static func remoteDocument(body: OfflineNoteBody, attachments: [NoteLocalAttachment], assetID: String? = nil) throws -> String {
        var document = try documentObject(body)
        var mapping: [String: String?] = [:]
        var identities = Set<String>()
        for attachment in attachments {
            guard identities.insert(attachment.uploadID).inserted else { throw NoteLocalStoreError.invalidAttachment }
            mapping[localMediaRef(uploadID: attachment.uploadID)] = .some(attachment.mediaRef)
        }
        document = try transformImages(document) { props in
            var result = props
            let ref = props["mediaRef"] as? String ?? props["media_ref"] as? String
            for key in ["url", "src"] {
                guard let address = result[key] as? String, let url = URL(string: address), url.scheme?.lowercased() == NoteAttachmentFiles.previewScheme else { continue }
                let id = try NoteAttachmentFiles.previewUploadID(url)
                if let ref, let assetID, id == NoteAttachmentFiles.downloadID(assetID: assetID, mediaRef: ref) {
                    result.removeValue(forKey: key); continue
                }
                guard let attachment = attachments.first(where: { $0.uploadID == id }),
                      ref == localMediaRef(uploadID: id) || ref != nil && ref == attachment.mediaRef else { throw NoteLocalStoreError.invalidAttachment }
                result.removeValue(forKey: key)
            }
            if let ref, ref.hasPrefix("local-note-attachment:") {
                guard let mapped = mapping[ref] ?? nil, !mapped.isEmpty else { throw NoteLocalStoreError.invalidAttachment }
                result["mediaRef"] = mapped
                if props["media_ref"] != nil { result["media_ref"] = mapped }
                // This URL is a local preview, not a second media identity.
                if let url = result["url"] as? String, url.hasPrefix("file:") || url.hasPrefix("data:") || url.hasPrefix("local-note-attachment:") {
                    result.removeValue(forKey: "url")
                }
            }
            for key in ["url", "src"] {
                if let value = result[key] as? String, value.hasPrefix("file:") || value.hasPrefix("data:") || value.hasPrefix("local-note-attachment:") {
                    throw NoteLocalStoreError.invalidAttachment
                }
            }
            return result
        }
        if let content = document["content"] as? String {
            document["content"] = try remoteContent(content, attachments: attachments)
        }
        let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        guard let value = String(data: data, encoding: .utf8) else { throw NoteSyncFailure.unsupportedDocument }
        return value
    }

    // Native Markdown export repeats image display URLs alongside the
    // canonical blocks. Keep captions in that auxiliary text; cloud identity
    // belongs to each image block's mediaRef, never its local preview address.
    private static func remoteContent(_ content: String, attachments: [NoteLocalAttachment]) throws -> String {
        var result = content
        for attachment in attachments {
            let url = try NoteAttachmentFiles.previewURL(uploadID: attachment.uploadID).absoluteString
            let pattern = #"!\[([^\]]*)\]\("# + NSRegularExpression.escapedPattern(for: url) + #"\)"#
            result = result.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
        }
        return result
    }

    static func documentObject(_ body: OfflineNoteBody) throws -> [String: Any] {
        if let raw = body.contentJSON, !raw.isEmpty {
            guard let bytes = raw.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: bytes) else { throw NoteSyncFailure.unsupportedDocument }
            if let document = value as? [String: Any] { return document }
            if let blocks = value as? [[String: Any]] {
                return ["schema_version": 1, "editor_kind": "blocknote", "tags": body.tags, "blocks": blocks]
            }
            throw NoteSyncFailure.unsupportedDocument
        }
        return ["schema_version": 1, "editor_kind": "blocknote", "tags": body.tags, "blocks": [[
            "id": "offline-text", "type": "paragraph", "props": [:], "children": [],
            "content": [["type": "text", "text": body.content, "styles": [:]]]
        ]]]
    }

    static func transformImages(_ document: [String: Any], _ change: ([String: Any]) throws -> [String: Any]) throws -> [String: Any] {
        func blocks(_ values: [[String: Any]]) throws -> [[String: Any]] {
            try values.map { value in
                var result = value
                if value["type"] as? String == "image", let props = value["props"] as? [String: Any] { result["props"] = try change(props) }
                if let children = value["children"] as? [[String: Any]] { result["children"] = try blocks(children) }
                return result
            }
        }
        var result = document
        if let values = document["blocks"] as? [[String: Any]] { result["blocks"] = try blocks(values) }
        return result
    }
}
