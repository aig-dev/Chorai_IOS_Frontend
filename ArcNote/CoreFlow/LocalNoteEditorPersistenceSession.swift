import BlockNoteEditor
import Combine
import CoreFlow
import Foundation

/// Owns the original scope, store and accepted-event drains after SwiftUI leaves.
/// A final flush never depends on the lifetime or cancellation of a View task.
@MainActor
final class LocalNoteEditorPersistenceSession: ObservableObject {
    let id: UUID
    let scope: NoteStoreScope
    @Published private(set) var hasSaveFailure = false
    private(set) var isVisible = true
    var onRelease: (() -> Void)?
    var onFinalFlushFailure: (() -> Void)?

    private let editingStore: CardEditingStore
    private let bodyModel: BlockNoteCardEditorModel
    private let isNew: Bool
    private let initialIsPublic: Bool
    private var retiringScope = false
    private var closedBindings: [BlockNoteEditorAttachment] = []
    private var finalFlushTask: Task<Bool, Never>?
    private var saveTask: Task<Bool, Never>?
    private var controllerSubscription: AnyCancellable?

    init(id: UUID = UUID(), scope: NoteStoreScope, editingStore: CardEditingStore,
         bodyModel: BlockNoteCardEditorModel, isNew: Bool, initialIsPublic: Bool) {
        self.id = id
        self.scope = scope
        self.editingStore = editingStore
        self.bodyModel = bodyModel
        self.isNew = isNew
        self.initialIsPublic = initialIsPublic
        controllerSubscription = bodyModel.$controller.sink { [weak self] controller in
            controller.onAttachmentWillClose = { [weak self] binding in
                self?.bindingWillClose(binding)
            }
        }
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if !visible { releaseIfFinished() }
    }

    func flushAcceptedEdits() async -> Bool {
        let binding = bodyModel.controller.attachment
        await binding?.drainAcceptedEvents()
        return await saveCurrentDraft()
    }

    func bindingWillClose(_ binding: BlockNoteEditorAttachment) {
        if !closedBindings.contains(where: { $0.id == binding.id }) {
            closedBindings.append(binding)
        }
        _ = startFinalFlush()
    }

    func beginClosingForScopeChange() {
        retiringScope = true
        bodyModel.controller.beginClosing()
    }

    func closeForScopeChange() async -> Bool {
        beginClosingForScopeChange()
        return await startFinalFlush().value
    }

    private func startFinalFlush() -> Task<Bool, Never> {
        if let finalFlushTask { return finalFlushTask }
        let task = Task { @MainActor in
            // Closing is synchronous. Only this final-save task awaits the fixed
            // handles; neither a handle's close callback nor save awaits itself.
            while let binding = self.closedBindings.first {
                await binding.drainAcceptedEvents()
                guard await self.saveCurrentDraft() else {
                    self.finalFlushTask = nil
                    if !self.isVisible || self.retiringScope { self.onFinalFlushFailure?() }
                    return false
                }
                self.closedBindings.removeAll { $0.id == binding.id }
            }
            let saved = await self.saveCurrentDraft()
            self.finalFlushTask = nil
            if saved { self.releaseIfFinished() }
            else if !self.isVisible || self.retiringScope { self.onFinalFlushFailure?() }
            return saved
        }
        finalFlushTask = task
        return task
    }

    private func saveCurrentDraft() async -> Bool {
        while let saveTask {
            guard await saveTask.value else { return false }
        }
        // Another serialized local transaction may have acknowledged an earlier
        // body while a later accepted event was being drained.
        let task = Task { @MainActor in
            if self.editingStore.phase == .saving {
                for await phase in self.editingStore.$phase.values {
                    if phase != .saving { break }
                }
                await Task.yield() // let the store release its operation owner
            }
            while self.editingStore.isDirty && !self.isUntouchedNewDraft {
                let previousCommit = self.editingStore.lastCommittedDraft
                let saved = await self.editingStore.save()
                if !saved {
                    if case .failed = self.editingStore.phase {
                        self.hasSaveFailure = true
                        self.saveTask = nil
                        return false
                    }
                    // A changed body can leave a successful transaction dirty.
                    // Non-save operations own their own retry rather than spin.
                    if self.editingStore.phase != .ready || self.editingStore.lastCommittedDraft == previousCommit {
                        self.hasSaveFailure = true
                        self.saveTask = nil
                        return false
                    }
                }
            }
            self.hasSaveFailure = false
            self.saveTask = nil
            return true
        }
        saveTask = task
        let saved = await task.value
        if saved { releaseIfFinished() }
        return saved
    }

    private var isUntouchedNewDraft: Bool {
        editingStore.cardID == nil && isNew
            && !editingStore.draft.hasMeaningfulContent
            && editingStore.draft.tags.isEmpty
            && editingStore.draft.isPublic == initialIsPublic
            && editingStore.backgroundIntent == .unchanged
            && editingStore.backgroundMediaRef == nil
    }

    private func releaseIfFinished() {
        guard (!isVisible || retiringScope), !hasSaveFailure,
              finalFlushTask == nil, saveTask == nil, closedBindings.isEmpty,
              bodyModel.controller.attachment?.isClosing != false,
              !editingStore.isDirty || isUntouchedNewDraft else { return }
        onRelease?()
    }
}
