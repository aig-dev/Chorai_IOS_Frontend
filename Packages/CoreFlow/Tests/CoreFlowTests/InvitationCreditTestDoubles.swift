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
    private var balanceResults: [Result<CreditBalance, Error>] = []
    private var invitationResults: [Result<InvitationPage, Error>] = []
    private var rewardResults: [Result<InvitationRewardPage, Error>] = []
    private var ledgerResults: [Result<CreditLedgerPage, Error>] = []
    private var validationResults: [Result<InvitationValidation, Error>] = []
    private var redemptionResults: [Result<InvitationRedemption, Error>] = []
    private var validationDelayNanoseconds: UInt64 = 0
    private var referralDelayNanoseconds: UInt64 = 0
    private var balanceDelayNanoseconds: UInt64 = 0
    private(set) var validationCodes: [String] = []
    private(set) var redemptionCalls: [(code: String, actorID: String)] = []
    private(set) var invitationCalls: [(actorID: String, page: Int, limit: Int)] = []
    private(set) var rewardCalls: [(actorID: String, page: Int, limit: Int)] = []
    private(set) var balanceCalls: [String] = []
    private(set) var ledgerCalls: [(actorID: String, cursor: String?, limit: Int)] = []
    let recorder: InvitationCallRecorder?

    init(recorder: InvitationCallRecorder? = nil) {
        self.recorder = recorder
    }

    func setReferralResults(_ values: [Result<InvitationReferral, Error>]) {
        referralResults = values
    }

    func setBalanceResults(_ values: [Result<CreditBalance, Error>]) {
        balanceResults = values
    }

    func setInvitationResults(_ values: [Result<InvitationPage, Error>]) {
        invitationResults = values
    }

    func setRewardResults(_ values: [Result<InvitationRewardPage, Error>]) {
        rewardResults = values
    }

    func setLedgerResults(_ values: [Result<CreditLedgerPage, Error>]) {
        ledgerResults = values
    }

    func setReferralDelay(nanoseconds: UInt64) {
        referralDelayNanoseconds = nanoseconds
    }

    func setBalanceDelay(nanoseconds: UInt64) {
        balanceDelayNanoseconds = nanoseconds
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

    func invitationCallPages() -> [Int] {
        invitationCalls.map(\.page)
    }

    func rewardCallPages() -> [Int] {
        rewardCalls.map(\.page)
    }

    func balanceCallActorIDs() -> [String] {
        balanceCalls
    }

    func ledgerCallCursors() -> [String?] {
        ledgerCalls.map(\.cursor)
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
        invitationCalls.append((actorID, page, limit))
        guard !invitationResults.isEmpty else {
            throw InvitationCreditError.requestFailed(message: nil)
        }
        return try invitationResults.removeFirst().get()
    }

    func rewards(
        actorID: String,
        page: Int,
        limit: Int
    ) async throws -> InvitationRewardPage {
        rewardCalls.append((actorID, page, limit))
        guard !rewardResults.isEmpty else {
            throw InvitationCreditError.requestFailed(message: nil)
        }
        return try rewardResults.removeFirst().get()
    }

    func balance(actorID: String) async throws -> CreditBalance {
        balanceCalls.append(actorID)
        if balanceDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: balanceDelayNanoseconds)
        }
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
        ledgerCalls.append((actorID, cursor, limit))
        guard !ledgerResults.isEmpty else {
            throw InvitationCreditError.requestFailed(message: nil)
        }
        return try ledgerResults.removeFirst().get()
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
