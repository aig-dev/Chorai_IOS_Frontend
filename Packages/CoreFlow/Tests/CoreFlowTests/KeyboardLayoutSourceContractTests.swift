import Foundation
import XCTest

final class KeyboardLayoutSourceContractTests: XCTestCase {
    func testAdaptiveLayoutOwnsMeasuredKeyboardState() throws {
        let source = try source(at: "ArcNote/AdaptiveLayout.swift")

        XCTAssertTrue(source.contains("final class KeyboardLayoutObserver"))
        XCTAssertTrue(source.contains("UIResponder.keyboardWillChangeFrameNotification"))
        XCTAssertTrue(source.contains("UIResponder.keyboardWillHideNotification"))
        XCTAssertTrue(source.contains("func overlap(in containerFrame: CGRect) -> CGFloat"))
        XCTAssertTrue(source.contains("struct KeyboardStableViewport"))
        XCTAssertTrue(source.contains("UIViewRepresentable"))
        XCTAssertTrue(source.contains("convert(bounds, to: nil).minY"))
        XCTAssertTrue(source.contains("restingMinY"))
        XCTAssertFalse(source.contains("UIScreen.main.bounds"))
    }

    func testProductTabBarDoesNotConsumeKeyboardViewport() throws {
        let source = try source(at: "ArcNote/TabBarView.swift")

        XCTAssertTrue(source.contains("@StateObject private var keyboardLayout"))
        XCTAssertTrue(source.contains("if !keyboardLayout.isVisible"))
        XCTAssertTrue(source.contains("CoreTabBar(selectedTab: $coordinator.selectedTab)"))
    }

    func testTopSearchAndFixedFormsDeclareTheirKeyboardPolicies() throws {
        let home = try source(at: "ArcNote/HomeView.swift")
        let explore = try source(at: "ArcNote/ExploreView.swift")
        let chat = try source(at: "ArcNote/ChatView.swift")
        let signIn = try source(at: "ArcNote/SignInView.swift")
        let report = try source(at: "ArcNote/CoreFlow/ContentReportView.swift")

        XCTAssertTrue(
            home.contains(
                "KeyboardStableViewport(isFocused: isLibrarySearchFocused)"
            )
        )
        XCTAssertTrue(home.contains("KeyboardStableViewport"))
        XCTAssertTrue(home.contains("height: geometry.size.height"))
        XCTAssertTrue(home.contains("alignment: .top"))
        XCTAssertTrue(home.contains(".scrollDismissesKeyboard(.interactively)"))
        XCTAssertTrue(
            explore.contains("KeyboardStableViewport(isFocused: isSearchFocused)")
        )
        XCTAssertTrue(
            chat.contains("KeyboardStableViewport(isFocused: isSearchFocused)")
        )
        XCTAssertTrue(
            try source(at: "ArcNote/CoreFlow/MergeLifecycleViews.swift")
                .contains("KeyboardStableViewport(isFocused: isTextInputFocused)")
        )
        XCTAssertTrue(
            try source(at: "ArcNote/MergeView.swift")
                .contains("KeyboardStableViewport(isFocused: isSearchFocused)")
        )
        XCTAssertTrue(signIn.contains("ScrollView"))
        XCTAssertTrue(signIn.contains(".scrollDismissesKeyboard(.interactively)"))
        XCTAssertTrue(report.contains("ScrollView"))
        XCTAssertTrue(report.contains(".scrollDismissesKeyboard(.interactively)"))
    }

    func testCustomOverlaysDoNotDoubleApplyKeyboardAvoidance() throws {
        let comment = try source(at: "ArcNote/CommentPopupView.swift")
        let link = try source(at: "ArcNote/LinkPopupView.swift")

        XCTAssertFalse(comment.contains("keyboardHeight"))
        XCTAssertFalse(comment.contains("keyboardFrame.height"))
        XCTAssertFalse(comment.contains("contentInsetAdjustmentBehavior"))
        XCTAssertFalse(comment.contains("keyboardDismissMode = .none"))
        XCTAssertTrue(comment.contains(".scrollDismissesKeyboard(.interactively)"))
        XCTAssertFalse(link.contains("window.endEditing(true)"))
        XCTAssertFalse(link.contains("disableKeyboardAdjustment()"))
        XCTAssertTrue(link.contains(".scrollDismissesKeyboard(.interactively)"))
    }

    func testEveryRemainingInputFamilyHasAnExplicitKeyboardPolicy() throws {
        let scrollableInputPaths = [
            "ArcNote/ChatView.swift",
            "ArcNote/ChatDetailView.swift",
            "ArcNote/SignUpView.swift",
            "ArcNote/EditProfileView.swift",
            "ArcNote/ChoraProfileView.swift",
            "ArcNote/InvitationCreditView.swift",
            "ArcNote/CoreFlow/MergeLifecycleViews.swift",
            "ArcNote/MergeView.swift",
            "ArcNote/NewInsightView.swift",
            "ArcNote/NewNoteView.swift",
            "ArcNote/CardEditor/CardEditorShell.swift",
        ]
        let policies = [
            ("ArcNote/ExploreView.swift", "isSearchFocused = false"),
        ] + scrollableInputPaths.map { path in
            (path, ".scrollDismissesKeyboard(.interactively)")
        }

        for (path, policy) in policies {
            let source = try source(at: path)
            XCTAssertTrue(
                source.contains(policy),
                "\(path) must expose its intended keyboard dismissal path"
            )
        }
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
