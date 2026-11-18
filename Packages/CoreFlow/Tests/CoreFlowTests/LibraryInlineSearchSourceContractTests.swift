import Foundation
import XCTest

final class LibraryInlineSearchSourceContractTests: XCTestCase {
    func testLibrarySearchPreparesNativeMenusWithoutOpeningTheLegacyOverlay() throws {
        let home = try source(at: "ArcNote/HomeView.swift")
        let start = try XCTUnwrap(home.range(of: "onShowMenu: { result in"))
        let end = try XCTUnwrap(home.range(of: "onCardTap:", range: start.upperBound..<home.endIndex))
        let preparation = String(home[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(preparation.contains("currentCardId = result.id"))
        XCTAssertTrue(preparation.contains("currentMenuCardData = result.card"))
        XCTAssertFalse(preparation.contains("showPopupMenu ="), "Both library result cards now open their native Menu directly")
    }

    func testLibraryOwnsInlineHeaderSearchInsteadOfNavigation() throws {
        let home = try source(at: "ArcNote/HomeView.swift")

        XCTAssertTrue(
            home.contains(
                "@State private var librarySearchSession = LibrarySearchSession()"
            )
        )
        XCTAssertFalse(home.contains("NavigationLink(destination: SearchView())"))
        XCTAssertTrue(home.contains("private var librarySearchHeader: some View"))
        XCTAssertTrue(home.contains("TextField("))
        XCTAssertTrue(home.contains(".submitLabel(.search)"))
        XCTAssertTrue(home.contains("submitLibrarySearch()"))
        XCTAssertTrue(home.contains(".focused($isLibrarySearchFocused)"))
        XCTAssertTrue(home.contains("@Environment(\\.accessibilityReduceMotion)"))
    }

    func testInlineFieldKeepsSearchControlsAccessibleAndFilterTrailing() throws {
        let home = try source(at: "ArcNote/HomeView.swift")

        XCTAssertTrue(home.contains(#".accessibilityIdentifier("home.search.input")"#))
        XCTAssertTrue(home.contains(#".accessibilityIdentifier("home.search.close")"#))
        XCTAssertTrue(home.contains(#".accessibilityIdentifier("home.search.clear")"#))
        XCTAssertTrue(home.contains(#".accessibilityIdentifier("home.search.filter")"#))
        XCTAssertTrue(home.contains(#".accessibilityIdentifier("home.filter")"#))
        XCTAssertTrue(home.contains(#".accessibilityIdentifier("home.search")"#))
        XCTAssertGreaterThanOrEqual(
            home.components(separatedBy: ".frame(minWidth: 44, minHeight: 52)").count - 1,
            4
        )

        let header = try section(
            named: "private var librarySearchHeader: some View",
            endingAt: "private var librarySearchInputBackground",
            in: home
        )
        let textFieldIndex = try XCTUnwrap(header.range(of: "TextField("))
        let filterIndex = try XCTUnwrap(
            header.range(of: #"Image(systemName: "line.3.horizontal.decrease")"#)
        )
        XCTAssertLessThan(textFieldIndex.lowerBound, filterIndex.lowerBound)
    }

    func testSearchRunsOnlyFromSubmittedLibraryScope() throws {
        let home = try source(at: "ArcNote/HomeView.swift")
        let search = try source(at: "ArcNote/SearchView.swift")

        XCTAssertTrue(home.contains("librarySearchSession.submit()"))
        XCTAssertTrue(home.contains("librarySearchSession.submittedQuery != nil"))
        XCTAssertTrue(search.contains("final class LibrarySearchManager"))
        XCTAssertTrue(search.contains("getUserAllCards("))
        XCTAssertTrue(search.contains("searchType: scope.apiSearchType"))
        XCTAssertTrue(search.contains("limit: 200"))
        XCTAssertTrue(search.contains("let sort = self.request.sort(for: requestID)"))
    }

    func testReturningAndRefreshingLibraryPreserveTheSelectedSort() throws {
        let home = try source(at: "ArcNote/HomeView.swift")
        let reload = try section(
            named: "private func loadUserCards()",
            endingAt: "private func presentCommittedCardIfNeeded",
            in: home
        )
        XCTAssertTrue(reload.contains("selectedSortOption.descriptor"))
        XCTAssertTrue(reload.contains("sortBy: descriptor.field.apiName"))
        XCTAssertTrue(reload.contains("sortOrder: descriptor.order.apiName"))
        XCTAssertFalse(reload.contains(#""updated_at""#),
                       "A reload must not silently replace the menu's selected order with Latest edited")

        for (start, end) in [
            (".onAppear {", ".onDisappear {"),
            (".onChange(of: refreshID)", ".onChange(of: committedCardID)")
        ] {
            let transition = try section(named: start, endingAt: end, in: home)
            XCTAssertTrue(transition.contains("loadUserCards()"),
                          "Returning and refresh events must reload with the current selection")
            XCTAssertFalse(transition.contains("selectedFilter ="))
            XCTAssertFalse(transition.contains("submitLibrarySearch()"),
                           "A list reload must not submit or replace a pending search draft")
        }
    }

    func testStandaloneSearchFiltersAndExploreSearchAreRetired() throws {
        let search = try source(at: "ArcNote/SearchView.swift")

        XCTAssertFalse(search.contains("SearchManager.shared"))
        XCTAssertFalse(search.contains("selectedCollection"))
        XCTAssertFalse(search.contains("selectedLabel"))
        XCTAssertFalse(search.contains("selectedTime"))
        XCTAssertFalse(search.contains("My Collection"))
        XCTAssertFalse(search.contains(#"Text("Label")"#))
        XCTAssertFalse(search.contains(#"Text("Time")"#))
    }

    func testResultsReuseBothSharedLibraryCardPresentations() throws {
        let search = try source(at: "ArcNote/SearchView.swift")
        let models = try source(at: "ArcNote/Models/UserAllCardsModels.swift")

        XCTAssertTrue(search.contains("struct LibrarySearchResultsView: View"))
        XCTAssertTrue(search.contains("NotesCard("))
        XCTAssertFalse(search.contains("NotesColorCard("))
        XCTAssertTrue(search.contains("HomePostCard("))
        XCTAssertTrue(search.contains(#".accessibilityIdentifier("home.search.results")"#))
        XCTAssertTrue(models.contains("let contentJSON: String?"))
        XCTAssertTrue(models.contains("let backgroundMediaRef: String?"))
        XCTAssertTrue(models.contains("var libraryUserCard: UserCard"))
        XCTAssertTrue(models.contains("backgroundMediaRef: backgroundMediaRef"))
    }

    func testResultSummaryUsesSingularGrammarForOneMatch() throws {
        let search = try source(at: "ArcNote/SearchView.swift")

        XCTAssertTrue(
            search.contains(
                "manager.results.count == 1 ? \"1 result\" : \"\\(manager.results.count) results\""
            )
        )
    }

    func testSearchResultMenuActionsWorkOutsideTheLoadedLibraryPage() throws {
        let home = try source(at: "ArcNote/HomeView.swift")
        let manager = try source(at: "ArcNote/HomeCardsManager.swift")

        XCTAssertTrue(manager.contains("fallbackCard: UserCard? = nil"))
        XCTAssertTrue(manager.contains("?? matchingFallbackCard"))
        XCTAssertTrue(home.contains("fallbackCard: currentMenuCardData"))
        XCTAssertTrue(home.contains("if librarySearchSession.isActive"))
        XCTAssertTrue(home.contains("retryLibrarySearch()"))
    }

    private func section(
        named startMarker: String,
        endingAt endMarker: String,
        in source: String
    ) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker))
        let end = try XCTUnwrap(
            source.range(
                of: endMarker,
                range: start.upperBound..<source.endIndex
            )
        )
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
