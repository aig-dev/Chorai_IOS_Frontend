import Combine
import CoreFlow
import Foundation

struct NetworkCoreInterestSelectionService: CoreInterestSelectionServing,
    @unchecked Sendable {
    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func fetchOptions() async throws -> [String] {
        let response = try await firstValue(
            from: network.getInterests(presentsError: false)
        )
        guard response.success else {
            throw InterestSelectionError.transport(code: "options_rejected")
        }
        return response.data.map(\.id)
    }

    func fetchSelection() async throws -> [String] {
        let response = try await firstValue(
            from: network.getUserInterests(presentsError: false)
        )
        guard response.success else {
            throw InterestSelectionError.transport(code: "selection_rejected")
        }
        return response.data.domains
    }

    func save(domains: [String]) async throws -> [String] {
        let response = try await firstValue(
            from: network.saveUserInterests(
                request: SaveUserInterestsRequest(domains: domains),
                presentsError: false
            )
        )
        guard response.success else {
            throw InterestSelectionError.transport(code: "save_rejected")
        }
        return response.data.domains
    }

    private func firstValue<T>(
        from publisher: AnyPublisher<T, NetworkError>
    ) async throws -> T {
        do {
            var iterator = publisher.values.makeAsyncIterator()
            guard let value = try await iterator.next() else {
                throw InterestSelectionError.transport(code: "empty_response")
            }
            return value
        } catch let error as InterestSelectionError {
            throw error
        } catch let error as NetworkError {
            throw InterestSelectionError.transport(code: error.interestCode)
        } catch {
            throw InterestSelectionError.transport(code: "unknown")
        }
    }
}

private extension NetworkError {
    var interestCode: String {
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
