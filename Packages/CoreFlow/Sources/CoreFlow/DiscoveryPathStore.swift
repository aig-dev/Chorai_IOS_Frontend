import Combine
import Foundation

@MainActor
public final class DiscoveryPathStore: ObservableObject {
    @Published public private(set) var cardID: String?
    @Published public private(set) var snapshot: DiscoveryPathSnapshot?
    @Published public private(set) var phase: DiscoveryPathPhase = .idle

    private let service: any CoreDiscoveryPathServing
    private var generation = UUID()
    private var subscriptions = Set<AnyCancellable>()

    public init(service: any CoreDiscoveryPathServing) {
        self.service = service
        let center = NotificationCenter.default
        center.publisher(for: .cardReadSessionDidChange).sink { [weak self] _ in
            self?.clearForSessionChange()
        }.store(in: &subscriptions)
        center.publisher(for: .cardReadInvalidated).sink { [weak self] event in
            if let cardID = event.object as? String {
                self?.invalidate(cardID: cardID, status: event.userInfo?[CardReadInvalidation.statusKey] as? Int)
            }
        }.store(in: &subscriptions)
    }

    public func load(cardID rawCardID: String) async {
        generation = UUID()
        snapshot = nil

        guard let cardID = Self.normalized(rawCardID) else {
            self.cardID = nil
            phase = .failed(.invalidCard)
            return
        }

        self.cardID = cardID
        phase = .loading
        let requestedGeneration = generation

        do {
            let value = try await service.discoveryPath(cardID: cardID)
            guard isCurrent(cardID: cardID, generation: requestedGeneration) else {
                return
            }
            snapshot = value
            phase = value.ancestors.isEmpty ? .empty : .ready
        } catch is CancellationError {
            if !Task.isCancelled, isCurrent(cardID: cardID, generation: requestedGeneration) {
                phase = .failed(.requestFailed(message: nil))
            }
        } catch {
            guard isCurrent(cardID: cardID, generation: requestedGeneration) else {
                return
            }
            phase = .failed(Self.map(error))
        }
    }

    public func retry() async {
        guard let cardID else {
            phase = .failed(.invalidCard)
            return
        }
        await load(cardID: cardID)
    }

    private func clearForSessionChange() {
        generation = UUID()
        snapshot = nil
        if cardID != nil { phase = .failed(.requestFailed(message: nil)) }
    }

    private func invalidate(cardID: String, status: Int?) {
        if self.cardID == cardID {
            generation = UUID()
            snapshot = nil
            switch status {
            case 401: phase = .failed(.unauthorized)
            case 404, 410: phase = .failed(.invalidCard)
            default: phase = .failed(.forbidden)
            }
        } else if let snapshot, snapshot.ancestors.contains(where: { $0.id == cardID }) {
            let remaining = snapshot.ancestors.filter { $0.id != cardID }
            if remaining.isEmpty {
                self.snapshot = nil
                phase = .failed(.requestFailed(message: nil))
            } else {
                self.snapshot = DiscoveryPathSnapshot(
                    collected: snapshot.collected,
                    nodes: remaining,
                    pathLength: snapshot.pathLength
                )
            }
        }
    }

    private func isCurrent(cardID: String, generation: UUID) -> Bool {
        self.cardID == cardID && self.generation == generation
    }

    private static func normalized(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func map(_ error: Error) -> DiscoveryPathError {
        (error as? DiscoveryPathError) ?? .requestFailed(message: nil)
    }
}
