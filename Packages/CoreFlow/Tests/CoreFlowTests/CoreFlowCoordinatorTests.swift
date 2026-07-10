import XCTest
@testable import CoreFlow

final class CoreFlowCoordinatorTests: XCTestCase {
    @MainActor
    func testMergeCompletionRefreshesLibraryWithoutRecordAcknowledgement() {
        let coordinator = CoreFlowCoordinator()
        let previousRefreshID = coordinator.libraryRefreshID

        coordinator.mergeCompleted(cardID: "card_merged")

        XCTAssertEqual(coordinator.lastCreatedCardID, "card_merged")
        XCTAssertNil(coordinator.recordAcknowledgementID)
        XCTAssertNotEqual(coordinator.libraryRefreshID, previousRefreshID)
    }

    @MainActor
    func testCaptureCompletionRefreshesLibraryAndDismissesSheet() {
        let coordinator = CoreFlowCoordinator()
        let previousRefreshID = coordinator.libraryRefreshID
        coordinator.presentCapture()

        coordinator.captureCompleted(
            CreatedCard(id: "card_1", content: "New", isPublic: false)
        )

        XCTAssertFalse(coordinator.isCapturePresented)
        XCTAssertEqual(coordinator.lastCreatedCardID, "card_1")
        XCTAssertEqual(coordinator.recordAcknowledgementID, "card_1")
        XCTAssertNotEqual(coordinator.libraryRefreshID, previousRefreshID)

        coordinator.clearRecordAcknowledgement(cardID: "stale_card")
        XCTAssertEqual(coordinator.recordAcknowledgementID, "card_1")

        coordinator.clearRecordAcknowledgement(cardID: "card_1")
        XCTAssertNil(coordinator.recordAcknowledgementID)
        XCTAssertEqual(coordinator.lastCreatedCardID, "card_1")
    }
}
