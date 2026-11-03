import XCTest

/// Real detail and Spark surfaces with terminal, process-local fixture transport.
/// These tests exercise presentation and keyboard state, not service mutations.
final class CommentPresentationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--dev-preview", "--ui-test-comment-presentation"]
        app.launch()
        XCTAssertTrue(element("screen.detail.loaded").waitForExistence(timeout: 15))
    }

    func testRootDetailCommentKeyboardAndCancelResetComposer() {
        openRootComments()
        XCTAssertFalse(app.buttons["comment.send"].isEnabled)
        app.buttons["comment.reply.fixture-comment-public"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        element("comment.input").typeText("An unsent local draft")
        XCTAssertTrue(app.buttons["comment.send"].isEnabled)
        capture("comments-root-keyboard")

        app.buttons["comment.reply.cancel"].tap()
        waitUntilGone(app.keyboards.firstMatch)
        app.buttons["comment.close"].tap()
        waitUntilGone(element("comment.popup"))
        openRootComments()
        XCTAssertFalse(app.buttons["comment.send"].isEnabled, "Closing must discard the former sheet's unsent composer state")
        XCTAssertFalse(element("comment.reply.cancel").exists)
        capture("comments-root-reopened")
    }

    func testSparkSheetCommentClosesWithoutDismissingSpark() {
        openSparkComments()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "comment.popup").count, 1)
        element("comment.input").tap()
        element("comment.input").typeText("A Spark reply")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        capture("comments-over-spark-keyboard")
        app.buttons["comment.close"].tap()
        waitUntilGone(element("comment.popup"))
        waitUntilGone(app.keyboards.firstMatch)
        XCTAssertTrue(app.buttons["spark.back"].isHittable, "Closing comments must leave its presenting Spark sheet intact")
        capture("comments-returned-to-spark")

        app.buttons["spark.back"].tap()
        XCTAssertTrue(app.buttons["comment.fixture.open-spark"].waitForExistence(timeout: 5))
        openRootComments()
        XCTAssertFalse(app.buttons["comment.send"].isEnabled)
    }

    func testInteractiveCommentDismissalAllowsReopeningFromSpark() {
        openSparkComments()
        for _ in 0..<3 where element("comment.popup").exists {
            app.navigationBars["Comments"].swipeDown()
        }
        waitUntilGone(element("comment.popup"))
        XCTAssertTrue(app.buttons["spark.back"].isHittable)
        tapSparkComment()
        XCTAssertTrue(element("comment.popup").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["comment.send"].isEnabled)
        capture("comments-spark-reopened-after-drag")
    }

    private func openRootComments() {
        let comment = app.buttons["detail.comment.open"]
        for _ in 0..<7 where !comment.isHittable || comment.frame.maxY > app.frame.maxY - 140 { app.swipeUp() }
        XCTAssertTrue(comment.isHittable)
        comment.tap()
        XCTAssertTrue(element("comment.popup").waitForExistence(timeout: 5))
        XCTAssertTrue(element("comment.content.fixture-comment-public").exists)
    }

    private func openSparkComments() {
        app.buttons["comment.fixture.open-spark"].tap()
        XCTAssertTrue(element("spark.fixture.offline").waitForExistence(timeout: 10))
        tapSparkComment()
        XCTAssertTrue(element("comment.popup").waitForExistence(timeout: 5))
        XCTAssertTrue(element("comment.content.fixture-comment-public").exists)
    }

    private func tapSparkComment() {
        let comment = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "spark.comment.")).firstMatch
        // isHittable can be true when the footer's center sits underneath the
        // floating Continue Spark bar. Scroll it clear before a real tap.
        for _ in 0..<7 where !comment.isHittable || comment.frame.maxY > app.frame.maxY - 140 { app.swipeUp() }
        XCTAssertTrue(comment.isHittable)
        XCTAssertTrue(comment.isEnabled)
        comment.tap()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitUntilGone(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
