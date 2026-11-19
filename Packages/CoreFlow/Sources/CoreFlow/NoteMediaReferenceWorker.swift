import Foundation

/// Pure document inspection, scoped and bounded; this cache never grants file access.
public actor NoteMediaReferenceWorker {
    private struct Key: Hashable { let scope: NoteStoreScope; let localID: String }
    private struct Entry {
        let body: OfflineNoteBody
        let revision: Int64
        let assetID: String?
        let references: Set<String>
        var remoteReferences: [String: String]?
        var bytes: Int
    }
    private let entryLimit: Int
    private let byteLimit: Int
    private let parse: @Sendable (OfflineNoteBody) throws -> Set<String>
    private let downloadID: @Sendable (String, String) -> String
    private var entries: [Key: Entry] = [:]
    private var recency: [Key] = []
    private var bytes = 0

    public init(entryLimit: Int = 40, byteLimit: Int = 4 * 1024 * 1024) {
        self.entryLimit = max(1, entryLimit); self.byteLimit = max(0, byteLimit)
        parse = { try NoteSyncPayload.imageReferences($0) }
        downloadID = { NoteAttachmentFiles.downloadID(assetID: $0, mediaRef: $1) }
    }

    init(entryLimit: Int = 40, byteLimit: Int = 4 * 1024 * 1024,
         parse: @escaping @Sendable (OfflineNoteBody) throws -> Set<String>,
         downloadID: @escaping @Sendable (String, String) -> String = { NoteAttachmentFiles.downloadID(assetID: $0, mediaRef: $1) }) {
        self.entryLimit = max(1, entryLimit); self.byteLimit = max(0, byteLimit); self.parse = parse
        self.downloadID = downloadID
    }

    public func references(in note: OfflineNote, scope: NoteStoreScope) throws -> Set<String> {
        try Task.checkCancellation()
        let key = Key(scope: scope, localID: note.localID)
        if let saved = entries[key], saved.revision == note.bodyRevision, saved.body == note.body, saved.assetID == note.serverAssetID {
            touch(key); return saved.references
        }
        let refs = try parse(note.body)
        let cost = note.body.content.utf8.count + (note.body.contentJSON?.utf8.count ?? 0)
            + (note.body.title?.utf8.count ?? 0) + note.body.tags.reduce(0) { $0 + $1.utf8.count }
            + refs.reduce(0) { $0 + $1.utf8.count } + scope.actorID.utf8.count + scope.environmentID.utf8.count + note.localID.utf8.count
            + (note.serverAssetID?.utf8.count ?? 0)
        remove(key)
        save(Entry(body: note.body, revision: note.bodyRevision, assetID: note.serverAssetID, references: refs, bytes: cost), for: key)
        return refs
    }

    /// All document-sized matching and SHA-derived download IDs stay on this actor.
    func previewURL(source: NoteThumbnailSource, in note: OfflineNote, scope: NoteStoreScope) throws -> URL {
        let refs = (try? references(in: note, scope: scope)) ?? []
        try Task.checkCancellation()
        switch source {
        case .reference(let ref):
            guard refs.contains(ref) else { throw NoteLocalStoreError.invalidAttachment }
            if let attachment = note.attachments.first(where: { NoteSyncPayload.localMediaRef(uploadID: $0.uploadID) == ref || $0.mediaRef == ref }) {
                return try NoteAttachmentFiles.previewURL(uploadID: attachment.uploadID)
            }
            guard let assetID = note.serverAssetID, !ref.hasPrefix("local-note-attachment:") else { throw NoteLocalStoreError.invalidAttachment }
            return try NoteAttachmentFiles.previewURL(uploadID: downloadID(assetID, ref))
        case .previewURL(let url):
            let id = try NoteAttachmentFiles.previewUploadID(url)
            let attachment = note.attachments.first { $0.uploadID == id }
            if let attachment, refs.contains(NoteSyncPayload.localMediaRef(uploadID: id)) || attachment.mediaRef.map(refs.contains) == true {
                return url
            }
            if (try? remoteReference(previewUploadID: id, in: note, scope: scope)) != nil { return url }
            if attachment != nil, displaysLegacyPreview(url, in: note) { return url }
            throw NoteLocalStoreError.invalidAttachment
        }
    }

    func remoteReference(previewUploadID: String, in note: OfflineNote, scope: NoteStoreScope) throws -> String? {
        try remoteReferences(in: note, scope: scope)[previewUploadID]
    }

    func displayURLs(in note: OfflineNote, scope: NoteStoreScope) throws -> [String: String] {
        try Task.checkCancellation()
        var result: [String: String] = [:]
        for attachment in note.attachments {
            let url = try NoteAttachmentFiles.previewURL(uploadID: attachment.uploadID).absoluteString
            result[NoteSyncPayload.localMediaRef(uploadID: attachment.uploadID)] = url
            if let ref = attachment.mediaRef { result[ref] = url }
        }
        for (id, ref) in (try? remoteReferences(in: note, scope: scope)) ?? [:]
            where result[ref] == nil && !ref.hasPrefix("local-note-attachment:") {
            result[ref] = try NoteAttachmentFiles.previewURL(uploadID: id).absoluteString
        }
        try Task.checkCancellation()
        return result
    }

    private func remoteReferences(in note: OfflineNote, scope: NoteStoreScope) throws -> [String: String] {
        guard let assetID = note.serverAssetID else { return [:] }
        let refs = try references(in: note, scope: scope)
        let key = Key(scope: scope, localID: note.localID)
        if let indexed = entries[key]?.remoteReferences { return indexed }
        let indexed = Dictionary(uniqueKeysWithValues: refs.map { (downloadID(assetID, $0), $0) })
        if var saved = entries[key] {
            saved.remoteReferences = indexed
            saved.bytes += indexed.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
            // An oversized index must not discard the smaller reusable reference set.
            if saved.bytes <= byteLimit { save(saved, for: key) }
        }
        return indexed
    }

    /// Compatibility for older Markdown/native URL-only notes. Parsing remains off-main.
    func displaysLegacyPreview(_ url: URL, in note: OfflineNote) -> Bool {
        LibraryCardPreviewParser.parse(content: note.body.content, contentJSON: note.body.contentJSON,
                                       allowsLocalImages: true).imageSource == url.absoluteString
    }

    private func touch(_ key: Key) { recency.removeAll { $0 == key }; recency.append(key) }
    private func save(_ entry: Entry, for key: Key) {
        guard entry.bytes <= byteLimit else { return }
        remove(key)
        while entries.count >= entryLimit || bytes > byteLimit - entry.bytes {
            guard let oldest = recency.first else { break }; remove(oldest)
        }
        entries[key] = entry; bytes += entry.bytes; touch(key)
    }
    private func remove(_ key: Key) {
        if let entry = entries.removeValue(forKey: key) { bytes -= entry.bytes }
        recency.removeAll { $0 == key }
    }
}

public enum NoteThumbnailSource: Hashable, Sendable {
    case reference(String)
    case previewURL(URL)
}

/// Created only by the library after checking the currently owned body and media binding.
/// Attachment IDs are immutable: retaining different bytes under an existing ID fails verification.
public struct NoteThumbnailIdentity: Hashable, Sendable {
    public let scope: NoteStoreScope
    public let localID: String
    public let bodyRevision: Int64
    public let previewURL: URL
}
