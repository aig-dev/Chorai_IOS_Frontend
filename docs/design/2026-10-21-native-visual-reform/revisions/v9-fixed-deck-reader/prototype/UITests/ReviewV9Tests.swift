import XCTest

@MainActor final class ReviewV9Tests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.chorai.nativeprototype.v9")
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "V9 failure hierarchy"; tree.lifetime = .keepAlways; add(tree)
            shot("failure")
        }
        app.terminate()
    }
    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    func launch(_ card: String = "photo", theme: String = "light", screen: String = "explore", state: String = "rest") {
        app.terminate()
        app.launchArguments = ["--card", card, "--appearance", theme, "--screen", screen, "--state", state]
        app.launch()
        XCTAssertTrue(element(screen == "reader" ? "v9.reader" : "v9.explore.position").waitForExistence(timeout: 8))
    }
    func returnUsingNativeBack() {
        let back = app.navigationBars["Read note"].buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Explore", "Back")
        ).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "The reader must retain the system navigation back button")
        back.tap()
    }
    func expectPosition(_ label: String) {
        let position = element("v9.explore.position")
        XCTAssertTrue(position.waitForExistence(timeout: 5))
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
    }
    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "v9-" + name
        a.lifetime = .keepAlways; add(a)
    }
    func testFixedSummaryReaderHistoryAndSearch() {
        launch()
        let initial = element("v9.explore.card").frame
        let summary = element("v9.explore.summary")
        XCTAssertGreaterThan(initial.height, app.windows.firstMatch.frame.height * 0.65)
        for button in [element("v9.card.collect"), app.buttons["Like sample"], app.buttons["Comments sample"]] {
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        XCTAssertFalse(app.buttons["Previous"].exists)
        XCTAssertFalse(app.staticTexts["← Skip · Collect →"].exists)
        for offset in [CGVector(dx: 30, dy: 0), CGVector(dx: -30, dy: 0), CGVector(dx: 0, dy: 30)] {
            let start = summary.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(offset))
            XCTAssertFalse(element("v9.reader").exists, "A canceled drag must not be reinterpreted as a tap")
            expectPosition("1 / 8")
        }
        summary.swipeLeft()
        expectPosition("2 / 8")
        let essay = element("v9.explore.card").frame
        XCTAssertEqual(initial.width, essay.width, accuracy: 1)
        XCTAssertEqual(initial.height, essay.height, accuracy: 1)
        XCTAssertEqual(initial.minY, essay.minY, accuracy: 1)
        element("v9.explore.summary").tap()
        XCTAssertTrue(element("v9.reader").waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Explore"].isHittable)
        let ending = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "The point is to keep something growing.")).firstMatch
        for _ in 0..<8 where !ending.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(ending.isHittable)
        returnUsingNativeBack()
        expectPosition("2 / 8")
        element("v9.explore.summary").swipeRight()
        expectPosition("3 / 8")
        element("v9.explore.history").tap()
        let old = element("v9.history.item.photo")
        XCTAssertTrue(old.waitForExistence(timeout: 5)); old.tap()
        expectPosition("1 / 8")
        XCTAssertTrue(element("v9.resume").isHittable)
        element("v9.resume").tap()
        expectPosition("3 / 8")
        element("v9.search.open").tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("garden")
        let result = element("v9.search.result.essay")
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        XCTAssertTrue(element("v9.reader").waitForExistence(timeout: 5))
        returnUsingNativeBack()
        expectPosition("3 / 8")
    }
    func testExhaustedDeckStillOpensGridAndReader() {
        launch("short")
        element("v9.explore.summary").swipeLeft()
        XCTAssertTrue(app.staticTexts["All caught up"].waitForExistence(timeout: 5))
        element("v9.mode").tap()
        XCTAssertTrue(element("v9.grid").waitForExistence(timeout: 5), "Grid remains available after the last swipe card")
        XCTAssertFalse(app.staticTexts["All caught up"].exists)
        element("v9.mode").tap()
        XCTAssertTrue(app.staticTexts["All caught up"].waitForExistence(timeout: 5))
        element("v9.explore.history").tap()
        let recent = element("v9.history.item.short")
        XCTAssertTrue(recent.waitForExistence(timeout: 5)); recent.tap()
        element("v9.explore.summary").tap()
        XCTAssertTrue(element("v9.reader").waitForExistence(timeout: 5))
        returnUsingNativeBack()
        expectPosition("8 / 8")
    }
    func testNativeEdgeBackKeepsTheSameCard() {
        launch("essay")
        element("v9.explore.summary").tap()
        XCTAssertTrue(element("v9.reader").waitForExistence(timeout: 5))
        let window = app.windows.firstMatch
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        expectPosition("2 / 8")
        XCTAssertFalse(element("v9.reader").exists)
    }
    func testDesignCapturesAndEqualCardFramesInBothThemes() {
        for theme in ["light", "dark"] {
            var reference: CGRect?
            for card in ["photo", "essay", "quote", "checklist", "code", "reference", "comparison", "short"] {
                launch(card, theme: theme)
                let frame = element("v9.explore.card").frame
                if let reference {
                    XCTAssertEqual(frame.height, reference.height, accuracy: 1)
                    XCTAssertEqual(frame.minY, reference.minY, accuracy: 1)
                    XCTAssertEqual(frame.width, reference.width, accuracy: 1)
                } else { reference = frame }
                shot("explore-\(card)-\(theme)")
            }
            for state in ["skip", "collect", "history"] {
                launch(theme: theme, state: state)
                if state != "history" { XCTAssertTrue(element("v9.swipe.feedback").exists) }
                else { XCTAssertTrue(element("v9.history.item.photo").waitForExistence(timeout: 5)) }
                shot("explore-\(state)-\(theme)")
            }
            for card in ["photo", "essay"] {
                launch(card, theme: theme, screen: "reader")
                shot("reader-\(card)-\(theme)")
            }
        }
    }
    func testReaderDesignCapturesInBothThemes() {
        for theme in ["light", "dark"] {
            for card in ["photo", "essay"] {
                launch(card, theme: theme, screen: "reader")
                shot("reader-\(card)-\(theme)")
            }
        }
    }

    func testHomeRetainsApprovedLayoutAndEditorInBothThemes() {
        for theme in ["light", "dark"] {
            launch(theme: theme)
            app.tabBars.buttons["Home"].tap()
            let notes = app.segmentedControls.buttons["Notes"]
            XCTAssertTrue(notes.waitForExistence(timeout: 5), "Home must reuse the approved prototype, not a placeholder list")
            XCTAssertTrue(app.segmentedControls.buttons["Collect"].exists)
            XCTAssertTrue(app.buttons["Filter notes"].isHittable)
            XCTAssertTrue(app.buttons["Search library"].isHittable)
            XCTAssertTrue(element("prototype.note.new").isHittable)
            XCTAssertFalse(app.staticTexts["Your sample notes"].exists)
            shot("home-restored-\(theme)")

            element("prototype.note.owned").tap()
            XCTAssertTrue(element("prototype.editor.body").waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Note details"].isHittable)
            XCTAssertFalse(app.tabBars.buttons["Home"].isHittable)
            element("prototype.editor.leading").tap()
            XCTAssertTrue(element("prototype.note.new").waitForExistence(timeout: 5))
            element("prototype.note.new").tap()
            XCTAssertTrue(element("prototype.editor.body").waitForExistence(timeout: 5))
            XCTAssertEqual(element("prototype.editor.body").value as? String, "")
            XCTAssertFalse(app.tabBars.buttons["Home"].isHittable)
            element("prototype.editor.leading").tap()
            XCTAssertTrue(app.segmentedControls.buttons["Notes"].waitForExistence(timeout: 5))
        }
    }

    func testHomeSharesCollectionsWithExplore() {
        launch()
        element("v9.explore.summary").swipeRight()
        expectPosition("2 / 8")
        app.tabBars.buttons["Home"].tap()
        let collect = app.segmentedControls.buttons["Collect"]
        XCTAssertTrue(collect.waitForExistence(timeout: 5)); collect.tap()
        let mira = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "prototype.note.collected", "Mira Chen")).firstMatch
        XCTAssertTrue(mira.waitForExistence(timeout: 5), "The restored Home must share the current Explore session state")
        mira.tap()
        XCTAssertTrue(element("prototype.reader.rich").waitForExistence(timeout: 5))
    }
}
