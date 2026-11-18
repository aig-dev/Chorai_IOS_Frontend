import XCTest
@testable import CoreFlow

final class LibrarySearchSessionTests: XCTestCase {
    func testEnteringSearchLocksTheCurrentLibraryScope() {
        var session = LibrarySearchSession()

        session.enter(scope: .collect)

        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.scope, .collect)
        XCTAssertEqual(session.draftQuery, "")
        XCTAssertNil(session.submittedQuery)
        XCTAssertEqual(session.scope?.apiSearchType, "favorited")
    }

    func testSubmitTrimsDraftAndCreatesTheFirstResultQuery() {
        var session = LibrarySearchSession()
        session.enter(scope: .notes)
        session.updateDraft("  design systems  ")

        let query = session.submit()

        XCTAssertEqual(query, "design systems")
        XCTAssertEqual(session.submittedQuery, "design systems")
        XCTAssertEqual(session.scope?.apiSearchType, "own")
    }

    func testEditingAfterSubmitDoesNotReplaceDisplayedResultQuery() {
        var session = LibrarySearchSession()
        session.enter(scope: .notes)
        session.updateDraft("design")
        _ = session.submit()

        session.updateDraft("design research")

        XCTAssertEqual(session.draftQuery, "design research")
        XCTAssertEqual(session.submittedQuery, "design")
    }

    func testEmptyDraftClearsSubmissionWithoutLeavingSearchMode() {
        var session = LibrarySearchSession()
        session.enter(scope: .collect)
        session.updateDraft("favorite")
        _ = session.submit()

        session.updateDraft("   ")

        XCTAssertTrue(session.isActive)
        XCTAssertNil(session.submittedQuery)
        XCTAssertEqual(session.scope, .collect)
    }

    func testExitResetsAllTransientSearchState() {
        var session = LibrarySearchSession()
        session.enter(scope: .notes)
        session.updateDraft("design")
        _ = session.submit()

        session.exit()

        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.scope)
        XCTAssertEqual(session.draftQuery, "")
        XCTAssertNil(session.submittedQuery)
    }

    func testLibrarySortOptionsKeepTheExistingFilterContract() {
        XCTAssertEqual(
            LibrarySortOption.latestEdited.descriptor,
            LibrarySortDescriptor(field: .updatedAt, order: .descending)
        )
        XCTAssertEqual(
            LibrarySortOption.latestAdded.descriptor,
            LibrarySortDescriptor(field: .createdAt, order: .descending)
        )
        XCTAssertEqual(
            LibrarySortOption.rarityHighLow.descriptor,
            LibrarySortDescriptor(field: .rate, order: .descending)
        )
        XCTAssertEqual(
            LibrarySortOption.rarityLowHigh.descriptor,
            LibrarySortDescriptor(field: .rate, order: .ascending)
        )
    }

    func testDateSortReusesParsedKeys() {
        let parse = LibrarySearchSortKey.makeDateParser()
        var dateConversions = 0
        let rows = [
            ("b", 5, "2026-11-18T09:00:00+08:00", "2026-11-18T01:00:00.123Z"),
            ("a", 1, "2026-11-18T01:00:00Z", "2026-11-18T09:00:00.123+08:00"),
            ("c", 5, "2026-11-18T00:00:00.456Z", "2026-11-18T01:01:00Z"),
            ("d", 3, "invalid", ""),
        ]
        let keys = rows.map { id, rate, createdAt, updatedAt in
            LibrarySearchSortKey(id: id, rate: rate, createdAt: createdAt, updatedAt: updatedAt) { value in
                dateConversions += 1
                return parse(value)
            }
        }

        for (option, expected): (LibrarySortOption, [String]) in [
            (.latestEdited, ["c", "a", "b", "d"]),
            (.latestAdded, ["a", "b", "c", "d"]),
            (.rarityHighLow, ["b", "c", "d", "a"]),
            (.rarityLowHigh, ["a", "d", "b", "c"]),
            (.latestEdited, ["c", "a", "b", "d"]),
        ] {
            XCTAssertEqual(keys.sorted { $0.precedes($1, by: option.descriptor) }.map(\.id), expected)
        }
        XCTAssertEqual(keys[0].updatedAt, keys[1].updatedAt)
        XCTAssertNotNil(keys[0].updatedAt)
        XCTAssertNil(keys[3].updatedAt)
        XCTAssertEqual(dateConversions, 2 * rows.count)
    }

    func testPendingResultsUseTheLatestSortAndOnlyTheCurrentRequest() {
        var request = LibrarySearchRequest()
        let first = request.begin(sort: .latestEdited)
        request.selectSort(.rarityHighLow)
        XCTAssertEqual(request.sort(for: first), .rarityHighLow)

        let second = request.begin(sort: .latestAdded)
        XCTAssertNil(request.sort(for: first))
        XCTAssertEqual(request.sort(for: second), .latestAdded)

        request.clear()
        XCTAssertNil(request.sort(for: second))
    }
}
