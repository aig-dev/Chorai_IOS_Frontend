import Foundation

extension NoteLocalStore {
    public func recordRetry(localID: String, operationID: String, nextAttemptAt: Date) async throws {
        _ = try await mutate(localID: localID) { note in
            guard var pending = note.pendingOperation, pending.operationID == operationID else { throw NoteLocalStoreError.invalidOperation }
            pending.attemptCount += 1; pending.nextAttemptAt = nextAttemptAt
            note.pendingOperation = pending; note.generation += 1
        }
    }

    public func recordSyncIssue(localID: String, issue: String?, rejectedOperationID: String? = nil, expectedGeneration: Int64? = nil, issueBodyRevision: Int64? = nil) async throws {
        _ = try await mutate(localID: localID) { note in
            if let expectedGeneration, note.generation != expectedGeneration { throw NoteLocalStoreError.staleGeneration }
            let rejectedRevision = issueBodyRevision ?? note.pendingOperation?.bodyRevision
            if let rejectedOperationID {
                guard note.pendingOperation?.operationID == rejectedOperationID else { throw NoteLocalStoreError.invalidOperation }
                note.pendingOperation = nil
            }
            let correctedBody = (issue == "unsupported_document" || issue == "validation")
                && rejectedRevision != nil && rejectedRevision != note.bodyRevision
            note.syncIssue = correctedBody ? nil : issue; note.generation += 1
        }
    }

    public func acknowledgeUpload(localID: String, uploadID: String, receipt: NoteSyncUploadReceipt) async throws {
        _ = try await mutate(localID: localID) { note in
            guard let index = note.attachments.firstIndex(where: { $0.uploadID == uploadID }) else { return }
            let original = note.attachments[index]
            guard original.sha256 == receipt.sha256, original.byteCount == receipt.byteCount,
                  original.mimeType == receipt.mimeType, !receipt.mediaRef.isEmpty,
                  original.mediaRef == nil || original.mediaRef == receipt.mediaRef else { throw NoteLocalStoreError.attachmentMismatch }
            note.attachments[index].mediaRef = receipt.mediaRef
            note.attachments[index].nextUploadAttemptAt = nil
            note.generation += 1
        }
    }

    public func recordUploadRetry(localID: String, uploadID: String, nextAttemptAt: Date) async throws {
        _ = try await mutate(localID: localID) { note in
            guard let index = note.attachments.firstIndex(where: { $0.uploadID == uploadID }), note.attachments[index].mediaRef == nil else { return }
            note.attachments[index].uploadAttemptCount = (note.attachments[index].uploadAttemptCount ?? 0) + 1
            note.attachments[index].nextUploadAttemptAt = nextAttemptAt
            note.generation += 1
        }
    }

    public func useRemoteVersion(localID: String) async throws -> OfflineNote {
        try await mutate(localID: localID) { note in
            guard note.pendingOperation == nil, let remote = note.remoteSnapshot else { throw NoteLocalStoreError.invalidOperation }
            Self.acceptConflictRemote(&note, remote)
        }
    }

    private static func acceptConflictRemote(_ note: inout OfflineNote, _ remote: NoteRemoteSnapshot) {
        note.body = remote.body; note.bodyRevision += 1; note.acknowledgedBodyRevision = note.bodyRevision
        note.baseSyncToken = remote.syncToken; note.desiredLifecycle = remote.lifecycle; note.confirmedLifecycle = remote.lifecycle
        note.isPublic = remote.isPublic; note.editorAtmosphere = remote.editorAtmosphere; note.backgroundMediaRef = remote.backgroundMediaRef
        note.isPinned = remote.isPinned
        note.remoteSnapshot = nil; note.syncIssue = nil; note.updatedAt = remote.updatedAt ?? note.updatedAt; note.generation += 1
    }

    /// A conflict copy and the decision about the original commit together.
    public func saveConflictCopy(localID: String, expectedGeneration: Int64, body: OfflineNoteBody, attachments: [NoteLocalAttachment]) async throws -> OfflineNote {
        let files = try NoteAttachmentFiles(directoryURL: directoryURL.appendingPathComponent("attachments"))
        for attachment in attachments { _ = try files.read(attachment) }
        let scope = scope
        return try await transaction { context in
            guard let row = try Self.row(localID: localID, in: context) else { throw NoteLocalStoreError.noteNotFound }
            var original = try Self.decode(row, scope: scope)
            guard original.generation == expectedGeneration else { throw NoteLocalStoreError.staleGeneration }
            guard original.pendingOperation == nil, original.remoteSnapshot != nil || original.syncIssue == "remote_unavailable" else { throw NoteLocalStoreError.invalidOperation }
            var copy = OfflineNote(localID: UUID().uuidString, body: body)
            copy.attachments = attachments
            if let remote = original.remoteSnapshot { Self.acceptConflictRemote(&original, remote) }
            try Self.write(original, scope: scope, in: context)
            try Self.write(copy, scope: scope, in: context)
            return copy
        }
    }
}
