import XCTest
import CoreFlow
@testable import ArcNote

@MainActor
final class AuthNoteAccessTests: XCTestCase {
    func testAdministratorOpensScopedNotesOnlyWhileOnlineAndVerified() {
        let auth = AuthManager.shared
        let network = NetworkManager.shared
        let wasConnected = network.isConnected
        auth.invalidateLocalSession()
        defer { auth.invalidateLocalSession(); network.isConnected = wasConnected }
        network.isConnected = true
        auth.saveUserSession(AuthResponse(success: true, message: nil, data: AuthResponseData(
            token: "test-online-administrator",
            user: User(id: "test-admin", username: "Test", email: "test@example.invalid",
                       avatar: nil, bio: nil, credit: 0, createdAt: "2026-11-20T00:00:00Z"),
            isNewUser: false,
            productAccess: AccessState(mode: "unavailable", status: "allowed", scope: nil,
                                       reasonCode: "admin_bypass"))))
        XCTAssertTrue(auth.canEnterProduct)
        XCTAssertTrue(auth.canOpenLocalNotes)
        XCTAssertFalse(auth.offlineNoteAccess.allows(auth.currentNoteScope))
        network.isConnected = false
        XCTAssertFalse(auth.canOpenLocalNotes)
        network.isConnected = true
        XCTAssertTrue(auth.canOpenLocalNotes)
        auth.markSessionNeedsLogin()
        XCTAssertFalse(auth.canEnterProduct)
        XCTAssertFalse(auth.canOpenLocalNotes)
        XCTAssertFalse(auth.isLoggedIn, "Online bypass must not retain an offline session after rejection")
    }

    func testRestrictedAccountLosesPriorGrantAndCannotSync() {
        let auth = AuthManager.shared
        auth.invalidateLocalSession()
        defer { auth.invalidateLocalSession() }
        auth.saveUserSession(AuthResponse(success: true, message: nil, data: AuthResponseData(
            token: "test-ordinary",
            user: User(id: "test-ordinary", username: "Test", email: "",
                       avatar: nil, bio: nil, credit: 0, createdAt: "2026-11-20T00:00:00Z"),
            isNewUser: false,
            productAccess: AccessState(mode: "private_beta", status: "allowed", scope: "product_full", reasonCode: nil))))
        let scope = auth.currentNoteScope
        XCTAssertTrue(auth.offlineNoteAccess.allows(scope))
        auth.markAccountRestricted()
        XCTAssertEqual(auth.accessState?.reasonCode, "account_restricted")
        XCTAssertFalse(auth.offlineNoteAccess.allows(scope))
        XCTAssertFalse(auth.canOpenLocalNotes)
        XCTAssertFalse(auth.canEnterProduct)
        auth.loadUserSession()
        XCTAssertFalse(auth.offlineNoteAccess.allows(scope))
        XCTAssertFalse(auth.canEnterProduct)
    }
}
