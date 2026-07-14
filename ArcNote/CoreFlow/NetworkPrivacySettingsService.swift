import Combine
import CoreFlow
import Foundation

struct NetworkPrivacySettingsService:
    CorePrivacySettingsServing,
    @unchecked Sendable {
    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func privacySettings(actorID: String) async throws -> PrivacySettings {
        try Self.requireActor(actorID)
        do {
            let response = try await firstValue(
                network.getPrivacySettings(presentsError: false)
            )
            guard response.success, let data = response.data else {
                throw PrivacySettingsError.requestFailed(
                    message: Self.safeMessage(response.message)
                )
            }
            return Self.map(data)
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func updatePrivacySetting(
        actorID: String,
        setting: PrivacySetting,
        enabled: Bool
    ) async throws -> PrivacySettings {
        try Self.requireActor(actorID)
        do {
            let response = try await firstValue(
                network.updatePrivacySetting(
                    setting,
                    enabled: enabled,
                    presentsError: false
                )
            )
            guard response.success, let data = response.data else {
                throw PrivacySettingsError.requestFailed(
                    message: Self.safeMessage(response.message)
                )
            }
            return Self.map(data)
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    static func map(_ response: PrivacySettingsData) -> PrivacySettings {
        PrivacySettings(
            showEmail: response.showEmail,
            showPhone: response.showPhone,
            showLocation: response.showLocation,
            showBirthday: response.showBirthday,
            allowFollow: response.allowFollow,
            showFollowLists: response.showFollowLists
        )
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

    private static func requireActor(_ actorID: String) throws {
        guard !actorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PrivacySettingsError.invalidActor
        }
    }

    private static func safeMessage(_ value: String?) -> String? {
        guard let value else { return nil }
        let message = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 160 else { return nil }
        return message
    }

    private static func mapNetworkError(_ error: Error) -> PrivacySettingsError {
        if let error = error as? PrivacySettingsError { return error }
        guard let error = error as? NetworkError else {
            return .requestFailed(message: nil)
        }
        switch error {
        case .unauthorized:
            return .unauthorized
        case .api(_, _, let message), .serverError(_, let message):
            return .requestFailed(message: safeMessage(message))
        default:
            return .requestFailed(message: nil)
        }
    }
}
