import Combine
import Foundation

public enum InvitationRedemptionPhase: Equatable, Sendable {
    case idle
    case pendingRetry
    case validating
    case redeeming
    case succeeded(InvitationRedemption)
    case failed(InvitationCreditError)
}

@MainActor
public final class InvitationRedemptionStore: ObservableObject {
    @Published public private(set) var actorID: String?
    @Published public private(set) var draft = ""
    @Published public private(set) var pendingIntent: PendingInvitationCode?
    @Published public private(set) var phase: InvitationRedemptionPhase = .idle
    @Published public private(set) var successfulRedemptionID: UUID?

    public var canSubmit: Bool {
        actorID != nil
            && activeSubmissionID == nil
            && InvitationCode.normalized(draft) != nil
    }

    private let service: any CoreInvitationCreditServing
    private let persistence: any PendingInvitationCodePersisting
    private var generation = UUID()
    private var activeSubmissionID: UUID?

    public init(
        service: any CoreInvitationCreditServing,
        persistence: any PendingInvitationCodePersisting
    ) {
        self.service = service
        self.persistence = persistence
    }

    public func load(actorID rawActorID: String) async {
        invalidateScope()
        guard let normalizedActor = Self.normalized(rawActorID) else {
            actorID = nil
            draft = ""
            pendingIntent = nil
            phase = .failed(.invalidActor)
            return
        }
        actorID = normalizedActor
        pendingIntent = persistence.pending(actorID: normalizedActor)
        draft = pendingIntent?.code ?? ""
        phase = pendingIntent == nil ? .idle : .pendingRetry
    }

    public func setDraft(_ value: String) {
        guard activeSubmissionID == nil else { return }
        draft = value
        if case .succeeded = phase {
            phase = .idle
        } else if case .failed = phase {
            phase = pendingIntent == nil ? .idle : .pendingRetry
        }
    }

    public func submit() async {
        guard activeSubmissionID == nil,
              let actorID,
              let code = InvitationCode.normalized(draft) else {
            if self.actorID != nil, activeSubmissionID == nil {
                phase = .failed(.invalidCode)
            }
            return
        }

        draft = code
        let submissionID = UUID()
        let requestedGeneration = generation
        activeSubmissionID = submissionID
        phase = .validating
        defer {
            if activeSubmissionID == submissionID {
                activeSubmissionID = nil
            }
        }

        do {
            let validation = try await service.validate(code: code)
            guard isCurrent(
                actorID: actorID,
                generation: requestedGeneration,
                submissionID: submissionID
            ) else { return }
            guard validation.valid else {
                phase = .failed(.invalidCode)
                return
            }

            phase = .redeeming
            let redemption = try await service.redeem(
                code: code,
                actorID: actorID
            )
            guard isCurrent(
                actorID: actorID,
                generation: requestedGeneration,
                submissionID: submissionID
            ) else { return }

            persistence.remove(actorID: actorID)
            pendingIntent = nil
            draft = ""
            successfulRedemptionID = UUID()
            phase = .succeeded(redemption)
        } catch is CancellationError {
            guard isCurrent(
                actorID: actorID,
                generation: requestedGeneration,
                submissionID: submissionID
            ) else { return }
            phase = pendingIntent == nil ? .idle : .pendingRetry
        } catch {
            guard isCurrent(
                actorID: actorID,
                generation: requestedGeneration,
                submissionID: submissionID
            ) else { return }
            let mapped = Self.map(error)
            if phase == .redeeming {
                let pending = PendingInvitationCode(
                    actorID: actorID,
                    code: code,
                    needsRetry: true
                )
                persistence.save(pending)
                pendingIntent = pending
            }
            phase = .failed(mapped)
        }
    }

    public func retry() async {
        await submit()
    }

    public func discard() {
        guard let actorID else { return }
        generation = UUID()
        activeSubmissionID = nil
        persistence.remove(actorID: actorID)
        pendingIntent = nil
        draft = ""
        phase = .idle
    }

    private func invalidateScope() {
        generation = UUID()
        activeSubmissionID = nil
        actorID = nil
        draft = ""
        pendingIntent = nil
        phase = .idle
        successfulRedemptionID = nil
    }

    private func isCurrent(
        actorID: String,
        generation: UUID,
        submissionID: UUID
    ) -> Bool {
        self.actorID == actorID
            && self.generation == generation
            && activeSubmissionID == submissionID
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
