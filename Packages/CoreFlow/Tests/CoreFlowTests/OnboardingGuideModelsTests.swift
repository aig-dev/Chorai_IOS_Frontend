import Foundation
import XCTest
@testable import CoreFlow

final class OnboardingGuideModelsTests: XCTestCase {
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
