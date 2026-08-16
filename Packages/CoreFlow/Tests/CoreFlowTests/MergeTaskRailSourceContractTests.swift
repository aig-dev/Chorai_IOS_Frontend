import Foundation
import XCTest

final class MergeTaskRailSourceContractTests: XCTestCase {
    func testRouteContextChoosesExactlyOneRootOrDestinationRailOwner() throws {
        let tabBar = try source(at: "ArcNote/TabBarView.swift")
        let popup = try source(at: "ArcNote/PopupMenuView.swift")
        let ownerToken = "MergeTaskRailShellOverlay("

        XCTAssertEqual(tabBar.components(separatedBy: ownerToken).count - 1, 1)
        XCTAssertEqual(popup.components(separatedBy: ownerToken).count - 1, 1)
        XCTAssertTrue(tabBar.contains("!isPushedCardDestinationVisible"))
        XCTAssertTrue(popup.contains("CardNavigationDestinationRail"))
        XCTAssertTrue(
            popup.contains(
                "CardNavigationDestinationRail(coordinator: coordinator)"
            )
        )
        XCTAssertFalse(
            popup.contains(
                "if isCardNavigationDestination,\n" +
                    "                   let mergeCoordinator"
            )
        )
        XCTAssertTrue(popup.contains(".environmentObject(coordinator)"))
    }

    func testAcceptedFailureRetryVisibilityUsesCoordinatorPolicy() throws {
        let source = try source(
            at: "ArcNote/CoreFlow/MergeLifecycleViews.swift"
        )

        XCTAssertTrue(source.contains("canRetryFailure:"))
        XCTAssertTrue(source.contains("if canRetryFailure"))
        XCTAssertTrue(source.contains("failureActions(jobID: jobID)"))
    }

    func testRailIsIconOnlyAccessibleAndReduceMotionAware() throws {
        let source = try source(at: "ArcNote/CoreFlow/MergeTaskRail.swift")
        XCTAssertTrue(source.contains("accessibilityReduceMotion"))
        XCTAssertTrue(source.contains("accessibilityReduceTransparency"))
        XCTAssertTrue(source.contains("frame(width: 44, height: 44)"))
        XCTAssertTrue(source.contains("Image(\"menu_merge\")"))
        XCTAssertTrue(source.contains("Image(systemName: \"checkmark\")"))
        XCTAssertTrue(source.contains("accessibilityLabel"))
        XCTAssertTrue(source.contains("accessibilityValue"))
        XCTAssertFalse(source.contains("Text(\"Weaving\")"))
        XCTAssertFalse(source.contains("Text(\"Preview\")"))
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
