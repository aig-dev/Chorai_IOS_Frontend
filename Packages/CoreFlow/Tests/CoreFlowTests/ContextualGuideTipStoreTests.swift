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

    func testAReplacementOnboardingSessionGetsFreshContextualTips() {
        let persistence = InMemoryContextualGuideTipPersistence()
        let originalSession = ContextualGuideTipStore(
            persistence: persistence
        )
        originalSession.load(
            actorID: "actor_a",
            sessionID: "session_original"
        )
        originalSession.complete(
            .libraryCreate,
            onboardingState: "elicit_signal",
            targetIsVisible: true
        )

        let sameSession = ContextualGuideTipStore(
            persistence: persistence
        )
        sameSession.load(
            actorID: "actor_a",
            sessionID: "session_original"
        )
        XCTAssertFalse(
            sameSession.isVisible(
                .libraryCreate,
                onboardingState: "elicit_signal",
                targetIsVisible: true
            ),
            "A relaunch of the same onboarding session must keep its outcome"
        )

        let replacementSession = ContextualGuideTipStore(
            persistence: persistence
        )
        replacementSession.load(
            actorID: "actor_a",
            sessionID: "session_replacement"
        )
        XCTAssertTrue(
            replacementSession.isVisible(
                .libraryCreate,
                onboardingState: "elicit_signal",
                targetIsVisible: true
            ),
            "A restarted onboarding session must not inherit terminal tips"
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
            (.flowCard, "product_explore_card"),
            (.flowSpark, "product_spark_intro"),
            (.sparkResume, "product_save_material"),
            (.sparkFavorite, "product_spark_results"),
            (.libraryMergeEntry, "product_merge_intro"),
            (.mergeAction, "product_merge_intro"),
            (.mergeResume, "product_merge_preview"),
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
            ContextualGuideTipID.flowCard.copy,
            "Swipe this card to continue."
        )
        XCTAssertEqual(
            ContextualGuideTipID.flowSpark.copy,
            "Tap Spark to continue from this card."
        )
        XCTAssertEqual(
            ContextualGuideTipID.sparkResume.copy,
            "Tap Spark to return to your results."
        )
        XCTAssertEqual(
            ContextualGuideTipID.sparkFavorite.copy,
            "Favorite a result to keep it."
        )
        XCTAssertEqual(
            ContextualGuideTipID.libraryMergeEntry.copy,
            "Open a note's menu to start Merge."
        )
        XCTAssertEqual(
            ContextualGuideTipID.mergeAction.copy,
            "Merge two related notes."
        )
        XCTAssertEqual(
            ContextualGuideTipID.mergeResume.copy,
            "Resume Merge to finish your note."
        )
    }

    func testHandoffTipsCoverFreshAndResumedServerStates() {
        let persistence = InMemoryContextualGuideTipPersistence()
        let store = ContextualGuideTipStore(persistence: persistence)
        store.load(actorID: "actor_resume")

        XCTAssertTrue(
            store.isVisible(
                .flowCard,
                onboardingState: "product_curator_intro",
                targetIsVisible: true
            )
        )
        XCTAssertTrue(
            store.isVisible(
                .flowCard,
                onboardingState: "product_explore_card",
                targetIsVisible: true
            )
        )
        XCTAssertTrue(
            store.isVisible(
                .sparkResume,
                onboardingState: "product_spark_results",
                targetIsVisible: true
            )
        )
        XCTAssertTrue(
            store.isVisible(
                .sparkResume,
                onboardingState: "product_save_material",
                targetIsVisible: true
            )
        )
        XCTAssertTrue(
            store.isVisible(
                .libraryMergeEntry,
                onboardingState: "product_merge_intro",
                targetIsVisible: true
            )
        )
        XCTAssertTrue(
            store.isVisible(
                .mergeResume,
                onboardingState: "product_merge_preview",
                targetIsVisible: true
            )
        )
    }
}

private final class InMemoryContextualGuideTipPersistence:
    ContextualGuideTipPersisting {
    private var values: [String: ContextualGuideTipOutcome] = [:]

    func outcome(
        actorID: String,
        sessionID: String?,
        tip: ContextualGuideTipID
    ) -> ContextualGuideTipOutcome? {
        values[key(actorID: actorID, sessionID: sessionID, tip: tip)]
    }

    func save(
        _ outcome: ContextualGuideTipOutcome,
        actorID: String,
        sessionID: String?,
        tip: ContextualGuideTipID
    ) {
        values[key(actorID: actorID, sessionID: sessionID, tip: tip)] = outcome
    }

    private func key(
        actorID: String,
        sessionID: String?,
        tip: ContextualGuideTipID
    ) -> String {
        "\(actorID)#\(sessionID ?? "actor")#\(tip.storageKey)"
    }
}
