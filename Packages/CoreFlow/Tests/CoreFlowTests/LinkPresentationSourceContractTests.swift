import Foundation
import XCTest

final class LinkPresentationSourceContractTests: XCTestCase {
    func testLinkHasOneRootPresenterAndNoCompetingSourceSheets() throws {
        let app = try source("ArcNote/ArcNoteApp.swift")
        XCTAssertEqual(app.components(separatedBy: ".overlay { LinkPopupPresenter() }").count - 1, 1)
        for file in ["TabBarView", "MyProfileView", "UserProfileView", "NewNoteView", "ExploreView", "CoreFlow/SparkContinuationViews"] {
            XCTAssertFalse(try source("ArcNote/\(file).swift").contains(".linkPopup()"), "Competing presenter in \(file)")
        }
        let link = try source("ArcNote/LinkPopupView.swift")
        XCTAssertTrue(link.contains("ChoraiNativeSheetPresenter("))
        XCTAssertTrue(link.contains("detents: [.large()]"))
        XCTAssertTrue(link.contains("set: { if !$0 { manager.hide() } }"), "Interactive dismiss must run the original cancellation and cleanup")
        XCTAssertFalse(link.contains("struct LinkPopupModifier"))
        XCTAssertFalse(link.contains("content.sheet(isPresented:"))
    }

    func testLinkRetainsCapturedOriginCallbackAndImmediateAction() throws {
        let link = try source("ArcNote/LinkPopupView.swift")
        for contract in ["let navigate = onNavigate", "let requestPresentationID = presentationID", "self.presentationID == requestPresentationID", "let selectionCallback = onCardSelected", "if shouldNavigate", "navigate?(", "selectionCallback?(linkItem)", "manager.linkCard(linkItem: item)"] {
            XCTAssertTrue(link.contains(contract), "Lost original origin/action contract: \(contract)")
        }
        XCTAssertFalse(link.contains("confirmationDialog"), "Selecting an existing candidate still performs its original action immediately")
        XCTAssertTrue(link.contains("LinkPopupManager.shared.show(mode: .selectionOnly)"))
        XCTAssertTrue(link.contains("LocalDevelopmentPreview.isEnabled\n            && ProcessInfo.processInfo.arguments.contains(\"--ui-test-link-presentation\")"))
    }

    private func source(_ path: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
