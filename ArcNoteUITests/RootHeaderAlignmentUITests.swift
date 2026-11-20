import XCTest

/// Uses real tab roots; a pushed Chat fixture cannot detect a hidden root toolbar.
@MainActor
final class RootHeaderAlignmentUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }
    func testRealTabRootsKeepTheirTitlesAndChatActionsVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["--dev-preview"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 10))
        capture(app, "root-explore")
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))
        capture(app, "root-home")
        app.tabBars.buttons["Chat"].tap()
        let bar = app.navigationBars["Chat"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        let menu = bar.buttons["Open menu"]
        XCTAssertTrue(menu.isHittable)
        XCTAssertTrue(app.buttons["chat.search"].isHittable)
        XCTAssertFalse(bar.buttons["Back"].exists)
        XCTAssertGreaterThanOrEqual(menu.frame.width, 44)
        XCTAssertGreaterThanOrEqual(menu.frame.height, 44)
        capture(app, "root-chat")
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["side-menu.close"].waitForExistence(timeout: 5))
        app.buttons["side-menu.close"].tap()
        app.tabBars.buttons["Explore"].tap()
        app.tabBars.buttons["Chat"].tap()
        XCTAssertTrue(bar.exists)
        XCTAssertTrue(menu.isHittable)
    }

    func testSidebarDismissalPreservesEachRootViewportAndSettingsReturnsToDrawer() {
        let app = XCUIApplication()
        app.launchArguments = ["--dev-preview"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 10))
        for title in ["Explore", "Home", "Chat"] {
            app.tabBars.buttons[title].tap()
            let navigationBar = app.navigationBars[title]
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
            let beforeBar = navigationBar.frame
            let beforeTabs = app.tabBars.firstMatch.frame
            let opener = navigationBar.buttons.matching(NSPredicate(format: "label IN %@", ["Open menu", "Open sidebar"])).firstMatch
            XCTAssertTrue(opener.isHittable)
            opener.tap()
            let close = app.buttons["side-menu.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            XCTAssertTrue(close.isHittable)
            XCTAssertGreaterThanOrEqual(close.frame.width, 44)
            XCTAssertGreaterThanOrEqual(close.frame.height, 44)
            let presentation = app.descendants(matching: .any)["side-menu.presentation"].firstMatch
            XCTAssertTrue(presentation.exists)
            XCTAssertEqual(presentation.frame.minY, app.frame.minY, accuracy: 1)
            XCTAssertEqual(presentation.frame.maxY, app.frame.maxY, accuracy: 1)
            XCTAssertEqual(presentation.frame.width, app.frame.width, accuracy: 1)
            capture(app, "sidebar-open-\(title.lowercased())")
            app.buttons["side-menu.settings"].tap()
            let settings = app.navigationBars["Settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            XCTAssertFalse(close.isHittable, "The visual drawer must not cover a pushed destination")
            settings.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            XCTAssertTrue(close.isHittable, "Back must restore the drawer in the same tab")
            close.tap()
            XCTAssertTrue(opener.waitForExistence(timeout: 5))
            XCTAssertTrue(opener.isHittable)
            XCTAssertFalse(close.exists, "A closed drawer must leave no accessible controls")
            XCTAssertEqual(navigationBar.frame, beforeBar)
            XCTAssertEqual(app.tabBars.firstMatch.frame, beforeTabs)
            capture(app, "sidebar-closed-\(title.lowercased())")
        }
    }

    func testExploreAndSparkKeepNavigationWithoutPositionCounters() {
        let app = XCUIApplication()
        app.launchArguments = ["--dev-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["flow.history"].waitForExistence(timeout: 10))
        assertNoPositionCounter(app)
        app.buttons["explore.search.open"].tap()
        let input = app.textFields["explore.search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Attention\n")
        XCTAssertTrue(app.buttons["explore.search.next"].waitForExistence(timeout: 10))
        assertNoPositionCounter(app)
        capture(app, "explore-search-no-counter")
        app.terminate()
        app.launchArguments = ["--dev-preview", "--ui-test-spark-fidelity"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["spark.card.fixture-spark-nia"].firstMatch.waitForExistence(timeout: 12))
        assertNoPositionCounter(app)
        capture(app, "spark-no-counter")
    }

    private func assertNoPositionCounter(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let count = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ (of|/) [0-9]+"))
        XCTAssertEqual(count.count, 0, file: file, line: line)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
