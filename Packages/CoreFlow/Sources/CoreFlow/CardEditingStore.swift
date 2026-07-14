import Combine
import Foundation

@MainActor
public final class CardEditingStore: ObservableObject {
    @Published public private(set) var phase: CardEditingPhase = .idle
    @Published public private(set) var cardID: String?
    @Published public private(set) var draft: CardEditingDraft
    @Published public private(set) var bodyRevision: Int
    @Published public private(set) var lastCommittedDraft: CardEditingDraft?
    @Published public private(set) var lastCommittedBodyRevision: Int?
    @Published public private(set) var backgroundMediaRef: String?
    @Published public private(set) var pendingBackground: CardEditingImage?
    @Published public private(set) var links: [CardEditingLink]
    @Published public private(set) var failureStage: CardEditingFailureStage?

    private let service: any CoreCardEditingServing
    private var stateGeneration = 0
    private var activeOperationID: UUID?
    private var retryLink: CardEditingLink?

    public init(
        cardID: String?,
        draft: CardEditingDraft,
        bodyRevision: Int = 0,
        backgroundMediaRef: String?,
        links: [CardEditingLink],
        service: any CoreCardEditingServing
    ) {
        self.cardID = cardID
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
        pendingBackground = nil
        self.links = links
        failureStage = nil
        retryLink = nil
        if !operationIsActive {
            phase = .ready
        }
    }

    public func replaceLinks(_ links: [CardEditingLink]) {
        self.links = links
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

    public func stageBackground(_ image: CardEditingImage) {
        guard image.isValidBackground else {
            failureStage = nil
            phase = .failed(.invalidDraft(code: "invalid_background_image"))
            return
        }
        pendingBackground = image
        if !isBusy, failureStage == nil {
            phase = .ready
        }
    }

    @discardableResult
    public func save() async -> Bool {
        guard let operationID = beginOperation() else { return false }
        defer { endOperation(operationID) }
        guard validateDraft() else { return false }
        failureStage = nil
        retryLink = nil

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
        if isDraftDirty {
            failureStage = nil
            retryLink = nil
            guard await persistDraft() else { return nil }
        }
        guard !isDraftDirty else { return nil }
        phase = .ready
        return cardID
    }

    @discardableResult
    public func retry() async -> Bool {
        guard let failureStage, !isBusy else { return false }
        switch failureStage {
        case .creatingCard, .updatingCard, .replacingBackground:
            return await save()
        case .removingBackground:
            return await removeBackground()
        case .creatingLink:
            guard let retryLink else { return false }
            return await createLink(retryLink)
        case .deletingLink:
            guard let retryLink else { return false }
            return await deleteLink(retryLink)
        }
    }

    @discardableResult
    public func createLink(_ link: CardEditingLink) async -> Bool {
        guard let operationID = beginOperation() else { return false }
        defer { endOperation(operationID) }
        guard let cardID, cardID == link.sourceCardID else {
            phase = .failed(.invalidDraft(code: "invalid_link_source"))
            return false
        }
        failureStage = nil
        retryLink = link
        phase = .linking
        do {
            try await service.createLink(link)
            if !links.contains(link) {
                links.append(link)
            }
            retryLink = nil
            phase = .ready
            return true
        } catch {
            retryLink = link
            failureStage = .creatingLink
            phase = .failed(Self.mapError(error))
            return false
        }
    }

    @discardableResult
    public func deleteLink(_ link: CardEditingLink) async -> Bool {
        guard let operationID = beginOperation() else { return false }
        defer { endOperation(operationID) }
        guard cardID == link.sourceCardID else {
            phase = .failed(.invalidDraft(code: "invalid_link_source"))
            return false
        }
        failureStage = nil
        retryLink = link
        phase = .linking
        do {
            try await service.deleteLink(link)
            links.removeAll {
                $0.sourceCardID == link.sourceCardID
                    && $0.targetCardID == link.targetCardID
            }
            retryLink = nil
            phase = .ready
            return true
        } catch {
            retryLink = link
            failureStage = .deletingLink
            phase = .failed(Self.mapError(error))
            return false
        }
    }

    @discardableResult
    public func removeBackground() async -> Bool {
        guard let operationID = beginOperation() else { return false }
        defer { endOperation(operationID) }
        pendingBackground = nil
        guard let cardID else {
            failureStage = nil
            phase = .ready
            return true
        }
        guard backgroundMediaRef != nil else {
            failureStage = nil
            phase = .ready
            return true
        }

        failureStage = nil
        phase = .updatingBackground
        do {
            try await service.removeBackground(cardID: cardID)
            backgroundMediaRef = nil
            phase = .ready
            return true
        } catch {
            failureStage = .removingBackground
            phase = .failed(Self.mapError(error))
            return false
        }
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
        failureStage = nil
        phase = .failed(validationError)
        return false
    }

    private func persistDraft() async -> Bool {
        let request = draft
        let requestRevision = bodyRevision
        let requestGeneration = stateGeneration
        let originalCardID = cardID
        let stage: CardEditingFailureStage = originalCardID == nil
            ? .creatingCard
            : .updatingCard
        phase = .saving

        do {
            let saved: CardEditingSnapshot
            if let originalCardID {
                saved = try await service.update(
                    cardID: originalCardID,
                    draft: request
                )
            } else {
                saved = try await service.create(draft: request)
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
            lastCommittedDraft = committed
            lastCommittedBodyRevision = requestRevision
            backgroundMediaRef = saved.backgroundMediaRef
            guard requestGeneration == stateGeneration else {
                failureStage = nil
                phase = .ready
                return false
            }
            if draft == request, bodyRevision == requestRevision {
                draft = committed
            }
            failureStage = nil
            phase = .ready
            return true
        } catch {
            guard requestGeneration == stateGeneration else {
                phase = .ready
                return false
            }
            failureStage = stage
            phase = .failed(Self.mapError(error))
            return false
        }
    }

    private func persistPendingBackground() async -> Bool {
        guard let image = pendingBackground else { return true }
        guard let cardID else {
            failureStage = .creatingCard
            phase = .failed(.transport(code: "card_id_missing"))
            return false
        }
        let requestGeneration = stateGeneration
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
            failureStage = nil
            phase = .ready
            return true
        } catch {
            guard requestGeneration == stateGeneration else {
                phase = .ready
                return false
            }
            failureStage = .replacingBackground
            phase = .failed(Self.mapError(error))
            return false
        }
    }

    private static func mapError(_ error: Error) -> CardEditingError {
        if let editingError = error as? CardEditingError {
            return editingError
        }
        return .transport(code: "card_editing_failed")
    }
}
