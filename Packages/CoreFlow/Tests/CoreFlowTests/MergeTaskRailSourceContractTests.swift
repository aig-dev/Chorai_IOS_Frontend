import Foundation
import XCTest

final class MergeTaskRailSourceContractTests: XCTestCase {
    func testOneGlobalPortalOwnsRailAcrossEveryNavigationEntry() throws {
        let app = try source(at: "ArcNote/ArcNoteApp.swift")
        let tabBar = try source(at: "ArcNote/TabBarView.swift")
        let popup = try source(at: "ArcNote/PopupMenuView.swift")
        let home = try source(at: "ArcNote/HomeView.swift")
        let explore = try source(at: "ArcNote/ExploreView.swift")
        let spark = try source(at: "ArcNote/SparkView.swift")
        let rail = try source(at: "ArcNote/CoreFlow/MergeTaskRail.swift")
        let ownerToken = "MergeTaskRailShellOverlay("

        XCTAssertEqual(rail.components(separatedBy: ownerToken).count - 1, 1)
        XCTAssertEqual(
            app.components(separatedBy: ".globalMergeTaskPortal()").count - 1,
            1
        )
        for source in [app, tabBar, popup, home, explore, spark] {
            XCTAssertFalse(source.contains(ownerToken))
            XCTAssertFalse(source.contains("CardNavigationDestinationRail"))
        }
        XCTAssertFalse(tabBar.contains(".mergeTaskRailPortal("))
        XCTAssertFalse(tabBar.contains("isPushedCardDestinationVisible"))
        XCTAssertFalse(tabBar.contains("isHidden: !navigationPath.isEmpty"))
        XCTAssertTrue(rail.contains("struct MergeTaskRailPortalModifier"))
        XCTAssertTrue(rail.contains("struct GlobalMergeTaskPortalModifier"))
        XCTAssertTrue(
            rail.contains(
                "isHidden: coordinator.presentation != nil"
            )
        )
        XCTAssertTrue(rail.contains("ContextualGuideCallout("))
        XCTAssertTrue(rail.contains("contextualTipStore.complete("))
        XCTAssertTrue(
            tabBar.contains(
                "@EnvironmentObject private var onboardingStore"
            )
        )
        XCTAssertTrue(
            tabBar.contains(
                "@EnvironmentObject private var contextualTipStore"
            )
        )
        XCTAssertTrue(rail.contains("ZStack {\n            content"))
        XCTAssertFalse(rail.contains("content.overlay"))
    }

    func testAcceptedFailureRetryVisibilityUsesCoordinatorPolicy() throws {
        let source = try source(
            at: "ArcNote/CoreFlow/MergeLifecycleViews.swift"
        )

        XCTAssertTrue(source.contains("canRetryFailure:"))
        XCTAssertTrue(source.contains("canCancelFailure:"))
        XCTAssertTrue(source.contains("if canRetryFailure"))
        XCTAssertTrue(source.contains("if canCancelFailure"))
        XCTAssertTrue(source.contains("failureActions(jobID: jobID)"))
        XCTAssertFalse(source.contains("else if store.job?.status.canCancel"))
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
