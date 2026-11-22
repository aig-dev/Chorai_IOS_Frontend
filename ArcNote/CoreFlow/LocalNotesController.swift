import Combine
import CoreFlow
import Foundation
import UIKit

enum NoteScopeTransitionState: Equatable { case ready, flushing, failed }

@MainActor
final class LocalNotesController: ObservableObject {
    static let shared = LocalNotesController()
    let library: NoteLibraryStore
    private var subscriptions = Set<AnyCancellable>()
    private let privacyJournal = NotePrivacyJournal(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotePrivacy", isDirectory: true))
    struct PrivacyTarget: Hashable {
        let scope: NoteStoreScope
        let session: UInt64
        let asset: String
    }
    private var privacyWrites = Set<PrivacyTarget>()
    private typealias PolicyRead = (policy: NotePrivacyPolicy, pending: NotePrivacyCommand?)
    private var privacyReads: [PrivacyTarget: Task<PolicyRead, Error>] = [:]

    struct PrivacyProjection: Equatable {
        let syncToken: String?
        let isPublic: Bool

        init(_ note: OfflineNote) {
            syncToken = note.baseSyncToken
            isPublic = note.isPublic
        }
    }

    private struct ConfirmedAudience {
        let policy: NotePrivacyPolicy
        let projection: PrivacyProjection?
    }
    @Published private var confirmedPrivacy: [PrivacyTarget: ConfirmedAudience] = [:]

    private func localNote(for asset: String) -> OfflineNote? {
        library.notes.first { $0.serverAssetID == asset }
    }

    func privacyTarget(for assetID: String?) -> PrivacyTarget? {
        guard let assetID, let scope = AuthManager.shared.currentNoteScope else { return nil }
        return PrivacyTarget(scope: scope, session: AuthManager.shared.sessionGeneration, asset: assetID)
    }

    func currentAudience(for assetID: String?) -> NotePrivacyPolicy? {
        guard let target = privacyTarget(for: assetID), let state = confirmedPrivacy[target] else { return nil }
        if let projection = localNote(for: target.asset).map(PrivacyProjection.init),
           projection != state.projection, projection.isPublic != state.policy.audience.isPublic { return nil }
        return state.policy
    }

    private func publishPrivacy(_ policy: NotePrivacyPolicy, scope: NoteStoreScope, session: UInt64,
                                expectedGeneration: Int64? = nil) async throws {
        let target = PrivacyTarget(scope: scope, session: session, asset: policy.assetID)
        let local = localNote(for: policy.assetID)
        let confirmed = ConfirmedAudience(policy: policy, projection: local.map(PrivacyProjection.init))
        // The confirmed write remains visible even if storing its local projection fails.
        if expectedGeneration == nil { confirmedPrivacy[target] = confirmed }
        guard local != nil else { return }
        do {
            let updated = try await library.recordMetadata(identifier: policy.assetID, isPublic: policy.audience.isPublic,
                scope: scope, expectedGeneration: expectedGeneration)
            try checkCloudTarget(scope, session: session, identifier: policy.assetID, assetID: policy.assetID)
            confirmedPrivacy[target] = ConfirmedAudience(policy: policy, projection: PrivacyProjection(updated))
        } catch NoteLocalStoreError.staleGeneration {
            throw NoteLocalStoreError.staleGeneration
        } catch {
            try checkCloudTarget(scope, session: session, identifier: policy.assetID, assetID: policy.assetID)
            if localNote(for: policy.assetID).map(PrivacyProjection.init) == confirmed.projection {
                confirmedPrivacy[target] = confirmed
            }
            throw error
        }
    }

    private var foreground = true
    private var accessTask: Task<Void, Never>?
    @Published private(set) var scopeTransition: NoteScopeTransitionState = .ready
    private(set) var editors: [UUID: LocalNoteEditorPersistenceSession] = [:]
    private let access: () -> (scope: NoteStoreScope?, cloudEnabled: Bool)

    private convenience init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineNotes", isDirectory: true)
        let library = NoteLibraryStore(rootURL: directory, service: { NetworkNoteSyncService(scope: $0) })
        self.init(library: library, access: {
            let auth = AuthManager.shared
            return (auth.canOpenLocalNotes ? auth.currentNoteScope : nil,
                    auth.canEnterProduct && NetworkManager.shared.isConnected)
        })
        AuthManager.shared.objectWillChange.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refreshAccess() }.store(in: &subscriptions)
        NetworkManager.shared.$isConnected.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                if connected { AuthManager.shared.verifyRestoredSession(force: true) }
                self?.refreshAccess()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.foreground = true; self?.refreshAccess() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.foreground = false; self?.refreshAccess() }.store(in: &subscriptions)
        library.$status.removeDuplicates().receive(on: DispatchQueue.main).sink { status in
            if status == .needsLogin { AuthManager.shared.markSessionNeedsLogin() }
            if status == .accessRevoked { AuthManager.shared.markAccountRestricted() }
        }.store(in: &subscriptions)
        refreshAccess()
    }

    init(library: NoteLibraryStore, access: @escaping () -> (scope: NoteStoreScope?, cloudEnabled: Bool)) {
        self.library = library
        self.access = access
        library.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
    }

    func canDisplayNotes(for scope: NoteStoreScope?) -> Bool {
        scopeTransition == .ready && library.scope == scope
    }

    @discardableResult
    func refreshAccess() -> Task<Void, Never> {
        if library.scope != access().scope, scopeTransition != .failed { scopeTransition = .flushing }
        let previous = accessTask
        let task = Task {
            await previous?.value
            guard self.scopeTransition != .failed else { return }
            while true {
                let target = self.access()
                if self.library.scope != target.scope || self.scopeTransition == .flushing {
                    self.scopeTransition = .flushing
                    // Suspend the original scope's cloud owner before sealing.
                    await self.library.configure(scope: self.library.scope, cloudEnabled: false)
                    let sessions = Array(self.editors.values)
                    sessions.forEach { $0.beginClosingForScopeChange() }
                    for session in sessions {
                        guard await session.closeForScopeChange() else {
                            self.scopeTransition = .failed
                            return
                        }
                    }
                }
                // Authentication may have changed while drain or disk I/O waited.
                let latest = self.access()
                let cloud = latest.cloudEnabled && self.foreground
                await self.library.configure(scope: latest.scope, cloudEnabled: cloud)
                guard self.library.scope == self.access().scope else { continue }
                self.scopeTransition = .ready
                if cloud { Task { await self.library.synchronize() } }
                return
            }
        }
        accessTask = task
        return task
    }

    @discardableResult
    func retryScopeTransition() -> Task<Void, Never> {
        scopeTransition = .flushing
        return refreshAccess()
    }

    func registerEditor(_ session: LocalNoteEditorPersistenceSession) {
        editors[session.id] = session
        session.onRelease = { [weak self, weak session] in
            guard let self, let session, self.editors[session.id] === session else { return }
            self.editors.removeValue(forKey: session.id)
        }
        session.onFinalFlushFailure = { [weak self] in self?.scopeTransition = .failed }
    }

    /// Persist the local decision first. The existing coordinator freezes and
    /// confirms its cloud operation separately from any body revision.
    func setLifecycle(identifier: String, lifecycle: NoteLifecycle) async throws {
        guard let scope = library.scope, AuthManager.shared.canOpenLocalNotes,
              AuthManager.shared.currentNoteScope == scope else { throw NoteLocalStoreError.invalidScope }
        try await library.setLifecycle(identifier: identifier, lifecycle: lifecycle, scope: scope)
        if lifecycle == .trashed, library.scope == scope, AuthManager.shared.currentNoteScope == scope {
            let serverID = library.notes.first { NoteLibraryStore.identifier($0) == identifier }?.serverAssetID
            NotificationCenter.default.post(name: .cardReadInvalidated, object: serverID ?? identifier)
        }
        Task { await library.synchronize() }
    }

    private func checkCloudTarget(_ scope: NoteStoreScope, session: UInt64, identifier: String, assetID: String) throws {
        guard foreground, scopeTransition == .ready, library.cloudEnabled, scope == library.scope,
              AuthManager.shared.currentNoteScope == scope, AuthManager.shared.sessionGeneration == session,
              cloudAssetID(for: identifier) == assetID, NotePrivacyWire.validID(assetID)
        else { throw NoteLocalStoreError.invalidScope }
    }

    func setPinned(identifier: String, isPinned: Bool,
                   send: (String, @escaping (Result<ToggleCardPinResponse, NetworkError>) -> Void) -> Void) async throws -> OwnedCardActionCommit {
        guard let scope = library.scope, let asset = cloudAssetID(for: identifier) else { throw NoteLocalStoreError.invalidScope }
        let session = AuthManager.shared.sessionGeneration
        func check() throws { try checkCloudTarget(scope, session: session, identifier: identifier, assetID: asset) }
        let response: ToggleCardPinResponse = try await withCheckedThrowingContinuation { continuation in
            do {
                try check()
                send(asset) { continuation.resume(with: $0) }
            } catch { continuation.resume(throwing: error) }
        }
        try check()
        guard response.success, let card = response.data, card.id == asset, card.isPinned == isPinned
        else { throw OwnedCardActionError.invalidResponse }
        if localNote(for: asset) != nil {
            try await library.recordMetadata(identifier: asset, isPinned: isPinned, scope: scope)
            try check()
        }
        return .pin(cardID: identifier, isPinned: isPinned, pinnedAt: card.pinnedAt)
    }

    private func readCurrentPrivacy(_ target: PrivacyTarget) async throws -> NotePrivacyPolicy {
        func check() throws {
            try checkCloudTarget(target.scope, session: target.session, identifier: target.asset, assetID: target.asset)
        }
        while true {
            try check()
            let generation = localNote(for: target.asset)?.generation
            let policy = try await NetworkManager.shared.notePrivacyRequest(scope: target.scope, assetID: target.asset)
            try check()
            guard localNote(for: target.asset)?.generation == generation else { continue }
            do {
                try await publishPrivacy(policy, scope: target.scope, session: target.session, expectedGeneration: generation)
                return policy
            } catch NoteLocalStoreError.staleGeneration { continue }
        }
    }

    func observePrivacy(identifier: String) async throws -> NotePrivacyObservation {
        guard let scope = library.scope, let asset = cloudAssetID(for: identifier) else { throw NoteLocalStoreError.invalidScope }
        let session = AuthManager.shared.sessionGeneration
        try checkCloudTarget(scope, session: session, identifier: identifier, assetID: asset)
        let target = PrivacyTarget(scope: scope, session: session, asset: asset)
        if confirmedPrivacy.keys.contains(where: { $0.session != session || $0.scope != scope }) {
            confirmedPrivacy = confirmedPrivacy.filter { $0.key.session == session && $0.key.scope == scope }
        }
        guard !privacyWrites.contains(target) else { throw NotePrivacyError.pendingCommand }
        let read: Task<PolicyRead, Error>
        if let active = privacyReads[target] {
            read = active
        } else {
            read = Task {
                // Only this task removes its slot. Scope and session are part of its key.
                defer { privacyReads[target] = nil }
                let pending = try await privacyJournal.pending(scope: scope, assetID: asset)
                let policy = try await readCurrentPrivacy(target)
                return (policy, pending)
            }
            privacyReads[target] = read
        }
        let observed = try await read.value
        try Task.checkCancellation()
        try checkCloudTarget(scope, session: session, identifier: identifier, assetID: asset)
        guard !privacyWrites.contains(target), currentAudience(for: asset) == observed.policy else {
            throw NotePrivacyError.pendingCommand
        }
        return NotePrivacyObservation(scope: scope, session: session, policy: observed.policy, pending: observed.pending)
    }

    func setPrivacy(identifier: String, observation: NotePrivacyObservation, isPublic: Bool) async throws -> NotePrivacyPolicy {
        let scope = observation.scope, asset = observation.policy.assetID
        func check() throws { try checkCloudTarget(scope, session: observation.session, identifier: identifier, assetID: asset) }
        try check()
        let target = PrivacyTarget(scope: scope, session: observation.session, asset: asset)
        guard privacyReads[target] == nil, privacyWrites.insert(target).inserted else { throw NotePrivacyError.pendingCommand }
        defer { privacyWrites.remove(target) }
        let command: NotePrivacyCommand
        if let pending = observation.pending {
            guard pending == (try await privacyJournal.pending(scope: scope, assetID: asset)) else { throw NotePrivacyError.invalidCommand }
            command = pending
        } else {
            command = try await privacyJournal.begin(scope: scope, path: APIEnvironment.visibilityPath(assetID: asset), observed: observation.policy, desired: isPublic ? .PUBLIC : .PRIVATE, requestID: observation.decisionID)
        }
        try check()
        let policy: NotePrivacyPolicy
        do {
            policy = try await NetworkManager.shared.notePrivacyRequest(scope: scope, assetID: asset, command: command)
        } catch NotePrivacyError.stalePolicy {
            try check()
            _ = try await readCurrentPrivacy(target)
            try check()
            try await privacyJournal.settle(command)
            throw NotePrivacyError.stalePolicy
        }
        try check()
        try await publishPrivacy(policy, scope: scope, session: observation.session)
        try check()
        try await privacyJournal.settle(command)
        try check()
        return policy
    }

    func cloudAssetID(for identifier: String) -> String? {
        guard AuthManager.shared.canEnterProduct, NetworkManager.shared.isConnected,
              AuthManager.shared.currentNoteScope == library.scope else { return nil }
        if let note = library.notes.first(where: { NoteLibraryStore.identifier($0) == identifier || $0.serverAssetID == identifier }) {
            return note.isSynchronized ? note.serverAssetID : nil
        }
        return identifier.hasPrefix("local-note:") ? nil : identifier
    }
}

@MainActor
final class LocalCoreCardEditingService: CoreCardEditingServing {
    let scope: NoteStoreScope
    private let library: NoteLibraryStore
    private let cloud = NetworkCoreCardEditingService()
    private let creationID: String
    private var identifier: String?
    private var observedBodyRevision: Int64?

    init(identifier: String?, creationID: String, scope: NoteStoreScope) {
        self.identifier = identifier; self.creationID = creationID; self.scope = scope
        library = LocalNotesController.shared.library
    }

    func create(draft: CardEditingDraft, createRequestID: String) async throws -> CardEditingSnapshot {
        let note = try await library.save(identifier: nil, createID: createRequestID, body: OfflineNoteBody(draft: draft), scope: scope, observedBodyRevision: observedBodyRevision)
        observedBodyRevision = note.bodyRevision
        identifier = NoteLibraryStore.identifier(note)
        return editorSnapshot(note, savedDraft: draft)
    }

    func update(cardID: String, draft: CardEditingDraft) async throws -> CardEditingSnapshot {
        let note = try await library.save(identifier: cardID, createID: creationID, body: OfflineNoteBody(draft: draft), scope: scope, observedBodyRevision: observedBodyRevision)
        observedBodyRevision = note.bodyRevision
        identifier = NoteLibraryStore.identifier(note)
        return editorSnapshot(note, savedDraft: draft)
    }

    func openExisting() async throws -> OfflineNote {
        guard let identifier else { throw NoteLocalStoreError.noteNotFound }
        let note = try await library.open(identifier: identifier, scope: scope)
        observedBodyRevision = note.bodyRevision
        return note
    }

    func uploadInlineImage(_ image: CardEditingImage) async throws -> CardEditingInlineImageUpload {
        try await library.retainImage(image, identifier: identifier, createID: creationID, scope: scope)
    }

    func imagePreview(_ url: URL) async throws -> (data: Data, mimeType: String) {
        try await library.imagePreview(url, identifier: identifier ?? "local-note:" + creationID, scope: scope)
    }

    func imageDisplayURLs() async throws -> [String: String] {
        try await library.imageDisplayURLs(identifier: identifier ?? "local-note:" + creationID, scope: scope)
    }

    func createLink(_ link: CardEditingLink) async throws -> CardEditingLink {
        let created = try await cloud.createLink(serverLink(link))
        return CardEditingLink(sourceCardID: link.sourceCardID, targetCardID: link.targetCardID,
            title: link.title, noteLinkID: created.noteLinkID, previewHTML: link.previewHTML,
            authorName: link.authorName, authorAvatarURL: link.authorAvatarURL)
    }
    func deleteLink(_ link: CardEditingLink) async throws { try await cloud.deleteLink(serverLink(link)) }
    func fetchLinks(cardID: String) async throws -> [CardEditingLink] {
        let server = try serverID(cardID)
        let generation = AuthManager.shared.sessionGeneration
        let links = try await cloud.fetchLinks(cardID: server)
        guard AuthManager.shared.sessionGeneration == generation,
              try serverID(cardID) == server else {
            throw CardEditingError.transport(code: "cloud_unavailable")
        }
        return links.map { link in
            CardEditingLink(sourceCardID: link.sourceCardID == server ? cardID : link.sourceCardID,
                targetCardID: link.targetCardID == server ? cardID : link.targetCardID,
                title: link.title, noteLinkID: link.noteLinkID, previewHTML: link.previewHTML, authorName: link.authorName, authorAvatarURL: link.authorAvatarURL)
        }
    }
    func replaceBackground(cardID: String, image: CardEditingImage) async throws -> String {
        let ref = try await cloud.replaceBackground(cardID: serverID(cardID), image: image)
        try await library.recordMetadata(identifier: cardID, backgroundMediaRef: .some(ref), scope: scope)
        return ref
    }
    func removeBackground(cardID: String) async throws {
        try await cloud.removeBackground(cardID: serverID(cardID))
        try await library.recordMetadata(identifier: cardID, backgroundMediaRef: .some(nil), scope: scope)
    }

    private func serverID(_ id: String) throws -> String {
        guard library.scope == scope, library.cloudEnabled, AuthManager.shared.canEnterProduct else {
            throw CardEditingError.transport(code: "cloud_unavailable")
        }
        if let serverID = library.serverID(for: id) { return serverID }
        guard !id.hasPrefix("local-note:") else { throw CardEditingError.transport(code: "note_not_yet_synced") }
        return id
    }

    private func serverLink(_ link: CardEditingLink) throws -> CardEditingLink {
        try CardEditingLink(sourceCardID: serverID(link.sourceCardID), targetCardID: serverID(link.targetCardID),
            title: link.title, noteLinkID: link.noteLinkID, previewHTML: link.previewHTML, authorName: link.authorName, authorAvatarURL: link.authorAvatarURL)
    }

    private func editorSnapshot(_ note: OfflineNote, savedDraft: CardEditingDraft) -> CardEditingSnapshot {
        // The stored JSON binds preview URLs to retained attachments. Acknowledge the
        // editor JSON that produced it so the next WebKit snapshot can match this save.
        CardEditingSnapshot(id: NoteLibraryStore.identifier(note), title: note.body.title, content: note.body.content,
            contentJSON: savedDraft.contentJSON, editorAtmosphere: note.editorAtmosphere, tags: note.body.tags,
            isPublic: note.isPublic, backgroundMediaRef: note.backgroundMediaRef)
    }
}
