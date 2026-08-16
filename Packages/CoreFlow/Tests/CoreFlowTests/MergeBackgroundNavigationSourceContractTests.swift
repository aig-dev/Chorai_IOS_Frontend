import Foundation
import XCTest

final class MergeBackgroundNavigationSourceContractTests: XCTestCase {
    func testMergeViewDoesNotOwnAcceptedRuntimeLifetime() throws {
        let source = try source(
            at: "ArcNote/CoreFlow/MergeLifecycleViews.swift"
        )
        XCTAssertTrue(
            source.contains("@EnvironmentObject private var mergeCoordinator")
        )
        XCTAssertTrue(source.contains("mergeCoordinator.adopt(draft)"))
        XCTAssertTrue(source.contains("guard let jobID, !jobID.isEmpty"))
        XCTAssertFalse(source.contains("resumePersistedSession: true"))
        XCTAssertFalse(
            source.contains(".onDisappear {\n            store.stop()")
        )
    }

    func testTabBarOwnsCoordinatorAndCommittedCardNavigation() throws {
        let source = try source(at: "ArcNote/TabBarView.swift")
        XCTAssertTrue(
            source.contains("@StateObject private var mergeTaskCoordinator")
        )
        XCTAssertTrue(source.contains("case detail(String)"))
        XCTAssertTrue(
            source.contains("mergeTaskCoordinator.committedCardIntent")
        )
        XCTAssertTrue(
            source.contains(".environmentObject(mergeTaskCoordinator)")
        )
        XCTAssertFalse(source.contains("mergeResumeMetadata"))
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
