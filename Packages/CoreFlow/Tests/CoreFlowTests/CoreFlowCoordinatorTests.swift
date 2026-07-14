import XCTest
@testable import CoreFlow

final class CoreFlowCoordinatorTests: XCTestCase {
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
