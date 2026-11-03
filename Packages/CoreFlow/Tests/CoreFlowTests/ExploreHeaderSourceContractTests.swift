import Foundation
import XCTest

final class ExploreHeaderSourceContractTests: XCTestCase {
    func testExploreHeaderUsesExploreTitleWithoutStatusDot() throws {
        let explore = try source(at: "ArcNote/ExploreView.swift")
        let menuButtonEnd = try XCTUnwrap(
            explore.range(
                of: ".accessibilityIdentifier(\"side-menu.open\")"
            )?.upperBound
        )
        let searchButtonStart = try XCTUnwrap(
            explore.range(
                of: ".accessibilityIdentifier(\"explore.search.open\")",
                range: menuButtonEnd..<explore.endIndex
            )?.lowerBound
        )
        let header = String(explore[menuButtonEnd..<searchButtonStart])

        XCTAssertTrue(header.contains("Text(isSearchMode ? \"Search\" : \"Explore\")"))
        XCTAssertFalse(header.contains("Text(\"Flow\")"))
        XCTAssertFalse(header.contains("Circle()"))
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
