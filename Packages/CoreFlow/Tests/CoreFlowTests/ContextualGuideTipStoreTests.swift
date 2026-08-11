import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class ContextualGuideTipStoreTests: XCTestCase {
    func testVisibleTipRequiresItsMatchingOnboardingStateAndTarget() {
        let persistence = InMemoryContextualGuideTipPersistence()
        let store = ContextualGuideTipStore(persistence: persistence)
        store.load(actorID: "actor_a")

        XCTAssertTrue(
            store.isVisible(
                .libraryCreate,
                onboardingState: "elicit_signal",
                targetIsVisible: true
            )
        )
        XCTAssertFalse(
            store.isVisible(
                .libraryCreate,
                onboardingState: "product_spark_intro",
                targetIsVisible: true
            )
        )
        XCTAssertFalse(
            store.isVisible(
                .libraryCreate,
                onboardingState: "elicit_signal",
                targetIsVisible: false
            )
        )
    }

    func testDismissalPersistsOnlyForTheCurrentActorAndTipVersion() {
        let persistence = InMemoryContextualGuideTipPersistence()
        let store = ContextualGuideTipStore(persistence: persistence)
        store.load(actorID: "actor_a")
        store.dismiss(
            .flowSpark,
            onboardingState: "product_spark_intro",
            targetIsVisible: true
        )

        XCTAssertFalse(
            store.isVisible(
                .flowSpark,
                onboardingState: "product_spark_intro",
                targetIsVisible: true
            )
        )

        let reloadedActor = ContextualGuideTipStore(persistence: persistence)
        reloadedActor.load(actorID: "actor_a")
        XCTAssertFalse(
            reloadedActor.isVisible(
                .flowSpark,
                onboardingState: "product_spark_intro",
                targetIsVisible: true
            )
        )

        let otherActor = ContextualGuideTipStore(persistence: persistence)
        otherActor.load(actorID: "actor_b")
        XCTAssertTrue(
            otherActor.isVisible(
                .flowSpark,
                onboardingState: "product_spark_intro",
                targetIsVisible: true
            )
        )
    }

    func testTargetCompletionWinsOverAnOutsideDismissal() {
        let persistence = InMemoryContextualGuideTipPersistence()
        let store = ContextualGuideTipStore(
            persistence: persistence
        )
        store.load(actorID: "actor_a")
        store.dismiss(
            .sparkFavorite,
            onboardingState: "product_spark_results",
            targetIsVisible: true
        )
        store.complete(
            .sparkFavorite,
            onboardingState: "product_spark_results",
            targetIsVisible: true
        )

        XCTAssertEqual(store.outcome(for: .sparkFavorite), .completed)

        let reloadedStore = ContextualGuideTipStore(persistence: persistence)
        reloadedStore.load(actorID: "actor_a")
        XCTAssertEqual(reloadedStore.outcome(for: .sparkFavorite), .completed)
    }

    func testOutcomesRequireMatchingStateAndVisibleTargetForEveryTip() {
        let cases: [(ContextualGuideTipID, String)] = [
            (.libraryCreate, "elicit_signal"),
            (.flowSpark, "product_spark_intro"),
            (.sparkFavorite, "product_spark_results"),
            (.mergeAction, "product_merge_intro"),
        ]

        for (tip, matchingState) in cases {
            let persistence = InMemoryContextualGuideTipPersistence()
            let store = ContextualGuideTipStore(persistence: persistence)
            store.load(actorID: "actor_\(tip.rawValue)")

            store.complete(
                tip,
                onboardingState: "unrelated_state",
                targetIsVisible: true
            )
            store.dismiss(
                tip,
                onboardingState: matchingState,
                targetIsVisible: false
            )
            XCTAssertNil(
                store.outcome(for: tip),
                "Ineligible \(tip.rawValue) interactions must not persist"
            )

            store.complete(
                tip,
                onboardingState: matchingState,
                targetIsVisible: true
            )
            XCTAssertEqual(
                store.outcome(for: tip),
                .completed,
                "Eligible \(tip.rawValue) target must complete"
            )
        }
    }

    func testApprovedTipCopyIsStableAtTheBehaviorBoundary() {
        XCTAssertEqual(
            ContextualGuideTipID.libraryCreate.copy,
            "Tap + to capture your first note."
        )
        XCTAssertEqual(
            ContextualGuideTipID.flowSpark.copy,
            "Tap Spark to continue from this card."
        )
        XCTAssertEqual(
            ContextualGuideTipID.sparkFavorite.copy,
            "Favorite a result to keep it."
        )
        XCTAssertEqual(
            ContextualGuideTipID.mergeAction.copy,
            "Merge two related notes."
        )
    }
}

private final class InMemoryContextualGuideTipPersistence:
    ContextualGuideTipPersisting {
    private var values: [String: ContextualGuideTipOutcome] = [:]

    func outcome(
        actorID: String,
        tip: ContextualGuideTipID
    ) -> ContextualGuideTipOutcome? {
        values[key(actorID: actorID, tip: tip)]
    }

    func save(
        _ outcome: ContextualGuideTipOutcome,
        actorID: String,
        tip: ContextualGuideTipID
    ) {
        values[key(actorID: actorID, tip: tip)] = outcome
    }

    private func key(actorID: String, tip: ContextualGuideTipID) -> String {
        "\(actorID)#\(tip.storageKey)"
    }
}
