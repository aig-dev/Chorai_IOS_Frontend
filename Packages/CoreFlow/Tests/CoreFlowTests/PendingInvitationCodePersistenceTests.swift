import XCTest
@testable import CoreFlow

final class PendingInvitationCodePersistenceTests: XCTestCase {
    func testPendingIntentRestoresOnlyForExactActor() {
        let defaults = isolatedDefaults()
        let store = UserDefaultsPendingInvitationCodeStore(defaults: defaults)
        store.save(
            PendingInvitationCode(
                actorID: "act_a",
                code: "  MixedCase  ",
                needsRetry: true
            )
        )

        XCTAssertEqual(store.pending(actorID: "act_a")?.code, "MixedCase")
        XCTAssertNil(store.pending(actorID: "act_b"))
    }

    func testRemoveClearsOnlyRequestedActor() {
        let defaults = isolatedDefaults()
        let store = UserDefaultsPendingInvitationCodeStore(defaults: defaults)
        store.save(.init(actorID: "act_a", code: "CodeA", needsRetry: true))
        store.save(.init(actorID: "act_b", code: "CodeB", needsRetry: true))

        store.remove(actorID: "act_a")

        XCTAssertNil(store.pending(actorID: "act_a"))
        XCTAssertEqual(store.pending(actorID: "act_b")?.code, "CodeB")
    }

    func testWrongSchemaAndCorruptDataArePruned() throws {
        let defaults = isolatedDefaults()
        let prefix = "test.pending"
        let store = UserDefaultsPendingInvitationCodeStore(
            defaults: defaults,
            keyPrefix: prefix
        )
        let wrongSchema = PendingInvitationCode(
            schemaVersion: 99,
            actorID: "act_a",
            code: "CodeA",
            needsRetry: true
        )
        defaults.set(
            try JSONEncoder().encode(wrongSchema),
            forKey: "\(prefix).act_a"
        )
        defaults.set(Data("broken".utf8), forKey: "\(prefix).act_b")

        XCTAssertNil(store.pending(actorID: "act_a"))
        XCTAssertNil(store.pending(actorID: "act_b"))
        XCTAssertNil(defaults.data(forKey: "\(prefix).act_a"))
        XCTAssertNil(defaults.data(forKey: "\(prefix).act_b"))
    }

    func testBlankActorOrCodeIsNeverPersisted() {
        let defaults = isolatedDefaults()
        let store = UserDefaultsPendingInvitationCodeStore(defaults: defaults)

        store.save(.init(actorID: " ", code: "CodeA", needsRetry: true))
        store.save(.init(actorID: "act_a", code: " ", needsRetry: true))

        XCTAssertNil(store.pending(actorID: "act_a"))
        XCTAssertNil(store.pending(actorID: " "))
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "PendingInvitationCodePersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
