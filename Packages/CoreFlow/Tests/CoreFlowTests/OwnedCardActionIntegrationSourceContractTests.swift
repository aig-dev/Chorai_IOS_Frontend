import Foundation
import XCTest

/// Cross-screen guarantees not covered by the package's action-store behavior tests.
final class OwnedCardActionIntegrationSourceContractTests: XCTestCase {
    func testHomeHandlesReceiptsAndRefreshesItsExistingSortAndSearch() throws {
        let home = try source("ArcNote/HomeView.swift")
        XCTAssertTrue(home.contains("onOwnedCardActionCommitted: handleOwnedCardActionCommit"))
        let handler = try section(home, from: "private func handleOwnedCardActionCommit", to: "private func presentCommittedCardIfNeeded")
        XCTAssertTrue(handler.contains("cardsManager.cards.removeAll"))
        XCTAssertTrue(handler.contains("librarySearchManager.remove(cardID: cardID)"))
        XCTAssertTrue(handler.contains("currentMenuCardData = nil"))
        XCTAssertTrue(handler.contains("currentCardId = nil"))
        XCTAssertTrue(handler.contains("loadUserCards()"))
        XCTAssertTrue(handler.contains("if librarySearchSession.isActive"))
        XCTAssertTrue(handler.contains("retryLibrarySearch()"))
        XCTAssertFalse(handler.contains("toggleCard"), "A receipt must not send the mutation again")
        XCTAssertFalse(handler.contains("NotificationCenter"))
        let loader = try section(home, from: "private func loadUserCards()", to: "private func handleOwnedCardActionCommit")
        XCTAssertTrue(loader.contains("selectedSortOption.descriptor"))
    }

    func testDetailUsesTheExactReceiptWithoutReachingThroughHomeOrRefetchingStaleMetadata() throws {
        let detail = try source("ArcNote/DetailView.swift")
        XCTAssertTrue(detail.contains("onOwnedCardActionCommitted: handleOwnedCardActionCommit"))
        let handler = try section(detail, from: "private func handleOwnedCardActionCommit", to: "// 关联笔记数据")
        XCTAssertTrue(handler.contains("guard commit.cardID == cardId"))
        XCTAssertTrue(handler.contains("dismiss()"))
        XCTAssertTrue(handler.contains("state.isPublic = isPublic"))
        XCTAssertTrue(handler.contains("state.isPinned = isPinned"))
        XCTAssertTrue(handler.contains("state.pinnedAt = pinnedAt"))
        XCTAssertFalse(handler.contains("loadCardDetail()"))
        XCTAssertFalse(handler.contains("NotificationCenter"))
        XCTAssertTrue(detail.contains("isPublic: committedOwnedCardState?.isPublic ?? detail.isPublic"))
        XCTAssertTrue(detail.contains("isPinned: committedOwnedCardState?.isPinned ?? detail.isPinned ?? false"))
        XCTAssertTrue(detail.contains("currentDetailUserCard?.isPublic == true"))
    }

    func testDefaultNetworkAdapterPreservesUnauthenticatedFixtureBoundaryAndHostsResetCallbacks() throws {
        let popup = try source("ArcNote/PopupMenuView.swift")
        let adapter = try section(popup, from: "private final class NetworkOwnedCardActionService", to: "private struct OwnedCardActionHostModifier")
        let guardRange = try XCTUnwrap(adapter.range(of: "guard AuthManager.shared.currentUser != nil"))
        let requestRange = try XCTUnwrap(adapter.range(of: "NetworkManager.shared.deleteCard"))
        XCTAssertLessThan(guardRange.lowerBound, requestRange.lowerBound)
        let host = try section(popup, from: "private struct OwnedCardActionHostModifier", to: "enum CardNavigationRoute")
        XCTAssertTrue(host.contains(".environment(\\.ownedCardActionCallbacks, OwnedCardActionCallbacks())"), "Callbacks from one page must not act on a later page's target")
    }

    private func source(_ path: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func section(_ source: String, from: String, to: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: from))
        let end = try XCTUnwrap(source.range(of: to, range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }
}
