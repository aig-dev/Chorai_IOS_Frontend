import Foundation
@testable import CoreFlow

actor InvitationCallRecorder {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

actor InvitationCreditServiceStub: CoreInvitationCreditServing {
    private var referralResults: [Result<InvitationReferral, Error>] = []
    private var balanceResults: [Result<CreditBalances, Error>] = []
    private var validationResults: [Result<InvitationValidation, Error>] = []
    private var redemptionResults: [Result<InvitationRedemption, Error>] = []
    private var validationDelayNanoseconds: UInt64 = 0
    private var referralDelayNanoseconds: UInt64 = 0
    private(set) var validationCodes: [String] = []
    private(set) var redemptionCalls: [(code: String, actorID: String)] = []
    let recorder: InvitationCallRecorder?

    init(recorder: InvitationCallRecorder? = nil) {
        self.recorder = recorder
    }

    func setReferralResults(_ values: [Result<InvitationReferral, Error>]) {
        referralResults = values
    }

    func setBalanceResults(_ values: [Result<CreditBalances, Error>]) {
        balanceResults = values
    }

    func setReferralDelay(nanoseconds: UInt64) {
        referralDelayNanoseconds = nanoseconds
    }

    func setValidationResults(_ values: [Result<InvitationValidation, Error>]) {
        validationResults = values
    }

    func setRedemptionResults(_ values: [Result<InvitationRedemption, Error>]) {
        redemptionResults = values
    }

    func setValidationDelay(nanoseconds: UInt64) {
        validationDelayNanoseconds = nanoseconds
    }

    func recordedValidationCodes() -> [String] {
        validationCodes
    }

    func redemptionCallCount() -> Int {
        redemptionCalls.count
    }

    func referral(actorID: String) async throws -> InvitationReferral {
        if referralDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: referralDelayNanoseconds)
        }
        guard !referralResults.isEmpty else {
            throw InvitationCreditError.requestFailed(message: nil)
        }
        return try referralResults.removeFirst().get()
    }

    func validate(code: String) async throws -> InvitationValidation {
        validationCodes.append(code)
        await recorder?.append("validate")
        if validationDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: validationDelayNanoseconds)
        }
        guard !validationResults.isEmpty else {
            throw InvitationCreditError.requestFailed(message: nil)
        }
        return try validationResults.removeFirst().get()
    }

    func redeem(code: String, actorID: String) async throws -> InvitationRedemption {
        redemptionCalls.append((code, actorID))
        await recorder?.append("redeem")
        guard !redemptionResults.isEmpty else {
            throw InvitationCreditError.requestFailed(message: nil)
        }
        return try redemptionResults.removeFirst().get()
    }

    func invitations(
        actorID: String,
        page: Int,
        limit: Int
    ) async throws -> InvitationPage {
        throw InvitationCreditError.requestFailed(message: nil)
    }

    func rewards(
        actorID: String,
        page: Int,
        limit: Int
    ) async throws -> InvitationRewardPage {
        throw InvitationCreditError.requestFailed(message: nil)
    }

    func balances(actorID: String) async throws -> CreditBalances {
        guard !balanceResults.isEmpty else {
            throw InvitationCreditError.requestFailed(message: nil)
        }
        return try balanceResults.removeFirst().get()
    }

    func ledger(
        actorID: String,
        cursor: String?,
        limit: Int
    ) async throws -> CreditLedgerPage {
        throw InvitationCreditError.requestFailed(message: nil)
    }
}

final class PendingInvitationCodeMemoryStore:
    PendingInvitationCodePersisting,
    @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: PendingInvitationCode] = [:]

    func pending(actorID: String) -> PendingInvitationCode? {
        lock.withLock { values[actorID] }
    }

    func save(_ pending: PendingInvitationCode) {
        lock.withLock { values[pending.actorID] = pending }
    }

    func remove(actorID: String) {
        lock.withLock { values[actorID] = nil }
    }
}

actor InvitationRegistrarStub: InvitationAccountRegistering {
    private var results: [Result<InvitationRegisteredAccount, Error>]
    private(set) var requests: [InvitationAccountRegistrationRequest] = []
    let recorder: InvitationCallRecorder?

    init(
        results: [Result<InvitationRegisteredAccount, Error>],
        recorder: InvitationCallRecorder? = nil
    ) {
        self.results = results
        self.recorder = recorder
    }

    func register(
        _ request: InvitationAccountRegistrationRequest
    ) async throws -> InvitationRegisteredAccount {
        requests.append(request)
        await recorder?.append("register")
        guard !results.isEmpty else {
            throw InvitationCreditError.requestFailed(message: nil)
        }
        let account = try results.removeFirst().get()
        await recorder?.append("session-established")
        return account
    }

    func requestCount() -> Int {
        requests.count
    }
}
