import XCTest

/// Guards against the glass button style adding padding to an already full-size
/// label, and against multiline input moving its actions away from the baseline.
@MainActor
final class ChatControlSizingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testComposerKeepsCompactTapTargetsAndBottomAlignedActions() {
        openAttachmentConversation()
        let attachment = app.buttons["chat.attachment.add"]
        let send = app.buttons["chat.message.send"]
        assertCompactControl(attachment)
        assertCompactControl(send)
        XCTAssertFalse(send.isEnabled)

        let input = element("chat.message.input")
        input.tap()
        input.typeText("First line\nSecond line\nThird line")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(send.isEnabled)
        assertCompactControl(attachment)
        assertCompactControl(send)
        XCTAssertEqual(attachment.frame.maxY, send.frame.maxY, accuracy: 3,
                       "Composer actions must stay at the bottom of multiline input")
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY)
        capture("chat-compact-multiline-composer")

        send.tap()
        XCTAssertTrue(element("chat.message.message_sent_persisted").waitForExistence(timeout: 10))
        XCTAssertFalse(send.isEnabled)
    }

    func testAttachmentPreviewScalesAndWrapsAtAccessibilitySize() {
        openAttachmentConversation()
        let ordinaryHeight = element("chat.attachment.preview.ast_fixture_note").frame.height
        capture("chat-compact-idle")
        app.terminate()

        openAttachmentConversation(accessibilitySize: true)
        let preview = element("chat.attachment.preview.ast_fixture_note")
        XCTAssertGreaterThan(preview.frame.height, ordinaryHeight * 1.5,
                             "Attachment text must respect Dynamic Type instead of retaining a fixed 17pt font")
        assertCompactControl(app.buttons["chat.attachment.add"])
        assertCompactControl(app.buttons["chat.message.send"])
        capture("chat-accessibility-attachment-and-composer")
    }

    private func openAttachmentConversation(accessibilitySize: Bool = false) {
        app.launchArguments = ["--ui-test-chat-visibility"]
        if accessibilitySize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let open = app.buttons["chat.fixture.open-attachment-list"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let conversation = app.buttons["chat.conversation.conversation_attachment"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 10))
        conversation.tap()
        let back = app.navigationBars.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(back.frame.width, 44)
        XCTAssertGreaterThanOrEqual(back.frame.height, 44)
        XCTAssertTrue(element("chat.attachment.preview.ast_fixture_note").waitForExistence(timeout: 10))
    }

    private func assertCompactControl(_ control: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(control.exists, file: file, line: line)
        XCTAssertGreaterThanOrEqual(control.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(control.frame.height, 44, file: file, line: line)
        XCTAssertLessThanOrEqual(control.frame.width, 48, file: file, line: line)
        XCTAssertLessThanOrEqual(control.frame.height, 48, file: file, line: line)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Exercises the real empty conversation response and real tab coordinator.
@MainActor
final class ChatEmptyStateUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    func testEmptyConversationActionOpensExistingExploreTab() {
        let app = openEmptyChat()
        let explore = app.buttons["chat.empty.explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        XCTAssertTrue(explore.isHittable)
        XCTAssertGreaterThanOrEqual(explore.frame.height, 48)
        XCTAssertFalse(element("chat.error", in: app).exists)
        capture(app, "chat-two-chora-empty")

        explore.tap()

        let exploreTab = app.tabBars.buttons["Explore"]
        XCTAssertTrue(exploreTab.isSelected,
                      "The empty-state action must use the existing Explore tab")
        XCTAssertTrue(element("screen.flow.content", in: app)
            .waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Explore"].buttons["Back"].exists,
                       "Explore must not be pushed as a second navigation stack")

        app.tabBars.buttons["Chat"].tap()
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Chat"].exists)
    }

    func testEmptyConversationActionRemainsReachableAtAccessibilitySize() {
        let app = openEmptyChat(accessibilitySize: true)
        let explore = app.buttons["chat.empty.explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        let headline = element("chat.empty.headline", in: app)
        XCTAssertTrue(headline.exists)
        XCTAssertGreaterThan(headline.frame.height, 60,
                             "The empty-state heading must scale and wrap")
        for _ in 0..<5 where !explore.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(explore.isHittable,
                      "Large text must scroll rather than clip the action")
        XCTAssertGreaterThanOrEqual(explore.frame.height, 48)
        capture(app, "chat-two-chora-accessibility")
        explore.tap()
        XCTAssertTrue(app.tabBars.buttons["Explore"].isSelected)
    }

    private func openEmptyChat(accessibilitySize: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--dev-preview"]
        if accessibilitySize {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        }
        app.launch()
        let chat = app.tabBars.buttons["Chat"]
        XCTAssertTrue(chat.waitForExistence(timeout: 10))
        chat.tap()
        return app
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
