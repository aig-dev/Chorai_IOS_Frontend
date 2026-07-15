import Foundation
import XCTest

final class LocalRunSchemeContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testSharedRunSchemeTargetsLiveLocalGoForHumanTesting() throws {
        let schemeURL = repositoryRoot
            .appendingPathComponent("ArcNote.xcodeproj")
            .appendingPathComponent("xcshareddata/xcschemes/ArcNote.xcscheme")
        let scheme = try String(contentsOf: schemeURL, encoding: .utf8)
        let launchStart = try XCTUnwrap(scheme.range(of: "<LaunchAction"))
        let launchEnd = try XCTUnwrap(
            scheme.range(
                of: "</LaunchAction>",
                range: launchStart.upperBound..<scheme.endIndex
            )
        )
        let launchAction = scheme[launchStart.lowerBound..<launchEnd.upperBound]

        XCTAssertTrue(launchAction.contains("key = \"CHORAI_API_BASE_URL\""))
        XCTAssertTrue(launchAction.contains("value = \"http://127.0.0.1:8180\""))
        XCTAssertTrue(launchAction.contains("isEnabled = \"YES\""))

        let apiConfiguration = try String(
            contentsOf: repositoryRoot.appendingPathComponent("ArcNote/APIConfiguration.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            apiConfiguration.contains(
                "ProcessInfo.processInfo.environment[\"CHORAI_API_BASE_URL\"]"
            )
        )
    }
}
