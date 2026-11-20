import Combine
import CoreFlow
import Foundation

@MainActor
struct NetworkDiscoveryPathService: CoreDiscoveryPathServing {
    private let reader: CardDetailReader
    private let fetchPath: (String) -> AnyPublisher<NetworkResponse<DiscoveryPathData>, NetworkError>

    init(
        network: NetworkManager = .shared,
        reader: CardDetailReader? = nil,
        fetchPath: ((String) -> AnyPublisher<NetworkResponse<DiscoveryPathData>, NetworkError>)? = nil
    ) {
        self.reader = reader ?? .shared
        self.fetchPath = fetchPath ?? { network.getDiscoveryPath(cardId: $0, presentsError: false) }
    }

    func discoveryPath(cardID: String) async throws -> DiscoveryPathSnapshot {
        let cardID = cardID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cardID.isEmpty else { throw DiscoveryPathError.invalidCard }

        do {
            return try await load(cardID: cardID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.mapError(error)
        }
    }

    private func load(cardID: String) async throws -> DiscoveryPathSnapshot {
        let scope = try reader.currentScope()
        let collected = Self.map(try await reader.confirmed(cardID: cardID))
        try checkCurrent(scope, cardID: cardID)

        let response: NetworkResponse<DiscoveryPathData>
        do {
            guard let value = try await NetworkManager.firstValue(fetchPath(cardID)) else { throw NetworkError.noData }
            response = value
        } catch let error as NetworkError where error.cardReadStatus == 404 {
            // The original endpoint uses 404 for no source. Confirm the target again
            // so a revoked or deleted card cannot be shown as an empty path.
            try checkCurrent(scope, cardID: cardID)
            let confirmed = try await reader.confirmed(cardID: cardID, requiringNewRead: true)
            return DiscoveryPathSnapshot(collected: Self.map(confirmed), nodes: [], pathLength: 0)
        }

        try checkCurrent(scope, cardID: cardID)
        guard response.success, let data = response.data else {
            throw DiscoveryPathError.requestFailed(message: Self.safeMessage(response.message))
        }
        guard data.targetAssetID == cardID, data.pathLength == data.path.count,
              data.path.allSatisfy({ !$0.assetID.isEmpty && !$0.versionID.isEmpty && !$0.activityID.isEmpty && $0.depth >= 0 }) else {
            throw DiscoveryPathError.requestFailed(message: nil)
        }
        let historical = data.path.filter { $0.assetID != cardID }
        let ancestorIDs = Set(historical.map(\.assetID))
        let cards: [String: DiscoveryPathCard]
        if let summaries = data.ancestorCards {
            cards = try Self.expandSummaries(summaries, ancestorIDs: ancestorIDs)
        } else {
            cards = try await legacyCards(historical, targetID: cardID, scope: scope)
        }

        try checkCurrent(scope, cardID: cardID)
        let nodes = historical.compactMap { node -> DiscoveryPathNode? in
            guard reader.isCurrent(scope, cardID: node.assetID), let card = cards[node.assetID] else { return nil }
            return DiscoveryPathNode(card: card, versionID: node.versionID, activityID: node.activityID, depth: node.depth)
        }
        if !historical.isEmpty && nodes.isEmpty {
            throw DiscoveryPathError.requestFailed(message: "The discovery path was found, but its cards could not be loaded.")
        }
        return DiscoveryPathSnapshot(collected: collected, nodes: nodes, pathLength: data.pathLength)
    }

    private func checkCurrent(_ scope: CardDetailReader.Scope, cardID: String) throws {
        try Task.checkCancellation()
        guard reader.isCurrent(scope, cardID: cardID) else { throw CancellationError() }
    }

    private func legacyCards(
        _ nodes: [DiscoveryPathNodeData], targetID: String, scope: CardDetailReader.Scope
    ) async throws -> [String: DiscoveryPathCard] {
        var seen = Set<String>()
        var cards: [String: DiscoveryPathCard] = [:]
        for node in nodes where seen.insert(node.assetID).inserted {
            try checkCurrent(scope, cardID: targetID)
            guard reader.isCurrent(scope, cardID: node.assetID) else { continue }
            do {
                cards[node.assetID] = Self.map(try await reader.confirmed(cardID: node.assetID))
            } catch is CancellationError {
                try checkCurrent(scope, cardID: targetID)
            } catch let error as NetworkError where error.cardReadStatus == 401 || error.cardReadStatus == 403 {
                throw error
            } catch {
                // An unavailable ancestor may be skipped if another ancestor is readable.
                continue
            }
        }
        return cards
    }

    private static func expandSummaries(
        _ summaries: [DiscoveryPathCardData], ancestorIDs: Set<String>
    ) throws -> [String: DiscoveryPathCard] {
        var cards: [String: DiscoveryPathCard] = [:]
        for summary in summaries {
            guard ancestorIDs.contains(summary.assetID), cards[summary.assetID] == nil,
                  !summary.ownerActorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DiscoveryPathError.requestFailed(message: nil)
            }
            cards[summary.assetID] = DiscoveryPathCard(
                id: summary.assetID, title: summary.title, content: summary.content, tags: summary.tags,
                createdAt: summary.createdAt, authorActorID: summary.author.actorId,
                authorName: summary.author.userName, avatarURL: summary.author.avatarUrl,
                rate: summary.rate, ownerActorID: summary.ownerActorID
            )
        }
        return cards
    }

    private static func map(_ card: CardDetail) -> DiscoveryPathCard {
        DiscoveryPathCard(
            id: card.id, title: card.title, content: card.content, tags: card.tags, createdAt: card.createdAt,
            authorActorID: card.author?.actorId, authorName: card.author?.userName ?? "Unknown",
            avatarURL: card.author?.avatarUrl, rate: card.rate,
            ownerActorID: card.ownerActorId ?? (card.isOwner == true ? AuthManager.shared.currentUser?.id : nil)
        )
    }

    private static func mapError(_ error: Error) -> DiscoveryPathError {
        if let error = error as? DiscoveryPathError { return error }
        guard let error = error as? NetworkError else { return .requestFailed(message: nil) }
        switch error.cardReadStatus {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404, 410: return .invalidCard
        default:
            switch error {
            case .api(_, _, let message), .serverError(_, let message):
                return .requestFailed(message: safeMessage(message))
            default:
                return .requestFailed(message: nil)
            }
        }
    }

    private static func safeMessage(_ value: String?) -> String? {
        guard let value else { return nil }
        let message = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 180 else { return nil }
        return message
    }
}
