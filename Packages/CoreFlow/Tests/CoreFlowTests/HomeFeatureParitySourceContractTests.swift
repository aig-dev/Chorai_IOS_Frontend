import Foundation
import XCTest

/// Guards production Home semantics against importing behavior from visual samples.
final class HomeFeatureParitySourceContractTests: XCTestCase {
    func testHomeKeepsExistingSortAndRendersRealTagsWithoutSampleCategories() throws {
        let home = try source("ArcNote/HomeView.swift")
        XCTAssertTrue(home.contains("ForEach(LibrarySortOption.allCases)"))
        XCTAssertTrue(home.contains("sortBy: descriptor.field.apiName"))
        XCTAssertTrue(home.contains("sortOrder: descriptor.order.apiName"))
        XCTAssertTrue(home.contains("ForEach(card.tags, id: \\.self)"))
        XCTAssertTrue(home.contains("ForEach(tags, id: \\.self)"))
        XCTAssertFalse(home.contains("NoteFilter"), "Writing/Ideas in the visual prototype are not production categories")
        XCTAssertFalse(home.contains("Text(\"Writing\")"))
        XCTAssertFalse(home.contains("Text(\"Ideas\")"))
    }

    func testEachLibraryCardRetainsItsOwnMoreMenuAndOwnershipActions() throws {
        let home = try source("ArcNote/HomeView.swift")
        let notes = try section("struct NotesCard: View", until: "struct HomePostCard: View", in: home)
        let collections = try section("struct HomePostCard: View", until: "// MARK: - Background Views", in: home)
        XCTAssertTrue(notes.contains("NativeCardActionsMenu(cardData: card, layout: .grid3x3, isOwnCard: true"))
        XCTAssertTrue(collections.contains("NativeCardActionsMenu(cardData: menuCardData, layout: .grid3x2, isOwnCard: false"))
        for card in [notes, collections] {
            XCTAssertTrue(card.contains(".overlay(alignment: .trailing)"))
            XCTAssertTrue(card.contains("Image(systemName: \"ellipsis\")"))
            XCTAssertTrue(card.contains(".frame(width: 44, height: 44)"))
            XCTAssertTrue(card.contains("home.card.menu."))
            XCTAssertFalse(card.contains("arrow.up.right"), "The more-menu entry must not become a navigation arrow")
        }
        let menu = try source("ArcNote/PopupMenuView.swift")
        let native = try section("var nativeMenuContent: some View", until: "private func nativeAction", in: menu)
        let owned = try section("case .grid3x3:", until: "case .grid3x2:", in: native)
        let collected = String(native[native.range(of: "case .grid3x2:")!.lowerBound...])
        for action in ["Edit", "Spark", "Merge", "Share", "Link", "Root", "Remove"] {
            XCTAssertTrue(owned.contains("nativeAction(\"\(action)\""), "Missing original owned-card action: \(action)")
        }
        XCTAssertTrue(owned.contains("(ownedState?.isPublic ?? card.isPublic) ? \"Private\" : \"Public\""))
        XCTAssertTrue(owned.contains("(ownedState?.isPinned ?? card.isPinned) ? \"Unpin\" : \"Pin\""))
        for action in ["View", "Spark", "Share", "Link", "Root", "Report"] {
            XCTAssertTrue(collected.contains("nativeAction(\"\(action)\""), "Missing original collected-card action: \(action)")
        }
        for ownerOnly in ["Edit", "Merge", "Remove", "Public", "Private", "Pin"] {
            XCTAssertFalse(collected.contains("nativeAction(\"\(ownerOnly)\""))
        }
    }

    func testCollectionCountAndRemovalRemainVisibleAndAccessible() throws {
        let home = try source("ArcNote/HomeView.swift")
        let collection = try section("struct HomePostCard: View", until: "// MARK: - Background Views", in: home)
        XCTAssertTrue(collection.contains("Label(\"\\(favoriteCount)\", systemImage: \"bookmark.fill\")"), "The original collection count was lost during visual migration")
        XCTAssertTrue(collection.contains("home.card.collection-count."))
        XCTAssertTrue(collection.contains("onUnfavorite?(cardId)"))
        XCTAssertTrue(collection.contains(".accessibilityLabel(\"Remove from collection\")"))
        XCTAssertTrue(collection.contains(".accessibilityValue(\"\\(favoriteCount) collections\")"))
    }

    func testCollectionSearchUsesTheSameNativeMenuWithoutDoublePresentation() throws {
        let home = try source("ArcNote/HomeView.swift")
        let search = try source("ArcNote/SearchView.swift")
        let preparation = try section("onShowMenu: { result in", until: "onCardTap:", in: home)
        XCTAssertTrue(preparation.contains("currentMenuCardData = result.card"))
        XCTAssertFalse(preparation.contains("showPopupMenu ="), "Native menus must not open the legacy overlay at the same time")
        let result = try section("private func resultCard", until: "private func relativeTime", in: search)
        XCTAssertTrue(result.contains("menuCardData: result.card"), "Collection search must pass the exact result and its actions to the shared card")
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
