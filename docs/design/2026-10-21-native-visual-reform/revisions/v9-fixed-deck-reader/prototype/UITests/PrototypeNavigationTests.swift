import XCTest

@MainActor
final class PrototypeNavigationTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.chorai.nativeprototype.v6")
        app.launchArguments = ["--screen", "explore", "--appearance", "light"]
        app.launch()
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            print("UI failure source diagnostics:\n\(app.debugDescription)")
            let source = XCTAttachment(string: app.debugDescription)
            source.name = "Native UI hierarchy at failure"
            source.lifetime = .keepAlways
            add(source)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Native UI at failure"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        try super.tearDownWithError()
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
        chooseNoteAction("Skip note")
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
        swipeExploreCard(right: false)
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

    func testMenuCollectionFallbackUpdatesHomeWithoutAdvancingCard() {
        assertExplorePosition(1)
        XCTAssertFalse(exploreElement("collected").exists)
        chooseNoteAction("Collect sample")
        assertExplorePosition(1)
        XCTAssertTrue(exploreElement("collected").waitForExistence(timeout: 3))

        app.tabBars.buttons["Home"].tap()
        app.buttons["Collect"].tap()
        let collectedMira = app.buttons.matching(identifier: "prototype.note.collected")
            .matching(NSPredicate(format: "label CONTAINS %@", "Attention is a kind of generosity.")).firstMatch
        XCTAssertTrue(collectedMira.waitForExistence(timeout: 3), "The menu fallback must add the note to Home Collect")

        app.tabBars.buttons["Explore"].tap()
        assertExplorePosition(1)
        chooseNoteAction("Remove from collection")
        assertExplorePosition(1)
        XCTAssertFalse(exploreElement("collected").exists)
        app.tabBars.buttons["Home"].tap()
        XCTAssertFalse(collectedMira.exists, "Removing via the menu must update Home Collect")
    }

    func testAppearanceChangesPreserveBrowsingHistoryAndCollection() {
        assertExplorePosition(1)
        swipeExploreCard(right: false)
        assertExplorePosition(2)
        XCTAssertTrue(exploreElement("collected").exists)

        app.buttons["Open menu"].tap()
        XCTAssertTrue(app.navigationBars["Your space"].waitForExistence(timeout: 3))
        chooseReviewOption("Dark")
        app.navigationBars["Your space"].buttons["Done"].tap()

        assertExplorePosition(2)
        XCTAssertTrue(exploreElement("collected").exists, "Review appearance changes must preserve collection membership")
        app.buttons["prototype.explore.previous"].tap()
        assertExplorePosition(1)
        XCTAssertTrue(exploreElement("history").exists, "Changing review controls must not reset previous-card history")
        XCTAssertFalse(exploreElement("collected").exists, "Changing appearance must not collect previously skipped content")
        app.buttons["prototype.explore.resume"].tap()
        assertExplorePosition(2)
        XCTAssertFalse(exploreElement("history").exists)
        XCTAssertTrue(exploreElement("collected").exists)
    }

    func testAllRichCardKindsOpenAndReturnToTheirPosition() {
        let kinds = ["photo", "essay", "quote", "checklist", "code", "reference", "comparison", "short"]
        for (index, kind) in kinds.enumerated() {
            app.launchArguments = ["--screen", "explore", "--appearance", index.isMultiple(of: 2) ? "light" : "dark", "--palette", "original", "--card", kind]
            app.launch()
            assertExplorePosition(index + 1)
            let body = app.buttons["prototype.explore.read"]
            XCTAssertTrue(body.waitForExistence(timeout: 3), "Missing content for \(kind)")
            XCTAssertTrue(body.isHittable, "Content must be tappable for \(kind)")
            let window = app.windows.firstMatch.frame
            XCTAssertGreaterThanOrEqual(body.frame.minX, window.minX + 16, kind)
            XCTAssertLessThanOrEqual(body.frame.maxX, window.maxX - 16, kind)
            XCTAssertTrue(app.buttons["prototype.explore.more"].isHittable, kind)
            body.tap()
            let reader = app.navigationBars["Note"]
            XCTAssertTrue(reader.waitForExistence(timeout: 3), "Full reader should open for \(kind)")
            XCTAssertTrue(app.descendants(matching: .any)["prototype.reader.rich"].firstMatch.exists, "Full content should remain available for \(kind)")
            reader.buttons.firstMatch.tap()
            assertExplorePosition(index + 1)
        }
    }

    func testModeTogglePreservesSwipePositionAndUnreadHistory() {
        assertExplorePosition(1)
        chooseNoteAction("Skip note")
        assertExplorePosition(2)
        chooseNoteAction("Skip note")
        assertExplorePosition(3)
        app.buttons["prototype.explore.previous"].tap()
        assertExplorePosition(2)
        XCTAssertTrue(exploreElement("history").exists)

        setGridMode(true)
        let photo = app.buttons["prototype.grid.photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 3), "Grid must expose the same first note")
        XCTAssertTrue(photo.isHittable)
        XCTAssertFalse(app.buttons["prototype.explore.read"].exists, "The hidden Flow must not remain in the accessibility tree")
        setGridMode(false)
        assertExplorePosition(2)
        XCTAssertTrue(exploreElement("history").exists, "Grid browsing must retain the revisited Flow position")
        XCTAssertTrue(exploreElement("collected").exists, "Leo must remain collected across the mode change")
        app.buttons["prototype.explore.resume"].tap()
        assertExplorePosition(3)
        XCTAssertFalse(exploreElement("history").exists, "Mode changes must not reset the unread frontier")
    }

    func testGridCollectionAndReaderShareFlowState() {
        launchGrid()
        let photo = app.buttons["prototype.grid.photo"]
        let collect = app.buttons["prototype.grid.collect.photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 3))
        XCTAssertTrue(collect.isHittable, "The top photo collection button must be directly reachable")
        XCTAssertEqual(collect.value as? String, "Not collected")
        collect.tap()
        XCTAssertEqual(collect.value as? String, "Collected")
        photo.tap()
        returnFromReader()
        XCTAssertTrue(photo.waitForExistence(timeout: 3))
        XCTAssertEqual(collect.value as? String, "Collected", "Opening the note must preserve its Grid collection state")

        setGridMode(false)
        assertExplorePosition(1)
        XCTAssertTrue(exploreElement("collected").exists, "Grid collection must be shared with Flow")
        chooseNoteAction("Remove from collection")
        XCTAssertFalse(exploreElement("collected").exists)
        setGridMode(true)
        XCTAssertTrue(collect.waitForExistence(timeout: 3))
        XCTAssertEqual(collect.value as? String, "Not collected", "Removing in Flow must update the Grid bookmark")
    }

    func testGridReaderAndModeTogglePreserveScrollPosition() {
        launchGrid()
        let reference = app.buttons["prototype.grid.reference"]
        scrollGridToReveal(reference)
        let initialY = reference.frame.minY
        XCTAssertFalse(app.buttons["prototype.grid.photo"].isHittable, "The test must first leave the top of the Grid")
        reference.tap()
        let richReader = app.descendants(matching: .any)["prototype.reader.rich"].firstMatch
        XCTAssertTrue(richReader.waitForExistence(timeout: 3), "A lower Grid tile must open the full reader")
        returnFromReader()
        XCTAssertTrue(reference.waitForExistence(timeout: 3))
        XCTAssertTrue(reference.isHittable, "Returning must reveal the same lower tile without another scroll")
        XCTAssertEqual(reference.frame.minY, initialY, accuracy: 36, "Reader return must preserve approximate Grid offset")

        setGridMode(false)
        assertExplorePosition(1)
        setGridMode(true)
        XCTAssertTrue(reference.waitForExistence(timeout: 3))
        XCTAssertTrue(reference.isHittable, "Switching back must preserve the lower Grid position")
        XCTAssertEqual(reference.frame.minY, initialY, accuracy: 36, "Mode toggling must preserve approximate Grid offset")
        XCTAssertFalse(app.buttons["prototype.grid.photo"].isHittable, "Mode toggling must not silently reset Grid to the top")
    }

    func testNoteActionMenusRespectOwnership() {
        assertExplorePosition(1)
        let more = app.buttons["prototype.explore.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        more.tap()
        XCTAssertTrue(app.buttons["Report"].waitForExistence(timeout: 3), "Another author’s Explore note needs Report")
        XCTAssertTrue(app.buttons["Link"].exists)
        XCTAssertFalse(app.buttons["Share"].exists, "Another author’s Explore menu must not expose owner Share")
        app.buttons["View"].tap()
        returnFromReader()

        app.tabBars.buttons["Home"].tap()
        let notesScope = app.buttons["Notes"]
        XCTAssertTrue(notesScope.waitForExistence(timeout: 3))
        notesScope.tap()
        let owned = app.buttons["prototype.note.owned"].firstMatch
        XCTAssertTrue(owned.waitForExistence(timeout: 3))
        XCTAssertTrue(owned.isHittable)
        owned.press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 3), "An owned note needs Share in its context menu")
        XCTAssertTrue(app.buttons["Link"].exists)
        XCTAssertTrue(app.buttons["Edit"].exists)
        XCTAssertFalse(app.buttons["Report"].exists, "An owned note must not offer reporting itself")
    }

    func testDesignScreensLightAndDark() {
        for mode in ["light", "dark"] {
            app.launchArguments = ["--screen", "explore", "--appearance", mode]
            app.launch()
            assertExplorePosition(1)
            captureDesign("flow-\(mode)")
            setGridMode(true)
            let photo = app.buttons["prototype.grid.photo"]
            XCTAssertTrue(photo.waitForExistence(timeout: 3))
            let essay = app.buttons["prototype.grid.essay"]
            XCTAssertLessThanOrEqual(photo.frame.maxX, essay.frame.minX - 8, "Grid photo must stay inside its own column")
            captureDesign("grid-\(mode)")
            photo.tap()
            XCTAssertTrue(app.navigationBars["Note"].waitForExistence(timeout: 3))
            captureDesign("reader-\(mode)")
            returnFromReader()
            scrollGridToReveal(app.buttons["prototype.grid.reference"])
            captureDesign("grid-lower-\(mode)")
        }
    }

    func testOfflineActionFormsAndDesignCaptures() {
        assertExplorePosition(1)
        app.buttons["prototype.explore.more"].tap()
        XCTAssertTrue(app.buttons["Report"].waitForExistence(timeout: 3))
        captureDesign("menu-light")
        app.buttons["Report"].tap()
        XCTAssertTrue(app.navigationBars["Report"].waitForExistence(timeout: 3))
        let preview = app.buttons["prototype.report.save-draft"]
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        XCTAssertTrue(app.descendants(matching: .any)["prototype.report.saved"].firstMatch.waitForExistence(timeout: 3))
        captureDesign("report-light")
        app.buttons["prototype.note-action.close"].tap()
        chooseNoteAction("Link")
        XCTAssertTrue(app.navigationBars["Link"].waitForExistence(timeout: 3))
        let create = app.buttons["prototype.link.create"]
        XCTAssertFalse(create.isEnabled)
        app.buttons.matching(identifier: "prototype.link.choice").firstMatch.tap()
        XCTAssertTrue(create.isEnabled)
        create.tap()
        XCTAssertTrue(app.descendants(matching: .any)["prototype.link.preview"].firstMatch.waitForExistence(timeout: 3))
        captureDesign("link-light")
        app.buttons["prototype.note-action.close"].tap()
        app.tabBars.buttons["Home"].tap()
        let owned = app.buttons["prototype.note.owned"].firstMatch
        XCTAssertTrue(owned.waitForExistence(timeout: 3))
        owned.press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 3))
        app.buttons["Share"].tap()
        XCTAssertTrue(app.buttons["prototype.share.open"].waitForExistence(timeout: 3))
        captureDesign("share-light")
    }

    func testGridBottomAndNativeSharePresentation() {
        for mode in ["light", "dark"] {
            app.launchArguments = ["--grid", "--appearance", mode]
            app.launch()
            let comparison = app.buttons["prototype.grid.comparison"]
            scrollGridToReveal(comparison)
            XCTAssertTrue(app.buttons["prototype.grid.short"].isHittable)
            captureDesign("grid-end-\(mode)")
        }
        app.launchArguments = ["--screen", "home", "--appearance", "light"]
        app.launch()
        let owned = app.buttons["prototype.note.owned"].firstMatch
        XCTAssertTrue(owned.waitForExistence(timeout: 5))
        owned.press(forDuration: 1.1)
        app.buttons["Share"].tap()
        let share = app.buttons["prototype.share.open"]
        XCTAssertTrue(share.waitForExistence(timeout: 3))
        share.tap()
        captureDesign("system-share-light")
    }

    private func captureDesign(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "design-" + name
        image.lifetime = .keepAlways
        add(image)
    }

    private func launchGrid(file: StaticString = #filePath, line: UInt = #line) {
        app.launchArguments = ["--screen", "explore", "--appearance", "light", "--grid"]
        app.launch()
        let grid = app.scrollViews["prototype.grid.scroll"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5), "Initial Grid launch must expose its scroll view", file: file, line: line)
        XCTAssertEqual(app.buttons["prototype.explore.mode"].label, "Switch to swipe mode", file: file, line: line)
    }

    private func setGridMode(_ grid: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let toggle = app.buttons["prototype.explore.mode"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), file: file, line: line)
        let expected = grid ? "Switch to swipe mode" : "Switch to grid mode"
        if toggle.label != expected { toggle.tap() }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 3), .completed, "Native mode button must reflect its next action", file: file, line: line)
        if grid {
            XCTAssertTrue(app.scrollViews["prototype.grid.scroll"].waitForExistence(timeout: 3), file: file, line: line)
        }
    }

    private func returnFromReader(file: StaticString = #filePath, line: UInt = #line) {
        let reader = app.navigationBars["Note"]
        XCTAssertTrue(reader.waitForExistence(timeout: 3), "The full note reader should be open", file: file, line: line)
        reader.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 3), "Back must return to Explore", file: file, line: line)
    }

    private func scrollGridToReveal(_ tile: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let grid = app.scrollViews["prototype.grid.scroll"]
        XCTAssertTrue(grid.waitForExistence(timeout: 3), file: file, line: line)
        for _ in 0..<8 {
            let top = max(grid.frame.minY, app.navigationBars["Explore"].frame.maxY) + 6
            let bottom = min(grid.frame.maxY, app.tabBars.firstMatch.frame.minY) - 6
            let availableHeight = bottom - top
            let centerY = (top + bottom) / 2
            let fits = tile.exists && tile.frame.height <= availableHeight
            let revealed = tile.exists && (fits
                ? tile.frame.minY >= top && tile.frame.maxY <= bottom
                : tile.frame.minY < bottom && tile.frame.maxY > top)
            if tile.exists && tile.isHittable && revealed { break }

            // Center the target through short, held drags rather than inertial full-page swipes.
            // Coordinates come from the visible scroll/navigation bounds, not a device-specific point.
            let distance = tile.exists ? tile.frame.midY - centerY : CGFloat(200)
            let maximumTravel = min(CGFloat(200), max(CGFloat(1), availableHeight / 2 - 24))
            let travel = min(maximumTravel, max(-maximumTravel, distance))
            let origin = grid.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: grid.frame.width / 2, dy: centerY - grid.frame.minY))
            let end = origin.withOffset(CGVector(dx: grid.frame.width / 2, dy: centerY - grid.frame.minY - travel))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.25)
        }
        XCTAssertTrue(tile.exists && tile.isHittable, "The requested lower Grid tile must be reachable", file: file, line: line)
        let visibleTop = max(grid.frame.minY, app.navigationBars["Explore"].frame.maxY)
        let visibleBottom = min(grid.frame.maxY, app.tabBars.firstMatch.frame.minY)
        if tile.frame.height <= visibleBottom - visibleTop {
            XCTAssertGreaterThanOrEqual(tile.frame.minY, visibleTop, file: file, line: line)
            XCTAssertLessThanOrEqual(tile.frame.maxY, visibleBottom, file: file, line: line)
        } else {
            XCTAssertLessThan(tile.frame.minY, visibleBottom, file: file, line: line)
            XCTAssertGreaterThan(tile.frame.maxY, visibleTop, file: file, line: line)
        }
    }

    private func chooseReviewOption(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        func option() -> XCUIElement {
            let button = app.buttons[title].firstMatch
            return button.exists ? button : app.staticTexts[title].firstMatch
        }
        var choice = option()
        for _ in 0..<3 {
            if choice.exists && choice.isHittable { break }
            app.swipeUp()
            choice = option()
        }
        XCTAssertTrue(choice.exists && choice.isHittable, "Review option \(title) should be reachable in the form", file: file, line: line)
        choice.tap()
    }

    private func chooseNoteAction(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let more = app.buttons["prototype.explore.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 3), file: file, line: line)
        print("Before note menu tap: frame=\(more.frame), hittable=\(more.isHittable), enabled=\(more.isEnabled)")
        more.tap()
        let action = app.buttons[title]
        let appeared = action.waitForExistence(timeout: 3)
        if !appeared {
            print("Missing note menu action \(title); More frame: \(more.frame)")
            print(app.debugDescription)
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.lifetime = .keepAlways
            add(capture)
        }
        XCTAssertTrue(appeared, file: file, line: line)
        action.tap()
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
