import Foundation
import XCTest
@testable import CoreFlow

final class OnboardingSparkResumePersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingSparkResumePersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMetadataIsIsolatedByActorAndOnboardingSession() throws {
        let store = UserDefaultsOnboardingSparkResumeStore(
            defaults: defaults,
            keyPrefix: "onboarding.spark.test"
        )
        let actorA = OnboardingSparkResumeMetadata(
            actorID: "act_a",
            sessionID: "onb_a",
            rootSourceAssetID: "ast_root_a"
        )
        let actorB = OnboardingSparkResumeMetadata(
            actorID: "act_b",
            sessionID: "onb_b",
            rootSourceAssetID: "ast_root_b"
        )

        store.save(actorA)
        store.save(actorB)

        XCTAssertEqual(
            store.metadata(actorID: "act_a", sessionID: "onb_a"),
            actorA
        )
        XCTAssertEqual(
            store.metadata(actorID: "act_b", sessionID: "onb_b"),
            actorB
        )
        XCTAssertNil(store.metadata(actorID: "act_a", sessionID: "onb_b"))

        store.remove(actorID: "act_a", sessionID: "onb_a")

        XCTAssertNil(store.metadata(actorID: "act_a", sessionID: "onb_a"))
        XCTAssertEqual(
            store.metadata(actorID: "act_b", sessionID: "onb_b"),
            actorB
        )
    }

    func testInvalidMetadataIsPruned() {
        let keyPrefix = "onboarding.spark.test"
        let store = UserDefaultsOnboardingSparkResumeStore(
            defaults: defaults,
            keyPrefix: keyPrefix
        )
        let key = "\(keyPrefix).act_a.onb_a"
        defaults.set(Data([0x00, 0x01]), forKey: key)

        XCTAssertNil(store.metadata(actorID: "act_a", sessionID: "onb_a"))
        XCTAssertNil(defaults.data(forKey: key))
    }

    func testMismatchedOrEmptyMetadataIsPruned() throws {
        let keyPrefix = "onboarding.spark.test"
        let store = UserDefaultsOnboardingSparkResumeStore(
            defaults: defaults,
            keyPrefix: keyPrefix
        )
        let key = "\(keyPrefix).act_a.onb_a"
        let invalidValues = [
            OnboardingSparkResumeMetadata(
                actorID: "act_other",
                sessionID: "onb_a",
                rootSourceAssetID: "ast_root"
            ),
            OnboardingSparkResumeMetadata(
                actorID: "act_a",
                sessionID: "onb_other",
                rootSourceAssetID: "ast_root"
            ),
            OnboardingSparkResumeMetadata(
                actorID: "act_a",
                sessionID: "onb_a",
                rootSourceAssetID: "   "
            ),
        ]

        for metadata in invalidValues {
            defaults.set(try JSONEncoder().encode(metadata), forKey: key)

            XCTAssertNil(
                store.metadata(actorID: "act_a", sessionID: "onb_a")
            )
            XCTAssertNil(defaults.data(forKey: key))
        }
    }
}
