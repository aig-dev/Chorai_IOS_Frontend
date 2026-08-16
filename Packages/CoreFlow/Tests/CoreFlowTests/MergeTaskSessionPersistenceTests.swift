import XCTest
@testable import CoreFlow

final class MergeTaskSessionPersistenceTests: XCTestCase {
    func testSavingCanonicalJobPromotesOnlyItsPendingRecord() {
        let collections = InMemoryMergeTaskCollectionStore(actorID: "actor_1")
        let first = MergeTaskSessionPersistence(
            actorID: "actor_1",
            operationID: "op_1",
            store: collections,
            now: { Date(timeIntervalSince1970: 10) }
        )
        let second = MergeTaskSessionPersistence(
            actorID: "actor_1",
            operationID: "op_2",
            store: collections,
            now: { Date(timeIntervalSince1970: 20) }
        )
        first.save(makeMergeSnapshot(jobID: nil, createKey: "create-1"))
        second.save(makeMergeSnapshot(jobID: nil, createKey: "create-2"))

        first.save(
            makeMergeSnapshot(
                jobID: "job_1",
                status: .created,
                createKey: "create-1"
            )
        )

        let value = collections.collection(actorID: "actor_1")
        XCTAssertNil(value.pendingCreations["op_1"])
        XCTAssertNotNil(value.pendingCreations["op_2"])
        XCTAssertEqual(value.tasks["job_1"]?.operationID, "op_1")
    }

    func testScopedRemoveLeavesSiblingTask() {
        let collections = InMemoryMergeTaskCollectionStore(actorID: "actor_1")
        let first = MergeTaskSessionPersistence(
            actorID: "actor_1",
            operationID: "op_1",
            store: collections
        )
        let second = MergeTaskSessionPersistence(
            actorID: "actor_1",
            operationID: "op_2",
            store: collections
        )
        first.save(
            makeMergeSnapshot(
                jobID: "job_1",
                status: .created,
                createKey: "create-1"
            )
        )
        second.save(
            makeMergeSnapshot(
                jobID: "job_2",
                status: .generating,
                createKey: "create-2"
            )
        )

        first.remove(actorID: "actor_1")

        XCTAssertNil(collections.collection(actorID: "actor_1").tasks["job_1"])
        XCTAssertNotNil(collections.collection(actorID: "actor_1").tasks["job_2"])
    }

    func testReplacementKeepsOldFailureUntilNewJobIsAccepted() {
        let collections = InMemoryMergeTaskCollectionStore(actorID: "actor_1")
        let adapter = MergeTaskSessionPersistence(
            actorID: "actor_1",
            operationID: "op_1",
            initialJobID: "job_old",
            store: collections
        )
        adapter.save(
            makeMergeSnapshot(
                jobID: "job_old",
                status: .failed,
                createKey: "create-old"
            )
        )

        adapter.save(makeMergeSnapshot(jobID: nil, createKey: "create-retry"))

        var value = collections.collection(actorID: "actor_1")
        XCTAssertNotNil(value.tasks["job_old"])
        XCTAssertEqual(value.pendingCreations["op_1"]?.replacesJobID, "job_old")

        let removable = MergeTaskSessionPersistence(
            actorID: "actor_1",
            operationID: "op_1",
            initialJobID: "job_old",
            store: collections
        )
        removable.remove(actorID: "actor_1")
        XCTAssertNil(
            collections.collection(actorID: "actor_1")
                .pendingCreations["op_1"]
        )
        XCTAssertNil(collections.collection(actorID: "actor_1").tasks["job_old"])

        adapter.save(
            makeMergeSnapshot(
                jobID: "job_old",
                status: .failed,
                createKey: "create-old"
            )
        )
        adapter.save(makeMergeSnapshot(jobID: nil, createKey: "create-retry"))
        adapter.save(
            makeMergeSnapshot(
                jobID: "job_new",
                status: .created,
                createKey: "create-retry"
            )
        )

        value = collections.collection(actorID: "actor_1")
        XCTAssertNil(value.tasks["job_old"])
        XCTAssertNil(value.pendingCreations["op_1"])
        XCTAssertEqual(value.tasks["job_new"]?.operationID, "op_1")
    }

    func testReplacementPendingSnapshotIsRestoredBeforeRetainedFailure() {
        let collections = InMemoryMergeTaskCollectionStore(actorID: "actor_1")
        let adapter = MergeTaskSessionPersistence(
            actorID: "actor_1",
            operationID: "op_1",
            initialJobID: "job_old",
            store: collections
        )
        adapter.save(
            makeMergeSnapshot(
                jobID: "job_old",
                status: .failed,
                createKey: "create-old"
            )
        )
        adapter.save(makeMergeSnapshot(jobID: nil, createKey: "create-retry"))

        let restored = MergeTaskSessionPersistence(
            actorID: "actor_1",
            operationID: "op_1",
            initialJobID: "job_old",
            store: collections
        )

        XCTAssertNil(restored.snapshot(actorID: "actor_1")?.jobID)
        XCTAssertEqual(
            restored.snapshot(actorID: "actor_1")?.createRequest.idempotencyKey,
            "create-retry"
        )
    }

    func testSavePreservesCreatedAtAcrossPromotionAndReplacement() {
        var timestamps = [10.0, 20.0, 30.0, 40.0, 50.0]
        let collections = InMemoryMergeTaskCollectionStore(actorID: "actor_1")
        let adapter = MergeTaskSessionPersistence(
            actorID: "actor_1",
            operationID: "op_1",
            store: collections,
            now: { Date(timeIntervalSince1970: timestamps.removeFirst()) }
        )

        adapter.save(makeMergeSnapshot(jobID: nil, createKey: "create-1"))
        adapter.save(
            makeMergeSnapshot(
                jobID: "job_old",
                status: .failed,
                createKey: "create-1"
            )
        )
        adapter.save(
            makeMergeSnapshot(
                jobID: "job_old",
                status: .failed,
                createKey: "create-1"
            )
        )
        adapter.save(makeMergeSnapshot(jobID: nil, createKey: "create-retry"))
        adapter.save(
            makeMergeSnapshot(
                jobID: "job_new",
                status: .created,
                createKey: "create-retry"
            )
        )

        XCTAssertEqual(
            collections.collection(actorID: "actor_1").tasks["job_new"]?.createdAt,
            Date(timeIntervalSince1970: 10)
        )
    }
}

final class InMemoryMergeTaskCollectionStore: MergeTaskCollectionPersisting {
    private var values: [String: MergeTaskCollection] = [:]

    init(actorID: String) {
        values[actorID] = .empty(actorID: actorID)
    }

    init(collection: MergeTaskCollection) {
        values[collection.actorID] = collection
    }

    func collection(actorID: String) -> MergeTaskCollection {
        values[actorID] ?? .empty(actorID: actorID)
    }

    func save(_ collection: MergeTaskCollection) {
        values[collection.actorID] = collection
    }

    func update(
        actorID: String,
        _ mutation: (inout MergeTaskCollection) -> Void
    ) {
        var value = collection(actorID: actorID)
        mutation(&value)
        save(value)
    }

    func remove(actorID: String) {
        values[actorID] = nil
    }
}
