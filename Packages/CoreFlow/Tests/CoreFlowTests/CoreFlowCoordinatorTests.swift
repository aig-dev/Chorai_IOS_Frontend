import XCTest
@testable import CoreFlow

final class CoreFlowCoordinatorTests: XCTestCase {
    @MainActor
    func testSidebarSelectionIsRetainedUntilTheLibraryCanMount() throws {
        let coordinator = CoreFlowCoordinator()
        XCTAssertNil(coordinator.librarySelectionRequest)

        coordinator.openLibrary(scope: .collect)

        let request = try XCTUnwrap(coordinator.librarySelectionRequest)
        XCTAssertEqual(request.scope, .collect)
        XCTAssertEqual(coordinator.selectedTab, .library)
        // A Home view created after the tab switch reads the same durable intent.
        coordinator.selectedTab = .flow
        coordinator.selectedTab = .library
        XCTAssertEqual(coordinator.librarySelectionRequest, request)
    }

    @MainActor
    func testRepeatedSidebarRequestsHaveDistinctIDsEvenForTheSameScope() throws {
        let coordinator = CoreFlowCoordinator()
        coordinator.openLibrary(scope: .collect)
        let first = try XCTUnwrap(coordinator.librarySelectionRequest)

        coordinator.openLibrary(scope: .collect)
        let repeated = try XCTUnwrap(coordinator.librarySelectionRequest)
        XCTAssertNotEqual(first.id, repeated.id)
        XCTAssertEqual(repeated.scope, .collect)

        coordinator.openLibrary(scope: .notes)
        XCTAssertEqual(coordinator.librarySelectionRequest?.scope, .notes)
        XCTAssertEqual(coordinator.selectedTab, .library)
    }

    @MainActor
    func testLibraryNoteCreationRefreshesLibrary() {
        let coordinator = CoreFlowCoordinator()
        let previousRefreshID = coordinator.libraryRefreshID

        coordinator.noteCreated()

        XCTAssertNotEqual(coordinator.libraryRefreshID, previousRefreshID)
    }

    @MainActor
    func testMergeCompletionRefreshesLibraryAndPublishesMergedCard() {
        let coordinator = CoreFlowCoordinator()
        let previousRefreshID = coordinator.libraryRefreshID

        coordinator.mergeCompleted(cardID: "card_merged")

        XCTAssertEqual(coordinator.lastMergedCardID, "card_merged")
        XCTAssertNotEqual(coordinator.libraryRefreshID, previousRefreshID)
    }
}
