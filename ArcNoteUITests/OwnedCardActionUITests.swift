import XCTest

/// Exercises the production shared menu without Home, authentication, or a backend.
/// The DEBUG-only route injects a deterministic in-memory action service.
final class OwnedCardActionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-test-owned-card-actions"]
        app.launch()
        XCTAssertTrue(element("owned.fixture.offline").waitForExistence(timeout: 10))
    }

    func testRemoveCancelMakesNoRequestWithoutHome() {
        choose("remove", card: "A")
        XCTAssertTrue(app.buttons["card-action.remove.confirm"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(element("owned.fixture.requests").label, "0")
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists { cancel.tap() }
        else {
            let dismissRegion = app.otherElements["PopoverDismissRegion"].firstMatch
            XCTAssertTrue(dismissRegion.waitForExistence(timeout: 3))
            dismissRegion.tap()
        }
        waitUntilGone(app.buttons["card-action.remove.confirm"].firstMatch)
        let requestArrived = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", "0"), object: element("owned.fixture.requests")
        )
        requestArrived.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [requestArrived], timeout: 0.5), .completed)
        XCTAssertTrue(app.buttons["owned.fixture.menu.A"].exists)
        XCTAssertTrue(app.buttons["owned.fixture.menu.B"].exists)
    }

    func testRemoveFailureRetryKeepsTheExactCardWithoutHome() {
        choose("remove", card: "B")
        XCTAssertTrue(app.buttons["card-action.remove.confirm"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["card-action.remove.confirm"].firstMatch.tap()
        let retry = app.buttons["card-action.retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        assertText("owned.fixture.requests", equals: "1")
        XCTAssertTrue(element("owned.fixture.state.B").exists, "A failed remove keeps its original card")
        capture("owned-remove-retry")
        retry.tap()
        waitUntilGone(app.buttons["owned.fixture.menu.B"])
        assertText("owned.fixture.requests", equals: "2")
        assertText("owned.fixture.history", equals: "B:remove\nB:remove")
        XCTAssertTrue(app.buttons["owned.fixture.menu.A"].exists, "Retry must not remove the other card")
    }

    func testRepeatedVisibilityAndPinFollowServiceReceiptsWithoutHome() {
        app.buttons["owned.fixture.keep-private"].tap()
        choose("public", card: "A")
        assertText("owned.fixture.requests", equals: "1")
        waitUntilGone(element("card-action.progress"))
        assertText("owned.fixture.state.A", equals: "Private, Unpinned")
        // The service deliberately returned private despite a public request.
        // The next menu must still offer Public and send true again.
        choose("public", card: "A")
        assertText("owned.fixture.state.A", equals: "Public, Unpinned")
        choose("private", card: "A")
        assertText("owned.fixture.state.A", equals: "Private, Unpinned")
        choose("pin", card: "A")
        assertText("owned.fixture.state.A", equals: "Private, Pinned")
        choose("unpin", card: "A")
        assertText("owned.fixture.state.A", equals: "Private, Unpinned")
        assertText("owned.fixture.requests", equals: "5")
        assertText("owned.fixture.history", equals: "A:public:true\nA:public:true\nA:public:false\nA:pin:true\nA:pin:false")
        capture("owned-confirmed-toggles")
    }

    func testFreshEditReceiptReplacesPreviouslyCommittedMenuStates() {
        choose("public", card: "A")
        assertText("owned.fixture.state.A", equals: "Public, Unpinned")
        choose("pin", card: "A")
        assertText("owned.fixture.state.A", equals: "Public, Pinned")
        app.buttons["owned.fixture.external-edit"].tap()
        assertText("owned.fixture.state.A", equals: "Private, Unpinned")
        assertText("owned.fixture.cache.A", equals: "Private, Unpinned")
        XCTAssertEqual(element("owned.fixture.cache.A").value as? String, "3")
        choose("public", card: "A")
        assertText("owned.fixture.state.A", equals: "Public, Unpinned")
        choose("pin", card: "A")
        assertText("owned.fixture.state.A", equals: "Public, Pinned")
        assertText("owned.fixture.requests", equals: "4")
        assertText("owned.fixture.history", equals: "A:public:true\nA:pin:true\nA:public:true\nA:pin:true")
    }

    private func choose(_ action: String, card: String) {
        let menu = app.buttons["owned.fixture.menu.\(card)"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        menu.tap()
        let item = app.buttons["popup-menu.item.\(action)"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertText(_ identifier: String, equals value: String, file: StaticString = #filePath, line: UInt = #line) {
        let text = element(identifier)
        XCTAssertTrue(text.waitForExistence(timeout: 5), file: file, line: line)
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: text)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed, file: file, line: line)
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
