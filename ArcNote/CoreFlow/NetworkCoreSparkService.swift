import Combine
import CoreFlow
import Foundation

struct NetworkCoreSparkService: CoreSparkServing {
    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func card(assetID: String) -> AnyPublisher<FlowCard, CoreSparkError> {
        network.getSparkCard(id: assetID)
            .tryMap { response in
                guard response.success, let card = response.data else {
                    throw CoreSparkError.server
                }
                return card.asFlowCard
            }
            .mapError(Self.mapError)
            .eraseToAnyPublisher()
    }

    func trigger(
        sourceAssetID: String,
        parentActivityID: String?
    ) -> AnyPublisher<SparkActivityPage, CoreSparkError> {
        network.triggerSpark(
            cardId: sourceAssetID,
            parentActivityId: parentActivityID
        )
        .mapError(Self.mapNetworkError)
        .flatMap { response -> AnyPublisher<SparkActivityPage, CoreSparkError> in
            guard response.success, let run = response.data else {
                return Fail(error: .server).eraseToAnyPublisher()
            }

            return hydrate(groups: run.groups)
                .map { groups in
                    SparkActivityPage(
                        activityID: run.activityId,
                        parentActivityID: parentActivityID,
                        rootActivityID: run.rootActivityId,
                        chainDepth: run.chainDepth,
                        sourceAssetID: sourceAssetID,
                        groups: groups,
                        createdAt: nil
                    )
                }
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }

    func activityResults(
        activityID: String
    ) -> AnyPublisher<SparkActivityPage, CoreSparkError> {
        network.getSparkActivityResults(activityId: activityID)
            .mapError(Self.mapNetworkError)
            .flatMap { response -> AnyPublisher<SparkActivityPage, CoreSparkError> in
                guard response.success, let result = response.data else {
                    return Fail(error: .server).eraseToAnyPublisher()
                }

                return hydrate(groups: result.groups)
                    .map { groups in
                        SparkActivityPage(
                            activityID: result.activityId,
                            parentActivityID: result.parentActivityId,
                            rootActivityID: result.rootActivityId,
                            chainDepth: result.chainDepth,
                            sourceAssetID: result.sourceAssetId,
                            groups: groups,
                            createdAt: Self.parseDate(result.createdAt)
                        )
                    }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    func history(
        sourceAssetID: String,
        limit: Int
    ) -> AnyPublisher<[SparkHistoryEntry], CoreSparkError> {
        network.getSparkHistory(cardId: sourceAssetID, limit: limit)
            .tryMap { response in
                guard response.success, let history = response.data else {
                    throw CoreSparkError.server
                }

                return try history.items.map { item in
                    guard let createdAt = Self.parseDate(item.createdAt) else {
                        throw CoreSparkError.decoding
                    }
                    return SparkHistoryEntry(
                        activityID: item.activityId,
                        parentActivityID: item.parentActivityId,
                        sourceAssetID: item.sourceAssetId,
                        rootActivityID: item.rootActivityId,
                        chainDepth: item.chainDepth,
                        createdAt: createdAt
                    )
                }
            }
            .mapError(Self.mapError)
            .eraseToAnyPublisher()
    }

    func more(
        sourceAssetID: String,
        cursor: String?,
        limit: Int
    ) -> AnyPublisher<SparkMorePage, CoreSparkError> {
        network.getSparkMore(cardId: sourceAssetID, cursor: cursor, limit: limit)
            .mapError(Self.mapNetworkError)
            .flatMap { response -> AnyPublisher<SparkMorePage, CoreSparkError> in
                guard response.success, let page = response.data else {
                    return Fail(error: .server).eraseToAnyPublisher()
                }

                return hydrate(items: page.items)
                    .map { results in
                        SparkMorePage(
                            results: results,
                            nextCursor: page.nextCursor.nilIfEmpty,
                            round: page.round,
                            sourceAssetID: page.sourceAssetId
                        )
                    }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    func favorite(
        assetID: String,
        sparkActivityID: String
    ) -> AnyPublisher<Void, CoreSparkError> {
        network.favoriteCard(
            cardId: assetID,
            sparkActivityId: sparkActivityID,
            presentsError: false
        )
        .tryMap { response in
            guard response.success else {
                throw CoreSparkError.server
            }
        }
        .mapError(Self.mapError)
        .eraseToAnyPublisher()
    }

    func unfavorite(assetID: String) -> AnyPublisher<Void, CoreSparkError> {
        network.unfavoriteCard(cardId: assetID, presentsError: false)
            .tryMap { response in
                guard response.success else {
                    throw CoreSparkError.server
                }
            }
            .mapError(Self.mapError)
            .eraseToAnyPublisher()
    }

    private func hydrate(
        groups: SparkResultGroups
    ) -> AnyPublisher<[SparkBucket: [SparkResult]], CoreSparkError> {
        let candidates = Self.deduplicatedCandidates(groups: groups)
        return hydrate(candidates: candidates)
            .map { hydrated in
                var mapped = Dictionary(
                    uniqueKeysWithValues: SparkBucket.allCases.map { ($0, [SparkResult]()) }
                )
                for item in hydrated {
                    mapped[item.bucket, default: []].append(item.result)
                }
                return mapped
            }
            .eraseToAnyPublisher()
    }

    private func hydrate(
        items: [SparkResultItem]
    ) -> AnyPublisher<[SparkResult], CoreSparkError> {
        var seen = Set<String>()
        let candidates = items.enumerated().compactMap { index, item -> Candidate? in
            guard seen.insert(item.assetId).inserted else { return nil }
            return Candidate(
                index: index,
                bucket: SparkBucket(rawValue: item.bucket) ?? .related,
                item: item
            )
        }

        return hydrate(candidates: candidates)
            .map { $0.map(\.result) }
            .eraseToAnyPublisher()
    }

    private func hydrate(
        candidates: [Candidate]
    ) -> AnyPublisher<[HydratedCandidate], CoreSparkError> {
        guard !candidates.isEmpty else {
            return Just([])
                .setFailureType(to: CoreSparkError.self)
                .eraseToAnyPublisher()
        }

        return candidates.publisher
            .setFailureType(to: CoreSparkError.self)
            .flatMap(maxPublishers: .max(4)) { candidate in
                hydrate(candidate: candidate)
            }
            .collect()
            .map { results in
                results.compactMap { $0 }.sorted { $0.index < $1.index }
            }
            .eraseToAnyPublisher()
    }

    private func hydrate(
        candidate: Candidate
    ) -> AnyPublisher<HydratedCandidate?, CoreSparkError> {
        if let embedded = candidate.item.card {
            return Just(Self.hydrated(candidate, card: embedded))
                .setFailureType(to: CoreSparkError.self)
                .map(Optional.some)
                .eraseToAnyPublisher()
        }

        return Deferred {
            return network.getSparkCard(id: candidate.item.assetId)
                .tryMap { response -> RelatedCard in
                    guard response.success, let card = response.data else {
                        throw CoreSparkError.server
                    }
                    return card
                }
                .map { Self.hydrated(candidate, card: $0) }
                .map(Optional.some)
                .mapError(Self.mapError)
                .catch { error -> AnyPublisher<HydratedCandidate?, CoreSparkError> in
                    switch error {
                    case .forbidden, .notFound:
                        return Just(nil)
                            .setFailureType(to: CoreSparkError.self)
                            .eraseToAnyPublisher()
                    default:
                        return Fail(error: error).eraseToAnyPublisher()
                    }
                }
                .eraseToAnyPublisher()
        }
            .eraseToAnyPublisher()
    }

    private static func hydrated(
        _ candidate: Candidate,
        card: RelatedCard
    ) -> HydratedCandidate {
        HydratedCandidate(
            index: candidate.index,
            bucket: candidate.bucket,
            result: SparkResult(
                card: card.asFlowCard,
                bucket: candidate.bucket,
                score: candidate.item.score,
                resultID: candidate.item.resultId
            )
        )
    }

    private static func deduplicatedCandidates(
        groups: SparkResultGroups
    ) -> [Candidate] {
        let bucketItems: [(SparkBucket, [SparkResultItem])] = [
            (.related, groups.related.items),
            (.angles, groups.angles.items),
            (.keywords, groups.keywords.items)
        ]
        var seen = Set<String>()
        var index = 0
        var candidates: [Candidate] = []

        for (bucket, items) in bucketItems {
            for item in items where seen.insert(item.assetId).inserted {
                candidates.append(Candidate(index: index, bucket: bucket, item: item))
                index += 1
            }
        }
        return candidates
    }

    private static func parseDate(_ raw: String) -> Date? {
        fractionalISO8601.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private static let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func mapError(_ error: Error) -> CoreSparkError {
        if let coreError = error as? CoreSparkError {
            return coreError
        }
        if let networkError = error as? NetworkError {
            return mapNetworkError(networkError)
        }
        return .unknown
    }

    private static func mapNetworkError(_ error: NetworkError) -> CoreSparkError {
        switch error {
        case .api(let statusCode, let code, let message):
#if DEBUG
            if let message {
                print("Spark API error [\(code ?? "UNKNOWN")]: \(message)")
            }
#endif
            let normalizedCode = code?.uppercased()
            if normalizedCode == "INSUFFICIENT_CREDIT" {
                return .insufficientCredit
            }
            if normalizedCode == "UNAUTHORIZED" || statusCode == 401 {
                return .unauthorized
            }
            if normalizedCode == "FORBIDDEN" || statusCode == 403 {
                return .forbidden
            }
            if normalizedCode == "NOT_FOUND" || normalizedCode == "RESOURCE_NOT_FOUND" || statusCode == 404 {
                return .notFound
            }
            if statusCode == 400, message?.lowercased().contains("max chain depth") == true {
                return .maximumDepth
            }
            if statusCode == 502 || statusCode == 503 {
                return .retrievalUnavailable
            }
            return .server
        case .serverError(let statusCode, let message):
            if statusCode == 400, message?.lowercased().contains("max chain depth") == true {
                return .maximumDepth
            }
            if statusCode == 502 || statusCode == 503 {
                return .retrievalUnavailable
            }
            return .server
        case .unauthorized:
            return .unauthorized
        case .forbidden:
            return .forbidden
        case .notFound:
            return .notFound
        case .timeout:
            return .timeout
        case .decodingError:
            return .decoding
        case .networkError:
            return .offline
        case .invalidURL,
             .noData,
             .encodingError,
             .unknown:
            return .unknown
        }
    }
}

private extension RelatedCard {
    var asFlowCard: FlowCard {
        FlowCard(
            id: id,
            title: title,
            content: content,
            contentHash: contentHash,
            tags: tags,
            isPublic: isPublic,
            createdAt: createdAt,
            updatedAt: updatedAt,
            favoriteCount: favoriteCount ?? 0,
            likeCount: likeCount ?? 0,
            commentCount: commentCount ?? 0,
            rate: rate,
            isFavorited: isFavorited ?? false,
            isLiked: isLiked ?? false,
            isPinned: isPinned,
            pinnedAt: pinnedAt,
            author: author.map {
                FlowAuthor(
                    id: $0.actorId,
                    username: $0.username,
                    avatarURL: $0.avatarUrl
                )
            }
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct Candidate {
    let index: Int
    let bucket: SparkBucket
    let item: SparkResultItem
}

private struct HydratedCandidate {
    let index: Int
    let bucket: SparkBucket
    let result: SparkResult
}
