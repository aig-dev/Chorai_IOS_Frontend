import Combine
import Foundation

public enum BlockedActorsOperation: Equatable, Sendable {
    case load
    case loadMore
    case unblock(actorID: String)
}

public enum BlockedActorsPhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case empty
    case loadingMore
    case unblocking(actorID: String)
    case failed(operation: BlockedActorsOperation, error: CommunitySocialError)
}

@MainActor
public final class BlockedActorsStore: ObservableObject {
    public static let pageSize = 20

    @Published public private(set) var items: [BlockedActor] = []
    @Published public private(set) var phase: BlockedActorsPhase = .idle
    @Published public private(set) var hasMore = false

    private let service: any CoreCommunityProfileServing
    private var nextCursor: String?
    private var operationTask: Task<Void, Never>?
    private var requestID = UUID()

    public init(service: any CoreCommunityProfileServing) {
        self.service = service
    }

    public func load() {
        operationTask?.cancel()
        items = []
        hasMore = false
        nextCursor = nil
        phase = .loading
        fetchPage(cursor: nil, operation: .load, replacing: true)
    }

    public func loadMore() {
        guard !isBusy,
              hasMore,
              let cursor = Self.normalize(nextCursor) else {
            return
        }
        phase = .loadingMore
        fetchPage(cursor: cursor, operation: .loadMore, replacing: false)
    }

    public func unblock(actorID: String) {
        guard !isBusy,
              items.contains(where: { $0.actorID == actorID }) else {
            return
        }
        let currentRequest = UUID()
        requestID = currentRequest
        phase = .unblocking(actorID: actorID)
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.unblock(actorID: actorID)
                guard !Task.isCancelled, requestID == currentRequest else {
                    return
                }
                items.removeAll { $0.actorID == actorID }
                phase = items.isEmpty ? .empty : .ready
            } catch {
                guard !Task.isCancelled, requestID == currentRequest else {
                    return
                }
                phase = .failed(
                    operation: .unblock(actorID: actorID),
                    error: Self.map(error)
                )
            }
        }
    }

    private var isBusy: Bool {
        switch phase {
        case .loading, .loadingMore, .unblocking:
            true
        default:
            false
        }
    }

    private func fetchPage(
        cursor: String?,
        operation: BlockedActorsOperation,
        replacing: Bool
    ) {
        let currentRequest = UUID()
        requestID = currentRequest
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await service.blockedActors(
                    cursor: cursor,
                    limit: Self.pageSize
                )
                guard !Task.isCancelled, requestID == currentRequest else {
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
                guard !Task.isCancelled, requestID == currentRequest else {
                    return
                }
                phase = .failed(
                    operation: operation,
                    error: Self.map(error)
                )
            }
        }
    }

    private static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func deduplicated(
        _ values: [BlockedActor]
    ) -> [BlockedActor] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.actorID).inserted }
    }

    private static func map(_ error: Error) -> CommunitySocialError {
        (error as? CommunitySocialError)
            ?? .transport(code: "blocked_actors_request_failed")
    }
}
