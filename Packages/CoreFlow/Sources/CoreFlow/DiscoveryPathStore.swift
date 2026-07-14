import Foundation

@MainActor
public final class DiscoveryPathStore: ObservableObject {
    @Published public private(set) var cardID: String?
    @Published public private(set) var snapshot: DiscoveryPathSnapshot?
    @Published public private(set) var phase: DiscoveryPathPhase = .idle

    private let service: any CoreDiscoveryPathServing
    private var generation = UUID()

    public init(service: any CoreDiscoveryPathServing) {
        self.service = service
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
            return
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
