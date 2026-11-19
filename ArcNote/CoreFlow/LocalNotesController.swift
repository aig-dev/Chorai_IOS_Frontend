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

    func createLink(_ link: CardEditingLink) async throws { try await cloud.createLink(serverLink(link)) }
    func deleteLink(_ link: CardEditingLink) async throws { try await cloud.deleteLink(serverLink(link)) }
    func fetchLinks(cardID: String) async throws -> [CardEditingLink] {
        let server = try serverID(cardID)
        let links = try await cloud.fetchLinks(cardID: server)
        return links.map { link in
            CardEditingLink(sourceCardID: link.sourceCardID == server ? cardID : link.sourceCardID,
                targetCardID: link.targetCardID == server ? cardID : link.targetCardID,
                title: link.title, previewHTML: link.previewHTML, authorName: link.authorName, authorAvatarURL: link.authorAvatarURL)
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
            title: link.title, previewHTML: link.previewHTML, authorName: link.authorName, authorAvatarURL: link.authorAvatarURL)
    }

    private func editorSnapshot(_ note: OfflineNote, savedDraft: CardEditingDraft) -> CardEditingSnapshot {
        // The stored JSON binds preview URLs to retained attachments. Acknowledge the
        // editor JSON that produced it so the next WebKit snapshot can match this save.
        CardEditingSnapshot(id: NoteLibraryStore.identifier(note), title: note.body.title, content: note.body.content,
            contentJSON: savedDraft.contentJSON, editorAtmosphere: note.editorAtmosphere, tags: note.body.tags,
            isPublic: note.isPublic, backgroundMediaRef: note.backgroundMediaRef)
    }
}
