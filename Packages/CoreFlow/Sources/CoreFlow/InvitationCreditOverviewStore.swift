import Combine
import Foundation

@MainActor
public final class InvitationCreditOverviewStore: ObservableObject {
    @Published public private(set) var actorID: String?
    @Published public private(set) var referral: InvitationReferral?
    @Published public private(set) var balance: CreditBalance?
    @Published public private(set) var referralPhase: InvitationCreditSectionPhase = .idle
    @Published public private(set) var balancePhase: InvitationCreditSectionPhase = .idle

    private let service: any CoreInvitationCreditServing
    private var generation = UUID()

    public init(service: any CoreInvitationCreditServing) {
        self.service = service
    }

    public func load(actorID rawActorID: String) async {
        generation = UUID()
        referral = nil
        balance = nil
        referralPhase = .idle
        balancePhase = .idle

        guard let actorID = Self.normalized(rawActorID) else {
            self.actorID = nil
            referralPhase = .failed(.invalidActor)
            balancePhase = .failed(.invalidActor)
            return
        }
        self.actorID = actorID
        referralPhase = .loading
        balancePhase = .loading
        let requestedGeneration = generation

        async let referralLoad: Void = fetchReferral(
            actorID: actorID,
            generation: requestedGeneration
        )
        async let balanceLoad: Void = fetchBalance(
            actorID: actorID,
            generation: requestedGeneration
        )
        _ = await (referralLoad, balanceLoad)
    }

    public func refresh() async {
        guard let actorID else {
            referralPhase = .failed(.invalidActor)
            balancePhase = .failed(.invalidActor)
            return
        }
        generation = UUID()
        let requestedGeneration = generation
        referralPhase = referral == nil ? .loading : .refreshing
        balancePhase = balance == nil ? .loading : .refreshing

        async let referralLoad: Void = fetchReferral(
            actorID: actorID,
            generation: requestedGeneration
        )
        async let balanceLoad: Void = fetchBalance(
            actorID: actorID,
            generation: requestedGeneration
        )
        _ = await (referralLoad, balanceLoad)
    }

    public func retryReferral() async {
        guard let actorID else {
            referralPhase = .failed(.invalidActor)
            return
        }
        let requestedGeneration = generation
        referralPhase = referral == nil ? .loading : .refreshing
        await fetchReferral(actorID: actorID, generation: requestedGeneration)
    }

    public func retryBalance() async {
        guard let actorID else {
            balancePhase = .failed(.invalidActor)
            return
        }
        let requestedGeneration = generation
        balancePhase = balance == nil ? .loading : .refreshing
        await fetchBalance(actorID: actorID, generation: requestedGeneration)
    }

    private func fetchReferral(actorID: String, generation: UUID) async {
        do {
            let value = try await service.referral(actorID: actorID)
            guard isCurrent(actorID: actorID, generation: generation) else {
                return
            }
            referral = value
            referralPhase = .ready
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(actorID: actorID, generation: generation) else {
                return
            }
            referralPhase = .failed(Self.map(error))
        }
    }

    private func fetchBalance(actorID: String, generation: UUID) async {
        do {
            let value = try await service.balance(actorID: actorID)
            guard isCurrent(actorID: actorID, generation: generation) else {
                return
            }
            balance = value
            balancePhase = .ready
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(actorID: actorID, generation: generation) else {
                return
            }
            balancePhase = .failed(Self.map(error))
        }
    }

    private func isCurrent(actorID: String, generation: UUID) -> Bool {
        self.actorID == actorID && self.generation == generation
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
