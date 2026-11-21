import Foundation

/// One coordinator belongs to one immutable actor/environment store. Durable
/// operations are the queue; Tasks and timers only provide execution chances.
public actor NoteSyncCoordinator {
    private struct Edit {
        let first: Date
        let last: Date
        var deadline: Date { min(last.addingTimeInterval(2), first.addingTimeInterval(30)) }
    }

    private struct SessionRetry {
        let attempt: Int
        let deadline: Date
        let status: NoteSyncStatus
        let failure: NoteSyncFailure?

        func allowsEarlyRetry(forceRetry: Bool) -> Bool {
            // A malformed page can be repaired and checked again on request.
            if failure == .invalidResponse { return true }
            if case .transient(.some) = failure { return false }
            return forceRetry
        }
    }

    public nonisolated let scope: NoteStoreScope
    public private(set) var status: NoteSyncStatus = .paused
    private let store: NoteLocalStore
    private let service: any NoteSyncServing
    private let now: @Sendable () -> Date
    private let jitter: @Sendable () -> Double
    private let didChange: @Sendable () async -> Void
    private let didInsertPage: (@Sendable ([OfflineNote]) async -> Void)?
    private static let pageSize = 20
    private var enabled = false
    private var epoch: UInt64 = 0
    private var work: Task<Void, Never>?
    private var wakeup: Task<Void, Never>?
    private var edits: [String: Edit] = [:]
    private var deliveryRetryAt: Date?
    private var sessionRetry: SessionRetry?
    private var protocolVersion = 0
    private var textOnly: Bool { protocolVersion == 2 }

    public init(store: NoteLocalStore, service: any NoteSyncServing,
                now: @escaping @Sendable () -> Date = { Date() },
                jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...0.25) },
                didChange: @escaping @Sendable () async -> Void = {},
                didInsertPage: (@Sendable ([OfflineNote]) async -> Void)? = nil) throws {
        guard store.scope == service.scope else { throw NoteLocalStoreError.invalidScope }
        self.store = store; self.service = service; self.scope = store.scope
        self.now = now; self.jitter = jitter; self.didChange = didChange; self.didInsertPage = didInsertPage
    }

    /// The app calls this only after confirming this account's cloud eligibility.
    public func resume() {
        epoch &+= 1; work?.cancel(); work = nil; wakeup?.cancel(); wakeup = nil
        enabled = true
        status = sessionRetry?.status ?? .idle
        scheduleWakeup()
    }

    public func suspend() {
        epoch &+= 1; enabled = false; work?.cancel(); work = nil; wakeup?.cancel(); wakeup = nil
        status = .paused
    }

    public func localDidChange(localID: String) {
        let instant = now()
        edits[localID] = Edit(first: edits[localID]?.first ?? instant, last: instant)
        scheduleWakeup()
    }

    public func synchronize(forceRetry: Bool = false) async {
        guard enabled else { return }
        if let work { await work.value; return }
        if let retry = sessionRetry, now() < retry.deadline, !retry.allowsEarlyRetry(forceRetry: forceRetry) {
            return
        }
        let session = epoch
        wakeup?.cancel(); wakeup = nil
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
        let previousAttempt = sessionRetry?.attempt ?? 0
        sessionRetry = nil
        deliveryRetryAt = nil
        // Consume elapsed wakeups before the store snapshot. Edits committed
        // during the network requests can schedule another pass.
        let instant = now()
        edits = edits.filter { $0.value.deadline > instant }
        status = .synchronizing
        do {
            // Capture generations before starting the manifest request. Missing
            // entries and delayed details cannot act on later local decisions.
            var initial = try await store.notes()
            var supportsPages = true
            guard valid(session) else { return }
            if !initial.contains(where: { $0.serverAssetID != nil }) {
                if let recent = try await service.readPage(assetIDs: nil) {
                    guard valid(session) else { return }
                    try await insertPage(recent, requestedIDs: nil, session: session)
                    initial = try await store.notes()
                } else {
                    supportsPages = false
                }
            }
            guard valid(session) else { return }
            let manifest = try await service.manifest()
            guard valid(session) else { return }
            guard manifest.isReady else { throw NoteSyncFailure.notReady }
            protocolVersion = manifest.protocolVersion
            let entries = Dictionary(uniqueKeysWithValues: manifest.notes.map { ($0.assetID, $0) })
            for note in initial {
                guard valid(session) else { return }
                if note.isSynchronized || note.pendingPurge != nil { continue }
                if ["needs_login", "sync_not_ready", "precondition_required"].contains(note.syncIssue ?? "") ||
                    (note.syncIssue == "unsupported_operation" && !textOnly) ||
                    (note.syncIssue == "unsupported_document" && protocolVersion == 3 &&
                     (try? NoteSyncPayload.requireSupportedDocument(note.body, includeImages: true)) != nil) ||
                    (note.syncIssue == "permission_denied" && note.serverAssetID.flatMap { entries[$0] } != nil) {
                    try await store.recordSyncIssue(localID: note.localID, issue: nil)
                }
                try await deliver(localID: note.localID, session: session, forceRetry: forceRetry)
            }
            guard valid(session) else { return }
            for note in initial {
                guard valid(session) else { return }
                guard note.pendingPurge == nil, let assetID = note.serverAssetID else { continue }
                guard let entry = entries[assetID] else {
                    if note.pendingOperation == nil {
                        do { try await store.recordSyncIssue(localID: note.localID, issue: "remote_unavailable", expectedGeneration: note.generation) }
                        catch NoteLocalStoreError.staleGeneration { /* A newer local decision wins. */ }
                        catch NoteLocalStoreError.pendingOperationExists { /* Manual purge owns its unresolved receipt. */ }
                    }
                    continue
                }
                if note.isSynchronized && note.baseSyncToken == entry.syncToken { continue }
                let latest = try await store.note(localID: note.localID)
                guard let latest, latest.pendingOperation == nil, latest.pendingPurge == nil else { continue }
                // A definite conflict needs its remote copy even though recording
                // that rejection advanced the local generation in this pass.
                let rejected = latest.syncIssue == "conflict"
                guard rejected || latest.generation == note.generation else { continue }
                if (latest.baseSyncToken != entry.syncToken && latest.remoteSnapshot?.syncToken != entry.syncToken) || latest.syncIssue == "remote_unavailable" || (rejected && latest.remoteSnapshot == nil) {
                    try await pull(assetID: assetID, localID: note.localID, generation: latest.generation, session: session)
                }
            }
            let known = Set(initial.compactMap(\.serverAssetID))
            let missing = manifest.notes.filter { !known.contains($0.assetID) }.map(\.assetID)
            try await pullMissing(missing, supportsPages: supportsPages, session: session)
            guard valid(session) else { return }
            if status == .synchronizing { status = .idle }
            await didChange()
        } catch {
            guard valid(session) else { return }
            classifySessionFailure(error, attempt: previousAttempt + 1)
            await didChange()
        }
    }

    private func pullMissing(_ missing: [String], supportsPages: Bool, session: UInt64) async throws {
        var usePages = supportsPages
        var failedPages = 0
        var missedPage = false
        for start in stride(from: 0, to: missing.count, by: Self.pageSize) {
            guard valid(session) else { return }
            let ids = Array(missing[start..<min(start + Self.pageSize, missing.count)])
            if usePages {
                do {
                    if let page = try await service.readPage(assetIDs: ids) {
                        try await insertPage(page, requestedIDs: ids, session: session)
                        failedPages = 0
                        continue
                    }
                } catch NoteSyncFailure.transient(let retryAfter) {
                    guard valid(session) else { return }
                    // A single unavailable page need not hide the rest. Stop promptly on loss of connectivity or a server backoff.
                    failedPages += 1
                    if failedPages > 1 || retryAfter != nil { throw NoteSyncFailure.transient(retryAfter: retryAfter) }
                    missedPage = true
                    continue
                }
                // A previous server can still fill this library through its owner-only detail route.
                usePages = false
            }
            for id in ids {
                guard valid(session) else { return }
                try await pull(assetID: id, localID: nil, generation: nil, session: session)
            }
            if valid(session) { await didChange() }
        }
        if missedPage { throw NoteSyncFailure.transient(retryAfter: nil) }
    }

    private func insertPage(_ snapshots: [NoteRemoteSnapshot], requestedIDs: [String]?, session: UInt64) async throws {
        guard valid(session) else { return }
        let ids = Set(snapshots.map(\.assetID))
        guard snapshots.count <= Self.pageSize, ids.count == snapshots.count,
              snapshots.allSatisfy({ !$0.assetID.isEmpty && !$0.syncToken.isEmpty }) else {
            throw NoteSyncFailure.invalidResponse
        }
        if let requestedIDs {
            guard ids.isSubset(of: requestedIDs) else { throw NoteSyncFailure.invalidResponse }
        } else {
            guard snapshots.allSatisfy({ $0.lifecycle == .active }) else { throw NoteSyncFailure.invalidResponse }
        }
        guard !snapshots.isEmpty else { return }
        let inserted = try await store.insertMissingPage(snapshots)
        guard valid(session), !inserted.isEmpty else { return }
        if let didInsertPage {
            await didInsertPage(inserted)
        } else {
            await didChange()
        }
    }

    private func deliver(localID: String, session: UInt64, forceRetry: Bool) async throws {
        // Bounded work even when typing continues throughout every HTTP request.
        for _ in 0..<3 {
            guard valid(session) else { return }
            var pending: NotePendingOperation?
            var attemptedBodyRevision: Int64?
            do {
                guard var note = try await store.note(localID: localID), valid(session) else { return }
                attemptedBodyRevision = note.bodyRevision
                guard note.remoteSnapshot == nil, note.syncIssue == nil, note.pendingPurge == nil else { edits[localID] = nil; return }
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
                    if !forceRetry, let next = existing.nextAttemptAt, next > now() {
                        scheduleDeliveryRetry(at: next)
                        return
                    }
                    pending = existing
                } else {
                    if textOnly {
                        guard note.desiredLifecycle == .active, note.confirmedLifecycle != .trashed else { return }
                        try NoteSyncPayload.requireTextOnly(note.body)
                    } else if protocolVersion == 3 && note.desiredLifecycle == .active && note.confirmedLifecycle != .trashed {
                        try NoteSyncPayload.requireSupportedDocument(note.body, includeImages: true)
                    }
                    guard note.desiredLifecycle == .active || note.serverAssetID != nil else { edits[localID] = nil; return }
                    if !forceRetry, note.desiredLifecycle == .active, note.confirmedLifecycle != .trashed,
                       let edit = edits[localID], edit.deadline > now() { return }
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
                try await recordFailure(error, localID: localID, pending: pending, session: session, bodyRevision: pending?.bodyRevision ?? attemptedBodyRevision)
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
            if !forceRetry, let next = attachment.nextUploadAttemptAt, next > now() {
                scheduleDeliveryRetry(at: next)
                return false
            }
            let data: Data
            do { data = try files.read(attachment) } catch { throw NoteLocalStoreError.invalidAttachment }
            let receipt: NoteSyncUploadReceipt
            do { receipt = try await service.upload(attachment, data: data) }
            catch {
                guard valid(session) else { throw CancellationError() }
                let failure = error as? NoteSyncFailure ?? .transient(retryAfter: nil)
                if case .transient(let retryAfter) = failure {
                    let next = retryDate(attempt: (attachment.uploadAttemptCount ?? 0) + 1, retryAfter: retryAfter)
                    try await store.recordUploadRetry(localID: note.localID, uploadID: attachment.uploadID, nextAttemptAt: next)
                    scheduleDeliveryRetry(at: next)
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

    private func recordFailure(_ error: Error, localID: String, pending: NotePendingOperation?, session: UInt64, bodyRevision: Int64? = nil) async throws {
        var rejectedVersion: (assetID: String, generation: Int64)?
        do {
            if error is NoteLocalStoreError {
                status = .localFailure
                try await store.recordSyncIssue(localID: localID, issue: "local_failure")
                return
            }
            let failure = error as? NoteSyncFailure ?? .transient(retryAfter: nil)
            edits[localID] = nil
            switch failure {
            case .transient(let retryAfter):
                if let pending { try await deferOperation(localID: localID, pending: pending, retryAfter: retryAfter) }
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
                    rejectedVersion = (asset, note.generation)
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
                    return try await recordFailure(failure == .mediaExpired ? NoteSyncFailure.validation : error, localID: localID, pending: pending, session: session)
                }
                guard valid(session) else { return }
                try await deferOperation(localID: localID, pending: pending, retryAfter: nil)
            }
        } catch {
            guard valid(session) else { return }
            if let pending {
                do { try await deferOperation(localID: localID, pending: pending, retryAfter: nil) }
                catch { status = .localFailure }
            } else { status = .localFailure }
            return
        }
        // The rejected write is closed. A failure to fetch its remote version is
        // now a read failure for this session.
        if let rejectedVersion, valid(session) {
            try await pull(assetID: rejectedVersion.assetID, localID: localID, generation: rejectedVersion.generation, session: session)
        }
        await didChange()
    }

    private func deferOperation(localID: String, pending: NotePendingOperation, retryAfter: TimeInterval?) async throws {
        let next = retryDate(attempt: pending.attemptCount + 1, retryAfter: retryAfter)
        try await store.recordRetry(localID: localID, operationID: pending.operationID, nextAttemptAt: next)
        scheduleDeliveryRetry(at: next)
    }

    private func scheduleDeliveryRetry(at deadline: Date) {
        deliveryRetryAt = min(deliveryRetryAt ?? deadline, deadline)
    }

    private func retryDate(attempt: Int, retryAfter: TimeInterval?) -> Date {
        let exponential = min(300, pow(2, Double(max(0, min(attempt, 9)))))
        let minimum = retryAfter.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0
        let delay = max(minimum, exponential * (1 + max(0, min(0.25, jitter()))))
        return now().addingTimeInterval(delay)
    }

    private func pull(assetID: String, localID: String?, generation: Int64?, session: UInt64) async throws {
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
            } else { throw error }
        }
    }

    private func classifySessionFailure(_ error: Error, attempt: Int) {
        var retryAfter: TimeInterval?
        let failure = error as? NoteSyncFailure
        switch failure {
        case .authenticationRequired: enabled = false; status = .needsLogin; return
        case .accountRestricted, .permissionDenied: enabled = false; status = .accessRevoked; return
        case .notReady, .preconditionRequired, .notFound, .invalidResponse: status = .notReady
        case .transient(let advertisedDelay): retryAfter = advertisedDelay; status = .waitingForNetwork
        default: status = error is NoteLocalStoreError ? .localFailure : .waitingForNetwork
        }
        sessionRetry = SessionRetry(attempt: attempt, deadline: retryDate(attempt: attempt, retryAfter: retryAfter),
                                    status: status, failure: failure)
    }

    private func scheduleWakeup() {
        wakeup?.cancel(); wakeup = nil
        guard enabled, work == nil else { return }
        let session = epoch
        let instant = now()
        let editDeadline = edits.values.map(\.deadline).min()
        let nextWork = [editDeadline, deliveryRetryAt].compactMap { $0 }.min()
        let poll = instant.addingTimeInterval(30)
        let deadline = sessionRetry?.deadline ?? min(poll, nextWork ?? poll)
        // Very large but valid Retry-After values exceed Task.sleep's nanosecond range.
        // Recheck the deadline after a day without starting network work early.
        let delay = max(0.05, min(86_400, deadline.timeIntervalSince(instant)))
        wakeup = Task {
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            guard self.valid(session) else { return }
            if let retry = self.sessionRetry, self.now() < retry.deadline {
                self.scheduleWakeup()
                return
            }
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
