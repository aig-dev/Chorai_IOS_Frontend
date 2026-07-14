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
        let service = try source(
            "Packages/CoreFlow/Sources/CoreFlow/CoreFlowService.swift"
        )
        let models = try source(
            "Packages/CoreFlow/Sources/CoreFlow/CoreFlowModels.swift"
        )

        XCTAssertFalse(shell.contains("QuickCaptureSheet"))
        XCTAssertFalse(shell.contains("record.open"))
        XCTAssertFalse(tabBar.contains("captureStore"))
        XCTAssertFalse(tabBar.contains("isCapturePresented"))
        XCTAssertFalse(tabBar.contains("recordAcknowledgementID"))
        XCTAssertFalse(service.contains("createPrivateCard"))
        XCTAssertFalse(models.contains("CreatedCard"))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryRoot
                    .appendingPathComponent(
                        "Packages/CoreFlow/Sources/CoreFlow/QuickCaptureStore.swift"
                    )
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryRoot
                    .appendingPathComponent(
                        "Packages/CoreFlow/Sources/CoreFlow/CaptureDraftStore.swift"
                    )
                    .path
            )
        )
    }

    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
