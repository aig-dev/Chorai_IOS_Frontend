import XCTest

@MainActor
final class PrototypeNavigationTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.chorai.nativeprototype")
        app.launchArguments = ["--screen", "explore", "--appearance", "light"]
        app.launch()
    }

    func testTabsOwnedEditingSaveStaysAndBackPreservesLocalSample() {
        let home = app.tabBars.buttons["Home"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        home.tap()
        app.buttons["Collect"].tap()
        XCTAssertTrue(app.buttons["prototype.note.collected"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Notes"].tap()
        let owned = app.buttons["prototype.note.owned"].firstMatch
        XCTAssertTrue(owned.waitForExistence(timeout: 3))
        owned.tap()
        let body = app.textViews["prototype.editor.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 3))
        body.tap()
        body.typeText(" Native UI check.")
        let leading = app.buttons["prototype.editor.leading"]
        XCTAssertEqual(leading.label, "Save sample changes")
        leading.tap()
        XCTAssertTrue(body.exists, "Saving must stay in the editor")
        XCTAssertEqual(leading.label, "Back")
        XCTAssertTrue(app.staticTexts["Saved to this sample"].exists)
        XCTAssertTrue((body.value as? String)?.contains("Native UI check.") == true)
        leading.tap()
        XCTAssertTrue(app.buttons["Notes"].waitForExistence(timeout: 3))
        app.buttons["prototype.note.owned"].firstMatch.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 3))
        XCTAssertTrue((body.value as? String)?.contains("Native UI check.") == true, "Reopening from Home must keep the saved local body")
    }

    func testSearchQueriesOnlyOnSubmitAndCancelRestoresExplore() {
        app.buttons["Search notes"].tap()
        let field = app.textFields["prototype.explore.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("curiosity")
        XCTAssertTrue(app.staticTexts["Follow a question"].exists, "Typing must not submit")
        field.typeText("\n")
        XCTAssertTrue(app.staticTexts["1 NOTES"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Follow a question"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Search notes"].exists)
        XCTAssertFalse(field.exists)
    }
    func testFloatingNewNoteCreatesPrivateLocalBodyAndReturnsHome() {
        app.tabBars.buttons["Home"].tap()
        let add = app.buttons["prototype.note.new"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertTrue(add.isHittable, "New note must be visible above the native tab bar")
        add.tap()
        let body = app.textViews["prototype.editor.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 3))
        XCTAssertEqual(body.value as? String, "")
        XCTAssertTrue(app.buttons["Note privacy"].exists)
        body.tap()
        body.typeText("A fresh local note.")
        let leading = app.buttons["prototype.editor.leading"]
        leading.tap()
        XCTAssertTrue(body.exists)
        XCTAssertEqual(leading.label, "Back")
        leading.tap()
        XCTAssertTrue(app.buttons["prototype.note.new"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["A fresh local note."].exists)
    }

    func testSwipeSkipHistoryAndResumeKeepTheUnreadPosition() {
        assertExplorePosition(1)
        XCTAssertFalse(exploreElement("collected").exists, "The first sample starts uncollected")

        swipeExploreCard(right: false)
        assertExplorePosition(2)
        app.buttons["prototype.explore.skip"].tap()
        assertExplorePosition(3)

        app.buttons["prototype.explore.previous"].tap()
        assertExplorePosition(2)
        XCTAssertTrue(exploreElement("history").exists)
        app.buttons["prototype.explore.previous"].tap()
        assertExplorePosition(1)
        XCTAssertFalse(exploreElement("collected").exists, "Skipping and revisiting must not collect a note")

        app.buttons["prototype.explore.resume"].tap()
        assertExplorePosition(3)
        XCTAssertFalse(exploreElement("history").exists, "Resume must return to the unread frontier")
    }

    func testSwipeCollectUndoAndHistoryHaveSeparateEffects() {
        assertExplorePosition(1)
        swipeExploreCard(right: true)
        assertExplorePosition(2)
        let undo = app.buttons["prototype.explore.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        assertExplorePosition(2)

        app.buttons["prototype.explore.previous"].tap()
        assertExplorePosition(1)
        XCTAssertFalse(exploreElement("collected").exists, "Undo must remove only the newly added collection")

        swipeExploreCard(right: true)
        assertExplorePosition(2)
        app.buttons["prototype.explore.previous"].tap()
        assertExplorePosition(1)
        XCTAssertTrue(exploreElement("collected").waitForExistence(timeout: 3), "Returning to a note must preserve its collection")
    }

    func testAlreadyCollectedSwipeStaysCollectedAndReaderReturnsToSameCard() {
        assertExplorePosition(1)
        app.buttons["prototype.explore.skip"].tap()
        assertExplorePosition(2)
        XCTAssertTrue(exploreElement("collected").exists, "The second sample is already in Collect")

        swipeExploreCard(right: true)
        assertExplorePosition(3)
        XCTAssertFalse(app.buttons["prototype.explore.undo"].exists, "An existing collection must not create a removal undo action")
        app.buttons["prototype.explore.previous"].tap()
        assertExplorePosition(2)
        XCTAssertTrue(exploreElement("collected").exists, "Right swipe must not toggle an existing collection off")

        app.buttons["prototype.explore.read"].tap()
        let reader = app.navigationBars["Note"]
        XCTAssertTrue(reader.waitForExistence(timeout: 3))
        reader.buttons.firstMatch.tap()
        assertExplorePosition(2)
        XCTAssertTrue(exploreElement("collected").exists)
        XCTAssertTrue(exploreElement("history").exists, "Closing the reader must preserve the browsing position")
    }

    func testShortAndVerticalDragsDoNotAdvanceCollectOrOpenReader() {
        assertExplorePosition(1)
        let body = app.buttons["prototype.explore.read"]
        XCTAssertTrue(body.waitForExistence(timeout: 3))
        XCTAssertTrue(body.isHittable)

        let shortStart = body.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5))
        let shortEnd = body.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
        shortStart.press(forDuration: 0.05, thenDragTo: shortEnd)
        assertExplorePosition(1)
        XCTAssertTrue(app.navigationBars["Explore"].exists)
        XCTAssertFalse(app.navigationBars["Note"].exists, "A short drag must not also activate the body tap")
        XCTAssertFalse(exploreElement("collected").exists, "A short drag must not collect the card")

        let verticalStart = body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let verticalEnd = body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        verticalStart.press(forDuration: 0.05, thenDragTo: verticalEnd)
        assertExplorePosition(1)
        XCTAssertTrue(app.navigationBars["Explore"].exists)
        XCTAssertFalse(app.navigationBars["Note"].exists, "A vertical drag must remain a scroll rather than opening the reader")
        XCTAssertFalse(exploreElement("collected").exists, "Vertical movement must not collect the card")
    }

    private func exploreElement(_ suffix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "prototype.explore.\(suffix)").firstMatch
    }

    private func assertExplorePosition(_ index: Int, file: StaticString = #filePath, line: UInt = #line) {
        let position = exploreElement("position")
        let found = position.waitForExistence(timeout: 5)
        if !found { print("Explore position missing after interaction: \(app.debugDescription)") }
        XCTAssertTrue(found, file: file, line: line)
        let expected = NSPredicate(format: "label BEGINSWITH %@", "\(index) /")
        let updated = XCTNSPredicateExpectation(predicate: expected, object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 4), .completed,
                       "Expected card \(index), found \(position.label)", file: file, line: line)
    }

    private func swipeExploreCard(right: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let body = app.buttons["prototype.explore.read"]
        XCTAssertTrue(body.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertTrue(body.isHittable, file: file, line: line)
        let start = body.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.15 : 0.85, dy: 0.5))
        let end = body.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.85 : 0.15, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

}
