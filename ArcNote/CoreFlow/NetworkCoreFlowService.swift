import Combine
import CoreFlow
import Foundation

struct NetworkCoreFlowService: CoreFlowServing {
    private let network: NetworkManager
    private let scope: NoteStoreScope?

    init(network: NetworkManager = .shared) {
        self.network = network
        scope = AuthManager.shared.currentNoteScope
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
        favoriteReceipt(from: network.favoriteCard(cardId: assetID, presentsError: false))
    }

    func unfavorite(assetID: String) -> AnyPublisher<Void, CoreFlowError> {
        favoriteReceipt(from: network.unfavoriteCard(cardId: assetID, presentsError: false))
    }

    private func favoriteReceipt<T: Codable>(
        from mutation: @autoclosure () -> AnyPublisher<NetworkResponse<T>, NetworkError>
    ) -> AnyPublisher<Void, CoreFlowError> {
        guard let scope, AuthManager.shared.currentNoteScope == scope else {
            return Fail(error: .unauthorized).eraseToAnyPublisher()
        }
        let session = AuthManager.shared.sessionGeneration
        return mutation()
            .receive(on: DispatchQueue.main)
            .tryMap { response in
                guard AuthManager.shared.sessionGeneration == session else { throw CoreFlowError.unauthorized }
                guard response.success else { throw CoreFlowError.server }
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
            contentJSON: contentJSON,
            backgroundMediaRef: backgroundMediaRef,
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
            },
            isOwner: isOwner ?? false
        )
    }
}

extension FlowCard {
    var asUserCard: UserCard {
        UserCard(
            id: id,
            title: title,
            content: content,
            contentJSON: contentJSON,
            backgroundMediaRef: backgroundMediaRef,
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
            rate: rate,
            isOwner: isOwner
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
        case .api(let statusCode, let code, _):
            if statusCode == 401 || code == "UNAUTHORIZED" {
                return .unauthorized
            }
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
