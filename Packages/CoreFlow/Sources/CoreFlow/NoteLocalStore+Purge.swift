import Foundation

extension NoteLocalStore {
    /// This is a user-confirmed online command, never a background queue item.
    /// Its intent and local row share a transaction, including final removal.
    public func beginPurge(localID: String, baseSyncToken: String) async throws -> NotePurgeWriteAttempt {
        let scope = scope
        return try await transaction { context in
            guard let row = try Self.row(localID: localID, in: context) else { throw NoteLocalStoreError.noteNotFound }
            var note = try Self.decode(row, scope: scope)
            if let retained = note.pendingPurge {
                try retained.validate()
                guard retained.scope == scope, retained.localID == note.localID,
                      retained.assetID == note.serverAssetID, retained.localGeneration == note.generation,
                      retained.baseSyncToken == note.baseSyncToken else { throw NoteLocalStoreError.corruptRecord }
                return retained
            }
            guard note.isSynchronized, note.confirmedLifecycle == .trashed,
                  note.baseSyncToken == baseSyncToken, let assetID = note.serverAssetID else {
                throw NoteLocalStoreError.invalidOperation
            }
            let attempt = try NotePurgeWriteAttempt(scope: scope, assetID: assetID, localID: localID,
                localGeneration: note.generation + 1, baseSyncToken: baseSyncToken)
            note.generation = attempt.localGeneration
            note.pendingPurge = attempt
            try Self.write(note, scope: scope, in: context)
            return attempt
        }
    }

    public func confirmPurge(_ attempt: NotePurgeWriteAttempt, receipt: NotePurgeWriteReceipt) async throws {
        guard attempt.scope == scope else { throw NoteLocalStoreError.invalidScope }
        try receipt.validate(for: attempt)
        let scope = scope
        try await transaction { context in
            guard let row = try Self.row(localID: attempt.localID, in: context) else { throw NoteLocalStoreError.noteNotFound }
            let note = try Self.decode(row, scope: scope)
            guard note.pendingPurge == attempt, note.generation == attempt.localGeneration,
                  note.serverAssetID == attempt.assetID, note.baseSyncToken == attempt.baseSyncToken,
                  !note.hasUnacknowledgedBody, note.desiredLifecycle == .trashed, note.confirmedLifecycle == .trashed,
                  note.pendingOperation == nil, note.remoteSnapshot == nil, note.syncIssue == nil else {
                throw NoteLocalStoreError.staleGeneration
            }
            try Self.removePurgedBackground(directory: self.directoryURL, localID: attempt.localID)
            context.delete(row)
        }
    }

    @discardableResult
    public func rejectPurge(_ attempt: NotePurgeWriteAttempt, status: Int, reason: String) async throws -> Bool {
        guard attempt.scope == scope else { throw NoteLocalStoreError.invalidScope }
        try attempt.validate()
        guard NotePurgeWriteAttempt.isTerminalRejection(status: status, reason: reason) else { return false }
        let scope = scope
        return try await transaction { context in
            guard let row = try Self.row(localID: attempt.localID, in: context) else { return false }
            var note = try Self.decode(row, scope: scope)
            guard note.pendingPurge == attempt, note.generation == attempt.localGeneration else { return false }
            if status == 404, reason == "purge_target_absent" {
                // The server proved no owned request and no target. This is
                // resolution of the user's local delete, not an ERASED receipt.
                guard note.serverAssetID == attempt.assetID, note.baseSyncToken == attempt.baseSyncToken,
                      !note.hasUnacknowledgedBody, note.desiredLifecycle == .trashed, note.confirmedLifecycle == .trashed,
                      note.pendingOperation == nil, note.remoteSnapshot == nil, note.syncIssue == nil else {
                    throw NoteLocalStoreError.staleGeneration
                }
                try Self.removePurgedBackground(directory: self.directoryURL, localID: attempt.localID)
                context.delete(row)
                return true
            }
            note.pendingPurge = nil
            note.generation += 1
            try Self.write(note, scope: scope, in: context)
            return false
        }
    }
}
