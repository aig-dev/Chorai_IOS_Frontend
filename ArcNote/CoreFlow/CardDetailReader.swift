import Combine
import CoreFlow
import Foundation

@MainActor
final class CardDetailReader {
    static let shared = CardDetailReader(
        session: { AuthManager.shared.cardReadSession },
        fetch: { NetworkManager.shared.getCardDetailPublisher(cardId: $0, presentsError: false) }
    )

    struct Scope: Sendable {
        fileprivate let session: UInt64
        fileprivate let revision: UInt64
    }

    private enum Outcome {
        case received(Result<CardDetail, NetworkError>, Scope)
        case cancelled
    }

    private final class Read {
        let scope: Scope
        let outcome = CurrentValueSubject<Outcome?, Never>(nil)
        var transport: AnyCancellable?
        var like: CardLikeState?
        var favorite: CardFavoriteState?

        init(scope: Scope) { self.scope = scope }

        func cancel() {
            transport?.cancel()
            outcome.send(.cancelled)
        }
    }

    private let session: () -> UInt64?
    private let fetch: (String) -> AnyPublisher<CardDetailResponse, NetworkError>
    private let recent = RecentCardReads<CardDetail>()
    private var snapshotSession: UInt64?
    private var reads: [String: Read] = [:]
    private var revision: UInt64 = 0
    private var sessionInvalidatedAt: UInt64 = 0
    private var cardInvalidatedAt: [String: UInt64] = [:]
    private var subscriptions = Set<AnyCancellable>()

    init(
        session: @escaping () -> UInt64?,
        fetch: @escaping (String) -> AnyPublisher<CardDetailResponse, NetworkError>
    ) {
        self.session = session
        self.fetch = fetch
        let center = NotificationCenter.default
        center.publisher(for: .cardReadSessionDidChange).sink { [weak self] _ in
            self?.invalidateSession()
        }.store(in: &subscriptions)
        center.publisher(for: .cardReadInvalidated).sink { [weak self] event in
            guard let id = event.object as? String else { return }
            self?.recent.remove(id)
            self?.retireRead(for: id)
        }.store(in: &subscriptions)
    }

    func cached(cardID: String) -> CardDetail? {
        guard let active = session(), snapshotSession == active else { return nil }
        return recent.value(for: cardID)
    }

    func currentScope() throws -> Scope {
        guard let session = session() else { throw NetworkError.unauthorized }
        return Scope(session: session, revision: revision)
    }

    func isCurrent(_ scope: Scope) -> Bool {
        session() == scope.session &&
            sessionInvalidatedAt <= scope.revision
    }

    func isCurrent(_ scope: Scope, cardID: String) -> Bool {
        isCurrent(scope) && (cardInvalidatedAt[cardID] ?? 0) <= scope.revision
    }

    func confirmed(cardID: String, requiringNewRead: Bool = false) async throws -> CardDetail {
        try Task.checkCancellation()
        let scope = try currentScope()
        if requiringNewRead { retireRead(for: cardID) }
        if let pending = reads[cardID], !isCurrent(pending.scope, cardID: cardID) {
            retireRead(for: cardID)
        }
        guard session() == scope.session else { throw NetworkError.unauthorized }
        let read = try reads[cardID] ?? startRead(cardID: cardID, scope: currentScope())
        let outcome = try await NetworkManager.firstValue(read.outcome.compactMap { $0 }.eraseToAnyPublisher())
        try Task.checkCancellation()
        guard case .received(let result, let confirmedScope) = outcome,
              isCurrent(confirmedScope, cardID: cardID) else {
            throw CancellationError()
        }
        let detail = try result.get()
        return cached(cardID: cardID) ?? detail
    }

    func didCommit(_ state: CardLikeState) {
        if let read = reads[state.cardID], isCurrent(read.scope, cardID: state.cardID) { read.like = state }
        if var detail = cached(cardID: state.cardID) {
            detail.applyLike(state)
            recent.insert(detail, for: state.cardID)
        }
    }

    /// Each subscription owns only its waiter. The reader still owns the shared GET.
    func confirmedPublisher(cardID: String) -> AnyPublisher<CardDetail, NetworkError> {
        Deferred { [weak self] in
            let result = PassthroughSubject<CardDetail, NetworkError>()
            let task = Task { @MainActor [weak self] in
                do {
                    guard let self else { throw NetworkError.unauthorized }
                    let detail = try await self.confirmed(cardID: cardID)
                    try Task.checkCancellation()
                    result.send(detail)
                    result.send(completion: .finished)
                } catch {
                    guard !Task.isCancelled else { return }
                    result.send(completion: .failure(error as? NetworkError ?? .networkError(error)))
                }
            }
            return result.handleEvents(receiveCancel: { task.cancel() }).eraseToAnyPublisher()
        }.eraseToAnyPublisher()
    }

    func referencedNote(cardID: String) -> AnyPublisher<NoteCard, NetworkError> {
        confirmedPublisher(cardID: cardID).map { card in
            NoteCard(id: card.id, title: (card.title?.isEmpty ?? true) ? "Untitled" : (card.title ?? ""),
                     description: card.content, isPublic: card.isPublic,
                     username: card.author?.userName ?? "Unknown", avatarUrl: card.author?.avatarUrl)
        }.eraseToAnyPublisher()
    }

    func didCommit(_ state: CardFavoriteState) {
        if let read = reads[state.cardID], isCurrent(read.scope, cardID: state.cardID) { read.favorite = state }
        if var detail = cached(cardID: state.cardID) {
            detail.applyFavorite(state)
            recent.insert(detail, for: state.cardID)
        }
    }

    private func startRead(cardID: String, scope: Scope) -> Read {
        let read = Read(scope: scope)
        reads[cardID] = read
        read.transport = fetch(cardID)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self, weak read] completion in
                guard let read else { return }
                let error: NetworkError
                switch completion {
                case .finished: error = .noData
                case .failure(let underlying): error = underlying
                }
                self?.finish(read, for: cardID, result: .failure(error))
            }, receiveValue: { [weak self, weak read] response in
                guard let read else { return }
                let result: Result<CardDetail, NetworkError> = response.success && response.data.id == cardID
                    ? .success(response.data) : .failure(.decodingError)
                self?.finish(read, for: cardID, result: result)
            })
        return read
    }

    private func finish(_ read: Read, for cardID: String, result: Result<CardDetail, NetworkError>) {
        guard reads[cardID] === read else { return }
        guard isCurrent(read.scope, cardID: cardID) else {
            retireRead(for: cardID)
            return
        }
        reads.removeValue(forKey: cardID)
        switch result {
        case .success(var detail):
            if let state = read.like { detail.applyLike(state) }
            if let state = read.favorite { detail.applyFavorite(state) }
            if snapshotSession != read.scope.session {
                recent.removeAll()
                snapshotSession = read.scope.session
            }
            recent.insert(detail, for: cardID)
            read.outcome.send(.received(.success(detail), read.scope))
        case .failure(let error):
            if error.invalidatesCardRead {
                NotificationCenter.default.post(
                    name: .cardReadInvalidated, object: cardID,
                    userInfo: error.cardReadStatus.map { [CardReadInvalidation.statusKey: $0] }
                )
            }
            if let scope = try? currentScope(), scope.session == read.scope.session {
                read.outcome.send(.received(.failure(error), scope))
            } else {
                read.cancel()
            }
        }
    }

    private func retireRead(for cardID: String) {
        revision &+= 1
        cardInvalidatedAt[cardID] = revision
        reads.removeValue(forKey: cardID)?.cancel()
    }

    private func invalidateSession() {
        revision &+= 1
        sessionInvalidatedAt = revision
        cardInvalidatedAt.removeAll()
        recent.removeAll()
        snapshotSession = nil
        let previousReads = reads.values
        reads.removeAll()
        previousReads.forEach { $0.cancel() }
    }
}
