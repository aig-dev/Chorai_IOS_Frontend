import XCTest
@testable import CoreFlow

final class CoreFlowCoordinatorTests: XCTestCase {
    @MainActor
    func testMergeCompletionRefreshesLibrary() {
        let coordinator = CoreFlowCoordinator()
        let previousRefreshID = coordinator.libraryRefreshID

        coordinator.mergeCompleted(cardID: "card_merged")

        XCTAssertEqual(coordinator.lastCreatedCardID, "card_merged")
        XCTAssertNotEqual(coordinator.libraryRefreshID, previousRefreshID)
    }
}
