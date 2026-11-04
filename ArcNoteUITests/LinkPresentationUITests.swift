import XCTest

/// Presentation and selection-only callbacks with an offline terminal transport.
final class LinkPresentationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--dev-preview", "--ui-test-link-presentation"]
        app.launch()
        XCTAssertTrue(app.buttons["link.fixture.open-root"].waitForExistence(timeout: 10))
    }

    func testRootLinkSelectionReturnsImmediatelyAndCancelDoesNotSelect() {
        app.buttons["link.fixture.open-root"].tap()
        XCTAssertTrue(element("linkPopup").waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "linkPopup").count, 1)
        let search = app.textFields["linkPopupSearch"]
        search.tap()
        search.typeText("unfinished")
        XCTAssertTrue(app.buttons["linkPopupCard.fixture-link-note"].waitForExistence(timeout: 5))
        capture("link-root-keyboard")
        app.buttons["linkPopupCancel"].tap()
        waitUntilGone(element("linkPopup"))
        XCTAssertEqual(element("link.fixture.root-selection").label, "none")
        waitUntilGone(app.keyboards.firstMatch)

        app.buttons["link.fixture.open-root"].tap()
        XCTAssertTrue(app.buttons["linkPopupCard.fixture-link-collected"].waitForExistence(timeout: 5))
        app.buttons["linkPopupCard.fixture-link-collected"].tap()
        waitUntilGone(element("linkPopup"))
        XCTAssertEqual(element("link.fixture.root-selection").label, "fixture-link-collected")
    }

    func testLinkFromExistingSheetKeepsOriginAndItsSelectionCallback() {
        app.buttons["link.fixture.open-origin-sheet"].tap()
        XCTAssertTrue(app.buttons["link.fixture.open-from-sheet"].waitForExistence(timeout: 5))
        app.buttons["link.fixture.open-from-sheet"].tap()
        XCTAssertTrue(app.buttons["linkPopupCard.fixture-link-note"].waitForExistence(timeout: 5))
        capture("link-over-existing-sheet")
        app.buttons["linkPopupCard.fixture-link-note"].tap()
        waitUntilGone(element("linkPopup"))
        XCTAssertEqual(element("link.fixture.sheet-selection").label, "fixture-link-note")
        XCTAssertTrue(app.buttons["link.fixture.close-origin-sheet"].isHittable)
        XCTAssertEqual(element("link.fixture.root-selection").label, "none")
        capture("link-returned-to-origin")
    }

    func testDraggingLinkClosedClearsSearchAndKeepsOriginSheet() {
        app.buttons["link.fixture.open-origin-sheet"].tap()
        app.buttons["link.fixture.open-from-sheet"].tap()
        XCTAssertTrue(element("linkPopup").waitForExistence(timeout: 5))
        app.textFields["linkPopupSearch"].tap()
        app.textFields["linkPopupSearch"].typeText("unfinished")
        app.navigationBars["Choose a note"].swipeDown()
        if element("linkPopup").exists { app.navigationBars["Choose a note"].swipeDown() }
        waitUntilGone(element("linkPopup"))
        XCTAssertTrue(app.buttons["link.fixture.close-origin-sheet"].isHittable)
        XCTAssertEqual(element("link.fixture.sheet-selection").label, "none")
        app.buttons["link.fixture.open-from-sheet"].tap()
        XCTAssertTrue(app.buttons["linkPopupCard.fixture-link-collected"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["linkPopupSearch"].value as? String, "Search notes")
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
