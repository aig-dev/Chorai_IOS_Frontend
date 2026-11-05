import XCTest
@testable import CoreFlow

final class NoteOfflineAccessTests: XCTestCase {
    private let scope = NoteStoreScope(actorID: "a", environmentID: "local")
    private let allowed = AccessState(mode: "private_beta", status: "allowed", scope: "product_full", reasonCode: nil)

    func testRestoredIdentityAloneDoesNotGrantOfflineAccess() {
        XCTAssertFalse(NoteOfflineAccess().allows(scope))
    }

    func testPreviouslyAllowedAccountSurvivesRevalidationAndRestartOnlyInSameEnvironment() throws {
        var access = NoteOfflineAccess()
        access.recordConfirmed(allowed, scope: scope)
        access.recordConfirmed(AccessState(mode: "unavailable", status: "required", scope: nil, reasonCode: nil), scope: scope)
        let restored = try JSONDecoder().decode(NoteOfflineAccess.self, from: JSONEncoder().encode(access))
        XCTAssertTrue(restored.allows(scope))
        XCTAssertFalse(restored.allows(NoteStoreScope(actorID: "b", environmentID: "local")))
        XCTAssertFalse(restored.allows(NoteStoreScope(actorID: "a", environmentID: "production")))
        XCTAssertFalse(restored.allows(nil))
    }

    func testConfirmedDenialAndExplicitLogoutRemoveEligibilityWithoutDeletingNotes() {
        var access = NoteOfflineAccess()
        access.recordConfirmed(allowed, scope: scope)
        access.recordConfirmed(AccessState(mode: "private_beta", status: "required", scope: nil, reasonCode: "revoked"), scope: scope)
        XCTAssertFalse(access.allows(scope))
        access.recordConfirmed(allowed, scope: scope)
        access.clear()
        XCTAssertFalse(access.allows(scope))
    }

    func testUnknownResponseCannotGrantAccessAndOtherActorDenialCannotAlterCurrentGrant() {
        var access = NoteOfflineAccess()
        access.recordConfirmed(AccessState(mode: "unknown", status: "allowed", scope: nil, reasonCode: nil), scope: scope)
        XCTAssertFalse(access.allows(scope))
        access.recordConfirmed(allowed, scope: scope)
        access.recordConfirmed(AccessState(mode: "private_beta", status: "required", scope: nil, reasonCode: nil), scope: NoteStoreScope(actorID: "b", environmentID: "local"))
        XCTAssertTrue(access.allows(scope))
    }
}
