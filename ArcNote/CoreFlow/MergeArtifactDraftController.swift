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
    @Published private(set) var unresolvedMediaReferences: [String]
    @Published private(set) var isPreparingAccept = false
    @Published private(set) var isRetryingArtifactDraft = false
    @Published var isDiscardConfirmationPresented = false

    let store: MergeSessionStore

    private let codec = MergeArtifactEditorCodec.self
    private let authorizedDisplayURLsByMediaReference: [String: String]
    private let documentRelay: MergeArtifactDocumentRelay
    private var preservationManifest: Data
    private var hasLosslessProjection: Bool
    private var projectedDraftIdentity: DraftProjectionIdentity
    private var storeObservation: AnyCancellable?
    private var bodyModelObservation: AnyCancellable?

    init(
        store: MergeSessionStore,
        authorizedDisplayURLsByMediaReference: [String: String] = [:]
    ) {
        self.store = store
        self.authorizedDisplayURLsByMediaReference = Self.validatedDisplayURLs(
            authorizedDisplayURLsByMediaReference
        )

        let relay = MergeArtifactDocumentRelay()
        documentRelay = relay
        let projection = Self.projection(
            from: store.artifactDraft,
            artifact: store.artifact,
            authorizedDisplayURLsByMediaReference:
                self.authorizedDisplayURLsByMediaReference
        )
        preservationManifest = projection.preservationManifest
        hasLosslessProjection = projection.isLossless
        projectedDraftIdentity = projection.draftIdentity
        tags = projection.tags
        unresolvedMediaReferences = projection.unresolvedMediaReferences
        validationMessage = projection.validationMessage
        bodyModel = Self.makeBodyModel(
            projection: projection,
            relay: relay
        )

        relay.controller = self
        storeObservation = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.reconcileCanonicalProjectionAfterStoreChange()
                self?.reconcileAcceptLockAfterStoreChange()
            }
        }
        observeBodyModel()
    }

    var levelStyle: CardLevelStyle {
        CardLevelStyle(
            rate: store.artifactDraft?.rate
                ?? store.artifact?.presentation.rate
                ?? 1
        )
    }

    var canEdit: Bool {
        store.phase == .ready
            && !store.isOperationInFlight
            && !isPreparingAccept
            && bodyModel.canMutate
    }

    var canDiscard: Bool {
        store.phase == .ready
            && !store.isOperationInFlight
            && !isPreparingAccept
    }

    var canAccept: Bool {
        guard store.phase == .ready,
              !store.isOperationInFlight,
              !isPreparingAccept,
              bodyModel.canSave,
              hasLosslessProjection else {
            return false
        }
        switch store.artifactDraftSyncState {
        case .clean, .dirty:
            return true
        case .saving, .unsynced, .conflict:
            return false
        }
    }

    var canRetryArtifactDraft: Bool {
        guard store.phase == .ready,
              !store.isOperationInFlight,
              !isPreparingAccept,
              !isRetryingArtifactDraft else {
            return false
        }
        guard case let .unsynced(failure) = store.artifactDraftSyncState else {
            return false
        }
        switch failure {
        case .timeout, .unavailable, .server, .unknown:
            return true
        case .offline, .validation:
            return false
        }
    }

    var syncMessage: String {
        if let validationMessage {
            return validationMessage
        }
        if store.artifactActionError != nil {
            return "That action didn’t finish. Your edits are still here."
        }
        if store.phase == .committing || isPreparingAccept {
            return "Accepting…"
        }
        if isRetryingArtifactDraft {
            return "Saving…"
        }
        switch store.artifactDraftSyncState {
        case .clean:
            return "Saved"
        case .dirty:
            return "Unsaved changes"
        case .saving:
            return "Saving…"
        case .unsynced(.offline):
            return "Offline — changes are saved on this device"
        case .unsynced(.validation):
            return "Fix the highlighted content before accepting"
        case .unsynced:
            return "Not synced — try again"
        case .conflict:
            return "A newer server version conflicts with these edits"
        }
    }

    var isConflict: Bool {
        if case .conflict = store.artifactDraftSyncState {
            return true
        }
        return false
    }

    func beginTag() {
        guard canEdit, tags.count < CardEditingTag.maximumCount else { return }
        bodyModel.dismissKeyboard()
        tagInput = ""
        isAddingTag = true
    }

    func completeTag() {
        guard isAddingTag else { return }
        isAddingTag = false
        defer { tagInput = "" }
        guard let next = CardEditingTag.appending(tagInput, to: tags) else {
            return
        }
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
        Task { @MainActor in
            guard await persistCurrentSnapshot() else { return }
            completeTag()
            onMinimize()
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
        completeTag()
        guard canAccept else { return }
        isPreparingAccept = true
        bodyModel.dismissKeyboard()
        Task { @MainActor in
            guard await persistCurrentSnapshot() else {
                isPreparingAccept = false
                return
            }
            do {
                _ = try await store.flushArtifactDraft()
                store.commit()
            } catch {
                // MergeSessionStore owns the retryable, persisted failure state.
                isPreparingAccept = false
            }
        }
    }

    func retryArtifactDraft() {
        guard canRetryArtifactDraft else { return }
        isRetryingArtifactDraft = true
        Task { @MainActor in
            defer { isRetryingArtifactDraft = false }
            do {
                _ = try await store.flushArtifactDraft()
            } catch {
                // The store retains the exact pending operation for retry.
            }
        }
    }

    func resolveConflict(_ resolution: MergeArtifactConflictResolution) {
        Task { @MainActor in
            await store.resolveArtifactConflict(resolution)
            if resolution == .reloadServer {
                reloadFromStore(preservePendingTagInput: false)
            }
        }
    }

    fileprivate func documentDidChange(_ revision: BlockNoteDocumentRevision) {
        guard canEdit else { return }
        persist(blockNoteJSON: revision.contentJSON)
    }

    @discardableResult
    private func persistCurrentSnapshot() async -> Bool {
        do {
            let snapshot = try await bodyModel.requestSnapshot()
            return persist(blockNoteJSON: snapshot.contentJSON)
        } catch {
            validationMessage =
                "The editor couldn’t capture the latest changes. Try again."
            return false
        }
    }

    @discardableResult
    private func persist(blockNoteJSON: String) -> Bool {
        do {
            let documentJSON = try codec.encode(
                blockNoteJSON: blockNoteJSON,
                preserving: preservationManifest
            )
            updateProjectedDraftIdentity(documentJSON: documentJSON)
            store.updateArtifactDraft(
                documentJSON: documentJSON,
                preservationManifest: preservationManifest
            )
            hasLosslessProjection = true
            validationMessage = nil
            unresolvedMediaReferences = Self.unresolvedMediaReferences(
                in: blockNoteJSON,
                authorized: authorizedDisplayURLsByMediaReference
            )
            return true
        } catch {
            hasLosslessProjection = false
            validationMessage =
                "This content can’t be accepted without losing information."
            return false
        }
    }

    private func reloadFromStore(preservePendingTagInput: Bool) {
        let projection = Self.projection(
            from: store.artifactDraft,
            artifact: store.artifact,
            authorizedDisplayURLsByMediaReference:
                authorizedDisplayURLsByMediaReference
        )
        preservationManifest = projection.preservationManifest
        hasLosslessProjection = projection.isLossless
        projectedDraftIdentity = projection.draftIdentity
        tags = projection.tags
        unresolvedMediaReferences = projection.unresolvedMediaReferences
        validationMessage = projection.validationMessage
        if !preservePendingTagInput {
            tagInput = ""
            isAddingTag = false
        }
        bodyModel = Self.makeBodyModel(
            projection: projection,
            relay: documentRelay
        )
        observeBodyModel()
    }

    private func observeBodyModel() {
        bodyModelObservation = bodyModel.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func updateProjectedDraftIdentity(
        documentJSON: Data? = nil,
        tags: [String]? = nil
    ) {
        projectedDraftIdentity = DraftProjectionIdentity(
            documentJSON: documentJSON
                ?? projectedDraftIdentity.documentJSON,
            tags: CardEditingTag.normalize(
                tags ?? projectedDraftIdentity.tags
            )
        )
    }

    private func reconcileCanonicalProjectionAfterStoreChange() {
        guard case .clean = store.artifactDraftSyncState,
              let draft = store.artifactDraft,
              draft.pendingSave == nil else {
            return
        }
        let canonicalIdentity = DraftProjectionIdentity(
            documentJSON: draft.documentJSON,
            tags: CardEditingTag.normalize(draft.tags)
        )
        guard canonicalIdentity != projectedDraftIdentity else { return }
        reloadFromStore(preservePendingTagInput: true)
    }

    private func reconcileAcceptLockAfterStoreChange() {
        guard isPreparingAccept,
              store.phase == .ready,
              !store.isOperationInFlight,
              store.artifactActionError != nil else {
            return
        }
        isPreparingAccept = false
    }
}

@MainActor
private final class MergeArtifactDocumentRelay {
    weak var controller: MergeArtifactDraftController?

    func receive(_ revision: BlockNoteDocumentRevision) {
        controller?.documentDidChange(revision)
    }
}

private extension MergeArtifactDraftController {
    struct DraftProjectionIdentity: Equatable {
        let documentJSON: Data
        let tags: [String]
    }

    struct EditorProjection {
        let draftIdentity: DraftProjectionIdentity
        let blockNoteJSON: String?
        let fallbackMarkdown: String
        let preservationManifest: Data
        let tags: [String]
        let unresolvedMediaReferences: [String]
        let isLossless: Bool
        let validationMessage: String?
        let compatibilityBlock: String?
        let displayURLsByMediaReference: [String: String]
    }

    static func projection(
        from draft: MergeArtifactDraftSnapshot?,
        artifact: MergeArtifact?,
        authorizedDisplayURLsByMediaReference: [String: String]
    ) -> EditorProjection {
        let documentJSON = draft?.documentJSON ?? artifact?.documentJSON ?? Data()
        let tags = CardEditingTag.normalize(
            draft?.tags ?? artifact?.presentation.tags ?? []
        )
        do {
            let editable = try MergeArtifactEditorCodec.decode(
                cardDocumentJSON: documentJSON
            )
            let manifest = draft?.preservationManifest.isEmpty == false
                ? draft?.preservationManifest ?? editable.preservationManifest
                : editable.preservationManifest
            return EditorProjection(
                draftIdentity: DraftProjectionIdentity(
                    documentJSON: documentJSON,
                    tags: tags
                ),
                blockNoteJSON: editable.blockNoteJSON,
                fallbackMarkdown: editable.fallbackMarkdown,
                preservationManifest: manifest,
                tags: tags,
                unresolvedMediaReferences: unresolvedMediaReferences(
                    in: editable.blockNoteJSON,
                    authorized: authorizedDisplayURLsByMediaReference
                ),
                isLossless: true,
                validationMessage: nil,
                compatibilityBlock: nil,
                displayURLsByMediaReference:
                    authorizedDisplayURLsByMediaReference
            )
        } catch {
            let fallback = artifact?.document.plainText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return EditorProjection(
                draftIdentity: DraftProjectionIdentity(
                    documentJSON: documentJSON,
                    tags: tags
                ),
                blockNoteJSON: nil,
                fallbackMarkdown: fallback?.isEmpty == false
                    ? fallback ?? "Merge content is unavailable."
                    : "Merge content is unavailable.",
                preservationManifest: draft?.preservationManifest ?? Data(),
                tags: tags,
                unresolvedMediaReferences: [],
                isLossless: false,
                validationMessage:
                    "This artifact can’t be edited safely on this version.",
                compatibilityBlock: "merge_artifact_codec_incompatible",
                displayURLsByMediaReference: [:]
            )
        }
    }

    @MainActor
    static func makeBodyModel(
        projection: EditorProjection,
        relay: MergeArtifactDocumentRelay
    ) -> BlockNoteCardEditorModel {
        BlockNoteCardEditorModel(
            document: BlockNoteInitialDocument(
                contentJSON: projection.blockNoteJSON,
                fallbackMarkdown: projection.fallbackMarkdown,
                profile: .mergeArtifact,
                displayURLsByMediaReference:
                    projection.displayURLsByMediaReference
            ),
            editable: projection.compatibilityBlock == nil,
            initialCompatibilityBlock: projection.compatibilityBlock,
            onDocumentChanged: relay.receive
        )
    }

    static func validatedDisplayURLs(
        _ values: [String: String]
    ) -> [String: String] {
        values.reduce(into: [:]) { result, entry in
            guard !entry.key.isEmpty,
                  let url = URL(string: entry.value),
                  let scheme = url.scheme?.lowercased(),
                  ["https", "http"].contains(scheme),
                  url.host != nil,
                  url.user == nil,
                  url.password == nil else {
                return
            }
            result[entry.key] = url.absoluteString
        }
    }

    static func unresolvedMediaReferences(
        in blockNoteJSON: String,
        authorized: [String: String]
    ) -> [String] {
        guard let data = blockNoteJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        var references = Set<String>()
        collectMediaReferences(in: root, into: &references)
        return references
            .filter { authorized[$0] == nil }
            .sorted()
    }

    static func collectMediaReferences(
        in value: Any,
        into references: inout Set<String>
    ) {
        if let values = value as? [Any] {
            values.forEach { collectMediaReferences(in: $0, into: &references) }
            return
        }
        guard let object = value as? [String: Any] else { return }
        if let mediaReference = object["mediaRef"] as? String,
           !mediaReference.isEmpty {
            references.insert(mediaReference)
        }
        object.values.forEach {
            collectMediaReferences(in: $0, into: &references)
        }
    }
}
