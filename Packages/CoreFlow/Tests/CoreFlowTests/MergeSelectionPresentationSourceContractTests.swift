import Foundation
import XCTest

final class MergeSelectionPresentationSourceContractTests: XCTestCase {
    func testMergeSelectionUsesOneSafeAreaPrimaryAction() throws {
        let lifecycle = try source(at: "ArcNote/CoreFlow/MergeLifecycleViews.swift")
        let cards = try source(at: "ArcNote/MergeSelectionCards.swift")

        XCTAssertTrue(lifecycle.contains("MergeSelectionPrimaryAction("))
        XCTAssertTrue(lifecycle.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(lifecycle.contains("count == 1 ? \"Merge 1 card\""))
        XCTAssertTrue(lifecycle.contains("\"Merge \\(count) cards\""))
        XCTAssertTrue(lifecycle.contains(".frame(minHeight: 56)"))
        XCTAssertTrue(lifecycle.contains("Label(\"Create Merge\", systemImage: \"sparkles\")"))
        XCTAssertTrue(lifecycle.contains("Text(\"2–8 sources\")"))
        XCTAssertTrue(lifecycle.contains(".accessibilityIdentifier(\"merge.action\")"))
        XCTAssertTrue(lifecycle.contains("MergeSelectionActionDockSurface()"))
        XCTAssertFalse(lifecycle.contains("Color.black.opacity(0.22)"))
        XCTAssertFalse(lifecycle.contains("MergeSelectionActionBar"))
        XCTAssertFalse(lifecycle.contains("Text(\"Selected notes\")"))
        XCTAssertTrue(cards.contains("struct MergeCardView: View"))
        XCTAssertTrue(cards.contains("LibraryCardBackgroundSurface("))
        XCTAssertTrue(cards.contains("LibraryCardContentPreview("))
        XCTAssertTrue(cards.contains("isSelected ? \"checkmark.circle.fill\" : \"circle\""))
    }

    func testVisualFixtureCanRenderARealCustomBackground() throws {
        let lifecycle = try source(at: "ArcNote/CoreFlow/MergeLifecycleViews.swift")

        XCTAssertTrue(
            lifecycle.contains("CHORAI_UI_TEST_MERGE_BACKGROUND_URL")
        )
        XCTAssertTrue(
            lifecycle.contains("backgroundMediaRef: customBackgroundMediaRef")
        )
    }

    func testFidelityFixtureUsesTheProductionSelectionWithOfflineDependencies() throws {
        let lifecycle = try source(at: "ArcNote/CoreFlow/MergeLifecycleViews.swift")
        let app = try source(at: "ArcNote/ArcNoteApp.swift")
        XCTAssertTrue(app.contains("--ui-test-merge-fidelity"))
        XCTAssertTrue(app.contains("MergeSelectionFidelityFixtureScreen()"))
        let routeStart = try XCTUnwrap(app.range(of: "private var rootContent: some View"))
        let routeEnd = try XCTUnwrap(app.range(of: "private var productContent: some View", range: routeStart.upperBound..<app.endIndex))
        XCTAssertFalse(app[routeStart.lowerBound..<routeEnd.lowerBound].contains(".globalMergeTaskPortal("), "The offline fixture must not activate persisted actor tasks")
        XCTAssertTrue(lifecycle.contains("network = nil\n        anchorCard = fixtureAnchor"))
        XCTAssertTrue(lifecycle.contains("struct MergeSelectionVisualFixtureScreen"), "Keep the existing behavior fixture stable")
        let start = try XCTUnwrap(lifecycle.range(of: "struct MergeSelectionFidelityFixtureScreen"))
        let end = try XCTUnwrap(lifecycle.range(of: "struct MergeSelectionVisualFixtureScreen", range: start.upperBound..<lifecycle.endIndex))
        let fixture = String(lifecycle[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(fixture.contains("MergeLifecycleView("))
        XCTAssertTrue(fixture.contains("MergeSessionStore("))
        XCTAssertTrue(fixture.contains("MergeArtifactFixtureService("))
        XCTAssertTrue(fixture.contains("MergeCandidateStore(fixtureAnchor:"))
        XCTAssertTrue(fixture.contains("resumePersistedSession: false"))
        XCTAssertFalse(fixture.contains("NetworkCoreMergeService"))
        XCTAssertFalse(fixture.contains("Text(\"Bring a few"), "The screenshot fixture must not duplicate the production layout")
    }

    func testArtifactFixtureDoesNotReintroduceTheRetiredInsetOverlay() throws {
        let lifecycle = try source(at: "ArcNote/CoreFlow/MergeLifecycleViews.swift")
        let start = try XCTUnwrap(lifecycle.range(of: "struct MergeArtifactVisualFixtureScreen"))
        let end = try XCTUnwrap(lifecycle.range(of: "private enum MergeArtifactFixtureFactory", range: start.upperBound..<lifecycle.endIndex))
        let fixture = String(lifecycle[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(fixture.contains("MergeArtifactEditorHost("))
        XCTAssertTrue(fixture.contains("ChoraiTheme.background"))
        XCTAssertFalse(fixture.contains("Color.black.opacity(0.58)"))
        XCTAssertFalse(fixture.contains(".adaptiveContentGutter()"))
        XCTAssertFalse(fixture.contains(".padding(.vertical, 18)"))
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
