import BlockNoteEditor
import Combine
import CoreFlow
import Foundation
import PhotosUI
import SwiftUI
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

struct NewNoteView: View {
    @Environment(\.dismiss) private var dismiss

    let cardId: String
    let onCreated: (String, String) -> Void

    @StateObject private var editingStore: CardEditingStore
    @State private var editorSeed: CardEditorSeed?
    @State private var loadErrorMessage: String?
    @State private var isLoading = false
    @State private var didStartLoading = false
    @State private var cancellables = Set<AnyCancellable>()

    private let networkManager = NetworkManager.shared

    init(
        cardId: String = "",
        onCreated: @escaping (String, String) -> Void = { _, _ in }
    ) {
        self.cardId = cardId
        self.onCreated = onCreated

        let isNew = cardId.isEmpty
        _editingStore = StateObject(
            wrappedValue: CardEditingStore(
                cardID: isNew ? nil : cardId,
                draft: CardEditingDraft(
                    title: nil,
                    content: "",
                    tags: [],
                    isPublic: false
                ),
                backgroundMediaRef: nil,
                links: [],
                service: NetworkCoreCardEditingService()
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
            loadRelatedLinks()
        }
    }

    private func loadExistingCard() {
        guard !cardId.isEmpty, !isLoading else { return }
        isLoading = true
        loadErrorMessage = nil

        networkManager.getCardDetail(cardId: cardId) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case let .success(response) where response.success:
                    hydrateExistingCard(response.data)
                case let .success(response):
                    loadErrorMessage = response.message ?? "Couldn't open this note."
                case let .failure(error):
                    loadErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func hydrateExistingCard(_ card: CardDetail) {
        guard editorSeed == nil else { return }

        let draft = CardEditingDraft(
            title: card.title,
            content: card.content,
            contentJSON: card.contentJSON,
            editorAtmosphere: card.editorAtmosphere ?? "none",
            tags: card.tags,
            isPublic: card.isPublic
        )
        editingStore.hydrate(
            draft: draft,
            bodyRevision: 0,
            backgroundMediaRef: card.backgroundMediaRef,
            links: editingStore.links
        )
        editorSeed = CardEditorSeed(
            id: UUID(),
            document: BlockNoteInitialDocument(
                contentJSON: card.contentJSON,
                fallbackMarkdown: card.content
            ),
            revision: 0,
            isNew: false,
            initialFocus: false,
            initialIsPublic: card.isPublic,
            isPinned: card.isPinned ?? false
        )
    }

    private func loadRelatedLinks() {
        guard !cardId.isEmpty else { return }
        networkManager.getCardLinks(cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { response in
                    guard response.success else { return }
                    let items = response.data.outgoingLinks
                        + response.data.incomingLinks
                    let links = items.map { item in
                        CardEditingLink(
                            sourceCardID: item.sourceAssetId,
                            targetCardID: item.targetAssetId,
                            title: item.title ?? "Related note",
                            previewHTML: item.content,
                            authorName: item.author?.userName,
                            authorAvatarURL: item.author?.avatar
                        )
                    }
                    editingStore.replaceLinks(links)
                }
            )
            .store(in: &cancellables)
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

    let seed: CardEditorSeed
    let onCreated: (String, String) -> Void

    @ObservedObject private var editingStore: CardEditingStore
    @ObservedObject private var linkPopupManager = LinkPopupManager.shared
    @StateObject private var bodyModel: BlockNoteCardEditorModel
    @StateObject private var nativeActionRouter: CardEditorNativeActionRouter

    @State private var showTagEditor = false
    @State private var tagInput = ""
    @State private var showBackgroundPicker = false
    @State private var selectedBackgroundPhoto: PhotosPickerItem?
    @State private var showInlineImagePicker = false
    @State private var selectedInlineImagePhoto: PhotosPickerItem?
    @State private var showInlineLinkSheet = false
    @State private var showCardActions = false
    @State private var showRemoveCardConfirmation = false
    @State private var showCloseWithoutSavingConfirmation = false
    @State private var pendingOntologyLinkSourceID: String?
    @State private var saveMessage: String?
    @State private var retryAction: CardEditorRetryAction?
    @State private var isSaving = false
    @State private var isPreparingCardAction = false
    @State private var isCardActionInFlight = false
    @State private var didNotifyCreation: Bool
    @State private var isPinned: Bool
    @State private var cancellables = Set<AnyCancellable>()

    init(
        seed: CardEditorSeed,
        editingStore: CardEditingStore,
        onCreated: @escaping (String, String) -> Void
    ) {
        self.seed = seed
        self.onCreated = onCreated
        _editingStore = ObservedObject(wrappedValue: editingStore)
        _didNotifyCreation = State(initialValue: !seed.isNew)
        _isPinned = State(initialValue: seed.isPinned)

        let router = CardEditorNativeActionRouter()
        _nativeActionRouter = StateObject(wrappedValue: router)
        _bodyModel = StateObject(
            wrappedValue: BlockNoteCardEditorModel(
                document: seed.document,
                initialRevision: seed.revision,
                initiallyFocused: seed.initialFocus,
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
        )
    }

    var body: some View {
        CardEditorShell(
            bodyModel: bodyModel,
            tags: editingStore.draft.tags,
            links: editorLinkItems,
            background: editorBackground,
            isPublic: editingStore.draft.isPublic,
            isMetadataEditable: bodyModel.canMutate && !isBusy,
            isSaving: isSaving,
            saveActionTitle: "Retry",
            saveMessage: saveMessage,
            onBack: handleBack,
            onAddTag: presentTagEditor,
            onRemoveTag: removeTag,
            onTogglePrivacy: togglePrivacy,
            onOpenCardActions: cardActionsHandler,
            onSave: retryHandler
        )
        .linkPopup()
        .accessibilityHidden(showCardActions)
        .overlay {
            if showCardActions {
                CardEditorActionBox(
                    isPresented: $showCardActions,
                    isEnabled: bodyModel.canMutate && !isBusy,
                    isPinned: isPinned,
                    onBackground: { showBackgroundPicker = true },
                    onSpark: { performPersistedCardAction(.notification("NavigateToSpark")) },
                    onMerge: { performPersistedCardAction(.notification("NavigateToMerge")) },
                    onShare: { performPersistedCardAction(.notification("ShowCardShare")) },
                    onLink: addOntologyLink,
                    onRoot: { performPersistedCardAction(.notification("NavigateToRoot")) },
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
            isPresented: $showInlineImagePicker,
            selection: $selectedInlineImagePhoto,
            matching: .images
        )
        .onChange(
            of: selectedBackgroundPhoto,
            perform: handleSelectedBackgroundPhoto
        )
        .onChange(
            of: selectedInlineImagePhoto,
            perform: handleSelectedInlineImage
        )
        .onChange(
            of: linkPopupManager.isShowing,
            perform: handleLinkPopupVisibilityChange
        )
        .alert("Add Tag", isPresented: $showTagEditor) {
            TextField("Tag", text: $tagInput)
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("cardEditorTagInput")
            Button("Cancel", role: .cancel) {
                tagInput = ""
            }
            Button("Add") {
                addTag(tagInput)
                tagInput = ""
            }
        } message: {
            Text("Tags are saved with this note.")
        }
        .sheet(isPresented: $showInlineLinkSheet) {
            CardEditorInlineLinkSheet { url, text in
                bodyModel.insertLink(url: url, text: text)
            }
        }
        .onAppear(perform: configureNativeActions)
        .onDisappear {
            bodyModel.dismissKeyboard()
            LinkPopupManager.shared.onCardSelected = nil
        }
    }

    private var isBusy: Bool {
        if isSaving || isPreparingCardAction || isCardActionInFlight {
            return true
        }
        switch editingStore.phase {
        case .saving, .linking, .updatingBackground:
            return true
        case .idle, .ready, .failed:
            return false
        }
    }

    private var retryHandler: (() -> Void)? {
        guard retryAction != nil else { return nil }
        return { retryCurrentFailure() }
    }

    private var cardActionsHandler: (() -> Void)? {
        guard bodyModel.canSave, !isBusy else { return nil }
        return { openCardActions() }
    }

    private var editorBackground: CardEditorBackgroundSource {
        if let pending = editingStore.pendingBackground {
            return .local(pending.data)
        }
        guard let mediaRef = editingStore.backgroundMediaRef,
              let url = URL(
                  string: APIConfiguration.resourceURLString(mediaRef)
              ) else {
            return .none
        }
        return .remote(url)
    }

    private var editorLinkItems: [CardEditorLinkItem] {
        guard let cardID = editingStore.cardID else { return [] }
        return editingStore.links.map { link in
            let linkedCardID = link.sourceCardID == cardID
                ? link.targetCardID
                : link.sourceCardID
            return CardEditorLinkItem(
                id: linkedCardID,
                title: link.authorName ?? link.title,
                previewHTML: link.previewHTML,
                avatarURL: link.authorAvatarURL
            )
        }
    }

    private func isUntouchedNewSnapshot(_ snapshot: BlockNoteSnapshot) -> Bool {
        seed.isNew
            && snapshot.revision == seed.revision
            && snapshot.fallbackMarkdown
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && editingStore.draft.tags.isEmpty
            && editingStore.draft.isPublic == seed.initialIsPublic
            && editingStore.pendingBackground == nil
            && editingStore.backgroundMediaRef == nil
    }

    private func configureNativeActions() {
        nativeActionRouter.onRequestCardLink = {
            addOntologyLink()
        }
        nativeActionRouter.onRequestInlineLink = {
            showInlineLinkSheet = true
        }
        nativeActionRouter.onRequestInlineImage = {
            showInlineImagePicker = true
        }
        nativeActionRouter.onSelectedLink = handleSelectedLink
        LinkPopupManager.shared.onCardSelected = { [weak nativeActionRouter] item in
            nativeActionRouter?.selectLink(item)
        }
    }

    private func handleBack() {
        guard !isBusy else { return }
        bodyModel.dismissKeyboard()

        if bodyModel.compatibilityNotice != nil {
            dismiss()
            return
        }
        if bodyModel.bridgeFailureNotice != nil {
            showCloseWithoutSavingConfirmation = true
            return
        }
        saveCurrentSnapshot(thenDismiss: true)
    }

    private func saveCurrentSnapshot(thenDismiss: Bool) {
        guard !isSaving else { return }
        isSaving = true
        saveMessage = nil
        retryAction = nil

        Task {
            defer { isSaving = false }
            do {
                let snapshot = try await applyCurrentSnapshot()
                if thenDismiss, isUntouchedNewSnapshot(snapshot) {
                    dismiss()
                    return
                }
                let didRecover = await recoverFailedDraftOperationIfNeeded()
                let didSave = didRecover
                    ? await editingStore.save()
                    : false
                notifyCreationIfNeeded()
                guard didSave,
                      editingStore.lastCommittedBodyRevision == snapshot.revision,
                      editingStore.bodyRevision == snapshot.revision,
                      bodyModel.revision == snapshot.revision,
                      !editingStore.isDirty else {
                    saveMessage = "Couldn't save this note. Retry when ready."
                    retryAction = .save(thenDismiss: thenDismiss)
                    return
                }
                saveMessage = nil
                retryAction = nil
                if thenDismiss {
                    dismiss()
                }
            } catch CardEditorBodyError.compatibilityBlocked {
                dismiss()
            } catch {
                saveMessage = "Couldn't take a safe editor snapshot. Retry."
                retryAction = .save(thenDismiss: thenDismiss)
            }
        }
    }

    private func retryCurrentFailure() {
        guard let retryAction, !isBusy else { return }
        switch retryAction {
        case let .save(thenDismiss):
            saveCurrentSnapshot(thenDismiss: thenDismiss)

        case .addLink:
            addOntologyLink()

        case let .persistedAction(action):
            performPersistedCardAction(action)

        case .store:
            isSaving = true
            Task {
                defer { isSaving = false }
                let didRetry = await editingStore.retry()
                if didRetry {
                    saveMessage = nil
                    self.retryAction = nil
                } else {
                    saveMessage = "That change still couldn't be saved. Retry."
                    self.retryAction = .store
                }
            }
        }
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

    private func recoverFailedDraftOperationIfNeeded() async -> Bool {
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
        guard editingStore.failureStage == nil else { return false }
        guard editingStore.isDirty else { return true }
        guard editingStore.cardID != nil else { return false }
        return await editingStore.save()
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
        retryAction = nil
    }

    private func presentTagEditor() {
        tagInput = ""
        showTagEditor = true
    }

    private func addTag(_ tag: String) {
        updateMetadata(tags: editingStore.draft.tags + [tag])
    }

    private func removeTag(_ tag: String) {
        updateMetadata(tags: editingStore.draft.tags.filter { $0 != tag })
    }

    private func togglePrivacy() {
        updateMetadata(isPublic: !editingStore.draft.isPublic)
    }

    private func addOntologyLink() {
        guard !isBusy else { return }
        saveMessage = nil
        retryAction = nil
        Task {
            do {
                _ = try await applyCurrentSnapshot()
                guard await recoverFailedDraftOperationIfNeeded() else {
                    notifyCreationIfNeeded()
                    saveMessage = "Save this note before adding a link."
                    retryAction = .addLink
                    return
                }
                guard let sourceID = await editingStore.ensurePersisted() else {
                    notifyCreationIfNeeded()
                    saveMessage = "Save this note before adding a link."
                    retryAction = .addLink
                    return
                }
                notifyCreationIfNeeded()
                pendingOntologyLinkSourceID = sourceID
                LinkPopupManager.shared.show(
                    cardId: sourceID,
                    navigateAfterLink: false,
                    mode: .selectionOnly
                )
            } catch {
                saveMessage = "Couldn't take a safe snapshot for linking."
                retryAction = .addLink
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
                retryAction = .store
                return
            }
            saveMessage = nil
            retryAction = nil
        }
    }

    private func handleSelectedBackgroundPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            defer { selectedBackgroundPhoto = nil }
            do {
                let image = try await cardEditingImage(
                    from: item,
                    stem: "card-background"
                )
                guard editingStore.stageBackground(image) else {
                    saveMessage = "That background image can't be used."
                    retryAction = nil
                    return
                }
                saveMessage = nil
                retryAction = nil
            } catch {
                saveMessage = "Couldn't read that background image."
                retryAction = nil
            }
        }
    }

    private func handleSelectedInlineImage(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            defer { selectedInlineImagePhoto = nil }
            do {
                let image = try await cardEditingImage(
                    from: item,
                    stem: "inline-image"
                )
                let uploaded = try await editingStore.uploadInlineImage(image)
                bodyModel.insertImage(
                    url: uploaded.url.absoluteString,
                    alt: "Inline image"
                )
                saveMessage = nil
                retryAction = nil
            } catch {
                saveMessage = "Couldn't upload that inline image."
                retryAction = nil
            }
        }
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
        showCardActions = true
    }

    private func performPersistedCardAction(
        _ action: CardEditorPersistedAction
    ) {
        guard bodyModel.canSave, !isBusy else { return }
        isPreparingCardAction = true
        saveMessage = nil
        retryAction = nil
        Task {
            defer { isPreparingCardAction = false }
            do {
                _ = try await applyCurrentSnapshot()
                guard await recoverFailedDraftOperationIfNeeded() else {
                    saveMessage = "Save this note before using that action."
                    retryAction = .persistedAction(action)
                    return
                }
                guard await editingStore.ensurePersisted() != nil else {
                    saveMessage = "Save this note before using that action."
                    retryAction = .persistedAction(action)
                    return
                }
                notifyCreationIfNeeded()
                saveMessage = nil
                retryAction = nil
                executePersistedCardAction(action)
            } catch {
                saveMessage = "Couldn't take a safe snapshot for that action."
                retryAction = .persistedAction(action)
            }
        }
    }

    private func executePersistedCardAction(
        _ action: CardEditorPersistedAction
    ) {
        switch action {
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
        guard let cardID = editingStore.cardID else { return }
        NotificationCenter.default.post(
            name: NSNotification.Name(name),
            object: nil,
            userInfo: ["cardId": cardID]
        )
    }

    private func togglePinnedCard() {
        guard let cardID = editingStore.cardID,
              !isCardActionInFlight else { return }
        isCardActionInFlight = true
        saveMessage = nil
        retryAction = nil
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
                        retryAction = .persistedAction(.togglePin)
                    }
                },
                receiveValue: { response in
                    if response.success {
                        isPinned.toggle()
                        saveMessage = nil
                        retryAction = nil
                    } else {
                        saveMessage = "Couldn't update pin status."
                        retryAction = .persistedAction(.togglePin)
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func removeCanonicalCard() {
        guard !isCardActionInFlight else { return }
        guard let cardID = editingStore.cardID else {
            dismiss()
            return
        }
        isCardActionInFlight = true
        saveMessage = nil
        retryAction = nil
        NetworkManager.shared.deleteCard(id: cardID)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isCardActionInFlight = false
                    if case .failure = completion {
                        saveMessage = "Couldn't move this note to Trash."
                    }
                },
                receiveValue: { response in
                    if response.success {
                        dismiss()
                    } else {
                        saveMessage = "Couldn't move this note to Trash."
                    }
                }
            )
            .store(in: &cancellables)
    }
}

private enum CardEditorSessionError: Error {
    case staleSnapshot
    case imageUnavailable
}

private enum CardEditorPersistedAction {
    case notification(String)
    case togglePin
}

private enum CardEditorRetryAction {
    case save(thenDismiss: Bool)
    case addLink
    case persistedAction(CardEditorPersistedAction)
    case store
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
                        .tint(.white)
                    Text("Opening note…")
                        .foregroundStyle(.white.opacity(0.72))
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.white.opacity(0.82))
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
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(ZenVisualTokens.background.opacity(0.82))
                    )
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.top, 6)
            .accessibilityLabel("Close note")
            .accessibilityIdentifier("cardEditorFloatingBack")
        }
    }
}

#Preview {
    NewNoteView()
}
