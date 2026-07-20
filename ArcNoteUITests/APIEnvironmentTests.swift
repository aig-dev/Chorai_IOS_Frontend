import XCTest

final class APIEnvironmentTests: XCTestCase {
    private let expectedLocal = ["http://", "127.0.0.1:8180"].joined()
    private let expectedProduction = ["https://", "api.chorai.top"].joined()

    func testCatalogMapsStableEnvironmentNamesToCanonicalURLs() {
        XCTAssertEqual(APIEnvironment.local.rawValue, "local")
        XCTAssertEqual(APIEnvironment.production.rawValue, "production")
        XCTAssertEqual(APIEnvironment.local.baseURL.absoluteString, expectedLocal)
        XCTAssertEqual(
            APIEnvironment.production.baseURL.absoluteString,
            expectedProduction
        )
    }

    func testCatalogRejectsUnknownEnvironmentNames() {
        XCTAssertNil(APIEnvironment(rawValue: "staging"))
        XCTAssertNil(APIEnvironment(rawValue: ""))
    }

    func testOverrideNormalizationRemovesOnlyATrailingRootSlash() {
        XCTAssertEqual(
            APIEnvironment.normalizedBaseURL(from: expectedLocal + "/")?
                .absoluteString,
            expectedLocal
        )
        XCTAssertEqual(
            APIEnvironment.normalizedBaseURL(from: "  \(expectedProduction)  ")?
                .absoluteString,
            expectedProduction
        )
    }

    func testOverrideNormalizationRejectsUnsafeOrAmbiguousValues() {
        XCTAssertNil(APIEnvironment.normalizedBaseURL(from: ""))
        XCTAssertNil(APIEnvironment.normalizedBaseURL(from: "ftp://127.0.0.1:8180"))
        XCTAssertNil(
            APIEnvironment.normalizedBaseURL(
                from: expectedProduction + "/unexpected-path"
            )
        )
        XCTAssertNil(
            APIEnvironment.normalizedBaseURL(from: expectedProduction + "?debug=1")
        )
        XCTAssertNil(
            APIEnvironment.normalizedBaseURL(from: "https://user:secret@api.chorai.top")
        )
    }
}
