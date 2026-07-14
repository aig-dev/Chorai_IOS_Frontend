import XCTest
@testable import CoreFlow

final class ChoraiWebDestinationTests: XCTestCase {
    func testReportUsesReachableCanonicalHost() {
        XCTAssertEqual(
            ChoraiWebDestination.report.absoluteString,
            "https://chorai.app/report"
        )
        XCTAssertEqual(ChoraiWebDestination.report.host, "chorai.app")
    }
}
