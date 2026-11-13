import Combine
import CoreFlow
import Foundation
import UIKit

@MainActor
final class LocalNotesController: ObservableObject {
    static let shared = LocalNotesController()
    let library: NoteLibraryStore
    private var subscriptions = Set<AnyCancellable>()
    private var foreground = true
    private var accessTask: Task<Void, Never>?
    private var editorFlushes: [UUID: () async -> Void] = [:]

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineNotes", isDirectory: true)
        library = NoteLibraryStore(rootURL: directory, service: { NetworkNoteSyncService(scope: $0) })
        library.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
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

    func refreshAccess() {
        let previous = accessTask
        accessTask = Task {
            await previous?.value
            let auth = AuthManager.shared
            if library.scope != (auth.canOpenLocalNotes ? auth.currentNoteScope : nil) {
                for flush in Array(editorFlushes.values) { await flush() }
            }
            let scope = auth.canOpenLocalNotes ? auth.currentNoteScope : nil
            let cloud = auth.canEnterProduct && NetworkManager.shared.isConnected && foreground
            await library.configure(scope: scope, cloudEnabled: cloud)
            if cloud { Task { await library.synchronize() } }
        }
    }

    func registerEditor(_ id: UUID, flush: @escaping () async -> Void) { editorFlushes[id] = flush }
    func unregisterEditor(_ id: UUID) { editorFlushes[id] = nil }

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
    private let scope: NoteStoreScope
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
        return snapshot(note)
    }

    func update(cardID: String, draft: CardEditingDraft) async throws -> CardEditingSnapshot {
        let note = try await library.save(identifier: cardID, createID: creationID, body: OfflineNoteBody(draft: draft), scope: scope, observedBodyRevision: observedBodyRevision)
        observedBodyRevision = note.bodyRevision
        identifier = NoteLibraryStore.identifier(note)
        return snapshot(note)
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

    private func snapshot(_ note: OfflineNote) -> CardEditingSnapshot {
        CardEditingSnapshot(id: NoteLibraryStore.identifier(note), title: note.body.title, content: note.body.content,
            contentJSON: note.body.contentJSON, editorAtmosphere: note.editorAtmosphere, tags: note.body.tags,
            isPublic: note.isPublic, backgroundMediaRef: note.backgroundMediaRef)
    }
}
