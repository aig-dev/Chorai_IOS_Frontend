import Foundation
import XCTest

final class NavigationOriginSourceContractTests: XCTestCase {
    func testOnboardingOnlySelectsItsInitialTab() throws {
        let tabBar = try source(at: "ArcNote/TabBarView.swift")

        XCTAssertTrue(
            tabBar.contains("routeInitialOnboardingState"),
            "Onboarding may select its resume tab once, but later state changes must not reroute behind a presented screen"
        )
        let initialRoute = try XCTUnwrap(
            slice(
                tabBar,
                from: "private func routeInitialOnboardingState",
                through: "private var activeScreenAutomationAnchor"
            )
        )
        XCTAssertFalse(initialRoute.contains("navigationPath.removeLast"))
        XCTAssertFalse(initialRoute.contains("navigateToMerge = false"))
    }

    func testPopupNavigationIsOwnedByItsPresentingStack() throws {
        let popup = try source(at: "ArcNote/PopupMenuView.swift")

        XCTAssertTrue(popup.contains("enum CardNavigationRoute"))
        XCTAssertTrue(popup.contains("@State private var presentedRoute"))
        XCTAssertTrue(popup.contains(".navigationDestination"))

        for notification in [
            "NavigateToEdit",
            "NavigateToDetail",
            "NavigateToSpark",
            "NavigateToMerge",
            "NavigateToRoot",
        ] {
            XCTAssertFalse(
                popup.contains("NSNotification.Name(\"\(notification)\")"),
                "\(notification) discards the presenting stack and cannot preserve Back semantics"
            )
        }
    }

    func testLinkedCardsAndEditorActionsReuseTheOriginRouter() throws {
        let linkPopup = try source(at: "ArcNote/LinkPopupView.swift")
        let editor = try source(at: "ArcNote/NewNoteView.swift")

        XCTAssertTrue(linkPopup.contains("CardNavigationRoute"))
        XCTAssertTrue(linkPopup.contains("onNavigate"))
        XCTAssertFalse(linkPopup.contains("NSNotification.Name(\"NavigateToEdit\")"))
        XCTAssertFalse(linkPopup.contains("NSNotification.Name(\"NavigateToDetail\")"))

        XCTAssertTrue(editor.contains("@Environment(\\.navigateCard)"))
        XCTAssertTrue(
            editor.contains(
                "case navigation((String) -> CardNavigationRoute)"
            ),
            "New notes must resolve the persisted card ID before building their local route"
        )
        XCTAssertFalse(editor.contains(".notification(\"NavigateToSpark\")"))
        XCTAssertFalse(editor.contains(".notification(\"NavigateToMerge\")"))
        XCTAssertFalse(editor.contains(".notification(\"NavigateToRoot\")"))
    }

    func testScreensDoNotCompeteForGlobalCardNavigationEvents() throws {
        for path in [
            "ArcNote/TabBarView.swift",
            "ArcNote/HomeView.swift",
            "ArcNote/ExploreView.swift",
            "ArcNote/MyProfileView.swift",
            "ArcNote/UserProfileView.swift",
        ] {
            let screen = try source(at: path)
            for notification in [
                "NavigateToEdit",
                "NavigateToDetail",
                "NavigateToSpark",
                "NavigateToMerge",
                "NavigateToRoot",
            ] {
                XCTAssertFalse(
                    screen.contains(notification),
                    "\(path) must not react to source-free \(notification) events"
                )
            }
        }
    }

    func testLinkCompletionCannotEscapeItsPresentationGeneration() throws {
        let linkPopup = try source(at: "ArcNote/LinkPopupView.swift")

        XCTAssertTrue(linkPopup.contains("private var presentationID = UUID()"))
        XCTAssertTrue(linkPopup.contains("guard !isLinking else { return }"))
        XCTAssertTrue(
            linkPopup.contains("let requestPresentationID = presentationID")
        )
        XCTAssertTrue(
            linkPopup.contains(
                "self.presentationID == requestPresentationID else"
            )
        )
        XCTAssertTrue(linkPopup.contains("linkRequestCancellable?.cancel()"))
    }

    func testLinkSearchCannotEscapeItsPresentationOrQueryGeneration() throws {
        let linkPopup = try source(at: "ArcNote/LinkPopupView.swift")
        let search = try XCTUnwrap(
            slice(
                linkPopup,
                from: "private func searchCards(keyword: String)",
                through: "var filteredItems: [LinkItem]"
            )
        )

        XCTAssertTrue(
            linkPopup.contains("private var searchRequestID = UUID()")
        )
        XCTAssertTrue(
            linkPopup.contains(
                "private var searchRequestCancellable: AnyCancellable?"
            )
        )
        XCTAssertTrue(search.contains("guard isShowing else { return }"))
        XCTAssertTrue(search.contains("searchRequestCancellable?.cancel()"))
        XCTAssertTrue(search.contains("let requestPresentationID = presentationID"))
        XCTAssertTrue(search.contains("let requestSearchID = UUID()"))
        XCTAssertTrue(
            search.contains("self.presentationID == requestPresentationID")
        )
        XCTAssertTrue(search.contains("self.searchRequestID == requestSearchID"))
    }

    func testOriginPresenterCarriesWorkflowDependenciesIntoDestination() throws {
        let popup = try source(at: "ArcNote/PopupMenuView.swift")
        let host = try XCTUnwrap(
            slice(
                popup,
                from: "private struct CardNavigationHostModifier",
                through: "// MARK: - Custom Scale Transition"
            )
        )
        let menu = try XCTUnwrap(
            slice(
                popup,
                from: "struct PopupMenuModifier",
                through: "// MARK: - PopupMenu Overlay"
            )
        )

        for presenter in [host, menu] {
            XCTAssertTrue(
                presenter.contains(
                    "@Environment(\\.cardNavigationOnboardingStore)"
                )
            )
            XCTAssertTrue(
                presenter.contains(
                    "@Environment(\\.cardNavigationMergeCompleted)"
                )
            )
            XCTAssertTrue(presenter.contains("onboardingStore: onboardingStore"))
        }
        XCTAssertTrue(host.contains("mergeCompleted: mergeCompleted"))
        XCTAssertTrue(
            menu.contains("mergeCompleted: handlePresentedMergeCompleted")
        )
    }

    func testReturningToLibraryRecordsTheLibraryViewWithoutRerouting() throws {
        let home = try source(at: "ArcNote/HomeView.swift")
        let popup = try source(at: "ArcNote/PopupMenuView.swift")
        let tabBar = try source(at: "ArcNote/TabBarView.swift")
        let stateObserver = try XCTUnwrap(
            slice(
                tabBar,
                from: ".onChange(of: onboardingStore.session?.state)",
                through: ".onAppear"
            )
        )

        XCTAssertTrue(
            popup.contains(
                "@State private var didCommitPresentedMerge = false"
            )
        )
        XCTAssertTrue(popup.contains("handlePresentedMergeCompleted"))
        XCTAssertTrue(
            popup.contains("didCommit: didCommitPresentedMerge")
        )
        XCTAssertTrue(home.contains("let onCardRouteDismissed:"))
        XCTAssertTrue(
            home.contains("onRouteDismissed: onCardRouteDismissed")
        )
        XCTAssertTrue(
            tabBar.contains("handleLibraryCardRouteDismissed")
        )
        XCTAssertTrue(
            tabBar.contains("guard dismissal.didCommit")
        )
        XCTAssertTrue(tabBar.contains("\"product_merge_intro\""))
        XCTAssertTrue(tabBar.contains("struct PendingLibraryReturn"))
        XCTAssertTrue(tabBar.contains("actorID: actorID"))
        XCTAssertTrue(tabBar.contains("sessionID: session.sessionID"))
        XCTAssertTrue(tabBar.contains("recordReturnedLibraryIfReady()"))
        XCTAssertTrue(stateObserver.contains("recordReturnedLibraryIfReady()"))
        XCTAssertFalse(stateObserver.contains("selectedTab ="))
        XCTAssertFalse(stateObserver.contains("navigationPath"))
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func slice(
        _ source: String,
        from startMarker: String,
        through endMarker: String
    ) -> Substring? {
        guard let start = source.range(of: startMarker) else { return nil }
        let remainder = source[start.lowerBound...]
        guard let end = remainder.range(of: endMarker) else { return nil }
        return remainder[..<end.lowerBound]
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
