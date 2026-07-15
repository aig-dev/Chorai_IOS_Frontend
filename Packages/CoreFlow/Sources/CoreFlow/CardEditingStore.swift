import Combine
import Foundation

@MainActor
public final class CardEditingStore: ObservableObject {
    @Published public private(set) var phase: CardEditingPhase = .idle
    @Published public private(set) var cardID: String?
    @Published public private(set) var createRequestID: String?
    @Published public private(set) var draft: CardEditingDraft
    @Published public private(set) var bodyRevision: Int
    @Published public private(set) var lastCommittedDraft: CardEditingDraft?
    @Published public private(set) var lastCommittedBodyRevision: Int?
    @Published public private(set) var backgroundMediaRef: String?
    @Published public private(set) var pendingBackground: CardEditingImage?
    @Published public private(set) var links: [CardEditingLink]

    private enum RetryOperation: Equatable, Sendable {
        case create(
            createRequestID: String,
            draft: CardEditingDraft,
            bodyRevision: Int
        )
        case update(
            cardID: String,
            draft: CardEditingDraft,
            bodyRevision: Int
        )
        case replaceBackground(cardID: String, image: CardEditingImage)
        case removeBackground(cardID: String)
        case createLink(CardEditingLink)
        case deleteLink(CardEditingLink)
    }

    private struct FailureContext: Equatable, Sendable {
        let error: CardEditingError
        let stage: CardEditingFailureStage?
        let retryOperation: RetryOperation?
    }

    private let service: any CoreCardEditingServing
    private var stateGeneration = 0
    private var activeOperationID: UUID?
    private var failureContext: FailureContext?

    public init(
        cardID: String?,
        createRequestID: String? = nil,
        draft: CardEditingDraft,
        bodyRevision: Int = 0,
        backgroundMediaRef: String?,
        links: [CardEditingLink],
        service: any CoreCardEditingServing
    ) {
        self.cardID = cardID
        self.createRequestID = cardID == nil
            ? Self.validCreateRequestID(createRequestID) ?? UUID().uuidString
            : nil
        self.draft = draft
        self.bodyRevision = bodyRevision
        self.backgroundMediaRef = backgroundMediaRef
        self.links = links
        self.service = service
        if cardID == nil {
            lastCommittedDraft = nil
            lastCommittedBodyRevision = nil
        } else {
            lastCommittedDraft = draft
            lastCommittedBodyRevision = bodyRevision
        }
    }

    public var failureStage: CardEditingFailureStage? {
        failureContext?.stage
    }

    public var isDirty: Bool {
        isDraftDirty || pendingBackground != nil
    }

    public func hydrate(
        draft: CardEditingDraft,
        bodyRevision: Int? = nil,
        backgroundMediaRef: String?,
        links: [CardEditingLink]
    ) {
        let operationIsActive = activeOperationID != nil
        stateGeneration += 1
        let revision = bodyRevision ?? self.bodyRevision
        self.draft = draft
        self.bodyRevision = revision
        if cardID == nil {
            lastCommittedDraft = nil
            lastCommittedBodyRevision = nil
        } else {
            lastCommittedDraft = draft
            lastCommittedBodyRevision = revision
        }
        self.backgroundMediaRef = backgroundMediaRef
        self.links = links

        guard !operationIsActive else { return }
        if let failureContext,
           failureContext.stage == .replacingBackground,
           pendingBackground != nil {
            phase = .failed(failureContext.error)
        } else {
            clearFailure()
            phase = .ready
        }
    }

    public func replaceLinks(_ links: [CardEditingLink]) {
        self.links = links
    }

    @discardableResult
    public func adoptCanonicalCardID(_ value: String) -> Bool {
        guard !isBusy else { return false }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            fail(with: .invalidDraft(code: "invalid_card_id"))
            return false
        }
        if let cardID, cardID != normalized {
            fail(with: .invalidDraft(code: "conflicting_card_id"))
            return false
        }
        cardID = normalized
        createRequestID = nil
        clearFailure()
        phase = .ready
        return true
    }

    public func updateDraft(
        _ draft: CardEditingDraft,
        bodyRevision explicitRevision: Int? = nil
    ) {
        let bodyChanged = self.draft.content != draft.content
            || self.draft.contentJSON != draft.contentJSON
        self.draft = draft
        if let explicitRevision {
            bodyRevision = explicitRevision
        } else if bodyChanged {
            bodyRevision += 1
        }
    }

    @discardableResult
    public func applyBodyRevision(
        content: String,
        contentJSON: String?,
        revision: Int
    ) -> Bool {
        guard revision >= bodyRevision else { return false }
        draft = CardEditingDraft(
            title: draft.title,
            content: content,
            contentJSON: contentJSON,
            editorAtmosphere: draft.editorAtmosphere,
            tags: draft.tags,
            isPublic: draft.isPublic
        )
        bodyRevision = revision
        return true
    }

    public func uploadInlineImage(
        _ image: CardEditingImage
    ) async throws -> CardEditingInlineImageUpload {
        try await service.uploadInlineImage(image)
    }

    @discardableResult
    public func stageBackground(_ image: CardEditingImage) -> Bool {
        guard image.isValidBackground else {
            if !isBusy {
                fail(with: .invalidDraft(code: "invalid_background_image"))
            }
            return false
        }
        pendingBackground = image
        if !isBusy, failureContext?.retryOperation == nil {
            clearFailure()
            phase = .ready
        }
        return true
    }

    @discardableResult
    public func save() async -> Bool {
        guard let operationID = beginOperation() else { return false }
        defer { endOperation(operationID) }
        guard validateDraft() else { return false }
        clearFailure()

        if isDraftDirty {
            guard await persistDraft() else { return false }
        }
        if pendingBackground != nil {
            guard await persistPendingBackground() else { return false }
        }

        phase = .ready
        return !isDirty
    }

    public func ensurePersisted() async -> String? {
        guard let operationID = beginOperation() else { return nil }
        defer { endOperation(operationID) }
        guard validateDraft() else { return nil }

        let retainedFailure = failureContext.flatMap { context -> FailureContext? in
            switch context.stage {
            case .replacingBackground, .removingBackground, .creatingLink, .deletingLink:
                return context
            case .creatingCard, .updatingCard, .none:
                return nil
            }
        }

        if isDraftDirty {
            clearFailure()
            guard await persistDraft() else { return nil }
        }
        guard !isDraftDirty else { return nil }

        if let retainedFailure {
            failureContext = retainedFailure
            phase = .failed(retainedFailure.error)
        } else if let failureContext {
            phase = .failed(failureContext.error)
        } else {
            phase = .ready
        }
        return cardID
    }

    @discardableResult
    public func retry() async -> Bool {
        guard let retryOperation = failureContext?.retryOperation,
              !isBusy else {
            return false
        }
        switch retryOperation {
        case .create, .update:
            return await retryDraft(retryOperation)
        case let .replaceBackground(cardID, image):
            return await retryBackground(cardID: cardID, image: image)
        case let .removeBackground(cardID):
            return await retryBackgroundRemoval(cardID: cardID)
        case let .createLink(link):
            return await createLink(link)
        case let .deleteLink(link):
            return await deleteLink(link)
        }
    }

    @discardableResult
    public func reconcileFailedRelationshipMutation() async -> Bool {
        guard !isBusy,
              let retainedFailure = failureContext,
              let cardID else {
            return false
        }
        switch retainedFailure.stage {
        case .creatingLink, .deletingLink:
            break
        case .creatingCard, .updatingCard, .replacingBackground,
             .removingBackground, .none:
            return false
        }
        guard let operationID = beginOperation() else { return false }
        defer { endOperation(operationID) }

        phase = .linking
        do {
            links = try await service.fetchLinks(cardID: cardID)
            clearFailure()
            phase = .ready
            return true
        } catch {
            fail(
                with: Self.mapError(error),
                stage: retainedFailure.stage,
                retryOperation: retainedFailure.retryOperation
            )
            return false
        }
    }

    @discardableResult
    public func createLink(_ link: CardEditingLink) async -> Bool {
        guard let operationID = beginOperation() else { return false }
        defer { endOperation(operationID) }
        guard let cardID, cardID == link.sourceCardID else {
            fail(with: .invalidDraft(code: "invalid_link_source"))
            return false
        }
        clearFailure()
        phase = .linking
        do {
            try await service.createLink(link)
            if !links.contains(link) {
                links.append(link)
            }
            phase = .ready
            return true
        } catch {
            fail(
                with: Self.mapError(error),
                stage: .creatingLink,
                retryOperation: .createLink(link)
            )
            return false
        }
    }

    @discardableResult
    public func deleteLink(_ link: CardEditingLink) async -> Bool {
        guard let operationID = beginOperation() else { return false }
        defer { endOperation(operationID) }
        guard cardID == link.sourceCardID else {
            fail(with: .invalidDraft(code: "invalid_link_source"))
            return false
        }
        clearFailure()
        phase = .linking
        do {
            try await service.deleteLink(link)
            links.removeAll {
                $0.sourceCardID == link.sourceCardID
                    && $0.targetCardID == link.targetCardID
            }
            phase = .ready
            return true
        } catch {
            fail(
                with: Self.mapError(error),
                stage: .deletingLink,
                retryOperation: .deleteLink(link)
            )
            return false
        }
    }

    @discardableResult
    public func removeBackground() async -> Bool {
        guard let operationID = beginOperation() else { return false }
        defer { endOperation(operationID) }
        pendingBackground = nil
        clearFailure()
        guard let cardID else {
            phase = .ready
            return true
        }
        guard backgroundMediaRef != nil else {
            phase = .ready
            return true
        }
        return await performBackgroundRemoval(cardID: cardID)
    }

    private var isDraftDirty: Bool {
        guard cardID != nil,
              let lastCommittedDraft,
              let lastCommittedBodyRevision else {
            return true
        }
        return draft != lastCommittedDraft
            || bodyRevision != lastCommittedBodyRevision
    }

    private var isBusy: Bool {
        if activeOperationID != nil {
            return true
        }
        switch phase {
        case .saving, .linking, .updatingBackground:
            return true
        case .idle, .ready, .failed:
            return false
        }
    }

    private func beginOperation() -> UUID? {
        guard !isBusy else { return nil }
        let operationID = UUID()
        activeOperationID = operationID
        return operationID
    }

    private func endOperation(_ operationID: UUID) {
        guard activeOperationID == operationID else { return }
        activeOperationID = nil
    }

    private func validateDraft() -> Bool {
        guard let validationError = draft.validationError else { return true }
        fail(with: validationError)
        return false
    }

    private func retryDraft(_ retryOperation: RetryOperation) async -> Bool {
        guard let operationID = beginOperation() else { return false }
        defer { endOperation(operationID) }
        clearFailure()
        guard await persistDraft(retryOperation) else { return false }
        if pendingBackground != nil {
            guard await persistPendingBackground() else { return false }
        }
        phase = .ready
        return !isDirty
    }

    private func retryBackground(cardID: String, image: CardEditingImage) async -> Bool {
        guard let operationID = beginOperation() else { return false }
        defer { endOperation(operationID) }
        clearFailure()
        guard await persistBackground(cardID: cardID, image: image) else {
            return false
        }
        phase = .ready
        return !isDirty
    }

    private func retryBackgroundRemoval(cardID: String) async -> Bool {
        guard let operationID = beginOperation() else { return false }
        defer { endOperation(operationID) }
        clearFailure()
        return await performBackgroundRemoval(cardID: cardID)
    }

    private func persistDraft(_ requestedOperation: RetryOperation? = nil) async -> Bool {
        let operation: RetryOperation
        if let requestedOperation {
            operation = requestedOperation
        } else if let cardID {
            operation = .update(
                cardID: cardID,
                draft: draft,
                bodyRevision: bodyRevision
            )
        } else if let createRequestID {
            operation = .create(
                createRequestID: createRequestID,
                draft: draft,
                bodyRevision: bodyRevision
            )
        } else {
            fail(with: .transport(code: "create_request_id_missing"))
            return false
        }

        let request: CardEditingDraft
        let requestRevision: Int
        let originalCardID: String?
        let stage: CardEditingFailureStage
        switch operation {
        case let .create(_, draft, bodyRevision):
            request = draft
            requestRevision = bodyRevision
            originalCardID = nil
            stage = .creatingCard
        case let .update(cardID, draft, bodyRevision):
            request = draft
            requestRevision = bodyRevision
            originalCardID = cardID
            stage = .updatingCard
        case .replaceBackground, .removeBackground, .createLink, .deleteLink:
            fail(with: .transport(code: "invalid_draft_retry_operation"))
            return false
        }

        let requestGeneration = stateGeneration
        phase = .saving
        do {
            let saved: CardEditingSnapshot
            switch operation {
            case let .create(createRequestID, draft, _):
                saved = try await service.create(
                    draft: draft,
                    createRequestID: createRequestID
                )
            case let .update(cardID, draft, _):
                saved = try await service.update(cardID: cardID, draft: draft)
            case .replaceBackground, .removeBackground, .createLink, .deleteLink:
                return false
            }
            guard !saved.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CardEditingError.transport(code: "card_id_missing")
            }

            let committed = CardEditingDraft(
                title: saved.title,
                content: saved.content,
                contentJSON: saved.contentJSON,
                editorAtmosphere: saved.editorAtmosphere,
                tags: saved.tags,
                isPublic: saved.isPublic
            )
            cardID = saved.id
            if originalCardID == nil {
                createRequestID = nil
            }
            lastCommittedDraft = committed
            lastCommittedBodyRevision = requestRevision
            backgroundMediaRef = saved.backgroundMediaRef
            guard requestGeneration == stateGeneration else {
                clearFailure()
                phase = .ready
                return false
            }
            if draft == request, bodyRevision == requestRevision {
                draft = committed
            }
            clearFailure()
            phase = .ready
            return true
        } catch {
            if requestGeneration != stateGeneration, originalCardID != nil {
                phase = .ready
                return false
            }
            fail(
                with: Self.mapError(error),
                stage: stage,
                retryOperation: operation
            )
            return false
        }
    }

    private func persistPendingBackground() async -> Bool {
        guard let image = pendingBackground else { return true }
        guard let cardID else {
            fail(with: .transport(code: "card_id_missing"))
            return false
        }
        return await persistBackground(cardID: cardID, image: image)
    }

    private func persistBackground(
        cardID: String,
        image: CardEditingImage
    ) async -> Bool {
        phase = .updatingBackground
        do {
            let mediaRef = try await service.replaceBackground(
                cardID: cardID,
                image: image
            )
            backgroundMediaRef = mediaRef
            if pendingBackground == image {
                pendingBackground = nil
            }
            clearFailure()
            phase = .ready
            return true
        } catch {
            fail(
                with: Self.mapError(error),
                stage: .replacingBackground,
                retryOperation: .replaceBackground(cardID: cardID, image: image)
            )
            return false
        }
    }

    private func performBackgroundRemoval(cardID: String) async -> Bool {
        phase = .updatingBackground
        do {
            try await service.removeBackground(cardID: cardID)
            backgroundMediaRef = nil
            clearFailure()
            phase = .ready
            return true
        } catch {
            fail(
                with: Self.mapError(error),
                stage: .removingBackground,
                retryOperation: .removeBackground(cardID: cardID)
            )
            return false
        }
    }

    private func fail(
        with error: CardEditingError,
        stage: CardEditingFailureStage? = nil,
        retryOperation: RetryOperation? = nil
    ) {
        failureContext = FailureContext(
            error: error,
            stage: stage,
            retryOperation: retryOperation
        )
        phase = .failed(error)
    }

    private func clearFailure() {
        failureContext = nil
    }

    private static func mapError(_ error: Error) -> CardEditingError {
        if let editingError = error as? CardEditingError {
            return editingError
        }
        return .transport(code: "card_editing_failed")
    }

    private static func validCreateRequestID(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
