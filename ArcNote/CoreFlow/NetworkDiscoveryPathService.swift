import Combine
import CoreFlow
import Foundation

struct NetworkDiscoveryPathService:
    CoreDiscoveryPathServing,
    @unchecked Sendable {
    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func discoveryPath(cardID: String) async throws -> DiscoveryPathSnapshot {
        let normalizedCardID = cardID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedCardID.isEmpty else {
            throw DiscoveryPathError.invalidCard
        }

        let collected = try await fetchCard(id: normalizedCardID)
        let response: NetworkResponse<DiscoveryPathData>
        do {
            response = try await firstValue(
                network.getDiscoveryPath(
                    cardId: normalizedCardID,
                    presentsError: false
                )
            )
        } catch NetworkError.notFound {
            return DiscoveryPathSnapshot(
                collected: collected,
                nodes: [],
                pathLength: 0
            )
        } catch {
            throw Self.mapNetworkError(error)
        }

        guard response.success, let data = response.data else {
            throw DiscoveryPathError.requestFailed(
                message: Self.safeMessage(response.message)
            )
        }
        guard data.targetAssetID == normalizedCardID else {
            throw DiscoveryPathError.requestFailed(
                message: "Discovery path target did not match the requested card."
            )
        }

        var hydrated: [DiscoveryPathNode] = []
        var ancestorRequests = 0
        var ancestorFailures = 0
        for node in data.path where node.assetID != normalizedCardID {
            ancestorRequests += 1
            do {
                let card = try await fetchCard(id: node.assetID)
                hydrated.append(
                    DiscoveryPathNode(
                        card: card,
                        versionID: node.versionID,
                        activityID: node.activityID,
                        depth: node.depth
                    )
                )
            } catch let error as DiscoveryPathError {
                switch error {
                case .unauthorized, .forbidden:
                    throw error
                default:
                    ancestorFailures += 1
                }
            }
        }

        if ancestorRequests > 0,
           hydrated.isEmpty,
           ancestorFailures == ancestorRequests {
            throw DiscoveryPathError.requestFailed(
                message: "The discovery path was found, but its cards could not be loaded."
            )
        }

        return DiscoveryPathSnapshot(
            collected: collected,
            nodes: hydrated,
            pathLength: data.pathLength
        )
    }

    static func map(_ card: CardDetail) -> DiscoveryPathCard {
        DiscoveryPathCard(
            id: card.id,
            title: card.title,
            content: card.content,
            tags: card.tags,
            createdAt: card.createdAt,
            authorActorID: card.author?.actorId,
            authorName: card.author?.userName ?? "Unknown",
            avatarURL: card.author?.avatarUrl,
            rate: card.rate
        )
    }

    private func fetchCard(id: String) async throws -> DiscoveryPathCard {
        do {
            let response = try await firstValue(
                network.getCardDetailPublisher(
                    cardId: id,
                    presentsError: false
                )
            )
            guard response.success else {
                throw DiscoveryPathError.requestFailed(
                    message: Self.safeMessage(response.message)
                )
            }
            return Self.map(response.data)
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    private func firstValue<Output>(
        _ publisher: AnyPublisher<Output, NetworkError>
    ) async throws -> Output {
        var iterator = publisher.values.makeAsyncIterator()
        guard let value = try await iterator.next() else {
            throw NetworkError.noData
        }
        return value
    }

    private static func mapNetworkError(_ error: Error) -> DiscoveryPathError {
        if let error = error as? DiscoveryPathError { return error }
        guard let error = error as? NetworkError else {
            return .requestFailed(message: nil)
        }
        switch error {
        case .unauthorized:
            return .unauthorized
        case .forbidden:
            return .forbidden
        case .api(_, _, let message), .serverError(_, let message):
            return .requestFailed(message: safeMessage(message))
        default:
            return .requestFailed(message: nil)
        }
    }

    private static func safeMessage(_ value: String?) -> String? {
        guard let value else { return nil }
        let message = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 180 else { return nil }
        return message
    }
}
