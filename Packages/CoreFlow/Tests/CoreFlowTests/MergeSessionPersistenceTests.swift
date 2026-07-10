import Foundation
import XCTest
@testable import CoreFlow

final class MergeSessionPersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MergeSessionPersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSnapshotsAreActorScopedAndOneActiveSessionReplacesThePreviousOne() {
        let store = makeStore()
        let actorAFirst = snapshot(actorID: "actor_a", anchorID: "ast_first")
        let actorASecond = snapshot(actorID: "actor_a", anchorID: "ast_second")
        let actorB = snapshot(actorID: "actor_b", anchorID: "ast_other")

        store.save(actorAFirst)
        store.save(actorB)
        store.save(actorASecond)

        XCTAssertEqual(store.snapshot(actorID: "actor_a"), actorASecond)
        XCTAssertEqual(store.snapshot(actorID: "actor_b"), actorB)
        XCTAssertNil(store.snapshot(actorID: "actor_c"))
    }

    func testRoundTripRetainsExactCreateAndCommitRecoveryValues() {
        let store = makeStore()
        var value = snapshot(actorID: "actor_a", anchorID: "ast_anchor")
        value.jobID = "job_1"
        value.lastStatus = .committing
        value.selectedCapability = "mindmap"
        value.artifactID = "artifact_1"
        value.commitRequest = MergeCommitRequest(
            idempotencyKey: "commit-stable",
            target: .newCard(spaceID: nil, titleOverride: "Merged title")
        )
        value.committedAssetID = "ast_committed"

        store.save(value)

        let restored = store.snapshot(actorID: "actor_a")
        XCTAssertEqual(restored, value)
        XCTAssertEqual(restored?.createRequest.idempotencyKey, "create-stable")
        XCTAssertEqual(
            restored?.createRequest.sources.map(\.assetID),
            ["ast_anchor", "ast_companion"]
        )
        XCTAssertEqual(restored?.commitRequest?.idempotencyKey, "commit-stable")
        XCTAssertEqual(restored?.committedAssetID, "ast_committed")
    }

    func testResumeMetadataContainsNoArtifactBody() {
        let store = makeStore()
        let value = snapshot(actorID: "actor_a", anchorID: "ast_anchor")
        store.save(value)

        XCTAssertEqual(
            store.resumeMetadata(actorID: "actor_a"),
            MergeResumeMetadata(
                actorID: "actor_a",
                anchorAssetID: "ast_anchor",
                anchorPreview: "Anchor preview",
                sourceCount: 2,
                jobID: nil,
                status: nil,
                committedAssetID: nil
            )
        )
    }

    func testCorruptActorSnapshotIsPrunedWithoutTouchingAnotherActor() {
        let keyPrefix = "merge.test"
        let store = UserDefaultsMergeSessionStore(
            defaults: defaults,
            keyPrefix: keyPrefix
        )
        let valid = snapshot(actorID: "actor_b", anchorID: "ast_valid")
        store.save(valid)
        defaults.set(Data([0x00, 0x01]), forKey: "\(keyPrefix).actor_a")

        XCTAssertNil(store.snapshot(actorID: "actor_a"))
        XCTAssertNil(defaults.data(forKey: "\(keyPrefix).actor_a"))
        XCTAssertEqual(store.snapshot(actorID: "actor_b"), valid)
    }

    func testUnsupportedSchemaIsPrunedForOnlyThatActor() throws {
        let keyPrefix = "merge.test"
        let store = UserDefaultsMergeSessionStore(
            defaults: defaults,
            keyPrefix: keyPrefix
        )
        let valid = snapshot(actorID: "actor_b", anchorID: "ast_valid")
        store.save(valid)

        let unsupported = snapshot(actorID: "actor_a", anchorID: "ast_old")
        let encoded = try JSONEncoder().encode(unsupported)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["schemaVersion"] = 999
        defaults.set(
            try JSONSerialization.data(withJSONObject: object),
            forKey: "\(keyPrefix).actor_a"
        )

        XCTAssertNil(store.snapshot(actorID: "actor_a"))
        XCTAssertNil(defaults.data(forKey: "\(keyPrefix).actor_a"))
        XCTAssertEqual(store.snapshot(actorID: "actor_b"), valid)
    }

    func testClearRemovesOnlyRequestedActor() {
        let store = makeStore()
        let actorA = snapshot(actorID: "actor_a", anchorID: "ast_a")
        let actorB = snapshot(actorID: "actor_b", anchorID: "ast_b")
        store.save(actorA)
        store.save(actorB)

        store.remove(actorID: "actor_a")

        XCTAssertNil(store.snapshot(actorID: "actor_a"))
        XCTAssertEqual(store.snapshot(actorID: "actor_b"), actorB)
    }

    private func makeStore() -> UserDefaultsMergeSessionStore {
        UserDefaultsMergeSessionStore(
            defaults: defaults,
            keyPrefix: "merge.test"
        )
    }

    private func snapshot(actorID: String, anchorID: String) -> MergeSessionSnapshot {
        let sources = [
            MergeSource(assetID: anchorID, versionID: nil, preview: "Anchor preview"),
            MergeSource(assetID: "ast_companion", versionID: "ver_1", preview: "Companion")
        ]
        return MergeSessionSnapshot(
            schemaVersion: 1,
            actorID: actorID,
            anchorAssetID: anchorID,
            anchorPreview: "Anchor preview",
            createRequest: MergeCreateRequest(
                sources: sources,
                capability: "auto",
                idempotencyKey: "create-stable",
                context: ["client": .string("ios")]
            ),
            selectedCapability: nil,
            jobID: nil,
            lastStatus: nil,
            artifactID: nil,
            commitRequest: nil,
            committedAssetID: nil
        )
    }
}
