import Combine
import Foundation

@MainActor
public final class CardEditingStore: ObservableObject {
    @Published public private(set) var phase: CardEditingPhase = .idle
    @Published public private(set) var draft: CardEditingDraft
    @Published public private(set) var backgroundMediaRef: String?
    @Published public private(set) var links: [CardEditingLink]

    private let cardID: String
    private let service: any CoreCardEditingServing
    private var operationTask: Task<Void, Never>?

    public init(
        cardID: String,
        draft: CardEditingDraft,
        backgroundMediaRef: String?,
        links: [CardEditingLink],
        service: any CoreCardEditingServing
    ) {
        self.cardID = cardID
        self.draft = draft
        self.backgroundMediaRef = backgroundMediaRef
        self.links = links
        self.service = service
    }

    public func hydrate(
        draft: CardEditingDraft,
        backgroundMediaRef: String?,
        links: [CardEditingLink]
    ) {
        operationTask?.cancel()
        self.draft = draft
        self.backgroundMediaRef = backgroundMediaRef
        self.links = links
        phase = .ready
    }

    public func updateDraft(_ draft: CardEditingDraft) {
        self.draft = draft
    }

    public func save() {
        guard !isBusy else { return }
        let request = draft
        phase = .saving
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await service.save(cardID: cardID, draft: request)
                guard !Task.isCancelled else { return }
                draft = CardEditingDraft(
                    title: saved.title,
                    content: saved.content,
                    tags: saved.tags,
                    isPublic: saved.isPublic
                )
                phase = .ready
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(Self.mapError(error))
            }
        }
    }

    public func createLink(_ link: CardEditingLink) {
        guard !isBusy else { return }
        phase = .linking
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.createLink(link)
                guard !Task.isCancelled else { return }
                if !links.contains(link) {
                    links.append(link)
                }
                phase = .ready
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(Self.mapError(error))
            }
        }
    }

    public func deleteLink(_ link: CardEditingLink) {
        guard !isBusy else { return }
        phase = .linking
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.deleteLink(link)
                guard !Task.isCancelled else { return }
                links.removeAll {
                    $0.sourceCardID == link.sourceCardID
                        && $0.targetCardID == link.targetCardID
                }
                phase = .ready
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(Self.mapError(error))
            }
        }
    }

    public func replaceBackground(with image: CardEditingImage) {
        guard !isBusy else { return }
        guard image.isValidBackground else {
            phase = .failed(.invalidDraft(code: "invalid_background_image"))
            return
        }
        phase = .updatingBackground
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let mediaRef = try await service.replaceBackground(
                    cardID: cardID,
                    image: image
                )
                guard !Task.isCancelled else { return }
                backgroundMediaRef = mediaRef
                phase = .ready
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(Self.mapError(error))
            }
        }
    }

    public func removeBackground() {
        guard !isBusy else { return }
        phase = .updatingBackground
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.removeBackground(cardID: cardID)
                guard !Task.isCancelled else { return }
                backgroundMediaRef = nil
                phase = .ready
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(Self.mapError(error))
            }
        }
    }

    private var isBusy: Bool {
        switch phase {
        case .saving, .linking, .updatingBackground:
            return true
        case .idle, .ready, .failed:
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
