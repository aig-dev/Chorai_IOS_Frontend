import Foundation
import XCTest
@testable import CoreFlow

final class MergeTaskPersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var notificationCenter: NotificationCenter!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "MergeTaskPersistenceTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        notificationCenter = NotificationCenter()
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        notificationCenter = nil
        suiteName = nil
    }

    func testCollectionRoundTripKeepsTwoJobsAndOnePendingCreation() throws {
        let store = makeTaskStore()
        var collection = MergeTaskCollection.empty(actorID: "actor_a")
        collection.pendingCreations["op_pending"] = record(
            operationID: "op_pending",
            actorID: "actor_a",
            jobID: nil,
            createKey: "create-pending"
        )
        collection.tasks["job_1"] = record(
            operationID: "op_1",
            actorID: "actor_a",
            jobID: "job_1",
            createKey: "create-1"
        )
        collection.tasks["job_2"] = record(
            operationID: "op_2",
            actorID: "actor_a",
            jobID: "job_2",
            createKey: "create-2"
        )

        store.save(collection)

        XCTAssertEqual(store.collection(actorID: "actor_a"), collection)
        XCTAssertEqual(store.collection(actorID: "actor_b"), .empty(actorID: "actor_b"))
    }

    func testCorruptSiblingRecordDoesNotDropValidTask() throws {
        let store = makeTaskStore()
        let good = record(
            operationID: "op_good",
            actorID: "actor_1",
            jobID: "job_good",
            createKey: "create-good"
        )
        let envelope = MergeTaskCollectionEnvelope(
            schemaVersion: MergeTaskCollection.currentSchemaVersion,
            actorID: "actor_1",
            pendingCreations: [:],
            tasks: [
                "job_good": try JSONEncoder().encode(good),
                "job_bad": Data("not-json".utf8),
            ],
            quarantinedRecords: [:]
        )
        defaults.set(
            try JSONEncoder().encode(envelope),
            forKey: store.storageKey(actorID: "actor_1")
        )

        let restored = store.collection(actorID: "actor_1")

        XCTAssertEqual(restored.tasks["job_good"], good)
        XCTAssertNil(restored.tasks["job_bad"])
        let persistedData = try XCTUnwrap(
            defaults.data(forKey: store.storageKey(actorID: "actor_1"))
        )
        let persistedEnvelope = try JSONDecoder().decode(
            MergeTaskCollectionEnvelope.self,
            from: persistedData
        )
        XCTAssertEqual(
            persistedEnvelope.quarantinedRecords["tasks:job_bad"],
            Data("not-json".utf8)
        )
    }

    func testLegacyAcceptedSnapshotMigratesExactlyOnce() {
        let legacy = makeLegacyStore()
        legacy.save(makeMergeSnapshot(jobID: "job_legacy", status: .generating))
        let store = makeTaskStore(legacy: legacy)

        let migrated = store.collection(actorID: "actor_1")

        XCTAssertEqual(migrated.tasks["job_legacy"]?.snapshot.jobID, "job_legacy")
        XCTAssertTrue(migrated.pendingCreations.isEmpty)
        XCTAssertNil(legacy.snapshot(actorID: "actor_1"))
        XCTAssertEqual(store.collection(actorID: "actor_1"), migrated)
    }

    func testLegacyPendingSnapshotMigratesWithExactCreateRequest() {
        let legacy = makeLegacyStore()
        let pending = makeMergeSnapshot(jobID: nil, createKey: "create-existing")
        legacy.save(pending)
        let store = makeTaskStore(legacy: legacy)

        let migrated = store.collection(actorID: "actor_1")

        XCTAssertEqual(migrated.pendingCreations.count, 1)
        XCTAssertEqual(
            migrated.pendingCreations.values.first?.snapshot.createRequest,
            pending.createRequest
        )
    }

    func testLegacySnapshotWithMoreThanEightSourcesRemainsAvailable() {
        let legacy = makeLegacyStore()
        var snapshot = makeMergeSnapshot()
        snapshot.createRequest = MergeCreateRequest(
            sources: (0..<9).map {
                MergeSource(
                    assetID: "ast_\($0)",
                    versionID: "ver_\($0)",
                    preview: "Source \($0)"
                )
            },
            capability: "auto",
            idempotencyKey: "create-too-many",
            context: ["client": .string("ios")]
        )
        legacy.save(snapshot)

        let migrated = makeTaskStore(legacy: legacy).collection(actorID: "actor_1")

        XCTAssertEqual(migrated, .empty(actorID: "actor_1"))
        XCTAssertEqual(legacy.snapshot(actorID: "actor_1"), snapshot)
    }

    func testLegacySnapshotWithDuplicateSourceAssetsRemainsAvailable() {
        let legacy = makeLegacyStore()
        var snapshot = makeMergeSnapshot()
        snapshot.createRequest = MergeCreateRequest(
            sources: [
                MergeSource(assetID: "ast_duplicate", versionID: "ver_1", preview: "One"),
                MergeSource(assetID: "ast_duplicate", versionID: "ver_2", preview: "Two"),
            ],
            capability: "auto",
            idempotencyKey: "create-duplicate",
            context: ["client": .string("ios")]
        )
        legacy.save(snapshot)

        let migrated = makeTaskStore(legacy: legacy).collection(actorID: "actor_1")

        XCTAssertEqual(migrated, .empty(actorID: "actor_1"))
        XCTAssertEqual(legacy.snapshot(actorID: "actor_1"), snapshot)
    }

    func testLegacySnapshotWithEmptySourceAssetIDRemainsAvailable() {
        let legacy = makeLegacyStore()
        var snapshot = makeMergeSnapshot()
        snapshot.createRequest = MergeCreateRequest(
            sources: [
                MergeSource(assetID: "ast_anchor", versionID: nil, preview: "Anchor"),
                MergeSource(assetID: "", versionID: "ver_empty", preview: "Empty"),
            ],
            capability: "auto",
            idempotencyKey: "create-empty-asset",
            context: ["client": .string("ios")]
        )
        legacy.save(snapshot)

        let migrated = makeTaskStore(legacy: legacy).collection(actorID: "actor_1")

        XCTAssertEqual(migrated, .empty(actorID: "actor_1"))
        XCTAssertEqual(legacy.snapshot(actorID: "actor_1"), snapshot)
    }

    private func record(
        operationID: String,
        actorID: String,
        jobID: String?,
        createKey: String,
        createdAt: TimeInterval = 10
    ) -> MergeTaskRecord {
        MergeTaskRecord(
            operationID: operationID,
            snapshot: makeMergeSnapshot(
                actorID: actorID,
                jobID: jobID,
                status: jobID == nil ? nil : .created,
                createKey: createKey
            ),
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: createdAt),
            replacesJobID: nil
        )
    }

    private func makeLegacyStore() -> UserDefaultsMergeSessionStore {
        UserDefaultsMergeSessionStore(
            defaults: defaults,
            keyPrefix: "merge.legacy",
            notificationCenter: notificationCenter
        )
    }

    private func makeTaskStore(
        legacy: (any MergeSessionPersisting)? = nil
    ) -> UserDefaultsMergeTaskStore {
        UserDefaultsMergeTaskStore(
            defaults: defaults,
            keyPrefix: "merge.tasks",
            legacy: legacy ?? makeLegacyStore(),
            notificationCenter: notificationCenter,
            now: { Date(timeIntervalSince1970: 100) }
        )
    }
}
