import Combine
import CoreFlow
import SwiftUI

struct LibrarySearchCard: Identifiable {
    let source: UserAllCard
    let card: UserCard

    init(source: UserAllCard) {
        self.source = source
        card = source.libraryUserCard
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
    private var activeRequestID: UUID?
    private let searchRequest: SearchRequest

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

        let requestID = UUID()
        activeRequestID = requestID
        rawResults = []
        results = []
        error = nil
        isLoading = true

        requestCancellable = searchRequest(query, scope)
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                guard let self,
                      requestID == self.activeRequestID else {
                    return
                }
                self.isLoading = false
                if case let .failure(error) = completion {
                    self.error = error
                }
            },
            receiveValue: { [weak self] cards in
                guard let self,
                      requestID == self.activeRequestID else {
                    return
                }

                self.rawResults = cards.map(LibrarySearchCard.init(source:))
                self.applySort(sort)
            }
        )
    }

    func applySort(_ sort: LibrarySortOption) {
        results = rawResults.sorted { lhs, rhs in
            Self.precedes(lhs, rhs, descriptor: sort.descriptor)
        }
    }

    func clear() {
        requestCancellable?.cancel()
        requestCancellable = nil
        activeRequestID = nil
        rawResults = []
        results = []
        error = nil
        isLoading = false
    }

    func remove(cardID: String) {
        rawResults.removeAll { $0.id == cardID }
        results.removeAll { $0.id == cardID }
    }

    private static func precedes(
        _ lhs: LibrarySearchCard,
        _ rhs: LibrarySearchCard,
        descriptor: LibrarySortDescriptor
    ) -> Bool {
        let comparison: ComparisonResult

        switch descriptor.field {
        case .updatedAt:
            comparison = compareDates(lhs.card.updatedAt, rhs.card.updatedAt)
        case .createdAt:
            comparison = compareDates(lhs.card.createdAt, rhs.card.createdAt)
        case .rate:
            comparison = compareInts(lhs.card.rate, rhs.card.rate)
        }

        if comparison == .orderedSame {
            return lhs.id < rhs.id
        }
        switch descriptor.order {
        case .ascending:
            return comparison == .orderedAscending
        case .descending:
            return comparison == .orderedDescending
        }
    }

    private static func compareInts(_ lhs: Int, _ rhs: Int) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private static func compareDates(
        _ lhs: String,
        _ rhs: String
    ) -> ComparisonResult {
        let lhsDate = parseDate(lhs) ?? .distantPast
        let rhsDate = parseDate(rhs) ?? .distantPast
        return lhsDate.compare(rhsDate)
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))

            Text("for “\(query)”")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.56))
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
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.64))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 96)
        .accessibilityLabel("Searching your Library")
    }

    private func errorState(_ error: NetworkError) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.white.opacity(0.62))

            Text("Search couldn’t be completed")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)

            Text(error.localizedDescription)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.58))
                .multilineTextAlignment(.center)

            Button("Try Again", action: onRetry)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(minWidth: 120, minHeight: 44)
                .background(
                    Capsule().fill(Color.white.opacity(0.14))
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
                .foregroundStyle(Color.white.opacity(0.52))

            Text("No Library results")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))

            Text("Try another title or phrase.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.54))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 96)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func resultCard(_ result: LibrarySearchCard) -> some View {
        switch scope {
        case .notes:
            if result.card.rate < 3 {
                NotesCard(
                    card: result.card,
                    onShowMenu: { _ in onShowMenu(result) },
                    cardsManager: cardsManager,
                    onCardTap: onCardTap
                )
            } else {
                NotesColorCard(
                    card: result.card,
                    onShowMenu: { _ in onShowMenu(result) },
                    cardsManager: cardsManager,
                    onCardTap: onCardTap
                )
            }

        case .collect:
            HomePostCard(
                profileImage: result.author?.avatar ?? "",
                name: result.author?.username ?? "Unknown author",
                time: relativeTime(result.card.updatedAt),
                content: result.card.content,
                contentJSON: result.card.contentJSON,
                backgroundMediaRef: result.card.backgroundMediaRef,
                tags: result.card.tags,
                showSpark: true,
                favoriteCount: result.card.favoriteCount ?? 0,
                cardId: result.card.id,
                rate: result.card.rate,
                authorId: result.author?.id,
                onShowMenu: { _ in onShowMenu(result) },
                onCardTap: onCardTap,
                onUnfavorite: onUnfavorite,
                onAvatarTap: onAvatarTap
            )
        }
    }

    private func relativeTime(_ value: String) -> String {
        guard let date = Self.parseDate(value) else {
            return "Recently updated"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}
