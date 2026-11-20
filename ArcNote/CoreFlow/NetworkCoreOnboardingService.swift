import Combine
import CoreFlow
import Foundation

@MainActor
struct NetworkCoreOnboardingService: @MainActor OnboardingGuideServing {
    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func status() -> AnyPublisher<OnboardingStatusSnapshot, OnboardingGuideError> {
        unwrap(network.getOnboardingStatus())
    }

    func start(
        flowVersion: Int
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        unwrap(network.startOnboarding(flowVersion: flowVersion))
    }

    func current() -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        unwrap(network.getCurrentOnboarding())
    }

    func respond(
        sessionID: String,
        input: OnboardingGuideInput
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        unwrap(network.respondToOnboarding(sessionID: sessionID, input: input))
    }

    func complete(
        sessionID: String
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        unwrap(network.completeOnboarding(sessionID: sessionID))
    }

    func skip(
        sessionID: String
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        unwrap(network.skipOnboarding(sessionID: sessionID))
    }

    private func unwrap<Value>(
        _ publisher: AnyPublisher<NetworkResponse<Value>, NetworkError>
    ) -> AnyPublisher<Value, OnboardingGuideError> where Value: Codable {
        publisher
            .tryMap { response in
                guard response.success, let data = response.data else {
                    throw OnboardingGuideError.server
                }
                return data
            }
            .mapError(Self.mapError)
            .eraseToAnyPublisher()
    }

    nonisolated private static func mapError(_ error: Error) -> OnboardingGuideError {
        if let guideError = error as? OnboardingGuideError {
            return guideError
        }
        guard let networkError = error as? NetworkError else {
            return .unknown
        }
        switch networkError {
        case .unauthorized:
            return .unauthorized
        case .timeout:
            return .timeout
        case .decodingError, .encodingError:
            return .decoding
        case .networkError(let error):
            if (error as? URLError)?.code == .timedOut {
                return .timeout
            }
            return .offline
        case .serverError, .api, .forbidden, .notFound:
            return .server
        case .invalidURL, .noData, .unknown:
            return .unknown
        }
    }
}
