import XCTest

/// Narrow V8 interaction coverage. Level choices are preview state, not earned growth.
@MainActor
final class CardLevelJourneyTests: XCTestCase {
    private var app: XCUIApplication!
    private let levels: [(key: String, name: String)] = [
        ("basic", "Basic"), ("notable", "Notable"), ("valuable", "Valuable"),
        ("significant", "Significant"), ("exceptional", "Exceptional"), ("definitive", "Definitive")
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.chorai.nativeprototype.v8")
    }

    override func tearDownWithError() throws {
        if let app, (testRun?.failureCount ?? 0) > 0 {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "V8 card level hierarchy at failure"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "V8 card level screen at failure"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        app?.terminate()
        try super.tearDownWithError()
    }

    func testNativeLevelGuideNamesAllSixLevelsAndChoosingPreviewDoesNotCreateContent() {
        launch(step: "basic")
        XCTAssertTrue(element("journey.levels.grade.basic").waitForExistence(timeout: 5))
        tap(button("journey.levels.about"))

        for level in levels {
            let row = button("journey.levels.select.\(level.key)")
            reveal(row)
            XCTAssertTrue(row.exists, "The native guide must include \(level.name)")
            XCTAssertTrue(accessibleText(row).contains(level.name), "The guide must name \(level.name), not just show an ornament")
        }

        tap(button("journey.levels.select.exceptional"))
        XCTAssertTrue(element("journey.levels.grade.exceptional").waitForExistence(timeout: 5))
        XCTAssertFalse(button("journey.levels.guide.close").exists,
                       "Selecting a guide row should return to the card preview")
        tap(button("journey.levels.close"))
        assertLabCount("journey.lab.notes", equals: 2)
        assertLabCount("journey.lab.collected", equals: 1)

        // Previewing a tier must not rewrite the saved sample body either.
        tap(app.buttons["journey.lab.workspace"].firstMatch)
        tap(app.tabBars.buttons["Home"])
        tap(app.buttons["Notes"].firstMatch)
        let original = app.buttons.matching(identifier: "prototype.note.owned")
            .matching(NSPredicate(format: "label CONTAINS %@", "Some ideas need a little room.")).firstMatch
        tap(original)
        let editor = app.textViews["prototype.editor.body"]
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        XCTAssertEqual(editor.value as? String, "Some ideas need a little room.\n\nI used to think a good note was a finished thought. Now I think it is a place to return to. A sentence, a question, something noticed on the way home.\n\nWhat if we leave the edges open? Give an idea enough space to meet another one. Let the connection arrive before the conclusion.\n\nToday, I’m keeping the unfinished things.")
    }

    func testLevelGridReaderReturnsToTheSameCardWithoutChangingCollection() {
        launch(step: "grid", appearance: "dark")
        let card = button("journey.levels.open.basic")
        reveal(card)
        XCTAssertTrue(card.exists)
        let collection = button("journey.levels.collect.basic")
        reveal(collection)
        let beforeCollection = collection.label
        XCTAssertTrue(["Collect", "Collected"].contains(beforeCollection),
                      "Collection must expose its current state in the button label")
        reveal(card)
        let beforeY = card.frame.minY
        tap(card)
        XCTAssertTrue(element("journey.levels.reader").waitForExistence(timeout: 4))
        assertReaderLevel("basic", name: "Basic")
        XCTAssertTrue(app.staticTexts["Mira Chen"].firstMatch.exists,
                      "The detail must retain the author of the selected Grid note")
        tap(button("journey.levels.reader.close"))
        XCTAssertTrue(card.waitForExistence(timeout: 4))
        XCTAssertTrue(card.isHittable, "Closing the reader must return to the tapped grid card")
        XCTAssertEqual(card.frame.minY, beforeY, accuracy: 36)
        XCTAssertEqual(collection.label, beforeCollection,
                       "Reading a level card must not implicitly collect or uncollect it")
    }

    func testExplicitDetailCollectionUpdatesItsGridCardAndSharedCollection() {
        launch(step: "grid")
        let collection = button("journey.levels.collect.basic")
        reveal(collection)
        XCTAssertEqual(collection.label, "Collect", "The Basic sample starts uncollected")
        tap(button("journey.levels.open.basic"))
        assertReaderLevel("basic", name: "Basic")

        let readerCollect = button("journey.levels.reader.collect")
        reveal(readerCollect)
        XCTAssertEqual(readerCollect.label, "Collect")
        tap(readerCollect)
        XCTAssertEqual(readerCollect.label, "Collected",
                       "Explicit collection should update the same note in the reader")
        tap(button("journey.levels.reader.close"))
        reveal(collection)
        XCTAssertEqual(collection.label, "Collected",
                       "Returning to Grid must retain the detail's explicit collection change")
        XCTAssertTrue(element("journey.levels.grade.basic").exists,
                      "Collection must not replace the note's displayed grade")

        tap(button("journey.levels.close"))
        assertLabCount("journey.lab.notes", equals: 2)
        assertLabCount("journey.lab.collected", equals: 2)
    }

    func testGrowthKeepsThreadStageSeparateFromItsSixDimensions() {
        launch(step: "growth")
        let stage = element("journey.levels.growth.stage")
        reveal(stage)
        XCTAssertTrue(stage.exists)
        XCTAssertTrue(accessibleText(stage).contains("Thread"))
        XCTAssertFalse(accessibleText(stage).contains("Definitive"),
                       "A character growth stage must not be presented as a content card tier")

        let dimensions: [(key: String, name: String)] = [
            ("curiosity", "Curiosity"), ("insight", "Insight"), ("creativity", "Creativity"),
            ("empathy", "Empathy"), ("judgment", "Judgment"), ("resonance", "Resonance")
        ]
        for dimension in dimensions {
            let row = element("journey.levels.growth.\(dimension.key)")
            reveal(row)
            XCTAssertTrue(row.exists, "Growth must expose \(dimension.name) separately")
            XCTAssertTrue(accessibleText(row).localizedCaseInsensitiveContains(dimension.name))
        }
        XCTAssertTrue(element("journey.levels.demo").exists,
                      "Illustrative growth must remain identified as a local sample")
        tap(button("journey.levels.close"))
        assertLabCount("journey.lab.notes", equals: 2)
        assertLabCount("journey.lab.collected", equals: 1)
    }

    private func assertReaderLevel(_ key: String, name: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let detailCard = element("journey.levels.reader.card.\(key)")
        XCTAssertTrue(detailCard.waitForExistence(timeout: 4),
                      "The selected note and tier must travel into the detail together", file: file, line: line)
        let grade = detailCard.descendants(matching: .any)
            .matching(identifier: "journey.levels.grade.\(key)").firstMatch
        XCTAssertTrue(grade.exists, "The detail must display the selected Grid tier", file: file, line: line)
        XCTAssertTrue(accessibleText(grade).contains(name),
                      "The reader must name the original card level", file: file, line: line)
    }

    private func launch(step: String, appearance: String = "light") {
        app.launchArguments = ["--journey", "levels", "--step", step, "--appearance", appearance]
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func button(_ id: String) -> XCUIElement {
        app.buttons.matching(identifier: id).firstMatch
    }

    private func accessibleText(_ target: XCUIElement) -> String {
        ([target.label, target.value as? String ?? ""] + target.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
    }

    private func reveal(_ target: XCUIElement) {
        _ = target.waitForExistence(timeout: 3)
        for _ in 0..<7 {
            if target.exists, target.isHittable { return }
            let moveTowardTop = target.exists && target.frame.midY < app.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: moveTowardTop ? 0.30 : 0.76))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: moveTowardTop ? 0.76 : 0.30))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    private func tap(_ target: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        reveal(target)
        XCTAssertTrue(target.exists, "Missing \(target.identifier)", file: file, line: line)
        XCTAssertTrue(target.isHittable, "Unreachable \(target.identifier)", file: file, line: line)
        target.tap()
    }

    private func assertLabCount(_ id: String, equals count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let row = element(id)
        XCTAssertTrue(row.waitForExistence(timeout: 5), file: file, line: line)
        let text = accessibleText(row)
        XCTAssertTrue(text.range(of: "(?<![0-9])\(count)(?![0-9])", options: .regularExpression) != nil,
                      "Expected \(count) in \(id), found \(text)", file: file, line: line)
    }
}
