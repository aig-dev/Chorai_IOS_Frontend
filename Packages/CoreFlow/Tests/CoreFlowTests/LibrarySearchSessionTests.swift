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
}
