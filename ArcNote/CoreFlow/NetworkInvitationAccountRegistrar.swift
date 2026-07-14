import Combine
import CoreFlow
import Foundation

struct NetworkInvitationAccountRegistrar:
    InvitationAccountRegistering,
    @unchecked Sendable {
    private let authManager: AuthManager

    init(authManager: AuthManager = .shared) {
        self.authManager = authManager
    }

    func register(
        _ request: InvitationAccountRegistrationRequest
    ) async throws -> InvitationRegisteredAccount {
        var iterator = authManager.register(
            username: request.username,
            email: request.email,
            password: request.password,
            verificationCode: request.verificationCode
        ).values.makeAsyncIterator()
        guard let response = try await iterator.next() else {
            throw NetworkError.noData
        }
        return InvitationRegisteredAccount(
            actorID: response.data.user.id,
            isNewUser: response.data.isNewUser == true
        )
    }
}
