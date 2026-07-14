import Combine
import Foundation

public enum InvitationRegistrationPhase: Equatable, Sendable {
    case idle
    case validating
    case registering
    case redeeming
    case failedBeforeAccount(InvitationCreditError)
    case accountCreatedPendingRedemption(
        InvitationRegisteredAccount,
        InvitationCreditError
    )
    case complete(InvitationRegisteredAccount)
}

@MainActor
public final class InvitationRegistrationStore: ObservableObject {
    @Published public private(set) var phase: InvitationRegistrationPhase = .idle
    @Published public private(set) var completedAccount: InvitationRegisteredAccount?
    @Published public private(set) var invitationCode = ""

    public var isBusy: Bool { activeOperationID != nil }

    private let registrar: any InvitationAccountRegistering
    private let invitationService: any CoreInvitationCreditServing
    private let persistence: any PendingInvitationCodePersisting
    private var activeOperationID: UUID?
    private var generation = UUID()
    private var pendingAccount: InvitationRegisteredAccount?

    public init(
        registrar: any InvitationAccountRegistering,
        invitationService: any CoreInvitationCreditServing,
        persistence: any PendingInvitationCodePersisting
    ) {
        self.registrar = registrar
        self.invitationService = invitationService
        self.persistence = persistence
    }

    public func submit(
        request: InvitationAccountRegistrationRequest,
        invitationCode rawInvitationCode: String
    ) async {
        guard activeOperationID == nil, completedAccount == nil else { return }
        let operationID = UUID()
        let requestedGeneration = generation
        let code = InvitationCode.normalized(rawInvitationCode)
        invitationCode = code ?? ""
        activeOperationID = operationID
        pendingAccount = nil
        defer {
            if activeOperationID == operationID {
                activeOperationID = nil
            }
        }

        if let code {
            phase = .validating
            do {
                let validation = try await invitationService.validate(code: code)
                guard isCurrent(operationID, generation: requestedGeneration) else {
                    return
                }
                guard validation.valid else {
                    phase = .failedBeforeAccount(.invalidCode)
                    return
                }
            } catch is CancellationError {
                guard isCurrent(operationID, generation: requestedGeneration) else {
                    return
                }
                phase = .idle
                return
            } catch {
                guard isCurrent(operationID, generation: requestedGeneration) else {
                    return
                }
                phase = .failedBeforeAccount(Self.map(error))
                return
            }
        }

        phase = .registering
        let account: InvitationRegisteredAccount
        do {
            account = try await registrar.register(request)
            guard isCurrent(operationID, generation: requestedGeneration) else {
                return
            }
            guard Self.normalized(account.actorID) != nil else {
                phase = .failedBeforeAccount(.contract(code: "invalid_actor"))
                return
            }
            pendingAccount = account
        } catch is CancellationError {
            guard isCurrent(operationID, generation: requestedGeneration) else {
                return
            }
            phase = .idle
            return
        } catch {
            guard isCurrent(operationID, generation: requestedGeneration) else {
                return
            }
            phase = .failedBeforeAccount(Self.map(error))
            return
        }

        guard let code else {
            complete(account)
            return
        }

        await redeem(
            code: code,
            account: account,
            operationID: operationID,
            generation: requestedGeneration
        )
    }

    public func retryRedemption() async {
        guard activeOperationID == nil,
              completedAccount == nil,
              let account = pendingAccount,
              let code = InvitationCode.normalized(invitationCode) else {
            return
        }
        let operationID = UUID()
        let requestedGeneration = generation
        activeOperationID = operationID
        defer {
            if activeOperationID == operationID {
                activeOperationID = nil
            }
        }
        await redeem(
            code: code,
            account: account,
            operationID: operationID,
            generation: requestedGeneration
        )
    }

    public func continueAfterPartialSuccess() {
        guard activeOperationID == nil,
              completedAccount == nil,
              let account = pendingAccount else {
            return
        }
        complete(account)
    }

    public func reset() {
        generation = UUID()
        activeOperationID = nil
        pendingAccount = nil
        completedAccount = nil
        invitationCode = ""
        phase = .idle
    }

    private func redeem(
        code: String,
        account: InvitationRegisteredAccount,
        operationID: UUID,
        generation: UUID
    ) async {
        phase = .redeeming
        do {
            _ = try await invitationService.redeem(
                code: code,
                actorID: account.actorID
            )
            guard isCurrent(operationID, generation: generation) else { return }
            persistence.remove(actorID: account.actorID)
            invitationCode = ""
            complete(account)
        } catch is CancellationError {
            guard isCurrent(operationID, generation: generation) else { return }
            persistPartial(account: account, code: code, error: nil)
        } catch {
            guard isCurrent(operationID, generation: generation) else { return }
            persistPartial(
                account: account,
                code: code,
                error: Self.map(error)
            )
        }
    }

    private func persistPartial(
        account: InvitationRegisteredAccount,
        code: String,
        error: InvitationCreditError?
    ) {
        let pending = PendingInvitationCode(
            actorID: account.actorID,
            code: code,
            needsRetry: true
        )
        persistence.save(pending)
        pendingAccount = account
        phase = .accountCreatedPendingRedemption(
            account,
            error ?? .requestFailed(message: nil)
        )
    }

    private func complete(_ account: InvitationRegisteredAccount) {
        pendingAccount = account
        completedAccount = account
        phase = .complete(account)
    }

    private func isCurrent(_ operationID: UUID, generation: UUID) -> Bool {
        self.generation == generation && activeOperationID == operationID
    }

    private static func normalized(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func map(_ error: Error) -> InvitationCreditError {
        if let error = error as? InvitationCreditError { return error }
        return .requestFailed(message: nil)
    }
}
