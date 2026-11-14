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

    func testTabBarConsumesRootCoordinatorAndOwnsCommittedCardNavigation() throws {
        let source = try source(at: "ArcNote/TabBarView.swift")
        XCTAssertTrue(
            source.contains("@EnvironmentObject private var mergeTaskCoordinator")
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

    func testCommittedMergeReturnsToRefreshedLibraryNotes() throws {
        let tabBar = try source(at: "ArcNote/TabBarView.swift")
        let coordinator = try source(
            at: "Packages/CoreFlow/Sources/CoreFlow/CoreFlowCoordinator.swift"
        )
        let home = try source(at: "ArcNote/HomeView.swift")
        let cardsManager = try source(at: "ArcNote/HomeCardsManager.swift")
        guard let start = tabBar.range(
            of: ".onChange(of: mergeTaskCoordinator.committedCardIntent)"
        ), let end = tabBar[start.upperBound...].range(
            of: ".onChange(of: showSideMenu)"
        ) else {
            return XCTFail("Missing committed Merge navigation handler")
        }

        let handler = String(tabBar[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(handler.contains("coordinator.mergeCompleted(cardID:"))
        XCTAssertTrue(handler.contains("clearTabNavigationPaths()"))
        XCTAssertTrue(handler.contains("onMyNotesTapped()"))
        XCTAssertFalse(
            handler.contains("navigationPath.append(TabRoute.detail")
        )
        XCTAssertTrue(coordinator.contains("func mergeCompleted(cardID:"))
        XCTAssertTrue(coordinator.contains("libraryRefreshID = UUID()"))
        XCTAssertTrue(
            tabBar.contains(
                "committedCardID: coordinator.lastMergedCardID"
            )
        )
        XCTAssertTrue(home.contains("let committedCardID: String?"))
        XCTAssertTrue(home.contains(".onChange(of: committedCardID)"))
        XCTAssertTrue(home.contains("cardsManager.promoteCommittedCard(id:"))
        XCTAssertTrue(home.contains(".onChange(of: refreshID)"))
        let loadStart = try XCTUnwrap(home.range(of: "private func loadUserCards()"))
        let loadEnd = try XCTUnwrap(home.range(of: "private func handleOwnedCardActionCommit", range: loadStart.upperBound..<home.endIndex))
        let load = String(home[loadStart.lowerBound..<loadEnd.lowerBound])
        XCTAssertTrue(load.contains("let descriptor = selectedSortOption.descriptor"))
        XCTAssertTrue(load.contains("refresh: true"))
        XCTAssertTrue(load.contains("sortBy: descriptor.field.apiName"))
        XCTAssertTrue(load.contains("sortOrder: descriptor.order.apiName"))
        XCTAssertFalse(load.contains("selectedFilter ="), "A Merge refresh preserves the user's chosen Library sort")
        XCTAssertTrue(home.contains("selectedSegment = 0"))
        XCTAssertTrue(cardsManager.contains("func promoteCommittedCard(id:"))
        XCTAssertTrue(cardsManager.contains("library.changes.sink"))
        XCTAssertTrue(cardsManager.contains("presentLocalNotes"))
        XCTAssertTrue(cardsManager.contains("library.synchronize"))
    }

    func testAppRootSynchronizesMergeRuntimeBeforeActorActivation() throws {
        let source = try source(at: "ArcNote/CoreFlow/MergeTaskRail.swift")

        XCTAssertTrue(source.contains("@Environment(\\.scenePhase)"))
        XCTAssertTrue(
            source.contains(
                "let actorDidChange = coordinator.synchronizeLifecycle("
            )
        )
        XCTAssertTrue(
            source.contains("isApplicationActive: scenePhase == .active")
        )
        XCTAssertTrue(
            source.contains(
                "isNetworkAvailable: NetworkManager.shared.isConnected"
            )
        )
        XCTAssertTrue(
            source.contains("NetworkManager.shared.$isConnected")
        )
        XCTAssertTrue(source.contains(".removeDuplicates()"))
        XCTAssertTrue(
            source.contains(
                "verifiedActorID: verifiedActorID"
            ),
            "Activity and network inputs must be installed before actor activation"
        )
    }

    func testNewMergeSessionExitAbandonsPendingDraft() throws {
        let source = try source(
            at: "ArcNote/CoreFlow/MergeLifecycleViews.swift"
        )

        XCTAssertTrue(source.contains("mergeCoordinator.abandon(draft)"))
        XCTAssertTrue(source.contains("onBack: abandonDraftAndDismiss"))
        XCTAssertTrue(
            source.contains(
                ".onDisappear {\n            abandonDraftIfNeeded()"
            )
        )
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
