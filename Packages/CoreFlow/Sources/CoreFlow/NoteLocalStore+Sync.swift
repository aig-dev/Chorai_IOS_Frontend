import CoreData
import Foundation

extension NoteLocalStore {
    public func freeze(localID: String, operation: NotePendingOperation, expectedGeneration: Int64) async throws -> OfflineNote {
        try await mutate(localID: localID) { note in
            guard note.pendingOperation == nil else { throw NoteLocalStoreError.pendingOperationExists }
            guard note.generation == expectedGeneration else { throw NoteLocalStoreError.staleGeneration }
            guard !operation.operationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !operation.requestBody.isEmpty, note.remoteSnapshot == nil,
                  operation.serverAssetID == note.serverAssetID,
                  operation.baseSyncToken == note.baseSyncToken,
                  operation.lifecycle == note.desiredLifecycle else { throw NoteLocalStoreError.invalidOperation }
            switch operation.kind {
            case .create:
                guard note.serverAssetID == nil, operation.lifecycle == .active,
                      operation.bodyRevision == note.bodyRevision else { throw NoteLocalStoreError.invalidOperation }
            case .update:
                guard note.serverAssetID != nil, note.baseSyncToken != nil,
                      note.confirmedLifecycle == .active, operation.lifecycle == .active,
                      operation.bodyRevision == note.bodyRevision, note.hasUnacknowledgedBody else {
                    throw NoteLocalStoreError.invalidOperation
                }
            case .delete, .restore:
                let restoring = operation.kind == .restore
                guard note.serverAssetID != nil, note.baseSyncToken != nil, operation.bodyRevision == nil,
                      note.confirmedLifecycle == (restoring ? .trashed : .active),
                      operation.lifecycle == (restoring ? .active : .trashed) else { throw NoteLocalStoreError.invalidOperation }
            }
            note.pendingOperation = operation
            note.generation += 1
        }
    }

    public func acknowledge(localID: String, receipt: NoteSyncReceipt) async throws -> OfflineNote {
        let scope = scope
        return try await transaction { context in
            guard let row = try Self.row(localID: localID, in: context) else { throw NoteLocalStoreError.noteNotFound }
            var note = try Self.decode(row, scope: scope)
            guard let pending = note.pendingOperation,
                  pending.operationID == receipt.operationID,
                  !receipt.assetID.isEmpty, !receipt.syncToken.isEmpty,
                  pending.serverAssetID == nil || pending.serverAssetID == receipt.assetID,
                  pending.lifecycle == receipt.lifecycle else { throw NoteLocalStoreError.invalidReceipt }
            if let other = try Self.row(key: "serverAssetID", value: receipt.assetID, in: context), other != row {
                throw NoteLocalStoreError.duplicateIdentity
            }
            if let revision = pending.bodyRevision {
                guard revision <= note.bodyRevision, revision >= note.acknowledgedBodyRevision,
                      let version = receipt.noteDocumentVersionID, !version.isEmpty else { throw NoteLocalStoreError.invalidReceipt }
                note.acknowledgedBodyRevision = revision
            }
            note.serverAssetID = receipt.assetID
            note.confirmedLifecycle = receipt.lifecycle
            note.baseSyncToken = receipt.syncToken
            note.pendingOperation = nil
            note.syncIssue = nil
            note.generation += 1
            try Self.write(note, scope: scope, in: context)
            return note
        }
    }

    /// Nil means a response lost its generation fence; callers must fetch again, not force it in.
    public func applyRemote(_ snapshot: NoteRemoteSnapshot, localID: String?, expectedGeneration: Int64?) async throws -> OfflineNote? {
        let scope = scope
        return try await transaction { context in
            try Self.applyRemote(snapshot, localID: localID, expectedGeneration: expectedGeneration, scope: scope, in: context)
        }
    }

    /// Backfill may race a manual open or an edit. Only insert bodies still missing in this transaction.
    func insertMissingPage(_ snapshots: [NoteRemoteSnapshot]) async throws -> [OfflineNote] {
        let scope = scope
        return try await transaction { context in
            try snapshots.compactMap {
                try Self.applyRemote($0, localID: nil, expectedGeneration: nil, scope: scope, in: context)
            }
        }
    }

    private static func applyRemote(_ snapshot: NoteRemoteSnapshot, localID: String?, expectedGeneration: Int64?,
                                    scope: NoteStoreScope, in context: NSManagedObjectContext) throws -> OfflineNote? {
        guard !snapshot.assetID.isEmpty, !snapshot.syncToken.isEmpty else { throw NoteLocalStoreError.invalidIdentity }
        var note: OfflineNote
        if let localID {
            guard let row = try Self.row(localID: localID, in: context) else { throw NoteLocalStoreError.noteNotFound }
            note = try Self.decode(row, scope: scope)
            guard note.serverAssetID == snapshot.assetID else { throw NoteLocalStoreError.invalidIdentity }
            guard note.generation == expectedGeneration, note.pendingOperation == nil, note.pendingPurge == nil else { return nil }
            // Transport/access warnings do not make an otherwise clean
            // working copy dirty. An authorized read may clear them.
            if note.hasUnacknowledgedBody || note.desiredLifecycle != note.confirmedLifecycle || note.remoteSnapshot != nil {
                if note.baseSyncToken == snapshot.syncToken {
                    if note.remoteSnapshot == nil && note.syncIssue == "remote_unavailable" {
                        // The owner-only read confirmed that this local edit still has the same base.
                        note.syncIssue = nil
                        note.generation += 1
                        try Self.write(note, scope: scope, in: context)
                    }
                    return note
                }
                note.remoteSnapshot = snapshot
                note.syncIssue = "conflict"
                note.generation += 1
                try Self.write(note, scope: scope, in: context)
                return note
            }
            note.bodyRevision += 1
            note.generation += 1
        } else {
            guard expectedGeneration == nil else { throw NoteLocalStoreError.staleGeneration }
            // A second manifest/detail request cannot insert another copy of the same remote note.
            guard try Self.row(key: "serverAssetID", value: snapshot.assetID, in: context) == nil else { return nil }
            note = OfflineNote(localID: UUID().uuidString, body: snapshot.body, now: snapshot.createdAt ?? Date())
        }
        note.serverAssetID = snapshot.assetID
        note.body = snapshot.body
        note.acknowledgedBodyRevision = note.bodyRevision
        note.baseSyncToken = snapshot.syncToken
        note.desiredLifecycle = snapshot.lifecycle
        note.confirmedLifecycle = snapshot.lifecycle
        note.isPublic = snapshot.isPublic
        note.editorAtmosphere = snapshot.editorAtmosphere
        note.acceptBackground(ref: snapshot.backgroundMediaRef, revision: snapshot.backgroundRevision)
        note.isPinned = snapshot.isPinned
        note.updatedAt = snapshot.updatedAt ?? note.updatedAt
        note.remoteSnapshot = nil
        note.syncIssue = nil
        try Self.write(note, scope: scope, in: context)
        return note
    }
}
