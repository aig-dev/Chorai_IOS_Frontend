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

    func testSharedResolverPrefersAValidOverride() throws {
        let resolution = try APIBaseURLResolver.resolve(
            processEnvironment: [
                APIEnvironment.overrideEnvironmentKey: expectedProduction,
            ],
            compiledEnvironment: APIEnvironment.local.rawValue
        )

        XCTAssertEqual(resolution.baseURL.absoluteString, expectedProduction)
        XCTAssertEqual(resolution.environmentLabel, "override")
    }

    func testUITestResolverTreatsWhitespaceOverrideAsAbsent() throws {
        XCTAssertEqual(
            try UITestAPIConfiguration.resolveBaseURL(
                in: [APIEnvironment.overrideEnvironmentKey: "  \n  "]
            ),
            expectedLocal
        )
    }

    func testUITestResolverNormalizesATrailingRootSlash() throws {
        XCTAssertEqual(
            try UITestAPIConfiguration.resolveBaseURL(
                in: [
                    APIEnvironment.overrideEnvironmentKey:
                        "  \(expectedProduction)/  ",
                ]
            ),
            expectedProduction
        )
    }

    func testUITestResolverRejectsMalformedOverride() {
        XCTAssertThrowsError(
            try UITestAPIConfiguration.resolveBaseURL(
                in: [
                    APIEnvironment.overrideEnvironmentKey:
                        expectedProduction + "/unexpected-path",
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? APIBaseURLResolutionError,
                .invalidOverride
            )
        }
    }

    func testSharedResolverRejectsInvalidCompiledEnvironment() {
        XCTAssertThrowsError(
            try APIBaseURLResolver.resolve(
                processEnvironment: [:],
                compiledEnvironment: "staging"
            )
        ) { error in
            XCTAssertEqual(
                error as? APIBaseURLResolutionError,
                .invalidCompiledEnvironment
            )
        }
    }
}
