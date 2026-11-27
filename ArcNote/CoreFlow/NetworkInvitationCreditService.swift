import Combine
import CoreFlow
import Foundation

@MainActor
protocol InvitationCreditNetworkTransporting: Sendable {
    func getUserGroup(
        presentsError: Bool
    ) -> AnyPublisher<InvitationReferralResponse, NetworkError>
    func validateInvitationCode(
        _ request: ValidateInvitationRequest,
        presentsError: Bool
    ) -> AnyPublisher<InvitationValidateResponse, NetworkError>
    func useInvitationCode(
        _ request: UseInvitationRequest,
        presentsError: Bool
    ) -> AnyPublisher<InvitationRedeemResponse, NetworkError>
    func getInvitationRecords(
        page: Int,
        limit: Int,
        status: String?,
        presentsError: Bool
    ) -> AnyPublisher<InvitationRecordsResponse, NetworkError>
    func getInvitationRewards(
        page: Int,
        limit: Int,
        presentsError: Bool
    ) -> AnyPublisher<InvitationRewardsResponse, NetworkError>
    func getUserCredit(
        presentsError: Bool
    ) -> AnyPublisher<NetworkResponse<CreditBalanceData>, NetworkError>
    func getCreditLedger(
        cursor: String?,
        limit: Int,
        presentsError: Bool
    ) -> AnyPublisher<CreditLedgerResponse, NetworkError>
}

extension NetworkManager: InvitationCreditNetworkTransporting {}

struct NetworkInvitationCreditService:
    CoreInvitationCreditServing,
    Sendable {
    private let network: any InvitationCreditNetworkTransporting

    @MainActor
    init(
        network: any InvitationCreditNetworkTransporting = NetworkManager.shared
    ) {
        self.network = network
    }

    func referral(actorID: String) async throws -> InvitationReferral {
        try Self.requireActor(actorID)
        do {
            let response = try await firstValue(
                network.getUserGroup(presentsError: false)
            )
            guard response.success else {
                throw InvitationCreditError.requestFailed(
                    message: Self.safeMessage(response.message)
                )
            }
            return try Self.mapReferral(response.data)
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func validate(code: String) async throws -> InvitationValidation {
        guard let code = InvitationCode.normalized(code) else {
            throw InvitationCreditError.invalidCode
        }
        do {
            let response = try await firstValue(
                network.validateInvitationCode(
                    ValidateInvitationRequest(code: code),
                    presentsError: false
                )
            )
            guard response.success else {
                throw InvitationCreditError.requestFailed(
                    message: Self.safeMessage(response.message)
                )
            }
            return InvitationValidation(valid: response.data.valid)
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func redeem(code: String, actorID: String) async throws -> InvitationRedemption {
        try Self.requireActor(actorID)
        guard let code = InvitationCode.normalized(code) else {
            throw InvitationCreditError.invalidCode
        }
        do {
            let response = try await firstValue(
                network.useInvitationCode(
                    UseInvitationRequest(code: code),
                    presentsError: false
                )
            )
            guard response.success else {
                throw InvitationCreditError.requestFailed(
                    message: Self.safeMessage(response.message)
                )
            }
            let recordID = response.data.invitationRecordId.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !recordID.isEmpty else {
                throw InvitationCreditError.contract(code: "missing_record_id")
            }
            return InvitationRedemption(
                recordID: recordID,
                status: InvitationStatus(canonical: response.data.status)
            )
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func invitations(
        actorID: String,
        page: Int,
        limit: Int
    ) async throws -> InvitationPage {
        try Self.requireActor(actorID)
        guard page > 0, limit > 0 else {
            throw InvitationCreditError.contract(code: "invalid_invitation_query")
        }
        do {
            let response = try await firstValue(
                network.getInvitationRecords(
                    page: page,
                    limit: limit,
                    status: nil,
                    presentsError: false
                )
            )
            guard response.success else {
                throw InvitationCreditError.requestFailed(
                    message: Self.safeMessage(response.message)
                )
            }
            return try Self.mapInvitationPage(response.data)
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func rewards(
        actorID: String,
        page: Int,
        limit: Int
    ) async throws -> InvitationRewardPage {
        try Self.requireActor(actorID)
        guard page > 0, limit > 0 else {
            throw InvitationCreditError.contract(code: "invalid_reward_query")
        }
        do {
            let response = try await firstValue(
                network.getInvitationRewards(
                    page: page,
                    limit: limit,
                    presentsError: false
                )
            )
            guard response.success else {
                throw InvitationCreditError.requestFailed(
                    message: Self.safeMessage(response.message)
                )
            }
            return try Self.mapRewardPage(response.data)
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func balance(actorID: String) async throws -> CreditBalance {
        try Self.requireActor(actorID)
        do {
            let response = try await firstValue(
                network.getUserCredit(presentsError: false)
            )
            guard response.success, let data = response.data else {
                throw InvitationCreditError.requestFailed(
                    message: Self.safeMessage(response.message)
                )
            }
            return try Self.mapBalance(data)
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func ledger(
        actorID: String,
        cursor: String?,
        limit: Int
    ) async throws -> CreditLedgerPage {
        try Self.requireActor(actorID)
        guard limit > 0 else {
            throw InvitationCreditError.contract(code: "invalid_ledger_query")
        }
        do {
            let response = try await firstValue(
                network.getCreditLedger(
                    cursor: cursor,
                    limit: limit,
                    presentsError: false
                )
            )
            guard response.success else {
                throw InvitationCreditError.requestFailed(
                    message: Self.safeMessage(response.message)
                )
            }
            return try Self.mapLedger(response.data)
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    static func mapReferral(
        _ response: InvitationReferralData
    ) throws -> InvitationReferral {
        guard let code = InvitationCode.normalized(response.code),
              response.usedCount >= 0,
              response.nextMilestone.map({ $0 >= 0 }) ?? true else {
            throw InvitationCreditError.contract(code: "invalid_referral")
        }
        return InvitationReferral(
            code: code,
            link: response.link.trimmingCharacters(in: .whitespacesAndNewlines),
            usedCount: response.usedCount,
            nextMilestone: response.nextMilestone
        )
    }

    static func mapBalance(
        _ response: CreditBalanceData
    ) throws -> CreditBalance {
        CreditBalance(
            balance: response.balance,
            updatedAt: response.updatedAt.isEmpty
                ? nil
                : try parseDate(response.updatedAt)
        )
    }

    static func mapInvitationPage(
        _ response: InvitationPaginatedData<InvitationRecordItem>
    ) throws -> InvitationPage {
        try validatePage(total: response.total, page: response.page, limit: response.limit)
        return InvitationPage(
            items: try response.items.map { item in
                guard !item.invitationRecordId.isEmpty else {
                    throw InvitationCreditError.contract(code: "missing_invitation_id")
                }
                return InvitationRecord(
                    id: item.invitationRecordId,
                    status: InvitationStatus(canonical: item.status),
                    createdAt: try parseDate(item.createdAt)
                )
            },
            total: response.total,
            page: response.page,
            limit: response.limit
        )
    }

    static func mapRewardPage(
        _ response: InvitationPaginatedData<InvitationRewardItem>
    ) throws -> InvitationRewardPage {
        try validatePage(total: response.total, page: response.page, limit: response.limit)
        return InvitationRewardPage(
            items: try response.items.map { item in
                guard !item.invitationRewardId.isEmpty else {
                    throw InvitationCreditError.contract(code: "missing_reward_id")
                }
                return InvitationReward(
                    id: item.invitationRewardId,
                    recipientRole: item.recipientRole,
                    amount: item.amount,
                    milestoneThreshold: item.milestoneThreshold,
                    status: InvitationRewardStatus(canonical: item.status),
                    createdAt: try parseDate(item.createdAt)
                )
            },
            total: response.total,
            page: response.page,
            limit: response.limit
        )
    }

    static func mapLedger(_ response: CreditLedgerData) throws -> CreditLedgerPage {
        CreditLedgerPage(
            entries: try response.entries.map { item in
                guard !item.logId.isEmpty, !item.transactionId.isEmpty else {
                    throw InvitationCreditError.contract(code: "missing_ledger_id")
                }
                return CreditLedgerEntry(
                    id: item.logId,
                    transactionID: item.transactionId,
                    account: item.account,
                    direction: LedgerDirection(canonical: item.direction),
                    delta: item.delta,
                    runningBalance: item.runningBalance,
                    status: LedgerStatus(canonical: item.status),
                    ruleID: item.ruleId,
                    actionType: item.actionType,
                    category: item.category,
                    referenceID: item.referenceId,
                    referenceType: item.referenceType,
                    activityID: item.activityId,
                    createdAt: try parseDate(item.createdAt),
                    settledAt: try item.settledAt.map(parseDate),
                    refundedAt: try item.refundedAt.map(parseDate)
                )
            },
            cursor: response.cursor.flatMap(InvitationCode.normalized),
            hasMore: response.hasMore
        )
    }

    @MainActor
    private func firstValue<Output: Sendable>(
        _ publisher: @autoclosure @MainActor @Sendable () -> AnyPublisher<Output, NetworkError>
    ) async throws -> Output {
        guard let value = try await NetworkManager.firstValue(publisher()) else {
            throw NetworkError.noData
        }
        return value
    }

    private static func requireActor(_ actorID: String) throws {
        guard InvitationCode.normalized(actorID) != nil else {
            throw InvitationCreditError.invalidActor
        }
    }

    private static func validatePage(total: Int, page: Int, limit: Int) throws {
        guard total >= 0, page > 0, limit > 0 else {
            throw InvitationCreditError.contract(code: "invalid_page")
        }
    }

    private static func parseDate(_ value: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) { return date }
        throw InvitationCreditError.contract(code: "invalid_date")
    }

    private static func safeMessage(_ value: String?) -> String? {
        guard let value else { return nil }
        let message = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 160 else { return nil }
        return message
    }

    private static func mapNetworkError(_ error: Error) -> InvitationCreditError {
        if let error = error as? InvitationCreditError { return error }
        guard let error = error as? NetworkError else {
            return .requestFailed(message: nil)
        }
        switch error {
        case .unauthorized:
            return .unauthorized
        case .api(_, _, let message, _), .serverError(_, let message):
            return .requestFailed(message: safeMessage(message))
        default:
            return .requestFailed(message: nil)
        }
    }
}
