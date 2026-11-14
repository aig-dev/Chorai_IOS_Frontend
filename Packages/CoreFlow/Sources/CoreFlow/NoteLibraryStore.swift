import Combine
import Foundation

/// App-owned local Library. Authentication determines access to a scope; cloud
/// eligibility can change without replacing its working copies or editor.
@MainActor
public final class NoteLibraryStore: ObservableObject {
    public enum Change {
        case reset
        case updated([OfflineNote], removed: Set<String>)
    }

    @Published public private(set) var scope: NoteStoreScope?
    @Published public private(set) var notes: [OfflineNote] = []
    private let noteChanges = PassthroughSubject<Change, Never>()
    public var changes: AnyPublisher<Change, Never> { noteChanges.eraseToAnyPublisher() }
    @Published public private(set) var status: NoteSyncStatus = .paused
    @Published public private(set) var localError: String?
    public private(set) var cloudEnabled = false
    private let rootURL: URL
    private let serviceFactory: @Sendable (NoteStoreScope) throws -> any NoteSyncServing
    private var store: NoteLocalStore?
    private var coordinator: NoteSyncCoordinator?
    private var service: (any NoteSyncServing)?
    private var generation: UInt64 = 0
    private var refreshSerial: UInt64 = 0
    private var fullRefreshInFlight = false
    private var locallyChangedDuringRefresh = Set<String>()
    private var configuration: Task<Void, Never>?
    private var imageDownloads: [String: Task<(data: Data, mimeType: String), Error>] = [:]

    public init(rootURL: URL, service: @escaping @Sendable (NoteStoreScope) throws -> any NoteSyncServing) {
        self.rootURL = rootURL; self.serviceFactory = service
    }

    public nonisolated static func identifier(_ note: OfflineNote) -> String { "local-note:" + note.localID }

    public func configure(scope nextScope: NoteStoreScope?, cloudEnabled nextCloud: Bool) async {
        if scope == nextScope, store != nil {
            guard cloudEnabled != nextCloud else { return }
            let epoch = generation
            cloudEnabled = nextCloud
            if nextCloud { await coordinator?.resume() } else { await coordinator?.suspend() }
            let state = await coordinator?.status ?? .paused
            if generation == epoch, cloudEnabled == nextCloud, status != state { status = state }
            return
        }
        if scope == nextScope, let configuration {
            await configuration.value
            if store != nil { await configure(scope: nextScope, cloudEnabled: nextCloud) }
            return
        }
        generation &+= 1
        imageDownloads.values.forEach { $0.cancel() }; imageDownloads.removeAll()
        let epoch = generation
        let previous = configuration
        let oldStore = store; let oldCoordinator = coordinator
        scope = nextScope; cloudEnabled = nextCloud
        refreshSerial &+= 1
        fullRefreshInFlight = false
        locallyChangedDuringRefresh.removeAll()
        store = nil; coordinator = nil; service = nil; notes = []; status = .paused; localError = nil
        noteChanges.send(.reset)
        let task = Task { [weak self] in
            await previous?.value
            await oldCoordinator?.suspend()
            do { try await oldStore?.close() }
            catch { if self?.generation == epoch { self?.localError = "Couldn't close local notes safely." } }
            guard let self, self.generation == epoch, let nextScope else { return }
            var opened: NoteLocalStore?
            do {
                let local = try await NoteLocalStore.open(rootURL: self.rootURL, scope: nextScope)
                opened = local
                guard self.generation == epoch else { try await local.close(); return }
                let transport = try self.serviceFactory(nextScope)
                let sync = try NoteSyncCoordinator(store: local, service: transport, didChange: { [weak self] in
                    await self?.refresh(generation: epoch)
                }, didInsertPage: { [weak self] inserted in
                    await self?.publishInsertedPage(inserted, generation: epoch)
                })
                self.store = local; self.service = transport; self.coordinator = sync
                if self.cloudEnabled { await sync.resume() }
                await self.refresh(generation: epoch)
            } catch {
                try? await opened?.close()
                guard self.generation == epoch else { return }
                self.store = nil; self.coordinator = nil; self.service = nil
                self.localError = "Couldn't open local notes. The saved files have been kept."
                self.status = .localFailure
            }
        }
        configuration = task
        await task.value
        if generation == epoch { configuration = nil }
    }

    public func synchronize(forceRetry: Bool = false) async {
        await configuration?.value
        guard cloudEnabled, let coordinator else { return }
        let epoch = generation
        await coordinator.synchronize(forceRetry: forceRetry)
        let state = await coordinator.status
        if epoch == generation, status != state { status = state }
    }

    public func open(identifier: String, scope expectedScope: NoteStoreScope? = nil) async throws -> OfflineNote {
        let (store, epoch) = try await context(expectedScope)
        if let note = try await find(identifier, store: store) { try check(epoch); return note }
        guard !identifier.hasPrefix("local-note:"), cloudEnabled, let service else { throw NoteLocalStoreError.noteNotFound }
        let snapshot = try await service.detail(assetID: identifier)
        try check(epoch)
        guard snapshot.assetID == identifier else { throw NoteSyncFailure.invalidResponse }
        if let note = try await store.applyRemote(snapshot, localID: nil, expectedGeneration: nil) {
            try check(epoch); publish([note])
            return note
        }
        // Another reader or the first sync page can insert this identity during the request.
        guard let note = try await store.note(serverAssetID: identifier) else { throw NoteLocalStoreError.noteNotFound }
        try check(epoch); publish([note])
        return note
    }

    public func save(identifier: String?, createID: String, body: OfflineNoteBody,
                     scope expectedScope: NoteStoreScope? = nil, observedBodyRevision: Int64? = nil) async throws -> OfflineNote {
        let (store, epoch) = try await context(expectedScope)
        let localID = try await localID(for: identifier, createID: createID, store: store)
        let note = try await store.saveEditorBody(localID: localID, body: body, creatingIfMissing: identifier == nil,
                                                   observedBodyRevision: observedBodyRevision)
        try check(epoch)
        publish([note])
        if !note.isSynchronized { await coordinator?.localDidChange(localID: note.localID) }
        try check(epoch)
        return note
    }

    public func retainImage(_ image: CardEditingImage, identifier: String?, createID: String,
                            scope expectedScope: NoteStoreScope) async throws -> CardEditingInlineImageUpload {
        let (store, epoch) = try await context(expectedScope)
        guard !image.data.isEmpty, image.data.count <= 25 * 1024 * 1024 else { throw NoteLocalStoreError.invalidAttachment }
        let localID = try await localID(for: identifier, createID: createID, store: store)
        let files = try NoteAttachmentFiles(directoryURL: store.directoryURL.appendingPathComponent("attachments"))
        let attachment = try await Task.detached { try files.retain(data: image.data, filename: image.filename, mimeType: image.mimeType) }.value
        try check(epoch)
        // Only this narrow mutation appends attachment metadata; a concurrent
        // body save or an upload ACK cannot be replaced with this older note.
        let updated = try await store.retainAttachment(localID: localID, attachment: attachment, creatingIfMissing: identifier == nil)
        try check(epoch); publish([updated])
        return CardEditingInlineImageUpload(mediaRef: NoteSyncPayload.localMediaRef(uploadID: attachment.uploadID),
            url: try NoteAttachmentFiles.previewURL(uploadID: attachment.uploadID))
    }

    public func imagePreview(_ url: URL, identifier: String, scope expectedScope: NoteStoreScope) async throws -> (data: Data, mimeType: String) {
        let (store, epoch) = try await context(expectedScope)
        let id = try NoteAttachmentFiles.previewUploadID(url)
        guard let note = try await find(identifier, store: store) else { throw NoteLocalStoreError.invalidAttachment }
        try check(epoch)
        let files = try NoteAttachmentFiles(directoryURL: store.directoryURL.appendingPathComponent("attachments"))
        if let attachment = note.attachments.first(where: { $0.uploadID == id }) {
            let data = try await Task.detached { try files.read(attachment) }.value
            try check(epoch)
            return (data, attachment.mimeType)
        }
        guard let assetID = note.serverAssetID,
              let ref = try NoteSyncPayload.imageReferences(note.body).first(where: { NoteAttachmentFiles.downloadID(assetID: assetID, mediaRef: $0) == id }) else { throw NoteLocalStoreError.invalidAttachment }
        guard cloudEnabled, let service else { throw NoteSyncFailure.notFound }
        if let pending = imageDownloads[id] {
            let value = try await pending.value
            try check(epoch)
            return value
        }
        let task = Task { @MainActor in
            let downloaded = try await service.downloadAttachment(assetID: assetID, mediaRef: ref)
            try self.check(epoch); try Task.checkCancellation()
            guard !downloaded.data.isEmpty, downloaded.data.count <= 25 * 1024 * 1024 else { throw NoteLocalStoreError.invalidAttachment }
            var attachment = try await Task.detached {
                try files.retain(data: downloaded.data, filename: downloaded.filename, mimeType: downloaded.mimeType, uploadID: id)
            }.value
            try self.check(epoch); try Task.checkCancellation()
            attachment.mediaRef = ref
            let updated = try await store.retainAttachment(localID: note.localID, attachment: attachment)
            try self.check(epoch)
            self.publish([updated])
            return (data: downloaded.data, mimeType: downloaded.mimeType)
        }
        imageDownloads[id] = task
        defer { if generation == epoch { imageDownloads.removeValue(forKey: id) } }
        let value = try await task.value
        try check(epoch)
        return value
    }

    public func imageDisplayURLs(identifier: String, scope expectedScope: NoteStoreScope) async throws -> [String: String] {
        let epoch = generation
        let note = try await open(identifier: identifier, scope: expectedScope)
        try check(epoch)
        var result: [String: String] = [:]
        for attachment in note.attachments {
            let url = try NoteAttachmentFiles.previewURL(uploadID: attachment.uploadID).absoluteString
            result[NoteSyncPayload.localMediaRef(uploadID: attachment.uploadID)] = url
            if let ref = attachment.mediaRef { result[ref] = url }
        }
        if let assetID = note.serverAssetID {
            for ref in (try? NoteSyncPayload.imageReferences(note.body)) ?? [] where result[ref] == nil && !ref.hasPrefix("local-note-attachment:") {
                result[ref] = try NoteAttachmentFiles.previewURL(uploadID: NoteAttachmentFiles.downloadID(assetID: assetID, mediaRef: ref)).absoluteString
            }
        }
        return result
    }

    public func setLifecycle(identifier: String, lifecycle: NoteLifecycle, scope expectedScope: NoteStoreScope? = nil) async throws {
        let (store, epoch) = try await context(expectedScope)
        guard let note = try await find(identifier, store: store) else { throw NoteLocalStoreError.noteNotFound }
        let updated = try await store.setLifecycle(localID: note.localID, lifecycle: lifecycle)
        try check(epoch); publish([updated])
        if !updated.isSynchronized { await coordinator?.localDidChange(localID: note.localID) }
        try check(epoch)
    }

    public func useCloudVersion(identifier: String) async throws {
        let note = try await open(identifier: identifier)
        guard let coordinator else { throw NoteLocalStoreError.closed }
        try await coordinator.useCloudVersion(localID: note.localID)
    }

    public func saveLocalAsNewNote(identifier: String) async throws -> OfflineNote {
        let note = try await open(identifier: identifier)
        guard let coordinator else { throw NoteLocalStoreError.closed }
        return try await coordinator.saveLocalAsNewNote(localID: note.localID)
    }

    public func serverID(for identifier: String) -> String? {
        notes.first { Self.identifier($0) == identifier || $0.serverAssetID == identifier }?.serverAssetID
    }

    /// Cache only metadata confirmed by its own online endpoint. Body and its
    /// baseline remain untouched, including a concurrently edited local draft.
    public func recordMetadata(identifier: String, isPublic: Bool? = nil, isPinned: Bool? = nil,
                               backgroundMediaRef: String?? = nil, scope expectedScope: NoteStoreScope) async throws {
        let (store, epoch) = try await context(expectedScope)
        guard let note = try await find(identifier, store: store) else { throw NoteLocalStoreError.noteNotFound }
        let updated = try await store.mutate(localID: note.localID) { current in
            if let isPublic { current.isPublic = isPublic }
            if let isPinned { current.isPinned = isPinned }
            if let backgroundMediaRef { current.backgroundMediaRef = backgroundMediaRef }
            current.generation += 1
        }
        try check(epoch); publish([updated])
    }

    public func discardConfirmedPurge(identifier: String, expectedGeneration: Int64, scope expectedScope: NoteStoreScope) async throws {
        let (store, epoch) = try await context(expectedScope)
        guard let note = try await find(identifier, store: store) else { throw NoteLocalStoreError.noteNotFound }
        try await store.transaction { context in
            guard let row = try NoteLocalStore.row(localID: note.localID, in: context) else { throw NoteLocalStoreError.noteNotFound }
            let current = try NoteLocalStore.decode(row, scope: expectedScope)
            guard current.generation == expectedGeneration else { throw NoteLocalStoreError.staleGeneration }
            guard current.isSynchronized, current.confirmedLifecycle == .trashed else { throw NoteLocalStoreError.invalidOperation }
            context.delete(row)
        }
        try check(epoch); publish([], removed: [note.localID])
    }

    private func context(_ expected: NoteStoreScope?) async throws -> (NoteLocalStore, UInt64) {
        let requested = expected ?? scope
        let epoch = generation
        await configuration?.value
        guard let requested, scope == requested, generation == epoch else { throw NoteLocalStoreError.invalidScope }
        guard let store else { throw NoteLocalStoreError.closed }
        return (store, epoch)
    }

    private func check(_ epoch: UInt64) throws {
        guard generation == epoch else { throw NoteLocalStoreError.invalidScope }
    }

    private func find(_ identifier: String, store: NoteLocalStore) async throws -> OfflineNote? {
        if identifier.hasPrefix("local-note:") { return try await store.note(localID: String(identifier.dropFirst(11))) }
        return try await store.note(serverAssetID: identifier)
    }

    private func localID(for identifier: String?, createID: String, store: NoteLocalStore) async throws -> String {
        guard let identifier else { return createID }
        if identifier.hasPrefix("local-note:") { return String(identifier.dropFirst(11)) }
        guard let note = try await store.note(serverAssetID: identifier) else { throw NoteLocalStoreError.noteNotFound }
        return note.localID
    }

    private func publishInsertedPage(_ inserted: [OfflineNote], generation epoch: UInt64) {
        guard generation == epoch else { return }
        publish(inserted)
        if status != .synchronizing { status = .synchronizing }
    }

    /// Publish committed rows. A delayed transaction result cannot replace a newer revision.
    private func publish(_ committed: [OfflineNote], removed: Set<String> = []) {
        var changed: [OfflineNote] = []
        var result = notes
        for note in committed {
            if let index = result.firstIndex(where: { $0.localID == note.localID }) {
                guard result[index].generation < note.generation else { continue }
                result.remove(at: index)
            }
            let index = result.firstIndex { OfflineNote.mostRecentFirst(note, $0) } ?? result.endIndex
            result.insert(note, at: index)
            changed.append(note)
        }
        if !removed.isEmpty { result.removeAll { removed.contains($0.localID) } }
        if fullRefreshInFlight {
            locallyChangedDuringRefresh.formUnion(changed.map(\.localID))
            locallyChangedDuringRefresh.formUnion(removed)
        }
        guard !changed.isEmpty || !removed.isEmpty else { return }
        notes = result
        noteChanges.send(.updated(changed, removed: removed))
    }

    private func refresh(generation epoch: UInt64) async {
        guard generation == epoch, let store else { return }
        refreshSerial &+= 1
        let serial = refreshSerial
        fullRefreshInFlight = true
        locallyChangedDuringRefresh.removeAll(keepingCapacity: true)
        defer {
            if refreshSerial == serial {
                fullRefreshInFlight = false
                locallyChangedDuringRefresh.removeAll(keepingCapacity: true)
            }
        }
        do {
            let saved = try await store.notes()
            let state = await coordinator?.status ?? .paused
            guard generation == epoch, refreshSerial == serial else { return }
            // A local commit or purge can finish while this snapshot is travelling back to the UI.
            // Absence from an older snapshot must not erase that change.
            var visible = Dictionary(uniqueKeysWithValues: notes.map { ($0.localID, $0.generation) })
            var changed: [OfflineNote] = []
            for note in saved {
                let previous = visible.removeValue(forKey: note.localID)
                if previous == nil && locallyChangedDuringRefresh.contains(note.localID) { continue }
                if note.generation > (previous ?? 0) { changed.append(note) }
            }
            let removed = Set(visible.keys).subtracting(locallyChangedDuringRefresh)
            if notes.isEmpty && !changed.isEmpty {
                notes = changed
                noteChanges.send(.reset)
            } else {
                publish(changed, removed: removed)
            }
            if status != state { status = state }
            if localError != nil { localError = nil }
        } catch {
            guard generation == epoch, refreshSerial == serial else { return }
            localError = "Couldn't read local notes. The saved files have been kept."
            status = .localFailure
        }
    }
}

extension NoteLocalStore {
    func retainAttachment(localID: String, attachment: NoteLocalAttachment, creatingIfMissing: Bool = false) async throws -> OfflineNote {
        let files = try NoteAttachmentFiles(directoryURL: directoryURL.appendingPathComponent("attachments"))
        _ = try files.read(attachment)
        return try await mutate(localID: localID, creatingWith: creatingIfMissing ? OfflineNoteBody(content: "") : nil) { note in
            guard !note.attachments.contains(where: { $0.uploadID == attachment.uploadID }) else { return }
            note.attachments.append(attachment); note.generation += 1
        }
    }
}
