import XCTest

/// Exercises production search with the existing read-only Local Preview transport.
final class SearchSummaryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--dev-preview"]
        app.launch()
        let search = app.buttons["explore.search.open"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        let input = app.textFields["explore.search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Attention\n")
        ready("explore.search.surface.preview-field-note")
        let keyboardGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardGone], timeout: 5), .completed)
    }

    func testDifferentRichResultsKeepTheSameCardAndReachableActions() {
        let initialFrame = element("explore.search.surface.preview-field-note").frame
        XCTAssertGreaterThan(initialFrame.height, 200)
        for index in 0..<6 {
            let id = index == 0 ? "preview-field-note" : "preview-field-note-\(index)"
            let surface = ready("explore.search.surface.\(id)")
            let summary = ready("explore.search.summary.\(id)")
            XCTAssertEqual(surface.frame.height, initialFrame.height, accuracy: 2, "Content length must not resize the search card")
            XCTAssertEqual(surface.frame.minY, initialFrame.minY, accuracy: 2)
            XCTAssertGreaterThan(summary.frame.height, 0)
            XCTAssertGreaterThanOrEqual(summary.frame.minY, surface.frame.minY)
            XCTAssertLessThanOrEqual(summary.frame.maxY, surface.frame.maxY + 1)
            XCTAssertLessThanOrEqual(surface.frame.maxY, app.frame.maxY)
            for action in ["explore.search.menu.", "explore.search.author.", "card.favorite.", "card.like."] {
                XCTAssertTrue(app.buttons[action + id].isHittable, "A fixed summary must keep \(action) reachable")
            }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "search-summary-\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
            if index < 5 { app.buttons["explore.search.next"].tap() }
        }
        XCTAssertFalse(app.buttons["explore.search.next"].isEnabled)
        app.buttons["explore.search.previous"].tap()
        ready("explore.search.surface.preview-field-note-4")
    }

    func testSummaryGesturesDoNotHijackVerticalMovementOrChildControls() {
        let first = "preview-field-note"
        let summary = ready("explore.search.summary.\(first)")
        drag(summary, from: CGVector(dx: 0.5, dy: 0.2), to: CGVector(dx: 0.5, dy: 0.8))
        XCTAssertTrue(element("explore.search.summary.\(first)").exists)

        let tags = element("explore.search.tags.\(first)")
        if tags.exists { tags.swipeLeft() }
        XCTAssertTrue(element("explore.search.summary.\(first)").exists, "Scrolling tags must not advance a search result")

        app.buttons["explore.search.menu.\(first)"].tap()
        ready("popup-menu.item.view")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.55)).tap()
        XCTAssertTrue(element("explore.search.summary.\(first)").exists)
        app.buttons["explore.search.author.\(first)"].tap()
        ready("screen.user-profile")
        app.navigationBars.buttons.matching(identifier: "Back").firstMatch.tap()
        ready("explore.search.summary.\(first)")

        drag(summary, from: CGVector(dx: 0.85, dy: 0.5), to: CGVector(dx: 0.15, dy: 0.5))
        let second = ready("explore.search.summary.preview-field-note-1")
        drag(second, from: CGVector(dx: 0.15, dy: 0.5), to: CGVector(dx: 0.85, dy: 0.5))
        ready("explore.search.summary.\(first)")
        XCTAssertFalse(app.buttons["explore.search.previous"].isEnabled)
        summary.tap()
        ready("screen.detail.loaded")
        XCTAssertEqual(element("screen.detail.card-id").label, first)
    }

    private func drag(_ element: XCUIElement, from start: CGVector, to end: CGVector) {
        element.coordinate(withNormalizedOffset: start).press(forDuration: 0.05, thenDragTo: element.coordinate(withNormalizedOffset: end))
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    private func ready(_ id: String) -> XCUIElement {
        let target = element(id)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Missing \(id)")
        return target
    }
}
