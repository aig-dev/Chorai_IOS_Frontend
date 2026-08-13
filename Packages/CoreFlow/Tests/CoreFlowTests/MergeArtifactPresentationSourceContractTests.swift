import Foundation
import XCTest

final class MergeArtifactPresentationSourceContractTests: XCTestCase {
    func testArtifactReviewOwnsTheOnlyInteractiveActions() throws {
        let lifecycle = try source(
            at: "ArcNote/CoreFlow/MergeLifecycleViews.swift"
        )

        XCTAssertTrue(lifecycle.contains("private var isArtifactPresentation"))
        XCTAssertTrue(
            lifecycle.contains("if !isArtifactPresentation {")
        )
        XCTAssertFalse(
            lifecycle.contains(".opacity(isArtifactPresentation ? 0 : 1)")
        )
        XCTAssertTrue(lifecycle.contains("identifier: \"merge.discard\""))
        XCTAssertTrue(lifecycle.contains("identifier: \"merge.commit\""))
        XCTAssertFalse(lifecycle.contains("identifier: \"merge.artifact.close\""))
    }

    func testArtifactVisualFixtureMatchesTheHiddenProductionHeader() throws {
        let lifecycle = try source(
            at: "ArcNote/CoreFlow/MergeLifecycleViews.swift"
        )
        let fixtureStart = try XCTUnwrap(
            lifecycle.range(of: "struct MergeArtifactVisualFixtureScreen")
        )
        let fixtureEnd = try XCTUnwrap(
            lifecycle.range(
                of: "#endif",
                range: fixtureStart.upperBound..<lifecycle.endIndex
            )
        )
        let fixture = lifecycle[
            fixtureStart.lowerBound..<fixtureEnd.lowerBound
        ]

        XCTAssertFalse(fixture.contains(#"Text("Merge")"#))
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
