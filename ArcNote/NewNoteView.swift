import AVFoundation
import BlockNoteEditor
import Combine
import CoreFlow
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct CardEditorSeed: Identifiable {
    let id: UUID
    let document: BlockNoteInitialDocument
    let revision: Int
    let isNew: Bool
    let initialFocus: Bool
    let initialIsPublic: Bool
    let isPinned: Bool

    static func newNote() -> CardEditorSeed {
        CardEditorSeed(
            id: UUID(),
            document: BlockNoteInitialDocument(
                contentJSON: nil,
                fallbackMarkdown: ""
            ),
            revision: 0,
            isNew: true,
            initialFocus: true,
            initialIsPublic: false,
            isPinned: false
        )
    }
}

private struct CardEditorLinkEdge: Hashable {
    let sourceCardID: String
    let targetCardID: String
}

struct NewNoteView: View {
    @Environment(\.dismiss) private var dismiss

    let cardId: String
    let onCreated: (String, String) -> Void

    @StateObject private var editingStore: CardEditingStore
    @State private var editorSeed: CardEditorSeed?
    @State private var loadErrorMessage: String?
    @State private var isLoading = false
    @State private var didStartLoading = false
    @State private var localEditingService: LocalCoreCardEditingService

    init(
        cardId: String = "",
        onCreated: @escaping (String, String) -> Void = { _, _ in }
    ) {
        self.cardId = cardId
        self.onCreated = onCreated
        let scope = AuthManager.shared.currentNoteScope ?? NoteStoreScope(actorID: "", environmentID: APIConfiguration.baseURL)
        let creationID = UUID().uuidString
        let service = LocalCoreCardEditingService(identifier: cardId.isEmpty ? nil : cardId, creationID: creationID, scope: scope)
        _localEditingService = State(initialValue: service)

        let isNew = cardId.isEmpty
        _editingStore = StateObject(
            wrappedValue: CardEditingStore(
                cardID: isNew ? nil : cardId,
                createRequestID: creationID,
                draft: CardEditingDraft(
                    title: nil,
                    content: "",
                    tags: [],
                    isPublic: false
                ),
                backgroundMediaRef: nil,
                links: [],
                service: service,
                preservesLocalDrafts: true
            )
        )
        _editorSeed = State(initialValue: isNew ? .newNote() : nil)
    }

    var body: some View {
        Group {
            if let seed = editorSeed {
                CardEditorSessionView(
                    seed: seed,
                    editingStore: editingStore,
                    localEditingService: localEditingService,
                    onCreated: onCreated
                )
                .id(seed.id)
            } else {
                CardEditorLoadingView(
                    isLoading: isLoading,
                    errorMessage: loadErrorMessage,
                    onBack: dismiss.callAsFunction,
                    onRetry: loadExistingCard
                )
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled()
        .task {
            guard !cardId.isEmpty, !didStartLoading else { return }
            didStartLoading = true
            loadExistingCard()
        }
        .cardNavigationHost()
        .toolbar(.hidden, for: .tabBar)
    }

    private func loadExistingCard() {
        guard !cardId.isEmpty, !isLoading else { return }
        isLoading = true
        loadErrorMessage = nil

        Task {
            defer { isLoading = false }
            do {
                let note = try await localEditingService.openExisting()
                let displayURLs = try await localEditingService.imageDisplayURLs()
                guard editorSeed == nil else { return }
                editingStore.hydrate(draft: CardEditingDraft(title: note.body.title, content: note.body.content,
                    contentJSON: note.body.contentJSON, editorAtmosphere: note.editorAtmosphere, tags: note.body.tags, isPublic: note.isPublic),
                    bodyRevision: Int(note.bodyRevision), backgroundMediaRef: note.backgroundMediaRef, links: [])
                editorSeed = CardEditorSeed(id: UUID(), document: BlockNoteInitialDocument.existingCard(contentJSON: note.body.contentJSON, fallbackMarkdown: note.body.content, displayURLsByMediaReference: displayURLs),
                    revision: Int(note.bodyRevision), isNew: false, initialFocus: false, initialIsPublic: note.isPublic, isPinned: note.isPinned ?? false)
                // Body hydration establishes the local identity before its relationships.
                // The store rejects reads overtaken by a newer edit/link operation.
                await editingStore.loadRelatedLinks()
            } catch {
                loadErrorMessage = "Couldn't open this local note. Your saved data has been kept."
            }
        }
    }


}

@MainActor
private final class CardEditorNativeActionRouter: ObservableObject {
    var onRequestCardLink: () -> Void = {}
    var onRequestInlineLink: () -> Void = {}
    var onRequestInlineImage: () -> Void = {}
    var onSelectedLink: (LinkItem) -> Void = { _ in }

    func requestCardLink() {
        onRequestCardLink()
    }

    func requestInlineLink() {
        onRequestInlineLink()
    }

    func requestInlineImage() {
        onRequestInlineImage()
    }

    func selectLink(_ item: LinkItem) {
        onSelectedLink(item)
    }
}

@MainActor
private struct CardEditorSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var localNotes = LocalNotesController.shared
    @ObservedObject private var authManager = AuthManager.shared
    @Environment(\.navigateCard) private var navigateCard

    let seed: CardEditorSeed
    let onCreated: (String, String) -> Void

    @ObservedObject private var editingStore: CardEditingStore
    @ObservedObject private var linkPopupManager = LinkPopupManager.shared
    @StateObject private var bodyModel: BlockNoteCardEditorModel
    @StateObject private var persistenceSession: LocalNoteEditorPersistenceSession
    @StateObject private var nativeActionRouter: CardEditorNativeActionRouter

    @State private var isAddingTag = false
    @State private var tagInput = ""
    @State private var showBackgroundPicker = false
    @State private var showBackgroundActions = false
    @State private var selectedBackgroundPhoto: PhotosPickerItem?
    @State private var showInlineImageSourceDialog = false
    @State private var showInlineImagePhotoPicker = false
    @State private var showInlineImageCamera = false
    @State private var showCameraSettingsAlert = false
    @State private var selectedInlineImagePhoto: PhotosPickerItem?
    @State private var showInlineLinkSheet = false
    @State private var showCardActions = false
    @State private var showRemoveCardConfirmation = false
    @State private var showCloseWithoutSavingConfirmation = false
    @State private var pendingOntologyLinkSourceID: String?
    @State private var unlinkingLinkID: String?
    @State private var saveMessage: String?
    @State private var hasSaveFailure = false
    @State private var failedCommitBaseline: CardEditorCommitBaseline?
    @State private var isSaving = false
    @State private var isLoadingBackgroundPhoto = false
    @State private var isProcessingInlineImage = false
    @State private var inlineImageTask: Task<Void, Never>?
    @State private var inlineImageGeneration = UUID()
    @State private var isPreparingCardAction = false
    @State private var isCardActionInFlight = false
    @State private var didNotifyCreation: Bool
    @State private var isPinned: Bool
    @State private var cancellables = Set<AnyCancellable>()
    @State private var autosaveTask: Task<Void, Never>?
    @State private var showCloudVersionConfirmation = false
    @State private var isResolvingConflict = false

    init(
        seed: CardEditorSeed,
        editingStore: CardEditingStore,
        localEditingService: LocalCoreCardEditingService,
        onCreated: @escaping (String, String) -> Void
    ) {
        self.seed = seed
        self.onCreated = onCreated
        _editingStore = ObservedObject(wrappedValue: editingStore)
        _didNotifyCreation = State(initialValue: !seed.isNew)
        _isPinned = State(initialValue: seed.isPinned)

        let router = CardEditorNativeActionRouter()
        _nativeActionRouter = StateObject(wrappedValue: router)
        let model = BlockNoteCardEditorModel(
                document: seed.document,
                initialRevision: seed.revision,
                initiallyFocused: seed.initialFocus,
                localImageSource: BlockNoteLocalImageSource(scheme: NoteAttachmentFiles.previewScheme) { url in
                    try await localEditingService.imagePreview(url)
                },
                onDocumentChanged: { revision in
                    _ = editingStore.applyBodyRevision(
                        content: revision.fallbackMarkdown,
                        contentJSON: revision.contentJSON,
                        revision: revision.revision
                    )
                },
                onRequestCardLink: router.requestCardLink,
                onRequestInlineLink: router.requestInlineLink,
                onRequestInlineImage: router.requestInlineImage
        )
        _bodyModel = StateObject(wrappedValue: model)
        _persistenceSession = StateObject(wrappedValue: LocalNoteEditorPersistenceSession(
            scope: localEditingService.scope, editingStore: editingStore,
            bodyModel: model, isNew: seed.isNew, initialIsPublic: seed.initialIsPublic
        ))
    }

    private var editorShell: some View {
        CardEditorShell(
            bodyModel: bodyModel,
            tags: editingStore.draft.tags,
            links: editorLinkItems,
            unlinkingLinkID: unlinkingLinkID,
            isLinkRemovalEnabled: bodyModel.canMutate
                && !isBusy
                && cloudCardID != nil
                && unlinkingLinkID == nil,
            background: editorBackground,
            isPublic: editingStore.draft.isPublic,
            isMetadataEditable: bodyModel.canMutate && !isBusy,
            isInlineImageProcessing: isProcessingInlineImage,
            saveMessage: saveMessage,
            isAddingTag: isAddingTag,
            tagInput: $tagInput,
            leadingControlState: leadingControlState,
            onLeadingControl: handleLeadingControl,
            onBeginTag: beginTagEntry,
            onCompleteTag: completeTagEntry,
            onRemoveTag: removeTag,
            onRemoveLink: removeOntologyLink,
            onTogglePrivacy: togglePrivacy,
            onOpenCardActions: cardActionsHandler,
            menuActions: nativeMenuActions,
            isPrivacyEditable: cloudCardID != nil,
            saveStatus: localSaveStatus,
            onReviewVersions: canReviewVersions ? {
                completeTagEntry()
                bodyModel.dismissKeyboard()
                showCloudVersionConfirmation = true
            } : nil
        )
    }

    var body: some View {
        editorShell
        .overlay {
            if showCardActions {
                CardEditorActionBox(
                    isPresented: $showCardActions,
                    isEnabled: bodyModel.canMutate && !isBusy && cloudCardID != nil,
                    isPinned: isPinned,
                    onBackground: presentBackgroundActions,
                    onSpark: {
                        performPersistedCardAction(
                            .navigation(CardNavigationRoute.spark)
                        )
                    },
                    onMerge: {
                        performPersistedCardAction(
                            .navigation(CardNavigationRoute.merge)
                        )
                    },
                    onShare: { performPersistedCardAction(.notification("ShowCardShare")) },
                    onLink: addOntologyLink,
                    onRoot: {
                        performPersistedCardAction(
                            .navigation {
                                .root(cardID: $0, type: nil)
                            }
                        )
                    },
                    onRemove: { showRemoveCardConfirmation = true },
                    onTogglePin: { performPersistedCardAction(.togglePin) }
                )
            }
        }
        .alert("Remove this note?", isPresented: $showRemoveCardConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive, action: removeCanonicalCard)
        } message: {
            Text(
                editingStore.cardID == nil
                    ? "The unsaved draft will be discarded."
                    : "The note will be moved to Trash."
            )
        }
        .alert(
            "Close without saving?",
            isPresented: $showCloseWithoutSavingConfirmation
        ) {
            Button("Keep Editing", role: .cancel) {}
            Button("Close", role: .destructive, action: dismiss.callAsFunction)
                .accessibilityIdentifier("cardEditorDiscardAndClose")
        } message: {
            Text(
                "The editor cannot produce a safe snapshot. "
                    + "Any unsaved changes will be discarded."
            )
        }
        .photosPicker(
            isPresented: $showBackgroundPicker,
            selection: $selectedBackgroundPhoto,
            matching: .images
        )
        .photosPicker(
            isPresented: $showInlineImagePhotoPicker,
            selection: $selectedInlineImagePhoto,
            matching: .images
        )
        .cardEditorInlineImageSourceDialog(
            isPresented: $showInlineImageSourceDialog,
            isCameraAvailable: isInlineImageCameraAvailable,
            onSelect: handleInlineImageSourceSelection
        )
        .cardEditorBackgroundActionDialog(
            isPresented: $showBackgroundActions,
            context: backgroundActionContext,
            onSelect: handleBackgroundAction
        )
        .fullScreenCover(isPresented: $showInlineImageCamera) {
            CardEditorCameraPicker(
                onCapture: handleCapturedInlineImage,
                onCancel: { showInlineImageCamera = false }
            )
            .ignoresSafeArea()
        }
        .alert("Camera Access Needed", isPresented: $showCameraSettingsAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Open Settings", action: openCameraSettings)
        } message: {
            Text(
                "Allow camera access in Settings to take a photo for this note."
            )
        }
        .onChange(
            of: selectedBackgroundPhoto,
            perform: handleSelectedBackgroundPhoto
        )
        .onChange(
            of: selectedInlineImagePhoto,
            perform: handleSelectedInlineImagePhoto
        )
        .onChange(
            of: linkPopupManager.isShowing,
            perform: handleLinkPopupVisibilityChange
        )
        .sheet(isPresented: $showInlineLinkSheet) {
            CardEditorInlineLinkSheet { url, text in
                bodyModel.insertLink(url: url, text: text)
            }
        }
        .onAppear {
            configureNativeActions()
            persistenceSession.setVisible(true)
            localNotes.registerEditor(persistenceSession)
        }
        .onChange(of: editingStore.draft) { _ in scheduleLocalSave() }
        .onChange(of: persistenceSession.hasSaveFailure) { failed in
            if failed {
                saveMessage = "Couldn't save on this device. Keep this note open and retry."
                hasSaveFailure = true
            }
        }
        .confirmationDialog(
            currentLocalNote?.remoteSnapshot == nil ? "Cloud version unavailable" : "Cloud version changed",
            isPresented: $showCloudVersionConfirmation,
            titleVisibility: .visible
        ) {
            if currentLocalNote?.remoteSnapshot != nil {
                Button("Use cloud version", role: .destructive) { resolveConflict(useCloud: true) }
            }
            Button("Keep mine as a new note") { resolveConflict(useCloud: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let note = currentLocalNote {
                let message = note.remoteSnapshot == nil
                    ? "Your edits are saved on this device."
                    : "Using the cloud version replaces your local edits."
                Text(NoteSyncPayload.hasUndownloadedImages(note)
                    ? message + " Connect to download the images for a new note."
                    : message)
            }
        }
        .disabled(isResolvingConflict)
        .allowsHitTesting(!isResolvingConflict)
        .onChange(of: scenePhase) { phase in
            if phase != .active { flushLocalSave() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cardReadSessionDidChange)) { _ in
            cancelInlineImagePreparation()
        }
        .onDisappear {
            cancelInlineImagePreparation()
            flushLocalSave()
            persistenceSession.setVisible(false)
            bodyModel.dismissKeyboard()
            LinkPopupManager.shared.onCardSelected = nil
        }
    }

    private var currentLocalNote: OfflineNote? {
        guard let id = editingStore.cardID else { return nil }
        return localNotes.library.notes.first { NoteLibraryStore.identifier($0) == id || $0.serverAssetID == id }
    }

    private var cloudCardID: String? {
        guard authManager.canEnterProduct, localNotes.library.cloudEnabled,
              currentLocalNote?.isSynchronized == true,
              let id = editingStore.cardID else { return nil }
        return localNotes.library.serverID(for: id)
    }

    private var canReviewVersions: Bool {
        guard let note = currentLocalNote, note.pendingOperation == nil else { return false }
        return note.remoteSnapshot != nil || note.syncIssue == "remote_unavailable"
    }

    private func resolveConflict(useCloud: Bool) {
        guard !isResolvingConflict, canReviewVersions, let id = editingStore.cardID,
              !useCloud || currentLocalNote?.remoteSnapshot != nil else { return }
        isResolvingConflict = true
        bodyModel.dismissKeyboard()
        Task {
            defer { isResolvingConflict = false }
            do {
                if bodyModel.canSave { _ = try await applyCurrentSnapshot() }
                await persistLocalDraft()
                guard !editingStore.isDirty else { return }
                if useCloud { try await localNotes.library.useCloudVersion(identifier: id) }
                else {
                    _ = try await localNotes.library.saveLocalAsNewNote(identifier: id)
                }
                dismiss()
            } catch {
                saveMessage = "Couldn't apply that choice. Your edits are still on this device."
            }
        }
    }

    private var localSaveStatus: String? {
        if editingStore.isDirty { return "Saving on this device…" }
        guard let note = currentLocalNote else { return nil }
        if note.remoteSnapshot != nil || note.syncIssue == "conflict" { return "Saved on this device · Cloud version changed" }
        if note.syncIssue == "remote_unavailable" { return "Saved on this device · Cloud version unavailable" }
        if note.syncIssue == "unsupported_document" { return "Saved on this device · This content can't sync yet" }
        if authManager.sessionPhase == .needsLogin { return "Saved on this device · Sign in to sync" }
        if note.syncIssue != nil { return "Saved on this device · Sync needs attention" }
        return note.isSynchronized ? "Synced" : "Saved on this device · Waiting to sync"
    }

    private func scheduleLocalSave() {
        guard autosaveTask == nil else { return }
        autosaveTask = Task {
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { autosaveTask = nil; return }
            await persistLocalDraft()
            autosaveTask = nil
            if editingStore.isDirty, !hasSaveFailure { scheduleLocalSave() }
        }
    }

    private func flushLocalSave() {
        autosaveTask?.cancel()
        autosaveTask = nil
        // A short OS background allowance is for flushing local bytes only.
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "Save local note")
        Task {
            defer { if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) } }
            await persistLocalDraft()
        }
    }

    private func persistLocalDraft() async {
        let saved = await persistenceSession.flushAcceptedEdits()
        notifyCreationIfNeeded()
        if !saved, persistenceSession.hasSaveFailure {
            saveMessage = "Couldn't save on this device. Keep this note open and retry."
            hasSaveFailure = true
        } else if saved {
            saveMessage = nil
            resolveSaveFailure()
        }
    }

    private var isBusy: Bool {
        if isSaving || isResolvingConflict || isLoadingBackgroundPhoto || isProcessingInlineImage
            || isPreparingCardAction || isCardActionInFlight {
            return true
        }
        switch editingStore.phase {
        case .saving, .linking, .updatingBackground:
            return true
        case .idle, .ready, .failed:
            return false
        }
    }

    private var isInlineImageCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var hasPendingInlineTagCandidate: Bool {
        isAddingTag
            && CardEditingTag.appending(
                tagInput,
                to: editingStore.draft.tags
            ) != nil
    }

    private var isUntouchedNewDraft: Bool {
        editingStore.cardID == nil
            && seed.isNew
            && !editingStore.draft.hasMeaningfulContent
            && editingStore.draft.tags.isEmpty
            && editingStore.draft.isPublic == seed.initialIsPublic
            && editingStore.backgroundIntent == .unchanged
            && editingStore.backgroundMediaRef == nil
    }

    private var hasPendingCommit: Bool {
        if hasPendingInlineTagCandidate { return true }
        if editingStore.cardID == nil, isUntouchedNewDraft { return false }
        if hasUncommittedEditorRevision { return true }
        if editingStore.cardID != nil { return editingStore.isDirty }
        return true
    }

    private var hasUncommittedEditorRevision: Bool {
        if let committedRevision = editingStore.lastCommittedBodyRevision {
            return bodyModel.revision != committedRevision
        }
        return bodyModel.revision != seed.revision
    }

    private var currentCommitBaseline: CardEditorCommitBaseline {
        CardEditorCommitBaseline(
            draft: editingStore.draft,
            bodyRevision: editingStore.bodyRevision,
            editorRevision: bodyModel.revision,
            backgroundIntent: editingStore.backgroundIntent
        )
    }

    private var hasCorrelatedSaveFailure: Bool {
        hasSaveFailure && failedCommitBaseline == currentCommitBaseline
    }

    private var editingStoreHasFailure: Bool {
        if editingStore.failureStage != nil { return true }
        if case .failed = editingStore.phase { return true }
        return false
    }

    private var leadingControlState: CardEditorLeadingControlState {
        if isSaving { return .saving }
        if bodyModel.compatibilityNotice != nil { return .readOnly }
        if bodyModel.bridgeFailureNotice != nil { return .bridgeFailed }
        if hasCorrelatedSaveFailure { return .retry }
        return hasPendingCommit ? .save : .back
    }

    private var cardActionsHandler: (() -> Void)? {
        guard bodyModel.canSave, !isBusy else { return nil }
        return { openCardActions() }
    }

    private var nativeMenuActions: CardEditorMenuActions {
        CardEditorMenuActions(
            isPinned: isPinned,
            prepare: {
                completeTagEntry()
                bodyModel.dismissKeyboard()
                saveMessage = nil
                hideSaveFailure()
            },
            background: presentBackgroundActions,
            spark: { performPersistedCardAction(.navigation(CardNavigationRoute.spark)) },
            merge: { performPersistedCardAction(.navigation(CardNavigationRoute.merge)) },
            share: { performPersistedCardAction(.notification("ShowCardShare")) },
            link: addOntologyLink,
            root: { performPersistedCardAction(.navigation { .root(cardID: $0, type: nil) }) },
            remove: { showRemoveCardConfirmation = true },
            togglePin: { performPersistedCardAction(.togglePin) },
            cloudActionsEnabled: cloudCardID != nil,
            removeEnabled: bodyModel.canMutate && !isBusy
        )
    }

    private var editorBackground: CardEditorBackgroundSource {
        switch editingStore.backgroundIntent {
        case let .replace(image):
            return .local(image.data)
        case .remove:
            return .none
        case .unchanged:
            guard let mediaRef = editingStore.backgroundMediaRef,
                  let url = URL(
                      string: APIConfiguration.resourceURLString(mediaRef)
                  ) else {
                return .none
            }
            return .remote(url)
        }
    }

    private var backgroundActionContext: CardEditorBackgroundActionContext {
        switch editingStore.backgroundIntent {
        case .unchanged:
            return .visible(canRestoreOriginal: false)
        case .replace:
            return .visible(
                canRestoreOriginal: editingStore.backgroundMediaRef != nil
                    && editingStore.canRestoreBackground
            )
        case .remove:
            return .removed(
                canRestoreBackground: editingStore.canRestoreBackground
            )
        }
    }

    private var editorLinkItems: [CardEditorLinkItem] {
        guard editingStore.cardID != nil else { return [] }
        var seenEdges = Set<CardEditorLinkEdge>()
        return editingStore.links.compactMap { link in
            let edge = CardEditorLinkEdge(
                sourceCardID: link.sourceCardID,
                targetCardID: link.targetCardID
            )
            guard seenEdges.insert(edge).inserted else { return nil }
            return CardEditorLinkItem(
                sourceCardID: link.sourceCardID,
                targetCardID: link.targetCardID,
                title: link.authorName ?? link.title,
                previewHTML: link.previewHTML,
                avatarURL: link.authorAvatarURL,
                canRemove: true
            )
        }
    }

    private func removeOntologyLink(_ item: CardEditorLinkItem) {
        completeTagEntry()
        guard bodyModel.canMutate,
              !isBusy,
              item.canRemove,
              unlinkingLinkID == nil,
              let cardID = editingStore.cardID,
              (cardID == item.sourceCardID
                  || cardID == item.targetCardID),
              let link = editingStore.links.first(where: {
                  $0.sourceCardID == item.sourceCardID
                      && $0.targetCardID == item.targetCardID
              }) else { return }
        unlinkingLinkID = item.id
        Task {
            defer { unlinkingLinkID = nil }
            let didDelete = await editingStore.deleteLink(link)
            if didDelete {
                saveMessage = nil
                hideSaveFailure()
            } else {
                saveMessage = "Couldn't unlink. Try again."
            }
        }
    }

    private func isUntouchedNewSnapshot(_ snapshot: BlockNoteSnapshot) -> Bool {
        let snapshotDraft = CardEditingDraft(
            title: editingStore.draft.title,
            content: snapshot.fallbackMarkdown,
            contentJSON: snapshot.contentJSON,
            editorAtmosphere: editingStore.draft.editorAtmosphere,
            tags: editingStore.draft.tags,
            isPublic: editingStore.draft.isPublic
        )
        return editingStore.cardID == nil
            && seed.isNew
            && !snapshotDraft.hasMeaningfulContent
            && editingStore.draft.tags.isEmpty
            && editingStore.draft.isPublic == seed.initialIsPublic
            && editingStore.backgroundIntent == .unchanged
            && editingStore.pendingBackground == nil
            && editingStore.backgroundMediaRef == nil
    }

    private func configureNativeActions() {
        nativeActionRouter.onRequestCardLink = {
            addOntologyLink()
        }
        nativeActionRouter.onRequestInlineLink = presentInlineLinkSheet
        nativeActionRouter.onRequestInlineImage = {
            presentInlineImageSourceOptions()
        }
        nativeActionRouter.onSelectedLink = handleSelectedLink
        LinkPopupManager.shared.onCardSelected = { [weak nativeActionRouter] item in
            nativeActionRouter?.selectLink(item)
        }
    }

    private func handleLeadingControl() {
        guard !isBusy else { return }
        switch leadingControlState {
        case .save, .retry:
            saveCurrentSnapshot()
        case .back:
            verifyCurrentSnapshotAndDismiss()
        case .readOnly:
            dismiss()
        case .bridgeFailed:
            showCloseWithoutSavingConfirmation = true
        case .saving:
            break
        }
    }

    private func saveCurrentSnapshot() {
        guard !isSaving else { return }
        completeTagEntry()
        let priorFailedBaseline = failedCommitBaseline
        isSaving = true
        saveMessage = nil

        Task {
            defer { isSaving = false }
            do {
                let snapshot = try await applyCurrentSnapshot()
                let baseline = try commitBaseline(matching: snapshot)
                let didRecover = await recoverFrozenFailedOperationIfNeeded()
                let outcome: CardEditorCommitOutcome
                var failureBaseline: CardEditorCommitBaseline?
                if !didRecover {
                    failureBaseline = priorFailedBaseline
                    outcome = priorFailedBaseline == baseline
                        ? .failed
                        : .pendingNewerChanges
                } else if snapshotMatchesCommittedBaseline(snapshot) {
                    outcome = .clean
                } else if !commitBaselineMatchesCurrent(baseline) {
                    outcome = .pendingNewerChanges
                } else {
                    let didSave = await editingStore.save()
                    if !didSave, editingStoreHasFailure {
                        failureBaseline = baseline
                    }
                    outcome = classifyCommit(
                        baseline: baseline,
                        snapshot: snapshot,
                        didSave: didSave
                    )
                }
                notifyCreationIfNeeded()

                switch outcome {
                case .clean:
                    saveMessage = nil
                    resolveSaveFailure()
                case .pendingNewerChanges:
                    saveMessage = nil
                    if let failureBaseline {
                        failedCommitBaseline = failureBaseline
                        hideSaveFailure()
                    } else {
                        resolveSaveFailure()
                    }
                case .failed:
                    saveMessage = "Couldn't save this note. Retry when ready."
                    failedCommitBaseline = failureBaseline ?? baseline
                    hasSaveFailure = true
                }
            } catch CardEditorSessionError.staleSnapshot {
                saveMessage = nil
                failedCommitBaseline = priorFailedBaseline
                hasSaveFailure = priorFailedBaseline == currentCommitBaseline
            } catch CardEditorBodyError.compatibilityBlocked {
                dismiss.callAsFunction()
            } catch {
                saveMessage = "Couldn't take a safe editor snapshot. Retry."
                if let priorFailedBaseline {
                    failedCommitBaseline = priorFailedBaseline
                    hasSaveFailure = priorFailedBaseline == currentCommitBaseline
                } else {
                    failedCommitBaseline = currentCommitBaseline
                    hasSaveFailure = true
                }
            }
        }
    }

    private func classifyCommit(
        baseline: CardEditorCommitBaseline,
        snapshot: BlockNoteSnapshot,
        didSave: Bool
    ) -> CardEditorCommitOutcome {
        let exactRevision = editingStore.lastCommittedBodyRevision == snapshot.revision
            && editingStore.bodyRevision == snapshot.revision
            && bodyModel.revision == snapshot.revision
        if didSave, exactRevision, !editingStore.isDirty {
            return .clean
        }
        if !commitBaselineMatchesCurrent(baseline) {
            return .pendingNewerChanges
        }
        if editingStore.failureStage == nil,
           editingStore.phase == .ready,
           (editingStore.isDirty || !exactRevision) {
            return .pendingNewerChanges
        }
        return .failed
    }

    private func verifyCurrentSnapshotAndDismiss() {
        guard !isSaving else { return }
        completeTagEntry()
        isSaving = true

        Task {
            defer { isSaving = false }
            do {
                let snapshot = try await applyCurrentSnapshot()
                // Back can receive a newer WebKit revision than the last autosave.
                await persistLocalDraft()
                if isUntouchedNewSnapshot(snapshot) || snapshotMatchesCommittedBaseline(snapshot) {
                    resolveSaveFailure()
                    dismiss()
                }
            } catch CardEditorSessionError.staleSnapshot {
                saveMessage = nil
                hideSaveFailure()
            } catch CardEditorBodyError.compatibilityBlocked {
                resolveSaveFailure()
                dismiss()
            } catch {
                showCloseWithoutSavingConfirmation = true
            }
        }
    }

    private func snapshotMatchesCommittedBaseline(
        _ snapshot: BlockNoteSnapshot
    ) -> Bool {
        guard editingStore.cardID != nil,
              let committedDraft = editingStore.lastCommittedDraft,
              let committedRevision = editingStore.lastCommittedBodyRevision else {
            return false
        }
        return !editingStore.isDirty
            && editingStore.draft.isCommitEquivalent(to: committedDraft)
            && committedRevision == snapshot.revision
            && editingStore.bodyRevision == snapshot.revision
            && bodyModel.revision == snapshot.revision
    }

    private func applyCurrentSnapshot() async throws -> BlockNoteSnapshot {
        bodyModel.dismissKeyboard()
        let snapshot = try await bodyModel.requestSnapshot()
        guard editingStore.applyBodyRevision(
            content: snapshot.fallbackMarkdown,
            contentJSON: snapshot.contentJSON,
            revision: snapshot.revision
        ) else {
            throw CardEditorSessionError.staleSnapshot
        }
        return snapshot
    }

    private func commitBaseline(
        matching snapshot: BlockNoteSnapshot
    ) throws -> CardEditorCommitBaseline {
        let baseline = currentCommitBaseline
        guard baseline.bodyRevision == snapshot.revision,
              baseline.editorRevision == snapshot.revision else {
            throw CardEditorSessionError.staleSnapshot
        }
        return baseline
    }

    private func commitBaselineMatchesCurrent(
        _ baseline: CardEditorCommitBaseline
    ) -> Bool {
        baseline == currentCommitBaseline
    }

    private func hideSaveFailure() {
        hasSaveFailure = false
    }

    private func resolveSaveFailure() {
        hideSaveFailure()
        failedCommitBaseline = nil
    }

    private func recoverFrozenFailedOperationIfNeeded() async -> Bool {
        if let stage = editingStore.failureStage {
            switch stage {
            case .creatingLink, .deletingLink:
                return await editingStore.reconcileFailedRelationshipMutation()
            default:
                break
            }
        }
        guard editingStore.failureStage != nil else { return true }
        let didRetry = await editingStore.retry()
        if didRetry {
            return true
        }
        return editingStore.failureStage == nil
    }

    private func updateMetadata(
        tags: [String]? = nil,
        isPublic: Bool? = nil
    ) {
        editingStore.updateDraft(
            CardEditingDraft(
                title: editingStore.draft.title,
                content: editingStore.draft.content,
                contentJSON: editingStore.draft.contentJSON,
                editorAtmosphere: editingStore.draft.editorAtmosphere,
                tags: tags ?? editingStore.draft.tags,
                isPublic: isPublic ?? editingStore.draft.isPublic
            )
        )
        saveMessage = nil
        hideSaveFailure()
    }

    private func beginTagEntry() {
        guard bodyModel.canMutate, !isBusy else { return }
        bodyModel.dismissKeyboard()
        tagInput = ""
        isAddingTag = true
    }

    private func completeTagEntry() {
        guard isAddingTag else { return }
        let candidate = tagInput
        isAddingTag = false
        tagInput = ""
        guard let tags = CardEditingTag.appending(
            candidate,
            to: editingStore.draft.tags
        ) else {
            return
        }
        updateMetadata(tags: tags)
    }

    private func removeTag(_ tag: String) {
        completeTagEntry()
        updateMetadata(tags: editingStore.draft.tags.filter { $0 != tag })
    }

    private func togglePrivacy() {
        guard let serverID = cloudCardID, let id = editingStore.cardID,
              let scope = authManager.currentNoteScope else {
            saveMessage = "Sync this note before changing who can see it."
            return
        }
        completeTagEntry()
        let value = !editingStore.draft.isPublic
        NetworkManager.shared.updateCardVisibility(cardId: serverID, isPublic: value)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { result in
                if case .failure = result { saveMessage = "Couldn't update visibility." }
            }, receiveValue: { response in
                guard response.success, authManager.currentNoteScope == scope else { return }
                Task {
                    do {
                        try await localNotes.library.recordMetadata(identifier: id, isPublic: response.data.isPublic, scope: scope)
                        updateMetadata(isPublic: response.data.isPublic)
                    } catch { saveMessage = "Visibility changed in the cloud. Refresh to check it." }
                }
            }).store(in: &cancellables)
    }

    private func presentBackgroundActions() {
        guard !isBusy, cloudCardID != nil else { return }
        completeTagEntry()
        bodyModel.dismissKeyboard()
        saveMessage = nil
        hideSaveFailure()
        if editingStore.backgroundIntent == .unchanged,
           editingStore.backgroundMediaRef == nil {
            showBackgroundPicker = true
        } else {
            showBackgroundActions = true
        }
    }

    private func handleBackgroundAction(_ action: CardEditorBackgroundAction) {
        switch action {
        case .choosePhoto:
            saveMessage = nil
            hideSaveFailure()
            showBackgroundPicker = true
        case .remove:
            editingStore.stageBackgroundRemoval()
            saveMessage = nil
            hideSaveFailure()
        case .restore:
            guard editingStore.restoreBackground() else {
                saveMessage = "Retry the pending background change before restoring."
                return
            }
            saveMessage = nil
            hideSaveFailure()
        }
    }

    private func addOntologyLink() {
        guard !isBusy, let serverID = cloudCardID else { return }
        saveMessage = nil
        hideSaveFailure()
        Task {
            do {
                _ = try await applyCurrentSnapshot()
                guard await recoverFrozenFailedOperationIfNeeded() else {
                    notifyCreationIfNeeded()
                    saveMessage = "Save this note before adding a link."
                    return
                }
                guard let sourceID = await editingStore.ensurePersisted() else {
                    notifyCreationIfNeeded()
                    saveMessage = "Save this note before adding a link."
                    return
                }
                notifyCreationIfNeeded()
                resolveSaveFailure()
                pendingOntologyLinkSourceID = sourceID
                LinkPopupManager.shared.show(
                    cardId: serverID,
                    navigateAfterLink: false,
                    mode: .selectionOnly
                )
            } catch {
                saveMessage = "Couldn't take a safe snapshot for linking."
            }
        }
    }

    private func handleSelectedLink(_ item: LinkItem) {
        guard let sourceID = pendingOntologyLinkSourceID,
              editingStore.cardID == sourceID else {
            return
        }
        pendingOntologyLinkSourceID = nil
        let link = CardEditingLink(
            sourceCardID: sourceID,
            targetCardID: item.id,
            title: item.title,
            previewHTML: item.description,
            authorName: item.username,
            authorAvatarURL: item.avatar
        )
        Task {
            let didCreate = await editingStore.createLink(link)
            guard didCreate else {
                saveMessage = "Couldn't add that link. Retry."
                return
            }
            saveMessage = nil
            hideSaveFailure()
        }
    }

    private func presentInlineImageSourceOptions() {
        guard !isBusy else { return }
        completeTagEntry()
        bodyModel.dismissKeyboard()
        saveMessage = nil
        hideSaveFailure()
        showInlineImageSourceDialog = true
    }

    private func presentInlineLinkSheet() {
        completeTagEntry()
        bodyModel.dismissKeyboard()
        saveMessage = nil
        hideSaveFailure()
        showInlineLinkSheet = true
    }

    private func handleInlineImageSourceSelection(
        _ source: CardEditorInlineImageSource
    ) {
        switch source {
        case .photoLibrary:
            showInlineImagePhotoPicker = true
        case .camera:
            requestInlineImageCamera()
        }
    }

    private func requestInlineImageCamera() {
        guard isInlineImageCameraAvailable else {
            saveMessage = "Camera isn't available on this device."
            hideSaveFailure()
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showInlineImageCamera = true
        case .notDetermined:
            Task {
                let isGranted = await AVCaptureDevice.requestAccess(for: .video)
                if isGranted {
                    showInlineImageCamera = true
                } else {
                    showCameraSettingsAlert = true
                }
            }
        case .denied, .restricted:
            showCameraSettingsAlert = true
        @unknown default:
            showCameraSettingsAlert = true
        }
    }

    private func openCameraSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }

    private func handleSelectedBackgroundPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        saveMessage = nil
        hideSaveFailure()
        isLoadingBackgroundPhoto = true
        Task {
            defer {
                selectedBackgroundPhoto = nil
                isLoadingBackgroundPhoto = false
            }
            do {
                let image = try await cardEditingImage(
                    from: item,
                    stem: "card-background"
                )
                guard editingStore.stageBackground(image) else {
                    saveMessage = "That background image can't be used."
                    hideSaveFailure()
                    return
                }
                saveMessage = nil
                hideSaveFailure()
            } catch {
                saveMessage = "Couldn't read that background image."
                hideSaveFailure()
            }
        }
    }

    private func handleSelectedInlineImagePhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        selectedInlineImagePhoto = nil
        beginInlineImageProcessing {
            try await cardEditingImage(
                from: item,
                stem: "inline-image"
            )
        }
    }

    private func handleCapturedInlineImage(_ image: UIImage) {
        showInlineImageCamera = false
        beginInlineImageProcessing {
            try await capturedCardEditingImage(image)
        }
    }

    private func cancelInlineImagePreparation() {
        inlineImageGeneration = UUID()
        inlineImageTask?.cancel()
        inlineImageTask = nil
        isProcessingInlineImage = false
    }

    private func beginInlineImageProcessing(
        _ makeImage: @escaping () async throws -> CardEditingImage
    ) {
        guard !isProcessingInlineImage else { return }
        isProcessingInlineImage = true
        saveMessage = nil
        hideSaveFailure()
        let generation = UUID()
        inlineImageGeneration = generation
        let authSession = authManager.sessionGeneration
        let scope = localNotes.library.scope

        inlineImageTask = Task {
            defer {
                if inlineImageGeneration == generation {
                    isProcessingInlineImage = false
                    inlineImageTask = nil
                }
            }
            do {
                let image = try await makeImage()
                guard !Task.isCancelled, inlineImageGeneration == generation,
                      authManager.sessionGeneration == authSession,
                      localNotes.library.scope == scope else { return }
                let uploaded = try await editingStore.uploadInlineImage(image)
                guard !Task.isCancelled, inlineImageGeneration == generation,
                      authManager.sessionGeneration == authSession,
                      localNotes.library.scope == scope else { return }
                bodyModel.insertImage(url: uploaded.url.absoluteString, alt: "Inline image")
                saveMessage = nil
                hideSaveFailure()
            } catch is CancellationError {
                // A replaced selection or closed editor has no result to publish.
            } catch {
                guard inlineImageGeneration == generation,
                      authManager.sessionGeneration == authSession else { return }
                saveMessage = "Couldn't insert that image. Your draft is unchanged."
                hideSaveFailure()
            }
        }
    }

    private func capturedCardEditingImage(_ image: UIImage) async throws -> CardEditingImage {
        try await CardImagePreparation.shared.jpeg(image, quality: 0.9, filename: "inline-camera.jpg")
    }

    private func cardEditingImage(
        from item: PhotosPickerItem,
        stem: String
    ) async throws -> CardEditingImage {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw CardEditorSessionError.imageUnavailable
        }
        let type = item.supportedContentTypes.first(where: {
            $0.conforms(to: .image)
        }) ?? .jpeg
        let fileExtension = type.preferredFilenameExtension ?? "jpg"
        return CardEditingImage(
            data: data,
            filename: "\(stem).\(fileExtension)",
            mimeType: type.preferredMIMEType ?? "image/jpeg"
        )
    }

    private func notifyCreationIfNeeded() {
        guard seed.isNew,
              !didNotifyCreation,
              let cardID = editingStore.cardID else {
            return
        }
        didNotifyCreation = true
        onCreated(
            cardID,
            editingStore.lastCommittedDraft?.content
                ?? editingStore.draft.content
        )
    }

    private func openCardActions() {
        guard bodyModel.canSave, !isBusy else { return }
        completeTagEntry()
        bodyModel.dismissKeyboard()
        saveMessage = nil
        hideSaveFailure()
        showCardActions = true
    }

    private func performPersistedCardAction(
        _ action: CardEditorPersistedAction
    ) {
        guard bodyModel.canSave, !isBusy, cloudCardID != nil else { return }
        isPreparingCardAction = true
        saveMessage = nil
        hideSaveFailure()
        Task {
            defer { isPreparingCardAction = false }
            do {
                _ = try await applyCurrentSnapshot()
                guard await recoverFrozenFailedOperationIfNeeded() else {
                    saveMessage = "Save this note before using that action."
                    return
                }
                guard await editingStore.ensurePersisted() != nil else {
                    saveMessage = "Save this note before using that action."
                    return
                }
                notifyCreationIfNeeded()
                saveMessage = nil
                resolveSaveFailure()
                executePersistedCardAction(action)
            } catch {
                saveMessage = "Couldn't take a safe snapshot for that action."
            }
        }
    }

    private func executePersistedCardAction(
        _ action: CardEditorPersistedAction
    ) {
        switch action {
        case .navigation(let route):
            guard let cardID = cloudCardID else { return }
            navigateCard(route(cardID))
        case let .notification(name):
            postCardAction(name)
        case .togglePin:
            togglePinnedCard()
        }
    }

    private func handleLinkPopupVisibilityChange(_ isShowing: Bool) {
        guard !isShowing,
              let sourceID = pendingOntologyLinkSourceID else { return }
        Task { @MainActor in
            await Task.yield()
            if pendingOntologyLinkSourceID == sourceID {
                pendingOntologyLinkSourceID = nil
            }
        }
    }

    private func postCardAction(_ name: String) {
        guard let cardID = cloudCardID else { return }
        NotificationCenter.default.post(
            name: NSNotification.Name(name),
            object: nil,
            userInfo: ["cardId": cardID]
        )
    }

    private func togglePinnedCard() {
        guard let cardID = cloudCardID,
              !isCardActionInFlight else { return }
        isCardActionInFlight = true
        saveMessage = nil
        hideSaveFailure()
        let request: AnyPublisher<PinResponse, NetworkError> = isPinned
            ? NetworkManager.shared.unpinCard(cardId: cardID)
            : NetworkManager.shared.pinCard(cardId: cardID)
        request
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isCardActionInFlight = false
                    if case .failure = completion {
                        saveMessage = "Couldn't update pin status."
                    }
                },
                receiveValue: { response in
                    if response.success {
                        isPinned.toggle()
                        saveMessage = nil
                        hideSaveFailure()
                    } else {
                        saveMessage = "Couldn't update pin status."
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func removeCanonicalCard() {
        guard !isCardActionInFlight else { return }
        isCardActionInFlight = true
        saveMessage = nil
        hideSaveFailure()
        Task {
            defer { isCardActionInFlight = false }
            // Save and change the local lifecycle without needing a cloud response.
            if bodyModel.canSave {
                do { _ = try await applyCurrentSnapshot() }
                catch { saveMessage = "Couldn't save this note before moving it to Trash."; return }
            }
            await persistLocalDraft()
            guard !editingStore.isDirty else { return }
            guard let cardID = editingStore.cardID else { dismiss(); return }
            do {
                try await localNotes.setLifecycle(identifier: cardID, lifecycle: .trashed)
                resolveSaveFailure()
                dismiss()
            } catch { saveMessage = "Couldn't move this note to Trash on this device. Your saved note is kept." }
        }
    }
}

private enum CardEditorSessionError: Error {
    case staleSnapshot
    case imageUnavailable
}

private enum CardEditorPersistedAction {
    case navigation((String) -> CardNavigationRoute)
    case notification(String)
    case togglePin
}

private struct CardEditorCommitBaseline: Equatable {
    let draft: CardEditingDraft
    let bodyRevision: Int
    let editorRevision: Int
    let backgroundIntent: CardEditingBackgroundIntent
}

private enum CardEditorCommitOutcome {
    case clean
    case pendingNewerChanges
    case failed
}

private struct CardEditorInlineLinkSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onInsert: (String, String) -> Void

    @State private var urlText = ""
    @State private var labelText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("https://example.com", text: $urlText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("cardEditorInlineLinkURL")
                TextField("Link text", text: $labelText)
                    .accessibilityIdentifier("cardEditorInlineLinkText")
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Insert Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert") {
                        guard let url = normalizedURL else { return }
                        let label = labelText
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        onInsert(
                            url.absoluteString,
                            label.isEmpty ? url.absoluteString : label
                        )
                        dismiss()
                    }
                    .disabled(normalizedURL == nil)
                    .accessibilityIdentifier("cardEditorInlineLinkInsert")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var normalizedURL: URL? {
        let value = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let candidate = value.contains("://") ? value : "https://\(value)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}

private struct CardEditorLoadingView: View {
    let isLoading: Bool
    let errorMessage: String?
    let onBack: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZenVisualTokens.background
                .ignoresSafeArea()

            VStack(spacing: 14) {
                if isLoading {
                    ProgressView()
                        .tint(ChoraiTheme.accent)
                    Text("Opening note…")
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                    Button("Retry", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("cardEditorLoadRetry")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)

            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ChoraiTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(ZenVisualTokens.background.opacity(0.82))
                    )
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.top, 6)
            .accessibilityLabel("Close note")
            .accessibilityIdentifier("cardEditorLeadingAction")
        }
    }
}

#Preview {
    NewNoteView()
}
