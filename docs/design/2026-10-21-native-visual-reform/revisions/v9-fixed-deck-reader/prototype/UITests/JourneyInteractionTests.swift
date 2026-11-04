import XCTest

/// Offline interaction contracts. These assertions do not claim live AI or server persistence.
@MainActor
final class JourneyInteractionTests: XCTestCase {
    private var app: XCUIApplication!
    private let firstSparkExcerpt = "Leave a little unfinished."

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.chorai.nativeprototype.v6")
    }

    override func tearDownWithError() throws {
        if let app, (testRun?.failureCount ?? 0) > 0 {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Journey UI hierarchy at failure"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Journey screen at failure"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        app?.terminate()
        try super.tearDownWithError()
    }

    func testSparkCollectReadAndReturnPreserveTheCurrentResultAndSharedCollection() {
        launch("spark", step: "results")
        assertFirstSparkResult()
        let collect = sparkButton("journey.spark.collect", labels: ["Collect", "Collected"])
        XCTAssertEqual(collect.value as? String, "Not collected",
                       "The first result is Nia's quote, not Leo's already-collected note")
        tap(collect)
        waitForValue(collect, equals: "Collected in prototype session")

        tap(sparkButton("journey.spark.reader", labels: ["Read full note"]))
        let reader = app.navigationBars["Read"]
        XCTAssertTrue(reader.waitForExistence(timeout: 4))
        XCTAssertTrue(textBeginning(firstSparkExcerpt).exists)
        tap(reader.buttons.firstMatch)
        assertFirstSparkResult()
        waitForValue(collect, equals: "Collected in prototype session")
        XCTAssertEqual(element("journey.spark.node.1").value as? String, "Current step")

        tap(app.buttons["journey.spark.close"])
        assertLabCount("journey.lab.collected", equals: 2)
        assertLabCount("journey.lab.notes", equals: 2)
    }

    func testSparkDeeperRequiresExplicitSampleContinuationAndPreviousNodeRestoresItsResult() {
        launch("spark", step: "results", appearance: "dark")
        assertFirstSparkResult()
        tap(app.buttons["journey.spark.deepen"])
        XCTAssertTrue(element("journey.spark.loading").waitForExistence(timeout: 4))
        XCTAssertFalse(element("journey.spark.node.2").exists,
                       "A loading illustration must not automatically invent a completed result")
        XCTAssertTrue(textBeginning(firstSparkExcerpt).exists,
                      "Existing results stay in the hierarchy while deeper Spark is loading")

        tap(sparkButton("journey.spark.show-result", labels: ["Show sample result"]))
        let secondNode = app.buttons["journey.spark.node.2"]
        XCTAssertTrue(secondNode.waitForExistence(timeout: 4))
        waitForValue(secondNode, equals: "Current step")
        XCTAssertTrue(app.buttons["journey.spark.source"].label.contains(firstSparkExcerpt),
                      "The selected result becomes the next Spark's source")

        tap(app.buttons["journey.spark.node.1"])
        waitForValue(app.buttons["journey.spark.node.1"], equals: "Current step")
        assertFirstSparkResult()
        XCTAssertTrue(app.buttons["journey.spark.source"].label.contains("Attention is a kind of generosity."))
        tap(app.buttons["journey.spark.original"])
        XCTAssertTrue(app.navigationBars["Source note"].waitForExistence(timeout: 4))
        XCTAssertTrue(textBeginning("Attention is a kind of generosity.").exists)
    }

    func testSparkAppendRetryKeepsTheCurrentCardAndAddsResultsOnlyAfterExplicitContinuation() {
        launch("spark", step: "error")
        XCTAssertTrue(element("journey.spark.error").waitForExistence(timeout: 4))
        assertFirstSparkResult()
        XCTAssertTrue(app.staticTexts["1 of 4"].exists)
        tap(sparkButton("journey.spark.retry", labels: ["Retry sample"]))
        XCTAssertTrue(element("journey.spark.loading").waitForExistence(timeout: 4))
        XCTAssertTrue(textBeginning(firstSparkExcerpt).exists)
        XCTAssertTrue(app.staticTexts["1 of 4"].exists)

        tap(sparkButton("journey.spark.show-result", labels: ["Show sample result"]))
        XCTAssertTrue(app.staticTexts["1 of 6"].waitForExistence(timeout: 4))
        XCTAssertFalse(element("journey.spark.error").exists)
        assertFirstSparkResult()
        XCTAssertFalse(element("journey.spark.node.2").exists,
                       "Appending results must not create a deeper Spark node")
    }

    func testMergeMinimumSourcesBackgroundResumeAndAcceptCreateExactlyOnePrivateNote() {
        launch("merge", step: "selection")
        let create = app.buttons["journey.merge.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertEqual(element("journey.merge.count").label, "1 selected")
        XCTAssertFalse(create.isEnabled, "The fixed source alone is not a valid Merge")

        let candidate = app.buttons["journey.merge.candidate.0"]
        tap(candidate)
        waitForValue(candidate, equals: "Selected")
        XCTAssertEqual(element("journey.merge.count").label, "2 selected")
        XCTAssertTrue(create.isEnabled)
        tap(candidate)
        XCTAssertFalse(create.isEnabled, "Removing the companion source must restore the minimum guard")
        tap(candidate)
        tap(create)
        XCTAssertTrue(element("journey.merge.progress").waitForExistence(timeout: 4))
        tap(app.buttons["journey.merge.background"])
        XCTAssertTrue(app.buttons["journey.merge.resume"].waitForExistence(timeout: 4))
        tap(app.buttons["journey.merge.close"])
        assertLabCount("journey.lab.notes", equals: 2)
        tap(app.buttons["journey.lab.merge"])
        tap(app.buttons["journey.merge.resume"])
        tap(app.buttons["journey.merge.continue"])
        XCTAssertTrue(app.textViews["journey.merge.body"].waitForExistence(timeout: 4))
        tap(app.buttons["journey.merge.accept"])
        XCTAssertTrue(element("journey.merge.saved").waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Private · this app session"].exists)
        tap(app.buttons["journey.merge.close"])
        assertLabCount("journey.lab.notes", equals: 3)

        // Same original anchor, same accepted task; reviewing its ready state must not duplicate it.
        tap(app.buttons["journey.lab.merge"])
        XCTAssertTrue(element("journey.merge.saved").waitForExistence(timeout: 4))
        chooseMergePreview("Insight ready")
        XCTAssertFalse(app.buttons["journey.merge.accept"].isEnabled)
        tap(app.buttons["journey.merge.close"])
        assertLabCount("journey.lab.notes", equals: 3)

        openHome()
        let newNote = app.buttons.matching(identifier: "prototype.note.owned")
            .matching(NSPredicate(format: "label CONTAINS %@", "Some ideas grow better together.")).firstMatch
        tap(newNote)
        XCTAssertTrue(app.textViews["prototype.editor.body"].waitForExistence(timeout: 4))
        XCTAssertTrue((app.textViews["prototype.editor.body"].value as? String)?.contains("Some ideas grow better together.") == true)
        tap(app.buttons["Note privacy"])
        tap(app.buttons["Private"])
        XCTAssertEqual(app.buttons["prototype.editor.leading"].label, "Back",
                       "Selecting Private must leave the accepted note unchanged, rather than dirtying a public note")
    }

    func testMergeClosingAnEditedDraftRetainsItWithoutCreatingANote() {
        launch("merge", step: "ready", appearance: "dark")
        let body = app.textViews["journey.merge.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        let marker = " Session-retained draft check."
        append(marker, to: body)
        tap(app.buttons["journey.merge.close"])
        assertLabCount("journey.lab.notes", equals: 2)
        tap(app.buttons["journey.lab.merge"])
        XCTAssertTrue(body.waitForExistence(timeout: 4))
        XCTAssertTrue((body.value as? String)?.contains(marker) == true)
        XCTAssertTrue(app.buttons["journey.merge.accept"].isEnabled)
    }

    func testMergeDiscardRemovesOnlyTheDraftAndKeepsTheOriginalNotes() {
        launch("merge", step: "ready")
        let body = app.textViews["journey.merge.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        append(" Discard this draft only.", to: body)
        tap(app.buttons["journey.merge.discard"])
        let confirmByID = app.buttons.matching(identifier: "journey.merge.discard-confirm").firstMatch
        let confirmation = confirmByID.waitForExistence(timeout: 2) ? confirmByID : app.buttons["Discard Merge"].firstMatch
        tap(confirmation)
        XCTAssertTrue(app.staticTexts["Merge discarded"].waitForExistence(timeout: 4))
        tap(app.buttons["journey.merge.close"])
        assertLabCount("journey.lab.notes", equals: 2)
        assertLabCount("journey.lab.collected", equals: 1)

        openHome()
        XCTAssertEqual(app.buttons.matching(identifier: "prototype.note.owned").count, 2)
        XCTAssertTrue(app.buttons.matching(identifier: "prototype.note.owned")
            .matching(NSPredicate(format: "label CONTAINS %@", "Some ideas need a little room.")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(identifier: "prototype.note.owned")
            .matching(NSPredicate(format: "label CONTAINS %@", "A small ritual for noticing.")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Discard this draft only.")).firstMatch.exists)
    }

    func testMergeSyncRecoveryRetainsEditsAndDoesNotAcceptAutomatically() {
        launch("merge", step: "sync-error", appearance: "dark")
        let body = app.textViews["journey.merge.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["journey.merge.accept"].isEnabled)
        let marker = " Keep this after sample sync recovery."
        append(marker, to: body)
        tap(app.buttons["journey.merge.retry"])
        XCTAssertTrue(app.buttons["journey.merge.accept"].isEnabled)
        XCTAssertTrue((body.value as? String)?.contains(marker) == true)
        XCTAssertTrue(element("journey.merge.sync-status").label.contains("Recovery preview complete"))
        tap(app.buttons["journey.merge.close"])
        assertLabCount("journey.lab.notes", equals: 2,
                       "Recovering a draft must not create an accepted note")
    }

    func testMergeConflictKeepPreservesLocalEditsAndReloadReplacesThem() {
        launch("merge", step: "conflict")
        let body = app.textViews["journey.merge.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertTrue((body.value as? String)?.contains("My local addition:") == true)
        XCTAssertFalse(app.buttons["journey.merge.accept"].isEnabled)
        let marker = " Distinct conflict edit."
        append(marker, to: body)
        tap(app.buttons["journey.merge.keep"])
        XCTAssertTrue((body.value as? String)?.contains(marker) == true)
        XCTAssertTrue(app.buttons["journey.merge.accept"].isEnabled)

        chooseMergePreview("Version conflict")
        XCTAssertFalse(app.buttons["journey.merge.accept"].isEnabled)
        tap(app.buttons["journey.merge.reload"])
        let reloaded = body.value as? String ?? ""
        XCTAssertTrue(reloaded.contains("This alternate sample draft keeps the question open:"))
        XCTAssertFalse(reloaded.contains(marker))
        XCTAssertFalse(reloaded.contains("My local addition:"))
        XCTAssertTrue(app.buttons["journey.merge.accept"].isEnabled)
        tap(app.buttons["journey.merge.close"])
        assertLabCount("journey.lab.notes", equals: 2)
    }

    private func launch(_ journey: String, step: String, appearance: String = "light") {
        app.launchArguments = ["--journey", journey, "--step", step, "--appearance", appearance]
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func sparkButton(_ identifier: String, labels: [String]) -> XCUIElement {
        // SwiftUI propagates the parent card/state-panel identifier to its child buttons.
        // Exact visible labels retain action identity even when that happens; collection
        // includes both labels so the same query survives Collect → Collected.
        app.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", identifier, labels)).firstMatch
    }

    private func textBeginning(_ prefix: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func assertFirstSparkResult(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element("journey.spark.results").waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(textBeginning(firstSparkExcerpt).exists, file: file, line: line)
    }

    private func waitForValue(_ target: XCUIElement, equals value: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 4), .completed,
                       "Expected \(target.identifier) value \(value)", file: file, line: line)
    }

    private func tap(_ target: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Missing \(target.identifier)", file: file, line: line)
        for _ in 0..<6 where !target.isHittable {
            // Stay outside the TextEditor's horizontal bounds so this scrolls the outer page.
            let needsEarlierContent = target.frame.midY < app.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: needsEarlierContent ? 0.32 : 0.76))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: needsEarlierContent ? 0.76 : 0.32))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(target.isHittable, "Unreachable \(target.identifier), frame \(target.frame)", file: file, line: line)
        target.tap()
    }

    private func append(_ text: String, to editor: XCUIElement) {
        tap(editor)
        editor.typeText(text)
        let done = app.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 2), done.isHittable { done.tap() }
        XCTAssertTrue((editor.value as? String)?.contains(text) == true)
    }

    private func chooseMergePreview(_ title: String) {
        tap(app.buttons["journey.merge.preview"])
        tap(app.buttons[title].firstMatch)
    }

    private func assertLabCount(_ identifier: String, equals count: Int, _ message: String = "",
                                file: StaticString = #filePath, line: UInt = #line) {
        let row = element(identifier)
        XCTAssertTrue(row.waitForExistence(timeout: 5), file: file, line: line)
        // LabeledContent may expose its value as a child staticText or as the combined row value.
        let exactChild = row.staticTexts[String(count)]
        let values = ([row.label, row.value as? String ?? ""] + row.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
        let exactNumber = values.range(of: "(?<![0-9])\(count)(?![0-9])", options: .regularExpression) != nil
        XCTAssertTrue(exactChild.exists || exactNumber, "\(message) Expected \(count), found \(values)", file: file, line: line)
    }

    private func openHome() {
        tap(app.buttons["journey.lab.workspace"])
        let home = app.tabBars.buttons["Home"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.tap()
        tap(app.buttons["Notes"])
    }
}
