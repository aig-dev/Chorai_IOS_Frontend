import Foundation

/// This device owes an offline copy only for the Merge receipts it has accepted.
/// Keep IDs independently of the note rows, which may not exist until the first authorized read.
@MainActor
final class CommittedNoteDownloads {
    private let rootURL: URL
    private var worker: Task<Void, Never>?
    private var wakeup: Task<Void, Never>?
    private struct Retry {
        let deadline: Date
        let serverDirected: Bool
    }
    private var retries: [String: Retry] = [:]

    init(rootURL: URL) { self.rootURL = rootURL }

    func enqueue(assetID: String, scope: NoteStoreScope, in library: NoteLibraryStore) throws {
        guard assetID.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else {
            throw NoteLocalStoreError.invalidIdentity
        }
        try update(assetID, in: scope, add: true)
        if library.scope == scope { resume(in: library) }
    }

    func resume(in library: NoteLibraryStore) {
        guard worker == nil, library.cloudEnabled, let scope = library.scope else { return }
        wakeup?.cancel()
        wakeup = nil
        worker = Task(priority: .utility) { [weak self, weak library] in
            guard let self, let library, !Task.isCancelled else { return }
            await self.drain(scope: scope, library: library)
        }
    }

    func suspend(scopeChanged: Bool = false) {
        worker?.cancel()
        worker = nil
        wakeup?.cancel()
        wakeup = nil
        if scopeChanged { retries.removeAll() }
        else { retries = retries.filter { $0.value.serverDirected } }
    }

    private func drain(scope: NoteStoreScope, library: NoteLibraryStore) async {
        while !Task.isCancelled, library.cloudEnabled, scope == library.scope {
            let pending: Set<String>
            do { pending = try pendingIDs(in: scope) }
            catch {
                scheduleRetry(in: library, at: Date().addingTimeInterval(30))
                return
            }
            let now = Date()
            guard let id = pending.sorted().first(where: { (retries[$0]?.deadline ?? .distantPast) <= now }) else {
                worker = nil
                if let next = pending.compactMap({ retries[$0]?.deadline }).min() { scheduleRetry(in: library, at: next) }
                return
            }
            do {
                try await downloadNote(id, scope: scope, library: library)
                try Task.checkCancellation()
                try update(id, in: scope, add: false)
                retries[id] = nil
            } catch {
                guard !Task.isCancelled, library.scope == scope, library.cloudEnabled else { return }
                // One unavailable note must not hold up other commits. Respect server backoff.
                let retryAfter: TimeInterval?
                if case .transient(let after) = error as? NoteSyncFailure, let after, after.isFinite, after > 0 {
                    retryAfter = after
                } else {
                    retryAfter = nil
                }
                retries[id] = Retry(deadline: Date().addingTimeInterval(max(30, retryAfter ?? 0)), serverDirected: retryAfter != nil)
            }
        }
    }

    private func downloadNote(_ id: String, scope: NoteStoreScope, library: NoteLibraryStore) async throws {
        let note = try await library.open(identifier: id, scope: scope)
        guard note.desiredLifecycle == .active else { return }
        let retained = Set(note.attachments.compactMap(\.mediaRef))
        let refs = try await library.imageReferences(identifier: id, scope: scope).subtracting(retained)
        var failure: Error?
        for ref in refs.sorted() where !ref.hasPrefix("local-note-attachment:") {
            try Task.checkCancellation()
            let url = try NoteAttachmentFiles.previewURL(uploadID: NoteAttachmentFiles.downloadID(assetID: id, mediaRef: ref))
            do { _ = try await library.imagePreview(url, identifier: id, scope: scope) }
            catch {
                // A missing image should not prevent retaining the rest of the document.
                if case .transient(.some) = error as? NoteSyncFailure { throw error }
                failure = error
            }
        }
        if let failure { throw failure }
        // The user can edit while media is in flight. Only finish against the current working copy.
        guard let latest = library.notes.first(where: { $0.localID == note.localID }) else { return }
        if latest.desiredLifecycle == .active, latest.bodyRevision != note.bodyRevision {
            let latestRefs = try await library.imageReferences(identifier: id, scope: scope)
            if latestRefs.contains(where: { ref in
                !latest.attachments.contains { NoteSyncPayload.localMediaRef(uploadID: $0.uploadID) == ref || $0.mediaRef == ref }
            }) { throw NoteLocalStoreError.staleGeneration }
        }
    }

    private func scheduleRetry(in library: NoteLibraryStore, at deadline: Date) {
        worker = nil
        wakeup = Task { [weak self, weak library] in
            // Recheck long server deadlines without overflowing Task.sleep.
            let seconds = max(0.05, min(86_400, deadline.timeIntervalSinceNow))
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
            guard let self, let library else { return }
            self.resume(in: library)
        }
    }

    private func pendingIDs(in scope: NoteStoreScope) throws -> Set<String> {
        let url = try queueURL(scope)
        do { return try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: url)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
    }

    private func update(_ id: String, in scope: NoteStoreScope, add: Bool) throws {
        var ids = try pendingIDs(in: scope)
        if add {
            guard ids.insert(id).inserted else { return }
        } else {
            guard ids.remove(id) != nil else { return }
        }
        let url = try queueURL(scope)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(ids.sorted()).write(to: url, options: options)
    }

    private func queueURL(_ scope: NoteStoreScope) throws -> URL {
        try NoteLocalStore.directory(rootURL: rootURL, scope: scope).appendingPathComponent("pending-merge-downloads.json")
    }
}
