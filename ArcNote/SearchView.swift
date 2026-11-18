import Combine
import CoreFlow
import SwiftUI

struct LibrarySearchCard: Identifiable {
    let source: UserAllCard
    let card: UserCard
    let sortKey: LibrarySearchSortKey

    init(source: UserAllCard, parseDate: (String) -> Date?) {
        self.source = source
        card = source.libraryUserCard
        sortKey = LibrarySearchSortKey(
            id: source.id, rate: source.rate,
            createdAt: source.createdAt, updatedAt: source.updatedAt,
            parseDate: parseDate
        )
    }

    var id: String { card.id }
    var author: UserAllCardAuthor? { source.author }
}

final class LibrarySearchManager: ObservableObject {
    typealias SearchRequest = (
        _ query: String,
        _ scope: LibrarySearchScope
    ) -> AnyPublisher<[UserAllCard], NetworkError>

    @Published private(set) var results: [LibrarySearchCard] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: NetworkError?

    private var rawResults: [LibrarySearchCard] = []
    private var requestCancellable: AnyCancellable?
    private var request = LibrarySearchRequest()
    private let searchRequest: SearchRequest
    private static let preparationQueue = DispatchQueue(label: "chorai.library-search.prepare", qos: .userInitiated)

    init(searchRequest: SearchRequest? = nil) {
        self.searchRequest = searchRequest ?? { query, scope in
            NetworkManager.shared.getUserAllCards(
                searchType: scope.apiSearchType,
                search: query,
                limit: 200
            )
            .map { response in
                switch scope {
                case .notes:
                    response.data.ownCards
                case .collect:
                    response.data.favoritedCards
                }
            }
            .eraseToAnyPublisher()
        }
    }

    func search(
        query: String,
        scope: LibrarySearchScope,
        sort: LibrarySortOption
    ) {
        requestCancellable?.cancel()

        let requestID = request.begin(sort: sort)
        rawResults = []
        results = []
        error = nil
        isLoading = true

        requestCancellable = searchRequest(query, scope)
        .receive(on: Self.preparationQueue)
        .map { cards in
            let parseDate = LibrarySearchSortKey.makeDateParser()
            return cards.map { LibrarySearchCard(source: $0, parseDate: parseDate) }
        }
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                guard let self,
                      self.request.sort(for: requestID) != nil else {
                    return
                }
                self.isLoading = false
                if case let .failure(error) = completion {
                    self.error = error
                }
            },
            receiveValue: { [weak self] cards in
                guard let self,
                      let sort = self.request.sort(for: requestID) else {
                    return
                }

                self.rawResults = cards
                self.applySort(sort)
            }
        )
    }

    func applySort(_ sort: LibrarySortOption) {
        request.selectSort(sort)
        let descriptor = sort.descriptor
        results = rawResults.sorted { lhs, rhs in
            lhs.sortKey.precedes(rhs.sortKey, by: descriptor)
        }
    }

    func clear() {
        requestCancellable?.cancel()
        requestCancellable = nil
        request.clear()
        rawResults = []
        results = []
        error = nil
        isLoading = false
    }

    func remove(cardID: String) {
        rawResults.removeAll { $0.id == cardID }
        results.removeAll { $0.id == cardID }
    }
}

struct LibrarySearchResultsView: View {
    let scope: LibrarySearchScope
    @ObservedObject var manager: LibrarySearchManager
    @ObservedObject var cardsManager: HomeCardsManager
    let query: String
    let onShowMenu: (LibrarySearchCard) -> Void
    let onCardTap: (String) -> Void
    let onAvatarTap: (String) -> Void
    let onUnfavorite: (String) -> Void
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                resultSummary

                if manager.isLoading && manager.results.isEmpty {
                    loadingState
                } else if let error = manager.error,
                          manager.results.isEmpty {
                    errorState(error)
                } else if manager.results.isEmpty {
                    emptyState
                } else {
                    ForEach(manager.results) { result in
                        resultCard(result)
                    }
                }
            }
            .adaptiveContentGutter()
            .padding(.top, 20)
            .padding(.bottom, 120)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.search.results")
    }

    private var resultSummary: some View {
        HStack(spacing: 8) {
            Text(manager.isLoading ? "Searching…" : resultCountLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ChoraiTheme.ink)

            Text("for “\(query)”")
                .font(.subheadline.weight(.regular))
                .foregroundStyle(ChoraiTheme.secondaryInk)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var resultCountLabel: String {
        manager.results.count == 1 ? "1 result" : "\(manager.results.count) results"
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            RotatingLoaderView()
            Text("Searching your Library")
                .font(.subheadline.weight(.regular))
                .foregroundStyle(ChoraiTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 96)
        .accessibilityLabel("Searching your Library")
    }

    private func errorState(_ error: NetworkError) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(ChoraiTheme.secondaryInk)

            Text("Search couldn’t be completed")
                .font(.body.weight(.semibold))
                .foregroundStyle(ChoraiTheme.ink)

            Text(error.localizedDescription)
                .font(.footnote.weight(.regular))
                .foregroundStyle(ChoraiTheme.secondaryInk)
                .multilineTextAlignment(.center)

            Button("Try Again", action: onRetry)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ChoraiTheme.ink)
                .frame(minWidth: 120, minHeight: 44)
                .background(
                    Capsule().fill(ChoraiTheme.surface)
                )
                .accessibilityIdentifier("home.search.retry")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(ChoraiTheme.secondaryInk)

            Text("No Library results")
                .font(.body.weight(.semibold))
                .foregroundStyle(ChoraiTheme.ink)

            Text("Try another title or phrase.")
                .font(.subheadline.weight(.regular))
                .foregroundStyle(ChoraiTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 96)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func resultCard(_ result: LibrarySearchCard) -> some View {
        switch scope {
        case .notes:
            NotesCard(
                card: result.card,
                onShowMenu: { _ in onShowMenu(result) },
                cardsManager: cardsManager,
                onCardTap: onCardTap
            )

        case .collect:
            HomePostCard(
                profileImage: result.author?.avatar ?? "",
                name: result.author?.username ?? "Unknown author",
                time: relativeTime(result.sortKey.updatedAt),
                content: result.card.content,
                contentJSON: result.card.contentJSON,
                backgroundMediaRef: result.card.backgroundMediaRef,
                tags: result.card.tags,
                showSpark: true,
                favoriteCount: result.card.favoriteCount ?? 0,
                cardId: result.card.id,
                rate: result.card.rate,
                authorId: result.author?.id,
                menuCardData: result.card,
                onShowMenu: { _ in onShowMenu(result) },
                onCardTap: onCardTap,
                onUnfavorite: onUnfavorite,
                onAvatarTap: onAvatarTap
            )
        }
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date else {
            return "Recently updated"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
