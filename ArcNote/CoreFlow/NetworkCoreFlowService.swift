import Combine
import CoreFlow
import Foundation

struct NetworkCoreFlowService: CoreFlowServing {
    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func recommendedCards(
        limit: Int,
        refreshToken: String?
    ) -> AnyPublisher<FlowPage, CoreFlowError> {
        network.getRecommendedCards(limit: limit, refreshToken: refreshToken)
            .tryMap { response in
                guard response.success else {
                    throw CoreFlowError.server
                }

                return FlowPage(
                    cards: response.data.map(\.asFlowCard),
                    nextRefreshToken: response.nextRefreshToken
                )
            }
            .mapError(Self.mapError)
            .eraseToAnyPublisher()
    }

    func favorite(assetID: String) -> AnyPublisher<Void, CoreFlowError> {
        network.favoriteCard(cardId: assetID)
            .tryMap { response in
                guard response.success else {
                    throw CoreFlowError.server
                }
            }
            .mapError(Self.mapError)
            .eraseToAnyPublisher()
    }

    func unfavorite(assetID: String) -> AnyPublisher<Void, CoreFlowError> {
        network.unfavoriteCard(cardId: assetID)
            .tryMap { response in
                guard response.success else {
                    throw CoreFlowError.server
                }
            }
            .mapError(Self.mapError)
            .eraseToAnyPublisher()
    }

    func createPrivateCard(
        content: String
    ) -> AnyPublisher<CreatedCard, CoreFlowError> {
        network.createCard(
            CreateCardRequest(
                title: nil,
                content: content,
                tags: [],
                isPublic: false
            )
        )
        .tryMap { response in
            guard response.success else {
                throw CoreFlowError.server
            }

            return CreatedCard(
                id: response.data.id,
                content: response.data.content,
                isPublic: response.data.isPublic
            )
        }
        .mapError(Self.mapError)
        .eraseToAnyPublisher()
    }

    private static func mapError(_ error: Error) -> CoreFlowError {
        if let coreError = error as? CoreFlowError {
            return coreError
        }
        if let networkError = error as? NetworkError {
            return networkError.asCoreFlowError
        }
        return .unknown
    }
}

extension Card {
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
            favoriteCount: favoriteCount,
            likeCount: likeCount,
            commentCount: commentCount,
            rate: rate,
            isFavorited: isFavorited ?? false,
            isLiked: isLiked ?? false,
            isPinned: isPinned ?? false,
            pinnedAt: pinnedAt,
            author: author.map {
                FlowAuthor(
                    id: $0.id,
                    username: $0.username,
                    avatarURL: $0.avatar
                )
            }
        )
    }
}

extension FlowCard {
    var asUserCard: UserCard {
        UserCard(
            id: id,
            title: title,
            content: content,
            contentHash: contentHash ?? "",
            isPublic: isPublic,
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            likeCount: likeCount,
            commentCount: commentCount,
            isLiked: isLiked,
            isPinned: isPinned,
            pinnedAt: pinnedAt,
            isFavorited: isFavorited,
            favoriteCount: favoriteCount,
            rate: rate
        )
    }
}

private extension NetworkError {
    var asCoreFlowError: CoreFlowError {
        switch self {
        case .unauthorized:
            return .unauthorized
        case .timeout:
            return .timeout
        case .decodingError:
            return .decoding
        case .networkError:
            return .offline
        case .serverError:
            return .server
        case .invalidURL,
             .noData,
             .encodingError,
             .forbidden,
             .notFound,
             .unknown:
            return .unknown
        }
    }
}
