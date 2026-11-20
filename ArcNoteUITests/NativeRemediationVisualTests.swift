import XCTest

/// Captures the real migrated pages and exercises their existing navigation.
/// Routes use preview transport or an authenticated, scoped loopback fixture.
@MainActor
final class NativeRemediationVisualTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testPublicProfileAndFollowListKeepTheirRealNavigation() {
        launch(["--dev-preview"])
        tap("explore.browse-mode")
        tap("explore.grid.card.preview-field-note")
        tap("detail.author")
        ready("screen.user-profile")
        ready("profile.card.open.preview-field-note")
        capture("public-profile")
        tap("user-profile.followers-count")
        ready("screen.follow-list")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "follow-list.row.")).firstMatch.waitForExistence(timeout: 10))
        capture("followers")
        app.navigationBars["Followers"].buttons["Back"].tap()
        ready("screen.user-profile")
        XCTAssertTrue(app.buttons["user-profile.followers-count"].isHittable)
    }

    func testAccountPrivacyKeepsFailedChangesAndBlockedListReachable() {
        openSidebar()
        tap("side-menu.settings")
        ready("screen.settings.loaded")
        capture("settings")
        tap("settings.account-privacy")
        ready("screen.account-privacy")
        let email = element("account-privacy.toggle.show_email")
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        capture("account-privacy")
        let before = email.value as? String
        XCTAssertTrue(email.isEnabled)
        XCTAssertTrue(email.isHittable)
        // SwiftUI exposes this Toggle as a full-width Switch. Its center is
        // the label (UI9 tapped x=201); the actual switch is at the trailing edge.
        email.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let privacyHierarchy = XCTAttachment(string: app.debugDescription)
        privacyHierarchy.name = "privacy-after-toggle-hierarchy"
        privacyHierarchy.lifetime = .keepAlways
        add(privacyHierarchy)
        scrollTo("account-privacy.visibility.update-error")
        ready("account-privacy.visibility.update-error")
        capture("privacy-failed-save")
        for _ in 0..<5 where !email.isHittable { app.swipeDown() }
        XCTAssertEqual(email.value as? String, before, "An offline rejected write must restore the original privacy setting")
        scrollTo("account-privacy.blocked-users")
        tap("account-privacy.blocked-users")
        ready("screen.blocked-users")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "blocked-users.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        capture("blocked-users")
    }

    func testTrashCancelAndRejectedDeleteKeepTheOriginalNote() throws {
        let server = try RecentNotesServer(libraryFixture: .trashedNote)
        defer { app.terminate(); server.stop() }
        launch([], environment: [
            APIEnvironment.overrideEnvironmentKey: try server.start(),
            "CHORAI_UI_TEST": "1",
            "CHORAI_UI_TEST_AUTH_TOKEN": server.token,
            "CHORAI_UI_TEST_ACTOR_ID": server.actorID
        ])
        tap("side-menu.open")
        app.buttons["Trash"].tap()
        ready("screen.trash")
        let delete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "trash.card.delete.")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        let originalIdentifier = delete.identifier
        capture("trash")
        delete.tap()
        ready("trash.delete.confirm")
        capture("trash-confirmation")
        tap("trash.delete.cancel")
        gone("trash.delete.confirm")
        XCTAssertTrue(app.buttons[originalIdentifier].exists)
        XCTAssertEqual(server.permanentDeleteRequests, 0, "Cancel must not issue a delete")
        app.buttons[originalIdentifier].tap()
        tap("trash.delete.confirm")
        ready("trash.delete.error")
        XCTAssertEqual(server.permanentDeleteRequests, 1, "The rejected request must reach the server once")
        XCTAssertTrue(app.buttons["trash.delete.cancel"].isEnabled)
        capture("trash-failed-delete")
        tap("trash.delete.cancel")
        gone("trash.delete.confirm")
        XCTAssertTrue(app.buttons[originalIdentifier].exists)
        XCTAssertEqual(server.permanentDeleteRequests, 1, "Closing the error must not retry deletion")
    }

    func testChoraSectionsRemainReadableAndHistoryHidingIsExplicit() {
        launch(["--ui-test-chora-profile"], environment: ["CHORAI_CHORA_PROFILE_FIXTURE_MODE": "loaded"])
        ready("chora.identity.displayName")
        ready("chora.growth.stage")
        capture("chora-identity-growth")
        scrollTo("chora.growth.resonance")
        capture("chora-growth")
        scrollTo("chora.sources.localNotes")
        capture("chora-sources")
        scrollTo("chora.chat.clear")
        capture("chora-chat-history")
        tap("chora.chat.clear")
        XCTAssertTrue(app.alerts["Clear Chat History?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.buttons["Hide Previous Messages"].exists)
        app.alerts.buttons["Cancel"].tap()
    }

    func testInvitationsKeepTheThreeExistingDetailDestinations() {
        launch(["--ui-test-invitation-credits"], environment: ["CHORAI_INVITATION_CREDIT_FIXTURE_MODE": "success"])
        ready("invitation-credits.balance.credit")
        capture("invitations-credits")
        for (identifier, name) in [
            ("invitation-credits.history.link", "invitation-history"),
            ("invitation-credits.rewards.link", "invitation-rewards"),
            ("invitation-credits.ledger.link", "credit-ledger")
        ] {
            scrollTo(identifier)
            tap(identifier)
            // The existing success fixture has one invitation and intentionally
            // no rewards or ledger entries; preserve those real empty states.
            if name == "invitation-history" {
                ready("invitation-history.row.inv_1")
            } else {
                ready("\(name).empty")
            }
            capture(name)
            app.navigationBars.buttons.firstMatch.tap()
            ready("screen.invitation-credits")
        }
    }

    func testNotificationFiltersRetainTheOriginalFourScopes() {
        launch(["--ui-test-notification-inbox"], environment: ["CHORAI_NOTIFICATION_FIXTURE_MODE": "loaded"])
        ready("notification.row.ntf_follow")
        capture("notifications")
        tap("notification.filter-toggle")
        for scope in ["all", "unread", "activity", "system"] {
            ready("notification.filter.\(scope)")
        }
        tap("notification.filter.unread")
        XCTAssertFalse(element("notification.row.ntf_like").exists)
        capture("notifications-unread")
        tap("notification.filter.system")
        ready("notification.row.ntf_system")
        XCTAssertFalse(element("notification.row.ntf_follow").exists)
        tap("notification.row.ntf_system")
        ready("notification.detail.loaded")
        XCTAssertTrue(app.staticTexts["Your weekly knowledge review is ready"].exists)
        capture("notification-detail")
        app.navigationBars.buttons.firstMatch.tap()
        ready("notification.row.ntf_system")
    }

    func testDiscoveryPathKeepsOriginalContentOrderAndSystemMenu() {
        launch(["--ui-test-discovery-path"], environment: ["CHORAI_DISCOVERY_PATH_FIXTURE_MODE": "loaded"])
        ready("discovery-path.ancestor.ast_origin")
        XCTAssertEqual(element("discovery-path.order").label, "ast_direct,ast_origin")
        capture("discovery-path")
        tap("discovery-path.menu.ast_collected")
        ready("popup-menu.item.view")
        XCTAssertFalse(element("popup-menu.overlay").exists)
        capture("discovery-path-menu")
    }

    func testSignInKeepsSystemNavigationAndSupportedInputs() {
        launch(["--ui-test-sign-in"])
        ready("signin.email")
        ready("signin.password")
        ready("auth.apple")
        capture("sign-in")
        XCTAssertFalse(element("signin.forgot-password").exists)
    }

    func testSparkMenusStayNativeAndKeepTheCurrentResult() {
        launch(["--dev-preview", "--ui-test-spark-fidelity", "--ui-test-spark-native-menus"])
        ready("spark.fixture.offline")
        ready("spark.card.fixture-spark-nia")
        tap("spark.header.menu")
        ready("popup-menu.item.view")
        XCTAssertFalse(element("popup-menu.overlay").exists)
        capture("spark-header-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.55)).tap()
        tap("spark.menu.fixture-spark-nia")
        ready("popup-menu.item.view")
        XCTAssertFalse(element("popup-menu.overlay").exists)
        capture("spark-result-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.55)).tap()
        ready("spark.card.fixture-spark-nia")
    }

    func testChatComposerKeepsNativeKeyboardAndReadableSendAction() {
        launch(["--ui-test-chat-visibility"])
        tap("chat.fixture.open-attachment-list")
        ready("chat.conversation.conversation_attachment")
        capture("chat-list")
        tap("chat.conversation.conversation_attachment")
        ready("chat.attachment.preview.ast_fixture_note")
        capture("chat-conversation")
        let input = element("chat.message.input")
        input.tap()
        input.typeText("A process-local fixture reply")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat.message.send"].isHittable)
        capture("chat-keyboard-send")
        tap("chat.message.send")
        ready("chat.message.message_sent_persisted")
        capture("chat-fixture-reply")
    }

    func testExploreSearchUsesOneSystemMenuAndReturnsToResults() {
        launch(["--dev-preview"])
        tap("explore.search.open")
        let input = element("explore.search.input")
        input.tap()
        input.typeText("Attention\n")
        ready("explore.search.results")
        XCTAssertEqual(element("explore.search.result.card-id").label, "preview-field-note")
        capture("explore-search")
        tap("explore.search.menu.preview-field-note")
        ready("popup-menu.item.view")
        XCTAssertFalse(element("popup-menu.overlay").exists)
        capture("explore-search-menu")
        tap("popup-menu.item.view")
        ready("screen.detail.loaded")
        app.navigationBars["Note"].buttons.firstMatch.tap()
        ready("explore.search.results")
    }

    func testExploreSummaryKeepsActionsInsideTheWindowAtAccessibilitySize() {
        launch(["--dev-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        ready("flow.card.preview-field-note")
        let surface = element("flow.card.surface.preview-field-note")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(surface.frame.minX, window.minX)
        XCTAssertLessThanOrEqual(surface.frame.maxX, window.maxX)
        XCTAssertLessThanOrEqual(surface.frame.maxY, app.tabBars.firstMatch.frame.minY + 1)
        let favorite = app.buttons["flow.favorite.preview-field-note"]
        XCTAssertTrue(favorite.isHittable)
        XCTAssertGreaterThanOrEqual(favorite.frame.height, 44)
        let spark = app.buttons["flow.spark.preview-field-note"]
        XCTAssertTrue(spark.isHittable)
        XCTAssertEqual(spark.label, "Spark")
        XCTAssertGreaterThanOrEqual(spark.frame.width, 44)
        XCTAssertGreaterThanOrEqual(spark.frame.height, 44)
        let header = element("flow.header.preview-field-note")
        let author = app.buttons["flow.author.preview-field-note"]
        let summary = element("flow.card.preview-field-note")
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertTrue(author.isHittable)
        XCTAssertTrue((author.value as? String)?.contains("Mira Chen,") == true,
                      "The identity must retain both author and date at large type")
        XCTAssertGreaterThanOrEqual(header.frame.minY, surface.frame.minY + 12,
                                    "The identity must stay inside the card's top inset, not spill into its rounded edge")
        XCTAssertGreaterThanOrEqual(author.frame.minY, header.frame.minY - 1)
        XCTAssertLessThanOrEqual(author.frame.maxY, header.frame.maxY + 1)
        XCTAssertGreaterThanOrEqual(spark.frame.minY, author.frame.maxY + 4,
                                    "The author/date block must not overlap the separate Spark action row")
        XCTAssertLessThanOrEqual(spark.frame.maxY, header.frame.maxY + 1)
        XCTAssertGreaterThanOrEqual(summary.frame.minY, header.frame.maxY + 8,
                                    "The full-size summary must have its own space below metadata")
        XCTAssertGreaterThan(summary.frame.height, 70,
                             "Metadata must not consume the full fixed card at accessibility size")
        capture("explore-accessibility-size")
        tap("flow.card.preview-field-note")
        ready("screen.detail.loaded")
        capture("reader-accessibility-size")
        let readerAuthor = app.buttons["detail.author"]
        let messageAuthor = app.buttons["detail.author.chat"]
        let followAuthor = app.buttons["detail.author.follow"]
        XCTAssertTrue(readerAuthor.isHittable)
        XCTAssertGreaterThanOrEqual(readerAuthor.frame.width, window.width * 0.75,
                                    "At accessibility size the author's name needs a full row")
        XCTAssertGreaterThanOrEqual(messageAuthor.frame.minY, readerAuthor.frame.maxY + 8,
                                    "Reader actions must move below the large author identity")
        XCTAssertGreaterThanOrEqual(followAuthor.frame.minY, readerAuthor.frame.maxY + 8)
        XCTAssertTrue(messageAuthor.isHittable)
        XCTAssertTrue(followAuthor.isHittable)
    }

    func testChatHeaderAndComposerRemainReachableAtAccessibilitySize() {
        launch(["--ui-test-chat-visibility", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        tap("chat.fixture.open-typing-list")
        tap("chat.conversation.conversation_typing")
        let identity = element("chat.header.identity")
        ready("chat.header.identity")
        XCTAssertEqual(identity.label, "Chora is typing")
        XCTAssertTrue(app.buttons["Back"].isHittable)
        XCTAssertTrue(element("chat.message.input").isHittable)
        capture("chat-accessibility-size")
        app.terminate()
        launch(["--ui-test-chat-visibility", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        tap("chat.fixture.open-attachment-list")
        tap("chat.conversation.conversation_attachment")
        ready("chat.header.identity")
        XCTAssertTrue(app.buttons["Back"].isHittable)
        capture("chat-accessibility-size-idle")
    }

    private func openSidebar() {
        launch(["--dev-preview"])
        tap("side-menu.open")
        ready("side-menu.settings")
        capture("sidebar")
    }

    private func launch(_ arguments: [String], environment: [String: String] = [:]) {
        app.launchArguments = arguments
        for (key, value) in environment { app.launchEnvironment[key] = value }
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func ready(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element(id).waitForExistence(timeout: 12), "Missing \(id)", file: file, line: line)
    }
    private func tap(_ id: String) {
        ready(id)
        let button = app.buttons.matching(identifier: id).firstMatch
        if button.exists { button.tap() } else { element(id).tap() }
    }
    private func gone(_ id: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element(id))
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
    private func scrollTo(_ id: String) {
        for _ in 0..<8 where !element(id).isHittable { app.swipeUp() }
        XCTAssertTrue(element(id).isHittable, "Cannot reach \(id)")
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "remediation-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
