import Foundation
import XCTest

final class LibraryInlineSearchSourceContractTests: XCTestCase {
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
            home.components(separatedBy: ".frame(minWidth: 44, minHeight: 44)").count - 1,
            4
        )

        let header = try section(
            named: "private var librarySearchHeader: some View",
            endingAt: "private var librarySearchInputBackground",
            in: home
        )
        let textFieldIndex = try XCTUnwrap(header.range(of: "TextField("))
        let filterIndex = try XCTUnwrap(
            header.range(of: #"Image("filter")"#)
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
        XCTAssertTrue(search.contains("requestID == self.activeRequestID"))
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
