import Foundation
import XCTest

final class AuxiliaryNativePresentationSourceContractTests: XCTestCase {
    func testConnectedAuxiliaryPagesUseSystemNavigation() throws {
        for file in ["SettingsView", "BlockedActorsView", "NotificationView", "NotificationDetailView", "InvitationCreditView", "InvitationCreditDetailViews"] {
            let view = try source(file)
            XCTAssertFalse(view.contains(".navigationBarHidden(true)"), "\(file) still replaces system navigation with a custom header")
            XCTAssertFalse(view.contains(".navigationBarBackButtonHidden(true)"))
            XCTAssertTrue(view.contains(".navigationTitle("))
        }
    }

    func testSettingsAndPrivacyKeepRealActionsInNativeForms() throws {
        let settings = try source("SettingsView")
        XCTAssertTrue(settings.contains("Form {"))
        for action in ["settings.personal-data", "settings.choraProfile", "settings.invitation-credits", "settings.account-privacy", "settings.logout"] {
            XCTAssertTrue(settings.contains(action))
        }
        XCTAssertTrue(settings.contains(".alert(\"Log Out\""))
        XCTAssertTrue(settings.contains("authManager.logoutCurrentSession()"))
        XCTAssertTrue(settings.contains("logoutError = \"Couldn’t log out. Try again.\""))
        let privacy = try source("BlockedActorsView")
        XCTAssertTrue(privacy.contains("Form {"))
        for setting in ["showFollowLists", "allowFollow", "showEmail", "showPhone", "showLocation", "showBirthday"] {
            XCTAssertTrue(privacy.contains(".\(setting),"))
        }
        XCTAssertTrue(privacy.contains("privacyStore.set(setting, enabled: enabled)"))
        XCTAssertTrue(privacy.contains("privacyStore.retryFailedUpdate()"))
        XCTAssertTrue(privacy.contains(".disabled(privacyStore.savingSetting != nil)"))
        XCTAssertTrue(privacy.contains("store.unblock(actorID: actor.actorID)"))
    }

    func testNotificationListRetainsReadBeforeRoutingAndOriginalFilters() throws {
        let inbox = try source("NotificationView")
        XCTAssertTrue(inbox.contains("List {"))
        XCTAssertTrue(inbox.contains(".pickerStyle(.segmented)"))
        for filter in ["all", "unread", "activity", "system"] {
            XCTAssertTrue(inbox.contains("NotificationFilter.\(filter)"))
        }
        XCTAssertTrue(inbox.contains("store.markAllLoadedRead()"))
        XCTAssertTrue(inbox.contains("!store.mutatingIDs.contains(notification.id)"))
        XCTAssertTrue(inbox.contains("store.markRead(notificationID: notification.id)"))
        XCTAssertTrue(inbox.contains("guard store.actionFailure == nil,"))
        XCTAssertTrue(inbox.contains("completePendingNavigation()"))
        XCTAssertTrue(inbox.contains("store.loadMore()"))
        for route in ["selectedActorID = actorID", "selectedAssetID = assetID", "selectedLegacyID = notification.id"] {
            XCTAssertTrue(inbox.contains(route))
        }
    }

    func testInvitationPagesRetainRedemptionRecoveryAndPagination() throws {
        let overview = try source("InvitationCreditView")
        XCTAssertTrue(overview.contains("Form {"))
        for contract in ["overview.retryBalance()", "redemption.submit()", "redemption.canSubmit", "redemption.pendingIntent", "refreshAfterRedemption()", "copyReferral()", "presentShare()", "store: invitationHistory", "store: rewards", "store: ledger"] {
            XCTAssertTrue(overview.contains(contract), "Missing existing invitation operation: \(contract)")
        }
        let detail = try source("InvitationCreditDetailViews")
        XCTAssertEqual(detail.components(separatedBy: "List {").count - 1, 3)
        XCTAssertEqual(detail.components(separatedBy: "Task { await store.loadMore() }").count - 1, 3)
        XCTAssertFalse(detail.contains("minHeight: 40"), "Retry controls must retain a 44pt tap target")
    }

    private func source(_ file: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent("ArcNote/\(file).swift"), encoding: .utf8)
    }
}
