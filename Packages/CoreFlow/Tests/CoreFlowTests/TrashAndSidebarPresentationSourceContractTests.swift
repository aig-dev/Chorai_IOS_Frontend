import Foundation
import XCTest

final class TrashAndSidebarPresentationSourceContractTests: XCTestCase {
    func testTrashKeepsExplicitTargetAndRetryableConfirmation() throws {
        let trash = try source("TrashView")
        XCTAssertTrue(trash.contains(".sheet(isPresented: $showDeleteConfirmation"))
        XCTAssertTrue(trash.contains(".interactiveDismissDisabled(busyCardID != nil)"))
        XCTAssertTrue(trash.contains("guard let card = cardToDelete, busyCardID == nil else { return }"))
        XCTAssertTrue(trash.contains("trashManager.permanentlyDeleteCard(cardId: card.id, baseSyncToken: card.syncToken)"))
        XCTAssertTrue(trash.contains("trashManager.restoreCard(cardId: card.id)"))
        for identifier in ["trash.delete.error", "trash.delete.confirm", "trash.delete.cancel", "trash.delete.close", "trash.card.error."] {
            XCTAssertTrue(trash.contains(identifier))
        }
        let deletion = try XCTUnwrap(trash.range(of: "private func permanentlyDeleteSelectedCard()"))
        let failure = try XCTUnwrap(trash[deletion.lowerBound...].range(of: "case .failure"))
        let body = String(trash[failure.lowerBound...].prefix(400))
        XCTAssertTrue(body.contains("actionErrorCardID = card.id"))
        XCTAssertFalse(body.contains("showDeleteConfirmation = false"))
    }

    func testTrashUsesSystemListAndRetainsRefreshLoadAndErrorStates() throws {
        let trash = try source("TrashView")
        XCTAssertTrue(trash.contains("List {"))
        XCTAssertTrue(trash.contains(".navigationTitle(\"Trash Can\")"))
        XCTAssertFalse(trash.contains(".navigationBarHidden(true)"))
        XCTAssertFalse(trash.contains(".lineLimit(1)"), "Retention guidance must wrap on compact screens")
        for operation in ["trashManager.loadTrashCards(refresh: true)", "trashManager.loadMoreTrashCards()", "trashManager.refreshTrashCards()"] {
            XCTAssertTrue(trash.contains(operation))
        }
        for state in ["trash.loading", "trash.load.error", "trash.empty", "trash.load-more"] {
            XCTAssertTrue(trash.contains(state))
        }
        XCTAssertTrue(trash.contains(".buttonStyle(.borderless)"), "List buttons must not activate other row actions")
    }

    func testSidebarKeepsExistingRoutesUnreadAndClosureInScrollableDrawer() throws {
        let sidebar = try source("SideMenuView")
        XCTAssertTrue(sidebar.contains("ScrollView {"))
        XCTAssertFalse(sidebar.contains(".frame(height: 150)"))
        for title in ["My Notes", "Favorites", "Notification", "Trash", "Settings", "Help & Report"] {
            XCTAssertTrue(sidebar.contains("title: \"\(title)\""))
        }
        for action in ["onMyNotesTapped?()", "onFavoritesTapped?()", "navigateToNotification = true", "navigateToTrash = true", "navigateToSettings = true", "navigateToMyProfile = true", "navigateToHelpReport = true"] {
            XCTAssertTrue(sidebar.contains(action))
        }
        XCTAssertTrue(sidebar.contains("notificationStore.unreadCount > 0"))
        XCTAssertTrue(sidebar.contains("notificationStore.load(actorID: actorID)"))
        XCTAssertTrue(sidebar.contains(".accessibilityIdentifier(\"side-menu.close\")"))
        XCTAssertTrue(sidebar.contains(".frame(minHeight: 44)"))
    }

    private func source(_ file: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent("ArcNote/\(file).swift"), encoding: .utf8)
    }
}
