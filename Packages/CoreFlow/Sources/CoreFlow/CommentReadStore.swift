import Combine
import Foundation

public enum CommentPageResult {
    case page([CommentModel], total: Int)
    case failed
    case accessLost
}

public enum CommentReadPhase: Equatable {
    case idle, loading, refreshing, loadingMore, ready
    case failed(page: Int)
}

@MainActor
public final class CommentReadStore: ObservableObject {
    public typealias FetchPage = @MainActor (String, Int, Int, @escaping (CommentPageResult) -> Void) -> Void

    @Published public private(set) var cardID: String?
    @Published public private(set) var comments: [CommentModel] = []
    @Published public private(set) var phase = CommentReadPhase.idle
    public private(set) var hasFirstPage = false
    public var loadedCommentCount: Int { flatComments.count }
    public var canLoadMore: Bool { phase == .ready && nextPage != nil }

    public func comment(withID id: String) -> CommentModel? {
        flatComments.first { $0.id == id }
    }

    private struct FirstPage {
        var rows: [CommentModel]
        var total: Int
    }

    private let recent = RecentCardReads<FirstPage>()
    private let session: () -> UInt64?
    private let fetch: FetchPage
    private let pageSize = 20
    private var flatComments: [CommentModel] = [] {
        didSet { comments = CommentModel.assembleThreads(from: flatComments) }
    }
    private var total = 0
    private var nextPage: Int?
    private var readSession: UInt64?
    private var requestID = UUID()
    private var subscriptions = Set<AnyCancellable>()

    public init(session: @escaping () -> UInt64?, fetch: @escaping FetchPage) {
        self.session = session
        self.fetch = fetch
        let center = NotificationCenter.default
        center.publisher(for: .cardReadSessionDidChange).sink { [weak self] _ in
            self?.close()
        }.store(in: &subscriptions)
        center.publisher(for: .cardReadInvalidated).sink { [weak self] event in
            guard let self, let id = event.object as? String, cardID == id else { return }
            close()
        }.store(in: &subscriptions)
    }

    public func open(_ id: String) {
        guard let currentSession = session() else {
            close()
            return
        }
        if let readSession, readSession != currentSession { recent.removeAll() }
        readSession = currentSession
        cardID = id
        let saved = recent.value(for: id)
        hasFirstPage = saved != nil
        flatComments = saved?.rows ?? []
        total = saved?.total ?? 0
        nextPage = flatComments.count < total ? 2 : nil
        load(1)
    }

    private func close() {
        // An unopened/already closed store has no active read to invalidate.
        // Avoid publishing an unchanged idle state during session restoration.
        guard cardID != nil else { return }
        requestID = UUID()
        cardID = nil
        hasFirstPage = false
        nextPage = nil
        flatComments = []
        total = 0
        phase = .idle
    }

    public func loadMore() {
        guard canLoadMore, let nextPage else { return }
        load(nextPage)
    }

    public func refresh() { load(1) }

    public func retry() {
        guard case .failed(let page) = phase else { return }
        load(page)
    }

    private func load(_ page: Int) {
        guard let id = cardID, let readSession, readSession == session() else { return }
        let request = UUID()
        requestID = request
        phase = page == 1 ? (hasFirstPage ? .refreshing : .loading) : .loadingMore
        fetch(id, page, pageSize) { [weak self] result in
            guard let self, requestID == request, session() == readSession else { return }
            switch result {
            case .page(let rows, let count):
                guard rows.allSatisfy({ $0.cardId == nil || $0.cardId == id }) else {
                    phase = .failed(page: page)
                    return
                }
                let combined = page == 1 ? rows : flatComments + rows
                var seen = Set<String>()
                flatComments = combined.filter { seen.insert($0.id).inserted }
                if page == 1 {
                    hasFirstPage = true
                }
                total = count
                recent.insert(FirstPage(rows: Array(flatComments.prefix(pageSize)), total: count), for: id)
                nextPage = !rows.isEmpty && flatComments.count < count ? page + 1 : nil
                phase = .ready
            case .failed:
                phase = .failed(page: page)
            case .accessLost:
                NotificationCenter.default.post(name: .cardReadInvalidated, object: id)
            }
        }
    }

    @discardableResult
    public func recordCreated(_ comment: CommentModel, for id: String) -> Int? {
        guard let readSession, readSession == session(),
              comment.cardId == nil || comment.cardId == id else { return nil }
        let alreadyLoaded = cardID == id && flatComments.contains { $0.id == comment.id }
        var cachedCount: Int?
        if var saved = recent.value(for: id) {
            if !alreadyLoaded && !saved.rows.contains(where: { $0.id == comment.id }) {
                // The endpoint pages oldest first. A new row belongs on page one only if it fits.
                if saved.rows.count < pageSize {
                    let position = comment.parentCommentId == nil ? 0 : saved.rows.count
                    saved.rows.insert(comment, at: position)
                }
                saved.total += 1
                recent.insert(saved, for: id)
            }
            cachedCount = saved.total
        }
        guard cardID == id else { return cachedCount }
        guard !alreadyLoaded else { return hasFirstPage ? total : nil }
        requestID = UUID()
        let wasReading = phase == .refreshing || phase == .loading || phase == .loadingMore
        let position = comment.parentCommentId == nil ? 0 : flatComments.count
        flatComments.insert(comment, at: position)
        total += 1
        phase = .ready
        let confirmedCount = hasFirstPage ? total : nil
        if wasReading || !hasFirstPage { refresh() }
        return confirmedCount
    }

    @discardableResult
    public func removeThread(_ commentID: String, for id: String) -> Int? {
        guard let readSession, readSession == session() else { return nil }
        guard cardID == id else {
            recent.remove(id)
            return nil
        }
        var removed: Set<String> = [commentID]
        var previousCount = 0
        while previousCount != removed.count {
            previousCount = removed.count
            for row in flatComments {
                if let parent = row.parentCommentId, removed.contains(parent) { removed.insert(row.id) }
            }
        }
        let remaining = flatComments.filter { !removed.contains($0.id) }
        let removedCount = flatComments.count - remaining.count
        guard removedCount > 0 else { return nil }
        requestID = UUID()
        flatComments = remaining
        total = max(0, total - removedCount)
        if var saved = recent.value(for: id) {
            saved.rows.removeAll { removed.contains($0.id) }
            saved.total = total
            recent.insert(saved, for: id)
        }
        phase = .ready
        return hasFirstPage ? total : nil
    }
}
