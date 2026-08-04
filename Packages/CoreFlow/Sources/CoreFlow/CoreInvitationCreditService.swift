import Foundation

public protocol CoreInvitationCreditServing: Sendable {
    func referral(actorID: String) async throws -> InvitationReferral
    func validate(code: String) async throws -> InvitationValidation
    func redeem(code: String, actorID: String) async throws -> InvitationRedemption
    func invitations(
        actorID: String,
        page: Int,
        limit: Int
    ) async throws -> InvitationPage
    func rewards(
        actorID: String,
        page: Int,
        limit: Int
    ) async throws -> InvitationRewardPage
    func balance(actorID: String) async throws -> CreditBalance
    func ledger(
        actorID: String,
        cursor: String?,
        limit: Int
    ) async throws -> CreditLedgerPage
}

public protocol InvitationAccountRegistering: Sendable {
    func register(
        _ request: InvitationAccountRegistrationRequest
    ) async throws -> InvitationRegisteredAccount
}
