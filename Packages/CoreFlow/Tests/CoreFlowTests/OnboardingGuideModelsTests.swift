import Foundation
import XCTest
@testable import CoreFlow

final class OnboardingGuideModelsTests: XCTestCase {
    func testLibraryViewedRequiresCanonicalStateVisibleLibrary() {
        XCTAssertTrue(
            OnboardingGuideLibraryVisibilityPolicy.shouldRecordLibraryViewed(
                onboardingState: "product_library_intro",
                isLibrarySelected: true,
                isLibrarySurfaceVisible: true,
                isLibraryCovered: false
            )
        )
    }

    func testLibraryViewedIsBlockedUntilLibraryIsActuallyVisible() {
        let cases: [(String?, Bool, Bool, Bool)] = [
            ("product_merge_preview", true, true, false),
            ("product_library_intro", false, true, false),
            ("product_library_intro", true, false, false),
            ("product_library_intro", true, true, true),
            (nil, true, true, false),
        ]

        for (state, isSelected, isSurfaceVisible, isCovered) in cases {
            XCTAssertFalse(
                OnboardingGuideLibraryVisibilityPolicy
                    .shouldRecordLibraryViewed(
                        onboardingState: state,
                        isLibrarySelected: isSelected,
                        isLibrarySurfaceVisible: isSurfaceVisible,
                        isLibraryCovered: isCovered
                    )
            )
        }
    }

    func testGuidedMergeDismissesTheOwningCardRoute() {
        for state in ["product_merge_intro", "product_merge_preview"] {
            XCTAssertTrue(
                OnboardingGuideMergeExitPolicy
                    .shouldDismissOwningCardRoute(
                        onboardingIsActive: true,
                        onboardingState: state
                    )
            )
        }

        XCTAssertFalse(
            OnboardingGuideMergeExitPolicy.shouldDismissOwningCardRoute(
                onboardingIsActive: false,
                onboardingState: "product_merge_preview"
            )
        )
        XCTAssertFalse(
            OnboardingGuideMergeExitPolicy.shouldDismissOwningCardRoute(
                onboardingIsActive: true,
                onboardingState: "product_library_intro"
            )
        )
    }

    func testSparkContinuationUsesPersistedRootWhenResuming() {
        XCTAssertEqual(
            OnboardingSparkContinuationPolicy.requestedRootSourceAssetID(
                onboardingState: "product_spark_results",
                proposedCardID: "ast_new_flow_card",
                resumeRootSourceAssetID: "ast_original_root"
            ),
            "ast_original_root"
        )
        XCTAssertEqual(
            OnboardingSparkContinuationPolicy.requestedRootSourceAssetID(
                onboardingState: "product_save_material",
                proposedCardID: "ast_new_flow_card",
                resumeRootSourceAssetID: "ast_original_root"
            ),
            "ast_original_root"
        )
    }

    func testSparkContinuationDoesNotStartAnotherRootWhenResumeIsMissing() {
        XCTAssertNil(
            OnboardingSparkContinuationPolicy.requestedRootSourceAssetID(
                onboardingState: "product_spark_results",
                proposedCardID: "ast_new_flow_card",
                resumeRootSourceAssetID: nil
            )
        )
        XCTAssertFalse(
            OnboardingSparkContinuationPolicy.shouldShowResumeTip(
                onboardingState: "product_save_material",
                resumeRootSourceAssetID: nil
            )
        )
    }

    func testSparkContinuationStartsProposedRootBeforeResultsExist() {
        XCTAssertEqual(
            OnboardingSparkContinuationPolicy.requestedRootSourceAssetID(
                onboardingState: "product_spark_intro",
                proposedCardID: "ast_flow_card",
                resumeRootSourceAssetID: nil
            ),
            "ast_flow_card"
        )
        XCTAssertFalse(
            OnboardingSparkContinuationPolicy.shouldShowResumeTip(
                onboardingState: "product_spark_intro",
                resumeRootSourceAssetID: "ast_original_root"
            )
        )
        XCTAssertTrue(
            OnboardingSparkContinuationPolicy.shouldShowResumeTip(
                onboardingState: "product_spark_results",
                resumeRootSourceAssetID: "ast_original_root"
            )
        )
    }

    func testSparkIntroReusesRootSavedBeforeAnInterruptedLaunch() {
        XCTAssertEqual(
            OnboardingSparkContinuationPolicy.requestedRootSourceAssetID(
                onboardingState: "product_spark_intro",
                proposedCardID: "ast_new_flow_card",
                resumeRootSourceAssetID: "ast_original_root"
            ),
            "ast_original_root"
        )
    }

    func testNavigationDirectiveRoutesEveryActionOwningV1State() {
        let cases: [
            (
                state: String,
                destination: OnboardingGuidePrimaryTabDestination,
                clearsNavigationPath: Bool,
                recordsLibraryViewedOnInitialLoad: Bool
            )
        ] = [
            ("elicit_signal", .library, false, false),
            ("product_curator_intro", .flow, false, false),
            ("product_explore_card", .flow, false, false),
            ("product_spark_intro", .flow, false, false),
            ("product_spark_results", .flow, false, false),
            ("product_save_material", .flow, false, false),
            ("product_merge_intro", .library, true, false),
            ("product_merge_preview", .library, false, false),
            ("product_library_intro", .library, false, true),
        ]

        for item in cases {
            let directive = OnboardingGuideNavigationDirective.forState(
                item.state
            )

            XCTAssertEqual(
                directive?.destination,
                item.destination,
                "Wrong primary route for \(item.state)"
            )
            XCTAssertEqual(
                directive?.clearsNavigationPath,
                item.clearsNavigationPath,
                "Wrong navigation reset for \(item.state)"
            )
            XCTAssertEqual(
                directive?.recordsLibraryViewedOnInitialLoad,
                item.recordsLibraryViewedOnInitialLoad,
                "Wrong initial Library evidence rule for \(item.state)"
            )
        }
    }

    func testNavigationDirectiveLeavesInPlaceStatesToTheirOwningViews() {
        for state in [
            "deepen_signal",
            "build_ignite",
            "completed",
            "unknown_state",
        ] {
            XCTAssertNil(
                OnboardingGuideNavigationDirective.forState(state),
                "\(state) must not force a primary-tab route"
            )
        }
    }

    func testPrimaryTabDestinationOnlyRoutesStatesThatOwnAPrimaryTab() {
        XCTAssertEqual(
            OnboardingGuidePrimaryTabDestination.forState("elicit_signal"),
            .library
        )
        XCTAssertEqual(
            OnboardingGuidePrimaryTabDestination.forState(
                "product_curator_intro"
            ),
            .flow
        )
        XCTAssertEqual(
            OnboardingGuidePrimaryTabDestination.forState(
                "product_merge_intro"
            ),
            .library
        )
        XCTAssertEqual(
            OnboardingGuidePrimaryTabDestination.forState(
                "product_spark_intro"
            ),
            .flow
        )
        XCTAssertEqual(
            OnboardingGuidePrimaryTabDestination.forState(
                "product_merge_preview"
            ),
            .library
        )
    }

    func testGoSessionPayloadDecodesSnakeCaseAndMissingOptionalSceneFields() throws {
        let data = Data(
            """
            {
              "session_id": "onb_1",
              "flow_key": "onboarding_conversation",
              "flow_version": 1,
              "status": "active",
              "state": "product_explore_card",
              "scene": {
                "speaker": "chora",
                "text": "Each card can be a starting point.",
                "input_mode": "choice",
                "can_skip": true,
                "next_route": "explore",
                "presentation": "guide_overlay"
              },
              "created_at": "2026-07-10T00:00:00Z"
            }
            """.utf8
        )

        let session = try JSONDecoder().decode(
            OnboardingGuideSession.self,
            from: data
        )

        XCTAssertEqual(session.sessionID, "onb_1")
        XCTAssertEqual(session.flowVersion, 1)
        XCTAssertEqual(session.scene.inputMode, "choice")
        XCTAssertTrue(session.scene.choices.isEmpty)
        XCTAssertFalse(session.scene.spotlight)
    }

    func testInputsEncodeExactGoContract() throws {
        let encoder = JSONEncoder()
        let text = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: encoder.encode(OnboardingGuideInput.text("Keep me"))
            ) as? [String: String]
        )
        let choice = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: encoder.encode(
                    OnboardingGuideInput.choice("activation:flow.viewed")
                )
            ) as? [String: String]
        )

        XCTAssertEqual(text, ["input_type": "text", "text": "Keep me"])
        XCTAssertEqual(
            choice,
            [
                "input_type": "choice",
                "choice_id": "activation:flow.viewed"
            ]
        )
    }

    func testUserDefaultsPersistenceScopesEvidenceByActorAndSession() throws {
        let suite = "CoreFlow.Onboarding.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = UserDefaultsOnboardingGuidePersistence(
            defaults: defaults,
            keyPrefix: "guide"
        )

        persistence.savePendingEvidence(
            [.flowViewed],
            actorID: "act_a",
            sessionID: "onb_a"
        )
        persistence.savePendingEvidence(
            [.flowCardSaved(assetID: "ast_b")],
            actorID: "act_b",
            sessionID: "onb_b"
        )
        persistence.clear(actorID: "act_a", sessionID: "onb_a")

        XCTAssertTrue(
            persistence.pendingEvidence(
                actorID: "act_a",
                sessionID: "onb_a"
            ).isEmpty
        )
        XCTAssertEqual(
            persistence.pendingEvidence(
                actorID: "act_b",
                sessionID: "onb_b"
            ),
            [.flowCardSaved(assetID: "ast_b")]
        )
    }
}
