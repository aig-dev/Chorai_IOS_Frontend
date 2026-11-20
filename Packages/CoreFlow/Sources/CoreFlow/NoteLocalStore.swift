import CoreData
import CryptoKit
import Foundation

/// Each mutation is one private-context transaction; managed objects never leave that queue.
public actor NoteLocalStore {
    public nonisolated let directoryURL: URL
    public nonisolated let scope: NoteStoreScope
    let context: NSManagedObjectContext
    private let container: NSPersistentContainer
    private var isClosed = false

    private init(directoryURL: URL, scope: NoteStoreScope, container: NSPersistentContainer) {
        self.directoryURL = directoryURL
        self.scope = scope
        self.container = container
        self.context = container.newBackgroundContext()
        self.context.mergePolicy = NSMergePolicy.error
        self.context.undoManager = nil
    }

    static func directory(rootURL: URL, scope: NoteStoreScope) throws -> URL {
        guard !scope.actorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !scope.environmentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NoteLocalStoreError.invalidScope
        }
        // An array encoding is unambiguous even when IDs contain separators or path characters.
        let identity = try JSONEncoder().encode([scope.environmentID, scope.actorID])
        let key = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        return rootURL.appendingPathComponent(key, isDirectory: true)
    }

    public static func open(rootURL: URL, scope: NoteStoreScope) async throws -> NoteLocalStore {
        let directory = try directory(rootURL: rootURL, scope: scope)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = NSPersistentContainer(name: "ChoraiOfflineNotes", managedObjectModel: model())
        let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("notes.sqlite"))
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(["journal_mode": "WAL", "synchronous": "FULL"] as NSDictionary, forKey: NSSQLitePragmasOption)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        description.setOption(FileProtectionType.completeUntilFirstUserAuthentication.rawValue as NSString, forKey: NSPersistentStoreFileProtectionKey)
        #endif
        container.persistentStoreDescriptions = [description]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        return NoteLocalStore(directoryURL: directory, scope: scope, container: container)
    }

    public func create(body: OfflineNoteBody, localID: String = UUID().uuidString) async throws -> OfflineNote {
        guard !localID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NoteLocalStoreError.invalidIdentity
        }
        let scope = scope
        return try await transaction { context in
            guard try Self.row(localID: localID, in: context) == nil else { throw NoteLocalStoreError.duplicateIdentity }
            let note = OfflineNote(localID: localID, body: body)
            try Self.write(note, scope: scope, in: context)
            return note
        }
    }

    /// Both the first body save and the first photo may arrive before the editor has a persisted ID.
    func saveEditorBody(localID: String, body: OfflineNoteBody, creatingIfMissing: Bool,
                        observedBodyRevision: Int64?) async throws -> OfflineNote {
        try await mutate(localID: localID, creatingWith: creatingIfMissing ? body : nil) { note in
            let retained = try NoteSyncPayload.retainingPreviewIdentities(
                body: body, attachments: note.attachments, assetID: note.serverAssetID
            )
            try Self.replaceBody(&note, with: retained, attachments: nil, observedBodyRevision: observedBodyRevision)
        }
    }

    public func saveBody(localID: String, body: OfflineNoteBody, attachments: [NoteLocalAttachment]? = nil, observedBodyRevision: Int64? = nil) async throws -> OfflineNote {
        if let attachments {
            guard Set(attachments.map(\.uploadID)).count == attachments.count else { throw NoteLocalStoreError.invalidAttachment }
            let files = try NoteAttachmentFiles(directoryURL: directoryURL.appendingPathComponent("attachments"))
            for attachment in attachments { _ = try files.read(attachment) }
        }
        return try await mutate(localID: localID) { note in
            try Self.replaceBody(&note, with: body, attachments: attachments, observedBodyRevision: observedBodyRevision)
        }
    }

    private static func replaceBody(_ note: inout OfflineNote, with body: OfflineNoteBody,
                                    attachments: [NoteLocalAttachment]?, observedBodyRevision: Int64?) throws {
        guard note.body != body || (attachments != nil && attachments != note.attachments) else { return }
        if let observedBodyRevision, observedBodyRevision != note.bodyRevision {
            // A pull may have committed while the editor was buffering input.
            guard !note.hasUnacknowledgedBody, note.pendingOperation == nil,
                  let assetID = note.serverAssetID, let token = note.baseSyncToken,
                  let lifecycle = note.confirmedLifecycle else { throw NoteLocalStoreError.staleGeneration }
            note.remoteSnapshot = NoteRemoteSnapshot(assetID: assetID, syncToken: token, body: note.body,
                lifecycle: lifecycle, isPublic: note.isPublic, editorAtmosphere: note.editorAtmosphere,
                backgroundMediaRef: note.backgroundMediaRef, isPinned: note.isPinned,
                createdAt: note.createdAt, updatedAt: note.updatedAt)
            note.syncIssue = "conflict"
        }
        note.body = body
        if let attachments { note.attachments = attachments }
        note.bodyRevision += 1
        note.generation += 1
        note.updatedAt = Date()
        if note.remoteSnapshot == nil && note.syncIssue != "remote_unavailable" && note.syncIssue != "conflict" {
            note.syncIssue = nil
        }
    }

    public func setLifecycle(localID: String, lifecycle: NoteLifecycle) async throws -> OfflineNote {
        try await mutate(localID: localID) { note in
            guard note.desiredLifecycle != lifecycle else { return }
            note.desiredLifecycle = lifecycle
            note.generation += 1
            note.updatedAt = Date()
        }
    }

    public func note(localID: String) async throws -> OfflineNote? {
        let scope = scope
        return try await transaction { context in
            try Self.row(localID: localID, in: context).map { try Self.decode($0, scope: scope) }
        }
    }

    func note(serverAssetID: String) async throws -> OfflineNote? {
        let scope = scope
        return try await transaction { context in
            try Self.row(key: "serverAssetID", value: serverAssetID, in: context).map { try Self.decode($0, scope: scope) }
        }
    }

    public func notes() async throws -> [OfflineNote] {
        let scope = scope
        return try await transaction { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "LocalNote")
            return try context.fetch(request).map { try Self.decode($0, scope: scope) }
                .sorted(by: OfflineNote.mostRecentFirst)
        }
    }

    /// Logout/scope changes close access; closing never deletes retained working copies.
    public func close() async throws {
        guard !isClosed else { return }
        isClosed = true
        let coordinator = container.persistentStoreCoordinator
        try await context.perform {
            self.context.reset()
            for store in coordinator.persistentStores { try coordinator.remove(store) }
        }
    }

    // The closure crosses from this actor to Core Data's private queue. Only its
    // value inputs and result may cross; managed objects stay inside the closure.
    func transaction<T: Sendable>(_ work: @escaping @Sendable (NSManagedObjectContext) throws -> T) async throws -> T {
        guard !isClosed else { throw NoteLocalStoreError.closed }
        let context = context
        return try await context.perform {
            do {
                let value = try work(context)
                if context.hasChanges { try context.save() }
                context.reset()
                return value
            } catch {
                // A failed transaction must not leak unsaved edits into the next successful one.
                context.rollback()
                context.reset()
                throw error
            }
        }
    }

    func mutate(localID: String, creatingWith initialBody: OfflineNoteBody? = nil,
                _ change: @escaping @Sendable (inout OfflineNote) throws -> Void) async throws -> OfflineNote {
        let scope = scope
        return try await transaction { context in
            let row = try Self.row(localID: localID, in: context)
            var note: OfflineNote
            if let row {
                note = try Self.decode(row, scope: scope)
            } else if let initialBody {
                guard !localID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NoteLocalStoreError.invalidIdentity }
                note = OfflineNote(localID: localID, body: initialBody)
            } else {
                throw NoteLocalStoreError.noteNotFound
            }
            let original = note
            try change(&note)
            if row == nil || original != note {
                try Self.write(note, scope: scope, in: context)
            }
            return note
        }
    }

    static func row(localID: String, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        try row(key: "localID", value: localID, in: context)
    }

    static func row(key: String, value: String, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "LocalNote")
        request.predicate = NSPredicate(format: "%K == %@", key, value)
        request.fetchLimit = 2
        let rows = try context.fetch(request)
        guard rows.count <= 1 else { throw NoteLocalStoreError.corruptRecord }
        return rows.first
    }

    private struct Envelope: Codable {
        let formatVersion: Int
        let scope: NoteStoreScope
        let note: OfflineNote
    }

    static func decode(_ row: NSManagedObject, scope: NoteStoreScope) throws -> OfflineNote {
        guard let bytes = row.value(forKey: "payload") as? Data else { throw NoteLocalStoreError.corruptRecord }
        struct Header: Decodable { let formatVersion: Int }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: bytes) else { throw NoteLocalStoreError.corruptRecord }
        guard header.formatVersion == 1 else { throw NoteLocalStoreError.unsupportedStoreVersion }
        guard let envelope = try? decoder.decode(Envelope.self, from: bytes), envelope.scope == scope else {
            throw NoteLocalStoreError.corruptRecord
        }
        let note = envelope.note
        guard row.value(forKey: "localID") as? String == note.localID,
              row.value(forKey: "serverAssetID") as? String == note.serverAssetID,
              note.bodyRevision > 0, note.bodyRevision < Int64.max,
              note.generation > 0, note.generation < Int64.max,
              note.acknowledgedBodyRevision >= 0, note.acknowledgedBodyRevision <= note.bodyRevision else {
            throw NoteLocalStoreError.corruptRecord
        }
        return note
    }

    static func write(_ note: OfflineNote, scope: NoteStoreScope, in context: NSManagedObjectContext) throws {
        let row = try row(localID: note.localID, in: context)
            ?? NSEntityDescription.insertNewObject(forEntityName: "LocalNote", into: context)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(Envelope(formatVersion: 1, scope: scope, note: note))
        row.setValue(note.localID, forKey: "localID")
        row.setValue(note.serverAssetID, forKey: "serverAssetID")
        row.setValue(bytes, forKey: "payload")
    }

    private static func model() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = ["ChoraiOfflineNotes-v1"]
        let entity = NSEntityDescription()
        entity.name = "LocalNote"
        entity.managedObjectClassName = "NSManagedObject"
        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = optional
            return attribute
        }
        entity.properties = [attribute("localID", .stringAttributeType), attribute("serverAssetID", .stringAttributeType, optional: true), attribute("payload", .binaryDataAttributeType)]
        entity.uniquenessConstraints = [["localID"]]
        model.entities = [entity]
        return model
    }
}
