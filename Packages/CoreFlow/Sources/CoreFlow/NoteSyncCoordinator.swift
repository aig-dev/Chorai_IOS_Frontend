import Foundation

/// One coordinator belongs to one immutable actor/environment store. Durable
/// operations are the queue; Tasks and timers only provide execution chances.
public actor NoteSyncCoordinator {
    public nonisolated let scope: NoteStoreScope
    public private(set) var status: NoteSyncStatus = .paused
    private let store: NoteLocalStore
    private let service: any NoteSyncServing
    private let now: @Sendable () -> Date
    private let jitter: @Sendable () -> Double
    private let didChange: @Sendable () async -> Void
    private var enabled = false
    private var epoch: UInt64 = 0
    private var work: Task<Void, Never>?
    private var wakeup: Task<Void, Never>?
    private var edits: [String: (first: Date, last: Date)] = [:]
    private var retryDeadline: Date?
    private var protocolVersion = 0
    private var textOnly: Bool { protocolVersion == 2 }

    public init(store: NoteLocalStore, service: any NoteSyncServing,
                now: @escaping @Sendable () -> Date = { Date() },
                jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...0.25) },
                didChange: @escaping @Sendable () async -> Void = {}) throws {
        guard store.scope == service.scope else { throw NoteLocalStoreError.invalidScope }
        self.store = store; self.service = service; self.scope = store.scope
        self.now = now; self.jitter = jitter; self.didChange = didChange
    }

    /// The app calls this only after confirming this account's cloud eligibility.
    public func resume() {
        epoch &+= 1; work?.cancel(); work = nil; wakeup?.cancel(); wakeup = nil
        enabled = true; status = .idle
    }

    public func suspend() {
        epoch &+= 1; enabled = false; work?.cancel(); work = nil; wakeup?.cancel(); wakeup = nil
        status = .paused
    }

    public func localDidChange(localID: String) {
        let instant = now()
        edits[localID] = (edits[localID]?.first ?? instant, instant)
        scheduleWakeup()
    }

    public func synchronize(forceRetry: Bool = false) async {
        guard enabled else { return }
        if let work { await work.value; return }
        let session = epoch
        let task = Task { await self.run(session: session, forceRetry: forceRetry) }
        work = task
        await task.value
        guard epoch == session else { return }
        work = nil
        scheduleWakeup()
    }

    private func valid(_ session: UInt64) -> Bool { enabled && epoch == session && !Task.isCancelled }

    private func run(session: UInt64, forceRetry: Bool) async {
        guard valid(session) else { return }
        status = .synchronizing
        do {
            // Capture generations before starting the manifest request. Missing
            // entries and delayed details cannot act on later local decisions.
            let initial = try await store.notes()
            guard valid(session) else { return }
            let manifest = try await service.manifest()
            guard valid(session) else { return }
            guard manifest.isReady else { status = .notReady; await didChange(); return }
            protocolVersion = manifest.protocolVersion
            let entries = Dictionary(uniqueKeysWithValues: manifest.notes.map { ($0.assetID, $0) })
            for note in initial {
                guard valid(session) else { return }
                if ["needs_login", "sync_not_ready", "precondition_required"].contains(note.syncIssue ?? "") ||
                    (note.syncIssue == "unsupported_operation" && !textOnly) ||
                    (note.syncIssue == "unsupported_document" && protocolVersion == 3 &&
                     (try? NoteSyncPayload.requireSupportedDocument(note.body, includeImages: true)) != nil) ||
                    (note.syncIssue == "permission_denied" && note.serverAssetID.flatMap { entries[$0] } != nil) {
                    try await store.recordSyncIssue(localID: note.localID, issue: nil)
                }
                await deliver(localID: note.localID, session: session, forceRetry: forceRetry)
            }
            guard valid(session) else { return }
            for note in initial {
                guard valid(session) else { return }
                guard let assetID = note.serverAssetID else { continue }
                guard let entry = entries[assetID] else {
                    if note.pendingOperation == nil {
                        do { try await store.recordSyncIssue(localID: note.localID, issue: "remote_unavailable", expectedGeneration: note.generation) }
                        catch NoteLocalStoreError.staleGeneration { /* A newer local decision wins. */ }
                    }
                    continue
                }
                let latest = try await store.note(localID: note.localID)
                guard let latest, latest.pendingOperation == nil else { continue }
                // A definite conflict needs its remote copy even though recording
                // that rejection advanced the local generation in this pass.
                let rejected = latest.syncIssue == "conflict"
                guard rejected || latest.generation == note.generation else { continue }
                if (latest.baseSyncToken != entry.syncToken && latest.remoteSnapshot?.syncToken != entry.syncToken) || latest.syncIssue == "remote_unavailable" || (rejected && latest.remoteSnapshot == nil) {
                    await pull(assetID: assetID, localID: note.localID, generation: latest.generation, session: session)
                }
            }
            let known = Set(initial.compactMap(\.serverAssetID))
            for entry in manifest.notes where !known.contains(entry.assetID) {
                guard valid(session) else { return }
                await pull(assetID: entry.assetID, localID: nil, generation: nil, session: session)
            }
            guard valid(session) else { return }
            let retained = try await store.notes()
            retryDeadline = retained.filter { $0.syncIssue == nil }.flatMap { note in
                let used = (try? NoteSyncPayload.referencedAttachments(body: note.body, attachments: note.attachments)) ?? []
                return [note.pendingOperation?.nextAttemptAt].compactMap { $0 } + used.filter { $0.mediaRef == nil }.compactMap(\.nextUploadAttemptAt)
            }.min()
            guard valid(session) else { return }
            if status == .synchronizing { status = .idle }
            await didChange()
        } catch {
            guard valid(session) else { return }
            classifySessionFailure(error)
            await didChange()
        }
    }

    private func deliver(localID: String, session: UInt64, forceRetry: Bool) async {
        // Bounded work even when typing continues throughout every HTTP request.
        for _ in 0..<3 {
            guard valid(session) else { return }
            var pending: NotePendingOperation?
            var attemptedBodyRevision: Int64?
            do {
                guard var note = try await store.note(localID: localID), valid(session) else { return }
                attemptedBodyRevision = note.bodyRevision
                guard note.remoteSnapshot == nil, note.syncIssue == nil else { edits[localID] = nil; return }
                if let existing = note.pendingOperation {
                    if textOnly || (protocolVersion == 3 && (existing.kind == .create || existing.kind == .update)) {
                        do {
                            guard existing.kind == .create || existing.kind == .update,
                                  let payload = try JSONSerialization.jsonObject(with: existing.requestBody) as? [String: Any],
                                  let json = payload["content_json"] as? String else { throw NoteSyncFailure.unsupportedDocument }
                            try NoteSyncPayload.requireSupportedDocument(OfflineNoteBody(content: "", contentJSON: json), includeImages: !textOnly)
                        } catch {
                            // Keep the frozen request intact for a capable protocol.
                            // One unsupported note must not disable this account's sync.
                            try await store.recordSyncIssue(localID: localID, issue: "unsupported_operation", expectedGeneration: note.generation)
                            edits[localID] = nil
                            await didChange()
                            return
                        }
                    }
                    if !forceRetry, let next = existing.nextAttemptAt, next > now() { return }
                    pending = existing
                } else {
                    if textOnly {
                        guard note.desiredLifecycle == .active, note.confirmedLifecycle != .trashed else { return }
                        try NoteSyncPayload.requireTextOnly(note.body)
                    } else if protocolVersion == 3 && note.desiredLifecycle == .active && note.confirmedLifecycle != .trashed {
                        try NoteSyncPayload.requireSupportedDocument(note.body, includeImages: true)
                    }
                    guard note.desiredLifecycle == .active || note.serverAssetID != nil else { edits[localID] = nil; return }
                    if !forceRetry, note.desiredLifecycle == .active, note.confirmedLifecycle != .trashed, let edit = edits[localID],
                       min(edit.last.addingTimeInterval(2), edit.first.addingTimeInterval(30)) > now() { return }
                    if note.desiredLifecycle == .active && note.confirmedLifecycle != .trashed {
                        guard try await uploadMissingAttachments(note, session: session, forceRetry: forceRetry) else { edits[localID] = nil; return }
                        guard valid(session), let refreshed = try await store.note(localID: localID) else { return }
                        // Uploads await the network. A newer body may reference
                        // images that this preparation has not uploaded yet.
                        guard refreshed.bodyRevision == note.bodyRevision,
                              refreshed.desiredLifecycle == note.desiredLifecycle,
                              refreshed.confirmedLifecycle == note.confirmedLifecycle else { continue }
                        note = refreshed
                        attemptedBodyRevision = note.bodyRevision
                    }
                    guard let operation = try NoteSyncPayload.operation(for: note, operationID: UUID().uuidString) else { edits[localID] = nil; return }
                    guard valid(session) else { return }
                    do { _ = try await store.freeze(localID: localID, operation: operation, expectedGeneration: note.generation) }
                    catch NoteLocalStoreError.staleGeneration { continue }
                    catch { status = .localFailure; return }
                    pending = operation
                    edits[localID] = nil
                }
                guard let operation = pending, valid(session) else { return }
                let receipt = try await service.send(operation)
                guard valid(session) else { return }
                do { _ = try await store.acknowledge(localID: localID, receipt: receipt) }
                catch NoteLocalStoreError.invalidReceipt { throw NoteSyncFailure.invalidResponse }
                catch { status = .localFailure; return }
                await didChange()
            } catch NoteLocalStoreError.staleGeneration {
                continue // Input changed while preparing, before any HTTP write.
            } catch {
                guard valid(session) else { return }
                await recordFailure(error, localID: localID, pending: pending, session: session, bodyRevision: pending?.bodyRevision ?? attemptedBodyRevision)
                return
            }
        }
    }

    private func uploadMissingAttachments(_ note: OfflineNote, session: UInt64, forceRetry: Bool) async throws -> Bool {
        let files = try NoteAttachmentFiles(directoryURL: store.directoryURL.appendingPathComponent("attachments"))
        let used = try NoteSyncPayload.referencedAttachments(body: note.body, attachments: note.attachments)
        for attachment in used where attachment.mediaRef == nil {
            guard valid(session) else { throw CancellationError() }
            guard let current = try await store.note(localID: note.localID),
                  current.bodyRevision == note.bodyRevision, current.desiredLifecycle == note.desiredLifecycle else {
                throw NoteLocalStoreError.staleGeneration
            }
            if !forceRetry, let next = attachment.nextUploadAttemptAt, next > now() { return false }
            let data: Data
            do { data = try files.read(attachment) } catch { throw NoteLocalStoreError.invalidAttachment }
            let receipt: NoteSyncUploadReceipt
            do { receipt = try await service.upload(attachment, data: data) }
            catch {
                guard valid(session) else { throw CancellationError() }
                let failure = error as? NoteSyncFailure ?? .transient(retryAfter: nil)
                if case .transient(let retryAfter) = failure {
                    try await store.recordUploadRetry(localID: note.localID, uploadID: attachment.uploadID,
                        nextAttemptAt: retryDate(attempt: (attachment.uploadAttemptCount ?? 0) + 1, retryAfter: retryAfter))
                }
                throw failure
            }
            guard valid(session) else { throw CancellationError() }
            try await store.acknowledgeUpload(localID: note.localID, uploadID: attachment.uploadID, receipt: receipt)
        }
        return true
    }

    private func recoverFrozenAttachments(_ operation: NotePendingOperation, session: UInt64) async throws {
        guard !operation.attachments.isEmpty else { throw NoteSyncFailure.validation }
        let files = try NoteAttachmentFiles(directoryURL: store.directoryURL.appendingPathComponent("attachments"))
        for attachment in operation.attachments {
            guard valid(session) else { throw CancellationError() }
            let receipt = try await service.upload(attachment, data: files.read(attachment))
            guard valid(session) else { throw CancellationError() }
            guard receipt.mediaRef == attachment.mediaRef, receipt.sha256 == attachment.sha256,
                  receipt.byteCount == attachment.byteCount, receipt.mimeType == attachment.mimeType else { throw NoteLocalStoreError.attachmentMismatch }
        }
    }

    private func recordFailure(_ error: Error, localID: String, pending: NotePendingOperation?, session: UInt64, bodyRevision: Int64? = nil) async {
        do {
            if error is NoteLocalStoreError {
                status = .localFailure
                try await store.recordSyncIssue(localID: localID, issue: "local_failure")
                return
            }
            let failure = error as? NoteSyncFailure ?? .transient(retryAfter: nil)
            if case .transient = failure { } else { edits[localID] = nil }
            switch failure {
            case .transient(let retryAfter):
                if let pending { try await deferOperation(localID: localID, pending: pending, retryAfter: retryAfter) }
                else { edits[localID] = nil }
                status = .waitingForNetwork
            case .authenticationRequired:
                try await store.recordSyncIssue(localID: localID, issue: "needs_login")
                enabled = false; status = .needsLogin
            case .accountRestricted:
                enabled = false; status = .accessRevoked
            case .notReady, .preconditionRequired:
                try await store.recordSyncIssue(localID: localID, issue: "sync_not_ready")
                status = .notReady; enabled = false
            case .permissionDenied, .notFound:
                try await store.recordSyncIssue(localID: localID, issue: failure == .notFound ? "remote_unavailable" : "permission_denied")
            case .authorityRevoked:
                try await store.recordSyncIssue(localID: localID, issue: "permission_denied", rejectedOperationID: pending?.operationID)
            case .staleVersion:
                try await store.recordSyncIssue(localID: localID, issue: "conflict", rejectedOperationID: pending?.operationID)
                if let asset = pending?.serverAssetID, let note = try await store.note(localID: localID), valid(session) {
                    await pull(assetID: asset, localID: localID, generation: note.generation, session: session)
                }
            case .unsupportedDocument, .validation:
                try await store.recordSyncIssue(localID: localID, issue: failure == .unsupportedDocument ? "unsupported_document" : "validation", rejectedOperationID: pending?.operationID, issueBodyRevision: bodyRevision)
            case .idempotencyConflict, .invalidResponse:
                try await store.recordSyncIssue(localID: localID, issue: failure == .idempotencyConflict ? "idempotency_conflict" : "invalid_response")
            case .mediaExpired:
                guard let pending else { throw NoteSyncFailure.validation }
                do { try await recoverFrozenAttachments(pending, session: session) }
                catch {
                    guard valid(session) else { return }
                    let failure = error as? NoteSyncFailure
                    await recordFailure(failure == .mediaExpired ? NoteSyncFailure.validation : error, localID: localID, pending: pending, session: session)
                    return
                }
                guard valid(session) else { return }
                try await deferOperation(localID: localID, pending: pending, retryAfter: nil)
            }
            await didChange()
        } catch {
            guard valid(session) else { return }
            if let pending {
                do { try await deferOperation(localID: localID, pending: pending, retryAfter: nil) }
                catch { status = .localFailure }
            } else { status = .localFailure }
        }
    }

    private func deferOperation(localID: String, pending: NotePendingOperation, retryAfter: TimeInterval?) async throws {
        try await store.recordRetry(localID: localID, operationID: pending.operationID, nextAttemptAt: retryDate(attempt: pending.attemptCount + 1, retryAfter: retryAfter))
    }

    private func retryDate(attempt: Int, retryAfter: TimeInterval?) -> Date {
        let exponential = min(300, pow(2, Double(max(0, min(attempt, 9)))))
        let minimum = retryAfter.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0
        let delay = max(minimum, exponential * (1 + max(0, min(0.25, jitter()))))
        return now().addingTimeInterval(delay)
    }

    private func pull(assetID: String, localID: String?, generation: Int64?, session: UInt64) async {
        do {
            let snapshot = try await service.detail(assetID: assetID)
            guard valid(session) else { return }
            guard snapshot.assetID == assetID else { throw NoteSyncFailure.invalidResponse }
            _ = try await store.applyRemote(snapshot, localID: localID, expectedGeneration: generation)
        } catch {
            guard valid(session) else { return }
            if let failure = error as? NoteSyncFailure, failure == .notFound || failure == .permissionDenied {
                if let localID {
                    do { try await store.recordSyncIssue(localID: localID, issue: "remote_unavailable", expectedGeneration: generation) }
                    catch NoteLocalStoreError.staleGeneration { }
                    catch { status = .localFailure }
                }
            } else { classifySessionFailure(error) }
        }
    }

    private func classifySessionFailure(_ error: Error) {
        switch error as? NoteSyncFailure {
        case .authenticationRequired: enabled = false; status = .needsLogin
        case .accountRestricted, .permissionDenied: enabled = false; status = .accessRevoked
        case .notReady, .preconditionRequired, .notFound, .invalidResponse: status = .notReady
        default: status = error is NoteLocalStoreError ? .localFailure : .waitingForNetwork
        }
    }

    private func scheduleWakeup() {
        wakeup?.cancel(); wakeup = nil
        guard enabled else { return }
        let session = epoch
        // Always finite. Foreground execution owns these chances; suspension
        // cancels the timer and the next resume rechecks server readiness.
        let instant = now()
        let editDeadline = edits.values.map { min($0.last.addingTimeInterval(2), $0.first.addingTimeInterval(30)) }.min()
        let deadline = [editDeadline, retryDeadline].compactMap { $0 }.min()
        let delay = max(0.05, min(30, deadline?.timeIntervalSince(instant) ?? 30))
        wakeup = Task {
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            guard self.valid(session) else { return }
            await self.synchronize()
        }
    }

    public func useCloudVersion(localID: String) async throws {
        _ = try await store.useRemoteVersion(localID: localID)
        await didChange()
    }

    public func saveLocalAsNewNote(localID: String) async throws -> OfflineNote {
        guard let original = try await store.note(localID: localID), original.pendingOperation == nil else { throw NoteLocalStoreError.invalidOperation }
        let session = epoch
        var document = try NoteSyncPayload.documentObject(original.body)
        var refs = Set<String>()
        _ = try NoteSyncPayload.transformImages(document) { props in
            guard let ref = props["mediaRef"] as? String ?? props["media_ref"] as? String else { throw NoteSyncFailure.unsupportedDocument }
            refs.insert(ref); return props
        }
        let files = try NoteAttachmentFiles(directoryURL: store.directoryURL.appendingPathComponent("attachments"))
        var attachments: [NoteLocalAttachment] = []
        var replacements: [String: String] = [:]
        for ref in refs.sorted() {
            let bytes: NoteSyncDownloadedAttachment
            if let local = original.attachments.first(where: { NoteSyncPayload.localMediaRef(uploadID: $0.uploadID) == ref || $0.mediaRef == ref }) {
                bytes = NoteSyncDownloadedAttachment(data: try files.read(local), filename: local.originalFilename, mimeType: local.mimeType)
            } else {
                guard let assetID = original.serverAssetID else { throw NoteLocalStoreError.invalidAttachment }
                bytes = try await service.downloadAttachment(assetID: assetID, mediaRef: ref)
                guard session == epoch else { throw CancellationError() }
            }
            let attachment = try files.retain(data: bytes.data, filename: bytes.filename, mimeType: bytes.mimeType)
            attachments.append(attachment); replacements[ref] = NoteSyncPayload.localMediaRef(uploadID: attachment.uploadID)
        }
        document = try NoteSyncPayload.transformImages(document) { props in
            var result = props
            if let ref = props["mediaRef"] as? String ?? props["media_ref"] as? String, let replacement = replacements[ref] {
                result["mediaRef"] = replacement
                if result["media_ref"] != nil { result["media_ref"] = replacement }
                result.removeValue(forKey: "url")
                result.removeValue(forKey: "src")
            }
            return result
        }
        let bytes = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        guard let json = String(data: bytes, encoding: .utf8), session == epoch else { throw CancellationError() }
        let copy = try await store.saveConflictCopy(localID: localID, expectedGeneration: original.generation,
            body: OfflineNoteBody(title: original.body.title, content: original.body.content, contentJSON: json, tags: original.body.tags), attachments: attachments)
        localDidChange(localID: copy.localID); await didChange(); return copy
    }
}
