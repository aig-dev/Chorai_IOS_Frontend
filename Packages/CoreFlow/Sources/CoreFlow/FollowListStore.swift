import Combine
import Foundation

public enum FollowListOperation: Equatable, Sendable {
    case load
    case loadMore
    case follow(actorID: String)
}

public enum FollowListPhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case empty
    case privateList
    case loadingMore
    case mutating(actorID: String)
    case failed(operation: FollowListOperation, error: CommunitySocialError)
}

@MainActor
public final class FollowListStore: ObservableObject {
    public static let pageSize = 20

    @Published public private(set) var items: [CommunityActor] = []
    @Published public private(set) var phase: FollowListPhase = .idle
    @Published public private(set) var hasMore = false

    private let service: any CoreCommunityProfileServing
    private var actorID: String?
    private var kind: FollowListKind?
    private var viewerActorID: String?
    private var nextCursor: String?
    private var operationTask: Task<Void, Never>?
    private var requestID = UUID()

    public init(service: any CoreCommunityProfileServing) {
        self.service = service
    }

    public func load(
        actorID rawActorID: String,
        kind: FollowListKind,
        viewerActorID rawViewerActorID: String
    ) {
        operationTask?.cancel()
        let actorID = Self.normalize(rawActorID)
        let viewerActorID = Self.normalize(rawViewerActorID)
        guard let actorID, let viewerActorID else {
            self.actorID = actorID
            self.kind = kind
            self.viewerActorID = viewerActorID
            items = []
            hasMore = false
            nextCursor = nil
            phase = .failed(operation: .load, error: .invalidActor)
            return
        }

        self.actorID = actorID
        self.kind = kind
        self.viewerActorID = viewerActorID
        items = []
        hasMore = false
        nextCursor = nil
        phase = .loading
        fetchPage(cursor: nil, operation: .load, replacing: true)
    }

    public func loadMore() {
        guard !isBusy,
              hasMore,
              let cursor = Self.normalize(nextCursor),
              actorID != nil,
              kind != nil else {
            return
        }
        phase = .loadingMore
        fetchPage(cursor: cursor, operation: .loadMore, replacing: false)
    }

    public func toggleFollow(actorID targetActorID: String) {
        guard !isBusy,
              targetActorID != viewerActorID,
              let index = items.firstIndex(where: {
                  $0.actorID == targetActorID
              }),
              let listActorID = actorID,
              let kind else {
            return
        }
        let committed = items[index]
        let target = !committed.isFollowing
        let currentRequest = UUID()
        requestID = currentRequest
        phase = .mutating(actorID: targetActorID)
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.setFollowing(
                    actorID: targetActorID,
                    following: target
                )
                guard !Task.isCancelled,
                      requestID == currentRequest,
                      actorID == listActorID,
                      self.kind == kind,
                      let currentIndex = items.firstIndex(where: {
                          $0.actorID == targetActorID
                      }) else {
                    return
                }
                items[currentIndex] = CommunityActor(
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
                phase = items.isEmpty ? .empty : .ready
            } catch {
                guard !Task.isCancelled,
                      requestID == currentRequest,
                      actorID == listActorID,
                      self.kind == kind else {
                    return
                }
                phase = .failed(
                    operation: .follow(actorID: targetActorID),
                    error: Self.map(error)
                )
            }
        }
    }

    private var isBusy: Bool {
        switch phase {
        case .loading, .loadingMore, .mutating:
            true
        default:
            false
        }
    }

    private func fetchPage(
        cursor: String?,
        operation: FollowListOperation,
        replacing: Bool
    ) {
        guard let actorID, let kind else { return }
        let currentRequest = UUID()
        requestID = currentRequest
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await service.followList(
                    actorID: actorID,
                    kind: kind,
                    cursor: cursor,
                    limit: Self.pageSize
                )
                guard !Task.isCancelled,
                      requestID == currentRequest,
                      self.actorID == actorID,
                      self.kind == kind else {
                    return
                }
                items = replacing
                    ? Self.deduplicated(page.items)
                    : Self.deduplicated(items + page.items)
                let candidate = Self.normalize(page.nextCursor)
                let advances = candidate != nil && candidate != cursor
                nextCursor = advances ? candidate : nil
                hasMore = page.hasMore && advances
                phase = items.isEmpty ? .empty : .ready
            } catch {
                guard !Task.isCancelled,
                      requestID == currentRequest,
                      self.actorID == actorID,
                      self.kind == kind else {
                    return
                }
                let mapped = Self.map(error)
                if replacing && mapped == .forbidden {
                    items = []
                    hasMore = false
                    nextCursor = nil
                    phase = .privateList
                } else {
                    phase = .failed(operation: operation, error: mapped)
                }
            }
        }
    }

    private static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func deduplicated(
        _ values: [CommunityActor]
    ) -> [CommunityActor] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.actorID).inserted }
    }

    private static func map(_ error: Error) -> CommunitySocialError {
        (error as? CommunitySocialError)
            ?? .transport(code: "follow_list_request_failed")
    }
}
