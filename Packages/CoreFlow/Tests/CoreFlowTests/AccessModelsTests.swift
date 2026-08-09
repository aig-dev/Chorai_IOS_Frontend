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

    func testCampaignBlockDecodesBoundedPresentationKeys() throws {
        let data = Data(#"{"campaign_id":"campaign_1","surface":"access.gate","template_key":"private_beta","content":{"title":"Join","description":"Use a code","action_label":"Unlock"}}"#.utf8)

        let block = try JSONDecoder().decode(CampaignBlock.self, from: data)

        XCTAssertEqual(block.campaignID, "campaign_1")
        XCTAssertEqual(block.templateKey, "private_beta")
        XCTAssertEqual(block.content.actionLabel, "Unlock")
    }
}
