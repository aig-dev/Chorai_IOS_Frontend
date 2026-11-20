import Combine
import CoreFlow
import Foundation

struct NetworkInvitationAccountRegistrar:
    InvitationAccountRegistering,
    Sendable {
    private let authManager: AuthManager

    @MainActor
    init(authManager: AuthManager = .shared) {
        self.authManager = authManager
    }

    @MainActor
    func register(
        _ request: InvitationAccountRegistrationRequest
    ) async throws -> InvitationRegisteredAccount {
        let publisher = authManager.register(
            username: request.username,
            email: request.email,
            password: request.password,
            verificationCode: request.verificationCode
        )
        guard let response = try await NetworkManager.firstValue(publisher) else {
            throw NetworkError.noData
        }
        return InvitationRegisteredAccount(
            actorID: response.data.user.id,
            isNewUser: response.data.isNewUser == true
        )
    }
}
