import Foundation
import XCTest

final class CommentPresentationSourceContractTests: XCTestCase {
    func testCommentsHaveOneSceneScopedPresenterAboveAnExistingSheet() throws {
        let app = try source("ArcNote/ArcNoteApp.swift")
        XCTAssertEqual(app.components(separatedBy: ".overlay { CommentPopupView() }").count - 1, 1)
        for path in ["ArcNote/TabBarView.swift", "ArcNote/DetailView.swift", "ArcNote/ExploreView.swift", "ArcNote/MyProfileView.swift", "ArcNote/UserProfileView.swift", "ArcNote/CoreFlow/SparkContinuationViews.swift"] {
            XCTAssertFalse(try source(path).contains("CommentPopupView()"), "Duplicate presenter in \(path)")
        }
        let presenter = try source("ArcNote/ChoraiTheme.swift")
        XCTAssertTrue(presenter.contains("attachment.view.window?.rootViewController"))
        XCTAssertTrue(presenter.contains("while let presented = presenter.presentedViewController"))
        XCTAssertTrue(presenter.contains("!(presenter is UIAlertController)"))
        XCTAssertTrue(presenter.contains("!presenter.isBeingPresented, !presenter.isBeingDismissed"))
        XCTAssertFalse(presenter.contains("UIApplication.shared"), "Presentation belongs to the attached scene, not an arbitrary global window")
    }

    func testNativeSheetOwnsKeyboardAndDismissesOnlyItsOwnController() throws {
        let comments = try source("ArcNote/CommentPopupView.swift")
        let presenter = try source("ArcNote/ChoraiTheme.swift")
        XCTAssertTrue(comments.contains("detents: [.medium(), .large()]"))
        XCTAssertTrue(presenter.contains("nativeSheet.animateChanges { nativeSheet.selectedDetentIdentifier = .large }"))
        XCTAssertTrue(presenter.contains("sheet.dismiss(animated: true)"))
        XCTAssertFalse(presenter.contains("presenter.dismiss("))
        XCTAssertTrue(presenter.contains("func presentationControllerDidDismiss("))
        XCTAssertTrue(presenter.contains("if presentingViewController == nil { onRemoval?() }"))
        XCTAssertTrue(presenter.contains("if isPresented.wrappedValue { isPresented.wrappedValue = false }"))
        XCTAssertTrue(comments.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(comments.contains("private struct CommentSheetContent: View"), "Each native presentation has a fresh composer lifetime")
    }

    func testPresentationFixtureUsesRealDestinationsAndCannotEnableLiveTransport() throws {
        let comments = try source("ArcNote/CommentPopupView.swift")
        let app = try source("ArcNote/ArcNoteApp.swift")
        let spark = try source("ArcNote/CoreFlow/SparkContinuationViews.swift")
        XCTAssertTrue(comments.contains("LocalDevelopmentPreview.isEnabled\n            && ProcessInfo.processInfo.arguments.contains(\"--ui-test-comment-presentation\")"))
        XCTAssertTrue(comments.contains("DetailView(cardId: \"preview-field-note\")"))
        XCTAssertTrue(comments.contains("SparkContinuationView.fidelityFixture()"))
        XCTAssertTrue(app.contains("if CommentPresentationFixture.isEnabled {\n            CommentPresentationFixtureScreen()"))
        XCTAssertTrue(spark.contains(".disabled(!allowsNetworkNavigation && !CommentPresentationFixture.isEnabled)"))
        XCTAssertTrue(spark.contains("#else\n            .disabled(!allowsNetworkNavigation)\n            #endif"))
        let service = try source("ArcNote/Models/CommentModels.swift")
        let fixture = try XCTUnwrap(service.range(of: "if CommentPresentationFixture.isEnabled"))
        let network = try XCTUnwrap(service.range(of: "NetworkManager.shared.getComments"))
        XCTAssertLessThan(fixture.upperBound, network.lowerBound)
        XCTAssertTrue(service[fixture.upperBound..<network.lowerBound].contains("return"))
    }

    private func source(_ path: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
