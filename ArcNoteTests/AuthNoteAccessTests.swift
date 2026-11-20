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
}
