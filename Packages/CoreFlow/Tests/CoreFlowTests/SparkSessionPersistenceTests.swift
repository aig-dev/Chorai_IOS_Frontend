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

    func testSnapshotsAreIsolatedByActorAndRootSource() {
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

        store.save(actorASnapshot)
        store.save(actorBSnapshot)

        XCTAssertEqual(
            store.snapshot(actorID: "act_a", rootSourceAssetID: "ast_root_a"),
            actorASnapshot
        )
        XCTAssertEqual(
            store.snapshot(actorID: "act_b", rootSourceAssetID: "ast_root_a"),
            actorBSnapshot
        )
        XCTAssertNil(
            store.snapshot(actorID: "act_a", rootSourceAssetID: "ast_other")
        )
    }

    func testRemoveDeletesOnlyRequestedActorRootSnapshot() {
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
        store.save(first)
        store.save(second)

        store.remove(actorID: "act_a", rootSourceAssetID: "ast_first")

        XCTAssertNil(
            store.snapshot(actorID: "act_a", rootSourceAssetID: "ast_first")
        )
        XCTAssertEqual(
            store.snapshot(actorID: "act_a", rootSourceAssetID: "ast_second"),
            second
        )
    }

    func testInvalidSnapshotIsPrunedWithoutRemovingOtherSnapshots() {
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
        store.save(valid)
        let invalidKey = "\(keyPrefix).act_a.ast_root"
        defaults.set(Data([0x00, 0x01]), forKey: invalidKey)

        XCTAssertNil(
            store.snapshot(actorID: "act_a", rootSourceAssetID: "ast_root")
        )
        XCTAssertNil(defaults.data(forKey: invalidKey))
        XCTAssertEqual(
            store.snapshot(actorID: "act_b", rootSourceAssetID: "ast_root"),
            valid
        )
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
