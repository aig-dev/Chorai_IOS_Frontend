import Combine
import Foundation

public struct OwnedCardActionSnapshot: Equatable, Sendable {
    public let cardID: String
    public let isOwned: Bool
    public var isPublic: Bool
    public var isPinned: Bool
    public var pinnedAt: String?

    public init(cardID: String, isOwned: Bool, isPublic: Bool, isPinned: Bool, pinnedAt: String?) {
        self.cardID = cardID
        self.isOwned = isOwned
        self.isPublic = isPublic
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
    }
}

/// An explicitly fresh read after another surface has edited the card. Ordinary
/// list/detail projections must not replace the more recent mutation receipt.
public struct OwnedCardActionRefresh: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let snapshot: OwnedCardActionSnapshot
    public init(id: UUID = UUID(), snapshot: OwnedCardActionSnapshot) {
        self.id = id
        self.snapshot = snapshot
    }
}

public struct OwnedCardActionRequest: Equatable, Sendable {
    public enum Operation: Equatable, Sendable {
        case remove
        case setVisibility(Bool)
        case setPinned(Bool)
    }
    public let cardID: String
    public let operation: Operation
    public let privacy: NotePrivacyObservation?
    public init(cardID: String, operation: Operation, privacy: NotePrivacyObservation? = nil) {
        self.privacy = privacy
        self.cardID = cardID
        self.operation = operation
    }
}

public enum OwnedCardActionCommit: Equatable, Sendable {
    case removed(cardID: String)
    case visibility(cardID: String, isPublic: Bool)
    case pin(cardID: String, isPinned: Bool, pinnedAt: String?)

    public var cardID: String {
        switch self {
        case .removed(let id), .visibility(let id, _), .pin(let id, _, _): return id
        }
    }
}

public enum OwnedCardActionError: Error, Equatable, Sendable {
    case requestFailed
    case invalidResponse
    case privacy(NotePrivacyError)

    public var mayRetry: Bool {
        switch self {
        case .privacy(.stalePolicy), .privacy(.idempotencyConflict), .privacy(.rejected), .privacy(.invalidCommand): false
        default: true
        }
    }
}

public struct OwnedCardActionFailure: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let request: OwnedCardActionRequest
    public let error: OwnedCardActionError
}

@MainActor
public protocol OwnedCardActionServing {
    func perform(_ request: OwnedCardActionRequest) async throws -> OwnedCardActionCommit
}

/// Owns an exact card/action until the service commits. It has no dependency on
/// a mounted library or its current page of cards, and never changes optimistically.
@MainActor
public final class OwnedCardActionStore: ObservableObject {
    @Published public private(set) var removalTarget: OwnedCardActionSnapshot?
    @Published public private(set) var workingRequest: OwnedCardActionRequest?
    @Published public private(set) var failure: OwnedCardActionFailure?
    @Published public private(set) var lastCommit: OwnedCardActionCommit?
    @Published public private(set) var commitRevision = 0
    @Published public private(set) var stateRevision = 0
    private var snapshots: [String: OwnedCardActionSnapshot] = [:]
    private var removedIDs: Set<String> = []
    private var sessionEpoch: UInt64 = 0
    private var retryIdentity: UUID?
    private var pendingRemoval: OwnedCardActionSnapshot?
    private var appliedRefreshIDs: Set<UUID> = []
    private let service: any OwnedCardActionServing

    public init(service: any OwnedCardActionServing) { self.service = service }

    public var isInteractionLocked: Bool {
        removalTarget != nil || workingRequest != nil || failure != nil
    }

    public func resolved(_ candidate: OwnedCardActionSnapshot) -> OwnedCardActionSnapshot {
        guard candidate.isOwned else { return candidate }
        return snapshots[candidate.cardID] ?? candidate
    }

    public func isRemoved(cardID: String) -> Bool { removedIDs.contains(cardID) }

    public func applyAuthoritativeRefresh(_ refresh: OwnedCardActionRefresh) {
        guard !isInteractionLocked, !appliedRefreshIDs.contains(refresh.id),
              refresh.snapshot.isOwned,
              !refresh.snapshot.cardID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        appliedRefreshIDs.insert(refresh.id)
        snapshots[refresh.snapshot.cardID] = refresh.snapshot
        removedIDs.remove(refresh.snapshot.cardID)
        retryIdentity = nil
        pendingRemoval = nil
        stateRevision += 1
    }

    public func requestRemoval(of candidate: OwnedCardActionSnapshot) {
        guard canStart(candidate) else { return }
        retryIdentity = nil
        removalTarget = resolved(candidate)
        pendingRemoval = removalTarget
    }

    /// A system confirmation can dismiss its binding before delivering its button.
    /// Keep that exact pending target until Confirm, Cancel, or a different action.
    public func dismissRemovalDialog() { removalTarget = nil }

    public func cancelRemoval() {
        removalTarget = nil
        pendingRemoval = nil
    }

    public func confirmRemoval() {
        guard let target = pendingRemoval else { return }
        confirmRemoval(of: target)
    }

    public func confirmRemoval(of target: OwnedCardActionSnapshot) {
        guard pendingRemoval == target, workingRequest == nil, failure == nil else { return }
        removalTarget = nil
        pendingRemoval = nil
        start(.init(cardID: target.cardID, operation: .remove), snapshot: target)
    }

    public func setVisibility(of candidate: OwnedCardActionSnapshot, desired: Bool, observation: NotePrivacyObservation) {
        guard canStart(candidate) else { return }
        start(.init(cardID: candidate.cardID, operation: .setVisibility(desired), privacy: observation), snapshot: resolved(candidate))
    }

    public func toggleVisibility(of candidate: OwnedCardActionSnapshot) {
        guard canStart(candidate) else { return }
        let target = resolved(candidate)
        start(.init(cardID: target.cardID, operation: .setVisibility(!target.isPublic)), snapshot: target)
    }

    public func togglePin(of candidate: OwnedCardActionSnapshot) {
        guard canStart(candidate) else { return }
        let target = resolved(candidate)
        start(.init(cardID: target.cardID, operation: .setPinned(!target.isPinned)), snapshot: target)
    }

    public func retireSession() {
        sessionEpoch &+= 1
        retryIdentity = nil
        removalTarget = nil
        pendingRemoval = nil
        workingRequest = nil
        failure = nil
        lastCommit = nil
        snapshots.removeAll()
        removedIDs.removeAll()
        appliedRefreshIDs.removeAll()
        stateRevision += 1
    }

    public func dismissFailure() { failure = nil }

    /// The failure token prevents an old alert from retrying after a later action.
    /// Dismissing the system alert before its Retry callback does not lose its request.
    public func retry(_ failed: OwnedCardActionFailure) {
        guard failed.error.mayRetry, retryIdentity == failed.id,
              workingRequest == nil, removalTarget == nil,
              failure == nil || failure?.id == failed.id,
              let snapshot = snapshots[failed.request.cardID], snapshot.isOwned,
              !removedIDs.contains(snapshot.cardID) else { return }
        failure = nil
        start(failed.request, snapshot: snapshot)
    }

    private func canStart(_ candidate: OwnedCardActionSnapshot) -> Bool {
        candidate.isOwned
            && !candidate.cardID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isInteractionLocked && !removedIDs.contains(candidate.cardID)
    }

    private func start(_ request: OwnedCardActionRequest, snapshot: OwnedCardActionSnapshot) {
        guard !isInteractionLocked, snapshot.isOwned,
              request.cardID == snapshot.cardID,
              !snapshot.cardID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !removedIDs.contains(snapshot.cardID) else { return }
        retryIdentity = nil
        pendingRemoval = nil
        snapshots[snapshot.cardID] = snapshot
        workingRequest = request
        let epoch = sessionEpoch
        Task { [weak self] in
            guard let self else { return }
            do {
                let commit = try await service.perform(request)
                guard sessionEpoch == epoch, workingRequest == request else { return }
                guard matches(commit, request: request) else { throw OwnedCardActionError.invalidResponse }
                var updated = snapshot
                switch commit {
                case .removed(let id): removedIDs.insert(id)
                case .visibility(_, let value): updated.isPublic = value
                case .pin(_, let value, let date): updated.isPinned = value; updated.pinnedAt = date
                }
                snapshots[updated.cardID] = updated
                workingRequest = nil
                lastCommit = commit
                commitRevision += 1
                stateRevision += 1
            } catch {
                guard sessionEpoch == epoch, workingRequest == request else { return }
                workingRequest = nil
                let failed = OwnedCardActionFailure(id: UUID(), request: request,
                    error: (error as? NotePrivacyError).map(OwnedCardActionError.privacy) ?? (error as? OwnedCardActionError) ?? .requestFailed)
                retryIdentity = failed.id
                failure = failed
            }
        }
    }

    private func matches(_ commit: OwnedCardActionCommit, request: OwnedCardActionRequest) -> Bool {
        guard commit.cardID == request.cardID else { return false }
        switch (request.operation, commit) {
        case (.remove, .removed), (.setVisibility, .visibility), (.setPinned, .pin): return true
        default: return false
        }
    }
}
