import Combine
import Foundation

@MainActor
public final class CommunityProfileStore: ObservableObject {
    @Published public private(set) var profile: CommunityProfile?
    @Published public private(set) var phase: CommunityProfilePhase = .idle
    @Published public private(set) var didBlock = false

    public var isMutating: Bool {
        switch phase {
        case .mutatingFollow, .blocking:
            true
        default:
            false
        }
    }

    private let service: any CoreCommunityProfileServing
    private var actorID: String?
    private var operationTask: Task<Void, Never>?
    private var requestID = UUID()

    public init(service: any CoreCommunityProfileServing) {
        self.service = service
    }

    public func load(actorID rawActorID: String) {
        operationTask?.cancel()
        requestID = UUID()
        let normalized = rawActorID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else {
            actorID = nil
            profile = nil
            didBlock = false
            phase = .failed(operation: .load, error: .invalidActor)
            return
        }

        actorID = normalized
        profile = nil
        didBlock = false
        phase = .loading
        let currentRequest = UUID()
        requestID = currentRequest
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await service.profile(actorID: normalized)
                guard !Task.isCancelled,
                      requestID == currentRequest,
                      actorID == normalized else {
                    return
                }
                profile = loaded
                phase = .ready
            } catch {
                guard !Task.isCancelled,
                      requestID == currentRequest,
                      actorID == normalized else {
                    return
                }
                phase = .failed(operation: .load, error: Self.map(error))
            }
        }
    }

    public func toggleFollow() {
        guard !isMutating,
              let actorID,
              let committed = profile else {
            return
        }
        let target = !committed.isFollowing
        let currentRequest = UUID()
        requestID = currentRequest
        phase = .mutatingFollow(targetFollowing: target)
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.setFollowing(
                    actorID: actorID,
                    following: target
                )
                guard !Task.isCancelled,
                      requestID == currentRequest,
                      self.actorID == actorID else {
                    return
                }
                profile = CommunityProfile(
                    actorID: committed.actorID,
                    username: committed.username,
                    avatarURL: committed.avatarURL,
                    bio: committed.bio,
                    followerCount: max(
                        0,
                        committed.followerCount + (target ? 1 : -1)
                    ),
                    followingCount: committed.followingCount,
                    isFollowing: target
                )
                phase = .ready
            } catch {
                guard !Task.isCancelled,
                      requestID == currentRequest,
                      self.actorID == actorID else {
                    return
                }
                phase = .failed(
                    operation: .follow,
                    error: Self.map(error)
                )
            }
        }
    }

    public func block() {
        guard !isMutating, !didBlock, let actorID, profile != nil else {
            return
        }
        let currentRequest = UUID()
        requestID = currentRequest
        phase = .blocking
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.block(actorID: actorID)
                guard !Task.isCancelled,
                      requestID == currentRequest,
                      self.actorID == actorID else {
                    return
                }
                didBlock = true
                phase = .blocked
            } catch {
                guard !Task.isCancelled,
                      requestID == currentRequest,
                      self.actorID == actorID else {
                    return
                }
                phase = .failed(
                    operation: .block,
                    error: Self.map(error)
                )
            }
        }
    }

    private static func map(_ error: Error) -> CommunitySocialError {
        (error as? CommunitySocialError)
            ?? .transport(code: "community_request_failed")
    }
}
