import XCTest
@testable import CoreFlow

final class CoreFlowCoordinatorTests: XCTestCase {
    @MainActor
    func testMergeCompletionRefreshesLibraryAndPublishesMergedCard() {
        let coordinator = CoreFlowCoordinator()
        let previousRefreshID = coordinator.libraryRefreshID

        coordinator.mergeCompleted(cardID: "card_merged")

        XCTAssertEqual(coordinator.lastMergedCardID, "card_merged")
        XCTAssertNotEqual(coordinator.libraryRefreshID, previousRefreshID)
    }
}
