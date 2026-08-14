import XCTest
@testable import CoreFlow

final class AccessModelsTests: XCTestCase {
    func testAccessStateDecodesExplicitSnakeCaseKeys() throws {
        let data = Data(#"{"mode":"private_beta","status":"required","reason_code":"grant_required"}"#.utf8)

        let state = try JSONDecoder().decode(AccessState.self, from: data)

        XCTAssertEqual(
            state,
            AccessState(
                mode: "private_beta",
                status: "required",
                scope: nil,
                reasonCode: "grant_required"
            )
        )
    }

    func testAllowedPrivateBetaFullAccessMapsToProMembership() {
        let state = AccessState(
            mode: "private_beta",
            status: "allowed",
            scope: "product_full",
            reasonCode: nil
        )

        XCTAssertEqual(state.membershipTier, .pro)
    }

    func testNonPrivateBetaAccessDoesNotReceiveProMembership() {
        let state = AccessState(
            mode: "public_beta",
            status: "allowed",
            scope: "product_full",
            reasonCode: nil
        )

        XCTAssertEqual(state.membershipTier, .free)
    }

    func testClaimInputEncodesExplicitSnakeCaseKeys() throws {
        let data = try JSONEncoder().encode(
            ClaimInput(accessCode: "CRAI-7KQ9", idempotencyKey: "ios-attempt-1")
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        XCTAssertEqual(object["access_code"], "CRAI-7KQ9")
        XCTAssertEqual(object["idempotency_key"], "ios-attempt-1")
        XCTAssertNil(object["accessCode"])
    }

    func testAccessCodePreflightInputEncodesOnlyExplicitAccessCodeKey() throws {
        let data = try JSONEncoder().encode(
            AccessCodePreflightInput(accessCode: "CRAI-7KQ9")
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        XCTAssertEqual(object, ["access_code": "CRAI-7KQ9"])
    }

    func testAccessCodePreflightResultDecodesBoundedAvailability() throws {
        let result = try JSONDecoder().decode(
            AccessCodePreflightResult.self,
            from: Data(#"{"available":true}"#.utf8)
        )

        XCTAssertEqual(result, AccessCodePreflightResult(available: true))
    }

    func testAccessCodePreflightErrorClassifiesOnlyExactWireContracts() {
        XCTAssertEqual(
            AccessCodePreflightError.classify(
                statusCode: 403,
                errorCode: "PRODUCT_ACCESS_CODE_INVALID",
                retryAfterSeconds: nil
            ),
            .invalid
        )
        XCTAssertEqual(
            AccessCodePreflightError.classify(
                statusCode: 429,
                errorCode: "RATE_LIMIT_EXCEEDED",
                retryAfterSeconds: 37
            ),
            .rateLimited(retryAfterSeconds: 37)
        )
        XCTAssertEqual(
            AccessCodePreflightError.classify(
                statusCode: 429,
                errorCode: "RATE_LIMIT_EXCEEDED",
                retryAfterSeconds: 0
            ),
            .rateLimited(retryAfterSeconds: nil)
        )
        XCTAssertEqual(
            AccessCodePreflightError.classify(
                statusCode: 503,
                errorCode: nil,
                retryAfterSeconds: nil
            ),
            .temporarilyUnavailable
        )

        for classification in [
            AccessCodePreflightError.classify(
                statusCode: 200,
                errorCode: nil,
                retryAfterSeconds: nil
            ),
            AccessCodePreflightError.classify(
                statusCode: 403,
                errorCode: "SOME_OTHER_ERROR",
                retryAfterSeconds: nil
            ),
            AccessCodePreflightError.classify(
                statusCode: 429,
                errorCode: "SOME_OTHER_ERROR",
                retryAfterSeconds: 37
            ),
            AccessCodePreflightError.classify(
                statusCode: 500,
                errorCode: "INTERNAL_ERROR",
                retryAfterSeconds: nil
            ),
            AccessCodePreflightError.classify(
                statusCode: nil,
                errorCode: nil,
                retryAfterSeconds: nil
            ),
        ] {
            XCTAssertEqual(classification, .temporarilyUnavailable)
        }
    }

    func testAuthAccessPairOnlyEmitsACompleteNormalizedPair() throws {
        XCTAssertNil(AuthAccessPair(code: "CRAI-7KQ9", idempotencyKey: nil))
        XCTAssertNil(AuthAccessPair(code: nil, idempotencyKey: "ios-attempt-1"))

        let pair = try XCTUnwrap(
            AuthAccessPair(
                code: "  CRAI-7KQ9  ",
                idempotencyKey: "  ios-attempt-1  "
            )
        )

        XCTAssertEqual(
            pair.requestFields,
            [
                "access_code": "CRAI-7KQ9",
                "idempotency_key": "ios-attempt-1",
            ]
        )
    }

    func testCampaignBlockDecodesBoundedPresentationKeys() throws {
        let data = Data(#"{"campaign_id":"campaign_1","surface":"access.gate","template_key":"private_beta","content":{"title":"Join","description":"Use a code","action_label":"Unlock"}}"#.utf8)

        let block = try JSONDecoder().decode(CampaignBlock.self, from: data)

        XCTAssertEqual(block.campaignID, "campaign_1")
        XCTAssertEqual(block.templateKey, "private_beta")
        XCTAssertEqual(block.content.actionLabel, "Unlock")
    }
}
