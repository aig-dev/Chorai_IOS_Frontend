import BlockNoteEditor
import Combine
import CoreFlow
import Foundation

@MainActor
final class MergeArtifactDraftController: ObservableObject {
    @Published private(set) var bodyModel: BlockNoteCardEditorModel
    @Published private(set) var tags: [String]
    @Published var isAddingTag = false
    @Published var tagInput = ""
    @Published private(set) var validationMessage: String?
    @Published private(set) var unresolvedMediaReferences: [String] = []
    @Published private(set) var isPreparingProjection = true
    @Published private(set) var isRetryingArtifactDraft = false
    @Published var isDiscardConfirmationPresented = false
    @Published private var pendingLocalRevision: Int?
    @Published private var pendingFinalAction: FinalAction?

    let store: MergeSessionStore
    private let worker: MergeArtifactEditorWorker
    private let requestedDisplayURLs: [String: String]
    private var authorizedDisplayURLs: [String: String] = [:]
    private var preservationManifest = Data()
    private var hasLosslessProjection = false
    private var projectedDraftIdentity: DraftProjectionIdentity
    private var projectionGeneration = UUID()
    private var projectionTask: Task<Void, Never>?
    private var canonicalReconciliationTask: Task<Void, Never>?
    private var localRevision = 0
    private var draftQueue: [DraftWork] = []
    private var conversionTask: Task<Void, Never>?
    private var failedDraft: DraftWork?
    private var storeObservation: AnyCancellable?
    private var bodyModelObservation: AnyCancellable?
    private var editorControllerObservation: AnyCancellable?

    private let lifetimeID = UUID()
    private weak var lifetimeCoordinator: MergeTaskCoordinator?
    private var isHostVisible = false
    private var isClosing = false
    private var closedAttachments: [BlockNoteEditorAttachment] = []
    private var finalFlushTask: Task<Void, Never>?

    init(store: MergeSessionStore,
         authorizedDisplayURLsByMediaReference: [String: String] = [:],
         worker: MergeArtifactEditorWorker? = nil) {
        self.store = store
        self.worker = worker ?? store.editorWorker
        requestedDisplayURLs = authorizedDisplayURLsByMediaReference
        let initialTags = CardEditingTag.normalize(store.artifactDraft?.tags ?? store.artifact?.presentation.tags ?? [])
        tags = initialTags
        projectedDraftIdentity = DraftProjectionIdentity(
            documentJSON: store.artifactDraft?.documentJSON ?? store.artifact?.documentJSON ?? Data(), tags: initialTags)
        bodyModel = BlockNoteCardEditorModel(document: .init(contentJSON: nil, fallbackMarkdown: "", profile: .mergeArtifact), editable: false)
        storeObservation = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.reconcileCanonicalProjectionAfterStoreChange()
            }
        }
        reloadFromStore(preservePendingTagInput: false)
    }

    var levelStyle: CardLevelStyle {
        CardLevelStyle(rate: store.artifactDraft?.rate ?? store.artifact?.presentation.rate ?? 1)
    }
    var isPreparingAccept: Bool { pendingFinalAction?.kind == .accept }
    var canEdit: Bool {
        store.phase == .ready && !store.isOperationInFlight && !isClosing
            && !isPreparingProjection && pendingFinalAction == nil && bodyModel.canMutate
    }
    var canBack: Bool {
        store.phase == .ready && !store.isOperationInFlight && !isClosing
            && !isPreparingProjection && pendingFinalAction == nil
    }
    var canDiscard: Bool { canBack && pendingLocalRevision == nil }
    var canAccept: Bool {
        guard canBack, pendingLocalRevision == nil, bodyModel.canSave, hasLosslessProjection else { return false }
        switch store.artifactDraftSyncState {
        case .clean, .dirty: return true
        case .saving, .unsynced, .conflict: return false
        }
    }
    var canRetryArtifactDraft: Bool {
        guard canBack, !isRetryingArtifactDraft,
              case let .unsynced(failure) = store.artifactDraftSyncState else { return false }
        switch failure {
        case .timeout, .unavailable, .server, .unknown: return true
        case .offline, .validation: return false
        }
    }
    var syncMessage: String {
        if isPreparingProjection { return "Loading…" }
        if let validationMessage { return validationMessage }
        if store.artifactActionError != nil { return "That action didn’t finish. Your edits are still here." }
        if store.phase == .committing || isPreparingAccept { return "Accepting…" }
        if pendingLocalRevision != nil || isRetryingArtifactDraft { return "Saving…" }
        switch store.artifactDraftSyncState {
        case .clean: return "Saved"
        case .dirty: return "Unsaved changes"
        case .saving: return "Saving…"
        case .unsynced(.offline): return "Offline — changes are saved on this device"
        case .unsynced(.validation): return "Fix the highlighted content before accepting"
        case .unsynced: return "Not synced — try again"
        case .conflict: return "A newer server version conflicts with these edits"
        }
    }
    var isConflict: Bool {
        if case .conflict = store.artifactDraftSyncState { return true }
        return false
    }

    func beginTag() {
        guard canEdit, tags.count < CardEditingTag.maximumCount else { return }
        bodyModel.dismissKeyboard()
        tagInput = ""
        isAddingTag = true
    }
    func completeTag() {
        guard isAddingTag, canEdit else { return }
        isAddingTag = false
        defer { tagInput = "" }
        guard let next = CardEditingTag.appending(tagInput, to: tags) else { return }
        tags = next
        updateProjectedDraftIdentity(tags: next)
        store.updateArtifactTags(next)
    }
    func removeTag(_ tag: String) {
        guard canEdit else { return }
        let next = tags.filter { $0 != tag }
        guard next != tags else { return }
        tags = next
        updateProjectedDraftIdentity(tags: next)
        store.updateArtifactTags(next)
    }

    func back(onMinimize: @escaping () -> Void) {
        guard canBack else { return }
        completeTag()
        let action = FinalAction(kind: .back)
        pendingFinalAction = action
        bodyModel.dismissKeyboard()
        Task { @MainActor in
            let saved = await persistCurrentSnapshot()
            guard pendingFinalAction?.id == action.id else { return }
            pendingFinalAction = nil
            if saved { onMinimize() }
        }
    }
    func discard() {
        guard canDiscard else { return }
        isDiscardConfirmationPresented = false
        bodyModel.dismissKeyboard()
        store.discardArtifact()
    }
    func requestDiscardConfirmation() {
        guard canDiscard else { return }
        bodyModel.dismissKeyboard()
        isDiscardConfirmationPresented = true
    }
    func accept() {
        guard canAccept else { return }
        completeTag()
        let action = FinalAction(kind: .accept)
        pendingFinalAction = action
        bodyModel.dismissKeyboard()
        Task { @MainActor in
            guard await persistCurrentSnapshot(), pendingFinalAction?.id == action.id else {
                finishAction(action)
                return
            }
            do {
                _ = try await store.flushArtifactDraft()
                guard pendingFinalAction?.id == action.id, !isClosing else { return }
                store.commit()
            } catch {
                // The store retains its exact pending operation for retry.
            }
            finishAction(action)
        }
    }
    private func finishAction(_ action: FinalAction) {
        if pendingFinalAction?.id == action.id { pendingFinalAction = nil }
    }
    func retryArtifactDraft() {
        guard canRetryArtifactDraft else { return }
        isRetryingArtifactDraft = true
        Task { @MainActor in
            defer { isRetryingArtifactDraft = false }
            guard await flushAcceptedDraft(), !isClosing else { return }
            do { _ = try await store.flushArtifactDraft() } catch { }
        }
    }
    func resolveConflict(_ resolution: MergeArtifactConflictResolution) {
        guard canBack, pendingLocalRevision == nil else { return }
        Task { @MainActor in
            await store.resolveArtifactConflict(resolution)
            if resolution == .reloadServer, !isClosing {
                reloadFromStore(preservePendingTagInput: false)
            }
        }
    }

    private func documentDidChange(_ revision: BlockNoteDocumentRevision, generation: UUID) {
        // UI locks stop new interaction. Already accepted bridge events still
        // belong to this generation, including those delivered during closing.
        guard generation == projectionGeneration, !isPreparingProjection, store.phase == .ready else { return }
        enqueueDraft(blockNoteJSON: revision.contentJSON)
    }

    private func persistCurrentSnapshot() async -> Bool {
        let generation = projectionGeneration
        let instance = bodyModel.editorInstanceID
        do {
            let snapshot = try await bodyModel.requestSnapshot()
            guard generation == projectionGeneration, instance == bodyModel.editorInstanceID else { return false }
            return await withCheckedContinuation { continuation in
                enqueueDraft(blockNoteJSON: snapshot.contentJSON, completion: continuation)
            }
        } catch {
            if generation == projectionGeneration, !isClosing {
                validationMessage = "The editor couldn’t capture the latest changes. Try again."
            }
            return false
        }
    }

    private func enqueueDraft(blockNoteJSON: String, completion: CheckedContinuation<Bool, Never>? = nil) {
        localRevision += 1
        let work = DraftWork(generation: projectionGeneration, instance: bodyModel.editorInstanceID,
            revision: localRevision, body: blockNoteJSON, manifest: preservationManifest, completion: completion)
        // Mark pending before any suspension or store notification can reload canonical content.
        pendingLocalRevision = work.revision
        failedDraft = nil
        if completion == nil, draftQueue.last?.completion == nil, !draftQueue.isEmpty {
            draftQueue[draftQueue.count - 1] = work
        } else { draftQueue.append(work) }
        guard conversionTask == nil else { return }
        conversionTask = Task { @MainActor in
            while !draftQueue.isEmpty {
                let work = draftQueue.removeFirst()
                let succeeded = await convert(work)
                work.completion?.resume(returning: succeeded)
            }
            conversionTask = nil
        }
    }

    private func convert(_ work: DraftWork) async -> Bool {
        do {
            let prepared = try await worker.prepareDraft(blockNoteJSON: work.body, preserving: work.manifest,
                displayURLsByMediaReference: authorizedDisplayURLs)
            guard isCurrent(work) else {
                // A bridge retry creates a new instance from the accepted body.
                // Re-submit that owner's value; never publish an old-instance result.
                rebindReplacedInstance(work)
                return false
            }
            guard pendingLocalRevision == work.revision, store.phase == .ready else { return false }
            tags = CardEditingTag.normalize(store.artifactDraft?.tags ?? tags)
            updateProjectedDraftIdentity(documentJSON: prepared.documentJSON, tags: tags)
            // Only the body/manifest are applied; tags retain their current owner and value.
            store.updateArtifactDraft(documentJSON: prepared.documentJSON, preservationManifest: work.manifest)
            unresolvedMediaReferences = prepared.unresolvedMediaReferences
            hasLosslessProjection = true
            validationMessage = nil
            pendingLocalRevision = nil
            failedDraft = nil
            return true
        } catch {
            rebindReplacedInstance(work)
            if isCurrent(work), pendingLocalRevision == work.revision {
                failedDraft = work.withoutCompletion
                hasLosslessProjection = false
                validationMessage = "This content can’t be accepted without losing information."
            }
            return false
        }
    }
    private func rebindReplacedInstance(_ work: DraftWork) {
        guard work.generation == projectionGeneration, work.instance != bodyModel.editorInstanceID,
              pendingLocalRevision == work.revision, let currentBody = bodyModel.contentJSON else { return }
        enqueueDraft(blockNoteJSON: currentBody)
    }
    private func isCurrent(_ work: DraftWork) -> Bool {
        work.generation == projectionGeneration && work.instance == bodyModel.editorInstanceID
    }

    func reloadFromStore(preservePendingTagInput: Bool) {
        guard !isClosing else { return }
        projectionGeneration = UUID()
        let generation = projectionGeneration
        projectionTask?.cancel()
        pendingFinalAction = nil
        for work in draftQueue { work.completion?.resume(returning: false) }
        draftQueue.removeAll()
        pendingLocalRevision = nil
        failedDraft = nil
        isPreparingProjection = true
        bodyModel.controller.beginClosing()
        let draft = store.artifactDraft
        let artifact = store.artifact
        let documentJSON = draft?.documentJSON ?? artifact?.documentJSON ?? Data()
        let projectedTags = CardEditingTag.normalize(draft?.tags ?? artifact?.presentation.tags ?? [])
        if !preservePendingTagInput { isAddingTag = false; tagInput = "" }
        projectionTask = Task { @MainActor [self] in
            let document: BlockNoteInitialDocument
            let compatibility: String?
            let manifest: Data
            do {
                let prepared = try await worker.project(cardDocumentJSON: documentJSON,
                    displayURLsByMediaReference: requestedDisplayURLs)
                guard generation == projectionGeneration else { return }
                manifest = draft?.preservationManifest.isEmpty == false
                    ? draft!.preservationManifest : prepared.editable.preservationManifest
                authorizedDisplayURLs = prepared.displayURLsByMediaReference
                unresolvedMediaReferences = prepared.unresolvedMediaReferences
                document = .init(contentJSON: prepared.editable.blockNoteJSON,
                    fallbackMarkdown: prepared.editable.fallbackMarkdown, profile: .mergeArtifact,
                    displayURLsByMediaReference: prepared.displayURLsByMediaReference)
                hasLosslessProjection = true
                validationMessage = nil
                compatibility = nil
            } catch {
                let fallback = await worker.fallbackMarkdown(from: artifact?.document)
                guard generation == projectionGeneration else { return }
                manifest = draft?.preservationManifest ?? Data()
                authorizedDisplayURLs = [:]
                unresolvedMediaReferences = []
                hasLosslessProjection = false
                validationMessage = "This artifact can’t be edited safely on this version."
                document = .init(contentJSON: nil, fallbackMarkdown: fallback, profile: .mergeArtifact)
                compatibility = "merge_artifact_codec_incompatible"
            }
            guard !isClosing else {
                isPreparingProjection = false
                projectionTask = nil
                return
            }
            preservationManifest = manifest
            tags = projectedTags
            projectedDraftIdentity = DraftProjectionIdentity(documentJSON: documentJSON, tags: tags)
            bodyModel = BlockNoteCardEditorModel(document: document, editable: compatibility == nil,
                initialCompatibilityBlock: compatibility,
                onDocumentChanged: { [weak self] in self?.documentDidChange($0, generation: generation) })
            observeBodyModel(generation: generation)
            isPreparingProjection = false
            projectionTask = nil
            reconcileCanonicalProjectionAfterStoreChange()
        }
    }

    func waitUntilPrepared() async {
        while let task = projectionTask { await task.value }
    }
    private func observeBodyModel(generation: UUID) {
        bodyModelObservation = bodyModel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        editorControllerObservation = bodyModel.$controller.sink { [weak self] controller in
            controller.onAttachmentWillClose = { [weak self] attachment in
                guard let self, generation == self.projectionGeneration else { return }
                self.closedAttachments.append(attachment)
                self.scheduleFinalFlush()
            }
        }
    }
    private func updateProjectedDraftIdentity(documentJSON: Data? = nil, tags: [String]? = nil) {
        projectedDraftIdentity = DraftProjectionIdentity(
            documentJSON: documentJSON ?? projectedDraftIdentity.documentJSON,
            tags: CardEditingTag.normalize(tags ?? projectedDraftIdentity.tags))
    }
    private var canReconcileCanonicalProjection: Bool {
        guard !isClosing, !isPreparingProjection, pendingLocalRevision == nil, pendingFinalAction == nil,
              store.phase == .ready, case .clean = store.artifactDraftSyncState,
              let draft = store.artifactDraft, draft.pendingSave == nil else { return false }
        return DraftProjectionIdentity(documentJSON: draft.documentJSON, tags: CardEditingTag.normalize(draft.tags))
            != projectedDraftIdentity
    }
    private func reconcileCanonicalProjectionAfterStoreChange() {
        guard canReconcileCanonicalProjection, canonicalReconciliationTask == nil else { return }
        let generation = projectionGeneration
        let controller = bodyModel.controller
        let attachment = controller.attachment
        canonicalReconciliationTask = Task { @MainActor in
            while true {
                // Each drain has a fixed cutoff. Recheck the live mailbox on
                // MainActor before replacing it so later accepted edits survive.
                await attachment?.drainAcceptedEvents()
                while let task = conversionTask { await task.value }
                guard generation == projectionGeneration else {
                    canonicalReconciliationTask = nil
                    return
                }
                guard bodyModel.controller === controller, controller.attachment?.id == attachment?.id else {
                    canonicalReconciliationTask = nil
                    reconcileCanonicalProjectionAfterStoreChange()
                    return
                }
                guard canReconcileCanonicalProjection else {
                    canonicalReconciliationTask = nil
                    return
                }
                if attachment?.hasPendingAcceptedEvents != true { break }
            }
            canonicalReconciliationTask = nil
            // No await between the empty-mailbox check and sealing this binding.
            reloadFromStore(preservePendingTagInput: true)
        }
    }

    func setHostVisible(_ visible: Bool, coordinator: MergeTaskCoordinator?) {
        isHostVisible = visible
        if visible, let coordinator, let jobID = store.activeSnapshot?.jobID {
            lifetimeCoordinator = coordinator
            coordinator.registerEditorDrain(id: lifetimeID, jobID: jobID,
                beginClosing: { [self] in beginClosing() }, drain: { [self] in await flushAcceptedDraft() })
        }
        if !visible {
            lifetimeCoordinator?.editorWillDisappear(id: lifetimeID)
            scheduleFinalFlush()
        }
    }
    func beginClosing() {
        completeTag()
        isClosing = true
        pendingFinalAction = nil
        bodyModel.controller.beginClosing()
    }
    func flushAcceptedDraft() async -> Bool {
        let retryFailed = failedDraft != nil
        let original = bodyModel.controller.attachment
        var attachments = closedAttachments
        if let original, !attachments.contains(where: { $0.id == original.id }) { attachments.append(original) }
        for attachment in attachments { await attachment.drainAcceptedEvents() }
        while let task = conversionTask { await task.value }
        if retryFailed, let failedDraft, isCurrent(failedDraft) {
            enqueueDraft(blockNoteJSON: failedDraft.body)
            while let task = conversionTask { await task.value }
        }
        guard pendingLocalRevision == nil else { return false }
        let drained = Set(attachments.map(\.id))
        closedAttachments.removeAll { drained.contains($0.id) }
        return true
    }
    private func scheduleFinalFlush() {
        guard finalFlushTask == nil else { return }
        finalFlushTask = Task { @MainActor in
            let saved = await flushAcceptedDraft()
            finalFlushTask = nil
            if !saved, !isHostVisible {
                lifetimeCoordinator?.editorDrainFailed(id: lifetimeID)
            }
            if saved, !closedAttachments.isEmpty { scheduleFinalFlush() }
            if saved, !isHostVisible, bodyModel.controller.attachment?.isClosing != false, closedAttachments.isEmpty {
                lifetimeCoordinator?.unregisterEditorDrain(id: lifetimeID)
            }
        }
    }

    private struct DraftProjectionIdentity: Equatable { let documentJSON: Data; let tags: [String] }
    private struct FinalAction {
        enum Kind { case accept, back }
        let id = UUID()
        let kind: Kind
    }
    private struct DraftWork {
        let generation: UUID
        let instance: UUID
        let revision: Int
        let body: String
        let manifest: Data
        let completion: CheckedContinuation<Bool, Never>?
        var withoutCompletion: DraftWork {
            DraftWork(generation: generation, instance: instance, revision: revision, body: body,
                manifest: manifest, completion: nil)
        }
    }
}
