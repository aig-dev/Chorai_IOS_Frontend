import Foundation
import XCTest

/// Cross-module integration guards: these SwiftUI callers are outside the macOS package target.
final class DiscoveryNativeMenuIntegrationTests: XCTestCase {
    func testSparkMenuPreparationCannotOpenACompetingOverlay() throws {
        let view = try source("ArcNote/CoreFlow/SparkContinuationViews.swift")
        let preparation = try section("private func openMenu(_ card: FlowCard)", until: "private struct SparkChainRail", in: view)
        XCTAssertTrue(preparation.contains("guard allowsNativeMenuPresentation else"))
        XCTAssertTrue(preparation.contains("showsOfflineFixtureNotice = true"))
        XCTAssertTrue(preparation.contains("currentMenuCard = card.asUserCard"))
        XCTAssertFalse(preparation.contains("showPopupMenu = true"), "Preparing a system menu must not present the old action overlay as well")
        XCTAssertTrue(view.contains("if allowsNativeMenuPresentation {\n            NativeCardActionsMenu("))
    }

    func testMenuOnlyFixtureRequiresLocalPreviewAndCannotEnableOrdinaryNetworkNavigation() throws {
        let view = try source("ArcNote/CoreFlow/SparkContinuationViews.swift")
        let policy = try section("private var allowsNativeMenuPresentation", until: "var body: some View", in: view)
        XCTAssertTrue(policy.contains("#if DEBUG"))
        XCTAssertTrue(policy.contains("usesOfflineFixture\n            && LocalDevelopmentPreview.isEnabled"))
        XCTAssertTrue(policy.contains("--ui-test-spark-native-menus"))
        for action in ["openDetail(_ cardID: String)", "openAuthor(_ authorID: String)"] {
            XCTAssertTrue(view.contains("private func \(action) {\n        guard allowsNetworkNavigation else {"))
        }
        let networkPolicy = try section("private var allowsNetworkNavigation", until: "private var allowsNativeMenuPresentation", in: view)
        XCTAssertTrue(networkPolicy.contains("!usesOfflineFixture"))
        XCTAssertFalse(networkPolicy.contains("--ui-test-spark-native-menus"))
    }

    func testSparkResultAndHeaderKeepTheSameOwnerAndContinuationPolicy() throws {
        let view = try source("ArcNote/CoreFlow/SparkContinuationViews.swift")
        let header = try section("private func headerMenu", until: "private var sourceStrip", in: view)
        let result = try section("private var resultMenu", until: "private var isSparkFavoriteTipVisible", in: view)
        for menu in [header, result] {
            XCTAssertTrue(menu.contains("? .grid3x3 : .grid3x2"), "Native presentation must retain the existing owner/result action matrix")
            XCTAssertTrue(menu.contains("onPrepare:"))
            XCTAssertTrue(menu.contains("onSpark:"), "Spark must continue the current session, not create a second generic Spark route")
        }
        XCTAssertTrue(header.contains("onSpark: store.sparkCurrentDeeper"))
        XCTAssertTrue(result.contains("onSpark: onSparkDeeper"))
        XCTAssertTrue(view.contains("isMenuCardOwned: result.card.isOwner || result.card.author?.id == actorID"))
    }

    func testExploreSearchSuppliesActualCardWithoutOpeningTheLegacyOverlay() throws {
        let explore = try source("ArcNote/ExploreView.swift")
        let search = try section("private var searchContent", until: "private func performSearch", in: explore)
        XCTAssertTrue(search.contains("menuCardData: convertCardToUserCard(displayCard)"))
        XCTAssertTrue(search.contains("displayCard.isOwner ?? isOwnedByCurrentUser(ownerId: displayCard.ownerActorId)"))
        let result = try section("private struct ExploreSearchResultCard", until: "private struct TagView", in: explore)
        XCTAssertTrue(result.contains("NativeCardActionsMenu(cardData: menuCardData, layout: .grid2x2, isOwnCard: isOwner)"))
        XCTAssertFalse(result.contains(".popupMenu("))
        let tabs = try source("ArcNote/TabBarView.swift")
        let host = try section("private func tabNavigationRoot", until: "var body: some View", in: tabs)
        XCTAssertTrue(host.contains(".popupMenu("))
        XCTAssertTrue(tabs.contains("tabNavigationRoot(.flow)"))
    }

    private func section(_ start: String, until end: String, in source: String) throws -> String {
        let lower = try XCTUnwrap(source.range(of: start))
        let upper = try XCTUnwrap(source.range(of: end, range: lower.upperBound..<source.endIndex))
        return String(source[lower.lowerBound..<upper.lowerBound])
    }

    private func source(_ path: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
