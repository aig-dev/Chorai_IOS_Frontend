import Combine
import Foundation

@MainActor
public final class NotificationInboxStore: ObservableObject {
    public static let pageSize = 20

    @Published public private(set) var items: [CommunityNotification] = []
    @Published public private(set) var phase: NotificationInboxPhase = .idle
    @Published public private(set) var unreadCount = 0
    @Published public private(set) var hasMore = false
    @Published public private(set) var mutatingIDs: Set<String> = []
    @Published public private(set) var isMarkingAll = false
    @Published public private(set) var actionFailure: NotificationActionFailure?

    private let service: any CoreNotificationServing
    private var actorID: String?
    private var loadedPageCount = 0
    private var total = 0
    private var scopeID = UUID()
    private var pageRequestID = UUID()
    private var operationTask: Task<Void, Never>?
    private var mutationTasks: [String: Task<Void, Never>] = [:]
    private var mutationTokens: [String: UUID] = [:]

    public init(service: any CoreNotificationServing) {
        self.service = service
    }

    public func load(actorID rawActorID: String) {
        invalidateScope()
        guard let actorID = Self.normalized(rawActorID) else {
            self.actorID = nil
            items = []
            unreadCount = 0
            hasMore = false
            loadedPageCount = 0
            total = 0
            phase = .failed(operation: .load, error: .invalidActor)
            return
        }

        self.actorID = actorID
        items = []
        unreadCount = 0
        hasMore = false
        loadedPageCount = 0
        total = 0
        phase = .loading
        fetchPage(1, replacing: true, operation: .load)
    }

    public func reload() {
        guard let actorID else {
            phase = .failed(operation: .load, error: .invalidActor)
            return
        }
        load(actorID: actorID)
    }

    public func loadMore() {
        guard !isPageBusy, hasMore, actorID != nil else { return }
        phase = .loadingMore
        fetchPage(
            loadedPageCount + 1,
            replacing: false,
            operation: .loadMore
        )
    }

    public func filteredItems(
        _ filter: NotificationFilter
    ) -> [CommunityNotification] {
        switch filter {
        case .all:
            return items
        case .unread:
            return items.filter { !$0.isRead }
        case .activity:
            return items.filter { $0.kind.category == .activity }
        case .system:
            return items.filter { $0.kind.category == .system }
        }
    }

    public func markRead(notificationID: String) {
        guard actorID != nil,
              !isMarkingAll,
              !mutatingIDs.contains(notificationID),
              let index = items.firstIndex(where: { $0.id == notificationID }),
              !items[index].isRead else {
            return
        }

        let snapshot = items[index]
        let unreadSnapshot = unreadCount
        let currentScope = scopeID
        let token = UUID()
        items[index].isRead = true
        unreadCount = max(0, unreadCount - 1)
        mutatingIDs.insert(notificationID)
        mutationTokens[notificationID] = token
        actionFailure = nil

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.markRead(notificationID: notificationID)
                guard scopeID == currentScope,
                      mutationTokens[notificationID] == token else {
                    return
                }
                finishMutation(notificationID: notificationID)
            } catch {
                guard scopeID == currentScope,
                      mutationTokens[notificationID] == token else {
                    return
                }
                if let currentIndex = items.firstIndex(where: {
                    $0.id == notificationID
                }) {
                    items[currentIndex] = snapshot
                }
                unreadCount = unreadSnapshot
                finishMutation(notificationID: notificationID)
                actionFailure = NotificationActionFailure(
                    operation: .markRead(id: notificationID),
                    error: Self.map(error)
                )
            }
        }
        mutationTasks[notificationID] = task
    }

    public func markAllLoadedRead() {
        let unreadIDs = items.filter { !$0.isRead }.map(\.id)
        guard actorID != nil,
              !isMarkingAll,
              mutatingIDs.isEmpty,
              !unreadIDs.isEmpty else {
            return
        }

        let snapshot = items
        let unreadSnapshot = unreadCount
        let pageCountSnapshot = max(1, loadedPageCount)
        let currentScope = scopeID
        for index in items.indices where !items[index].isRead {
            items[index].isRead = true
        }
        unreadCount = max(0, unreadCount - unreadIDs.count)
        mutatingIDs = Set(unreadIDs)
        isMarkingAll = true
        actionFailure = nil

        operationTask = Task { [weak self] in
            guard let self else { return }
            var mutationError: NotificationInboxError?
            for notificationID in unreadIDs {
                do {
                    try await service.markRead(notificationID: notificationID)
                } catch {
                    mutationError = Self.map(error)
                    break
                }
            }
            guard scopeID == currentScope else { return }

            if let mutationError {
                items = snapshot
                unreadCount = unreadSnapshot
                actionFailure = NotificationActionFailure(
                    operation: .markAllRead,
                    error: mutationError
                )
                do {
                    try await reconcileLoadedPages(
                        count: pageCountSnapshot,
                        scope: currentScope
                    )
                } catch {
                    // Keep the exact pre-mutation snapshot and original action error.
                }
            }
            guard scopeID == currentScope else { return }
            mutatingIDs = []
            isMarkingAll = false
            phase = items.isEmpty ? .empty : .ready
        }
    }

    public func retryLastFailure() {
        if let actionFailure {
            switch actionFailure.operation {
            case .markRead(let id):
                markRead(notificationID: id)
            case .markAllRead:
                markAllLoadedRead()
            case .load, .loadMore:
                break
            }
            return
        }
        guard case .failed(let operation, _) = phase else { return }
        switch operation {
        case .load:
            reload()
        case .loadMore:
            loadMore()
        case .markRead, .markAllRead:
            break
        }
    }

    private var isPageBusy: Bool {
        switch phase {
        case .loading, .loadingMore:
            return true
        default:
            return false
        }
    }

    private func fetchPage(
        _ requestedPage: Int,
        replacing: Bool,
        operation: NotificationInboxOperation
    ) {
        guard let actorID else { return }
        let requestID = UUID()
        let currentScope = scopeID
        pageRequestID = requestID
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await service.notifications(
                    page: requestedPage,
                    perPage: Self.pageSize
                )
                guard !Task.isCancelled,
                      scopeID == currentScope,
                      pageRequestID == requestID,
                      self.actorID == actorID else {
                    return
                }
                guard page.page == requestedPage else {
                    throw NotificationInboxError.contract(
                        code: "unexpected_page"
                    )
                }
                items = replacing
                    ? Self.deduplicated(page.items)
                    : Self.deduplicated(items + page.items)
                unreadCount = max(0, page.unreadCount)
                total = max(0, page.total)
                loadedPageCount = replacing
                    ? requestedPage
                    : max(loadedPageCount, requestedPage)
                let pageAdvanced = page.page == requestedPage &&
                    !page.items.isEmpty
                hasMore = items.count < total && pageAdvanced
                phase = items.isEmpty ? .empty : .ready
            } catch {
                guard !Task.isCancelled,
                      scopeID == currentScope,
                      pageRequestID == requestID,
                      self.actorID == actorID else {
                    return
                }
                phase = .failed(
                    operation: operation,
                    error: Self.map(error)
                )
            }
        }
    }

    private func reconcileLoadedPages(
        count: Int,
        scope: UUID
    ) async throws {
        var canonicalItems: [CommunityNotification] = []
        var canonicalTotal = 0
        var canonicalUnread = 0
        var lastPageHadItems = false
        for requestedPage in 1...count {
            let page = try await service.notifications(
                page: requestedPage,
                perPage: Self.pageSize
            )
            guard scopeID == scope else { return }
            guard page.page == requestedPage else {
                throw NotificationInboxError.contract(
                    code: "unexpected_reconcile_page"
                )
            }
            canonicalItems = Self.deduplicated(
                canonicalItems + page.items
            )
            canonicalTotal = max(0, page.total)
            canonicalUnread = max(0, page.unreadCount)
            lastPageHadItems = !page.items.isEmpty
        }
        guard scopeID == scope else { return }
        items = canonicalItems
        total = canonicalTotal
        unreadCount = canonicalUnread
        loadedPageCount = count
        hasMore = items.count < total && lastPageHadItems
    }

    private func invalidateScope() {
        scopeID = UUID()
        pageRequestID = UUID()
        operationTask?.cancel()
        operationTask = nil
        for task in mutationTasks.values { task.cancel() }
        mutationTasks = [:]
        mutationTokens = [:]
        mutatingIDs = []
        isMarkingAll = false
        actionFailure = nil
    }

    private func finishMutation(notificationID: String) {
        mutationTokens[notificationID] = nil
        mutationTasks[notificationID] = nil
        mutatingIDs.remove(notificationID)
    }

    private static func normalized(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func deduplicated(
        _ values: [CommunityNotification]
    ) -> [CommunityNotification] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func map(_ error: Error) -> NotificationInboxError {
        (error as? NotificationInboxError)
            ?? .transport(code: "notification_request_failed")
    }
}
