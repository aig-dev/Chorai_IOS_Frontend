import Combine
import CoreFlow
import Foundation

struct NetworkCoreCardLikeService: CoreCardLikeServing, @unchecked Sendable {
    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func setLiked(cardID: String, liked: Bool) async throws {
        if liked {
            let response = try await firstValue(
                from: network.likeCard(
                    cardId: cardID,
                    presentsError: false
                )
            )
            guard response.success else {
                throw CardLikeError.transport(code: "like_rejected")
            }
        } else {
            let response = try await firstValue(
                from: network.unlikeCard(
                    cardId: cardID,
                    presentsError: false
                )
            )
            guard response.success else {
                throw CardLikeError.transport(code: "unlike_rejected")
            }
        }
    }

    private func firstValue<T>(
        from publisher: AnyPublisher<T, NetworkError>
    ) async throws -> T {
        do {
            var iterator = publisher.values.makeAsyncIterator()
            guard let value = try await iterator.next() else {
                throw CardLikeError.transport(code: "empty_response")
            }
            return value
        } catch let error as CardLikeError {
            throw error
        } catch let error as NetworkError {
            throw CardLikeError.transport(code: error.cardLikeCode)
        } catch {
            throw CardLikeError.transport(code: "unknown")
        }
    }
}

private extension NetworkError {
    var cardLikeCode: String {
        switch self {
        case .invalidURL: "invalid_url"
        case .noData: "no_data"
        case .decodingError: "decoding"
        case .encodingError: "encoding"
        case .serverError(let status, _): "server_\(status)"
        case .api(let status, let code, _): code ?? "api_\(status)"
        case .networkError: "network"
        case .unauthorized: "unauthorized"
        case .forbidden: "forbidden"
        case .notFound: "not_found"
        case .timeout: "timeout"
        case .unknown: "unknown"
        }
    }
}
