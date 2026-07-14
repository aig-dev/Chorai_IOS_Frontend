import Foundation
import XCTest

final class IOSRecordRemovalContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testRecordProductPathIsRemoved() throws {
        let shell = try source("ArcNote/CoreFlow/CoreShellViews.swift")
        let tabBar = try source("ArcNote/TabBarView.swift")

        XCTAssertFalse(shell.contains("QuickCaptureSheet"))
        XCTAssertFalse(shell.contains("record.open"))
        XCTAssertFalse(tabBar.contains("captureStore"))
        XCTAssertFalse(tabBar.contains("isCapturePresented"))
        XCTAssertFalse(tabBar.contains("recordAcknowledgementID"))
        XCTAssertFalse(try source("Packages/CoreFlow/Sources/CoreFlow/CoreFlowService.swift")
            .contains("createPrivateCard"))
        XCTAssertFalse(try source("Packages/CoreFlow/Sources/CoreFlow/CoreFlowModels.swift")
            .contains("CreatedCard"))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryRoot
                    .appendingPathComponent("Packages/CoreFlow/Sources/CoreFlow/QuickCaptureStore.swift")
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryRoot
                    .appendingPathComponent("Packages/CoreFlow/Sources/CoreFlow/CaptureDraftStore.swift")
                    .path
            )
        )
    }

    func testExistingPlusCreationReportsOnboardingEvidence() throws {
        let home = try source("ArcNote/HomeView.swift")
        let editor = try source("ArcNote/NewNoteView.swift")
        let tabBar = try source("ArcNote/TabBarView.swift")

        XCTAssertTrue(home.contains("accessibilityIdentifier(\"note.create\")"))
        XCTAssertTrue(home.contains("NewNoteView(onCreated: onNoteCreated)"))
        XCTAssertTrue(editor.contains("let onCreated: (String, String) -> Void"))
        XCTAssertTrue(
            tabBar.contains(
                "onboardingStore.receive(.recordCreated(cardID: cardID, content: content))"
            )
        )
    }

    func testFlowMetricsUseAssetsInReferenceOrder() throws {
        let flow = try source("ArcNote/CoreFlow/FlowViews.swift")
        let like = try XCTUnwrap(
            flow.range(of: "flowMetric(image: \"like\", count: card.likeCount)")
        )
        let comment = try XCTUnwrap(
            flow.range(of: "flowMetric(image: \"comment\", count: card.commentCount)")
        )
        let favorite = try XCTUnwrap(
            flow.range(of: "flowMetric(image: \"favorite\", count: card.favoriteCount)")
        )

        XCTAssertLessThan(like.lowerBound, comment.lowerBound)
        XCTAssertLessThan(comment.lowerBound, favorite.lowerBound)
        XCTAssertFalse(flow.contains("systemImage: \"bookmark\""))
        XCTAssertFalse(flow.contains("systemImage: \"bubble.left\""))
    }

    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
