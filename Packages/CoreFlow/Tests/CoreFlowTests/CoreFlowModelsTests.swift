import XCTest
@testable import CoreFlow

final class CoreFlowModelsTests: XCTestCase {
    func testSwipeResolverUsesTranslationAndPredictionThresholds() {
        XCTAssertEqual(
            FlowSwipeResolver.resolve(translation: -90, predictedEndTranslation: -100),
            .advanceLeft
        )
        XCTAssertEqual(
            FlowSwipeResolver.resolve(translation: 30, predictedEndTranslation: 140),
            .advanceRight
        )
        XCTAssertEqual(
            FlowSwipeResolver.resolve(translation: 40, predictedEndTranslation: 80),
            .cancel
        )
    }

    func testFlowPageCarriesCanonicalRefreshToken() {
        let page = FlowPage(cards: [], nextRefreshToken: "refresh-2")

        XCTAssertEqual(page.nextRefreshToken, "refresh-2")
    }
}
