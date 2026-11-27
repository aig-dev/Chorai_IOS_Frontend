import Foundation
import XCTest
@testable import CoreFlow

final class SparkSessionPersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SparkSessionPersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSnapshotsAreIsolatedByActorAndRootSource() throws {
        let store = UserDefaultsSparkSessionStore(
            defaults: defaults,
            keyPrefix: "spark.test"
        )
        let actorASnapshot = snapshot(
            actorID: "act_a",
            rootSourceAssetID: "ast_root_a",
            activityID: "act_spark_a"
        )
        let actorBSnapshot = snapshot(
            actorID: "act_b",
            rootSourceAssetID: "ast_root_a",
            activityID: "act_spark_b"
        )

        try store.save(actorASnapshot)
        try store.save(actorBSnapshot)

        XCTAssertEqual(
            try store.snapshot(actorID: "act_a", rootSourceAssetID: "ast_root_a"),
            actorASnapshot
        )
        XCTAssertEqual(
            try store.snapshot(actorID: "act_b", rootSourceAssetID: "ast_root_a"),
            actorBSnapshot
        )
        XCTAssertNil(
            try store.snapshot(actorID: "act_a", rootSourceAssetID: "ast_other")
        )
    }

    func testRemoveDeletesOnlyRequestedActorRootSnapshot() throws {
        let store = UserDefaultsSparkSessionStore(
            defaults: defaults,
            keyPrefix: "spark.test"
        )
        let first = snapshot(
            actorID: "act_a",
            rootSourceAssetID: "ast_first",
            activityID: "act_spark_first"
        )
        let second = snapshot(
            actorID: "act_a",
            rootSourceAssetID: "ast_second",
            activityID: "act_spark_second"
        )
        try store.save(first)
        try store.save(second)

        try store.remove(actorID: "act_a", rootSourceAssetID: "ast_first")

        XCTAssertNil(
            try store.snapshot(actorID: "act_a", rootSourceAssetID: "ast_first")
        )
        XCTAssertEqual(
            try store.snapshot(actorID: "act_a", rootSourceAssetID: "ast_second"),
            second
        )
    }

    func testInvalidSnapshotIsReportedAndPreservedWithoutRemovingOtherSnapshots() throws {
        let keyPrefix = "spark.test"
        let store = UserDefaultsSparkSessionStore(
            defaults: defaults,
            keyPrefix: keyPrefix
        )
        let valid = snapshot(
            actorID: "act_b",
            rootSourceAssetID: "ast_root",
            activityID: "act_spark_valid"
        )
        try store.save(valid)
        let invalidKey = "\(keyPrefix).act_a.ast_root"
        defaults.set(Data([0x00, 0x01]), forKey: invalidKey)

        XCTAssertThrowsError(try store.snapshot(actorID: "act_a", rootSourceAssetID: "ast_root"))
        XCTAssertEqual(defaults.data(forKey: invalidKey), Data([0x00, 0x01]))
        XCTAssertEqual(
            try store.snapshot(actorID: "act_b", rootSourceAssetID: "ast_root"),
            valid
        )
    }

    func testExtremeParentDepthIsRejectedWithoutDeletingRecord() throws {
        let store = UserDefaultsSparkSessionStore(defaults: defaults, keyPrefix: "extreme")
        let value = SparkSessionSnapshot(actorID: "actor", rootSourceAssetID: "source",
            nodes: [
                SparkChainNode(sourceAssetID: "source", sourcePreview: "", activityID: "child", parentActivityID: "parent",
                    rootActivityID: "parent", chainDepth: 1, visibleIndex: 0),
                SparkChainNode(sourceAssetID: "source", sourcePreview: "", activityID: "parent", parentActivityID: nil,
                    rootActivityID: "parent", chainDepth: Int.max, visibleIndex: 0)
            ], activeActivityID: "child", pendingTrigger: nil, didShowUpwardCue: false)
        let bytes = try JSONEncoder().encode(value)
        defaults.set(bytes, forKey: "extreme.actor.source")
        XCTAssertThrowsError(try store.snapshot(actorID: "actor", rootSourceAssetID: "source"))
        XCTAssertEqual(defaults.data(forKey: "extreme.actor.source"), bytes)
    }

    func testSecondSessionCannotOverwriteOrRemoveAnOperationSavedSinceItsRead() throws {
        let first = UserDefaultsSparkSessionStore(defaults: defaults, keyPrefix: "shared")
        let second = UserDefaultsSparkSessionStore(defaults: defaults, keyPrefix: "shared")
        XCTAssertNil(try first.snapshot(actorID: "actor", rootSourceAssetID: "source"))
        XCTAssertNil(try second.snapshot(actorID: "actor", rootSourceAssetID: "source"))
        let original = snapshot(actorID: "actor", rootSourceAssetID: "source", activityID: "first")
        try first.save(original)
        let bytes = defaults.data(forKey: "shared.actor.source")
        XCTAssertThrowsError(try second.save(snapshot(actorID: "actor", rootSourceAssetID: "source", activityID: "second")))
        XCTAssertEqual(defaults.data(forKey: "shared.actor.source"), bytes)
        XCTAssertThrowsError(try second.remove(actorID: "actor", rootSourceAssetID: "source"))
        XCTAssertEqual(defaults.data(forKey: "shared.actor.source"), bytes)
        XCTAssertEqual(try second.snapshot(actorID: "actor", rootSourceAssetID: "source"), original)
    }

    private func snapshot(
        actorID: String,
        rootSourceAssetID: String,
        activityID: String
    ) -> SparkSessionSnapshot {
        SparkSessionSnapshot(
            actorID: actorID,
            rootSourceAssetID: rootSourceAssetID,
            nodes: [
                SparkChainNode(
                    sourceAssetID: rootSourceAssetID,
                    sourcePreview: "A source",
                    activityID: activityID,
                    parentActivityID: nil,
                    rootActivityID: activityID,
                    chainDepth: 0,
                    visibleIndex: 1
                )
            ],
            activeActivityID: activityID,
            pendingTrigger: PendingSparkTrigger(
                    requestKey: UUID(),
                sourceAssetID: rootSourceAssetID,
                sourcePreview: "A source",
                parentActivityID: nil,
                startedAt: Date(timeIntervalSince1970: 100),
                priorActivityID: nil,
                priorVisibleIndex: 0
            ),
            didShowUpwardCue: true
        )
    }
}
