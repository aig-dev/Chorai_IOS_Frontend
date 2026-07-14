import XCTest
@testable import CoreFlow

final class InvitationCreditModelsTests: XCTestCase {
    func testBalancesKeepRegularAndPremiumSeparate() {
        let balances = CreditBalances.normalized([
            CreditBalance(tier: .premiumCredit, balance: 4, updatedAt: nil),
            CreditBalance(tier: .credit, balance: 12, updatedAt: nil)
        ])

        XCTAssertEqual(balances, CreditBalances(regular: 12, premium: 4))
    }

    func testBalancesDefaultOnlyMissingCanonicalTierToZero() {
        let balances = CreditBalances.normalized([
            CreditBalance(tier: .credit, balance: 12, updatedAt: nil),
            CreditBalance(tier: .unknown("future_credit"), balance: 99, updatedAt: nil)
        ])

        XCTAssertEqual(balances, CreditBalances(regular: 12, premium: 0))
    }

    func testUnknownCanonicalValuesRemainLossless() {
        XCTAssertEqual(CreditTier(canonical: "future_credit"), .unknown("future_credit"))
        XCTAssertEqual(
            InvitationStatus(canonical: "future_invitation"),
            .unknown("future_invitation")
        )
        XCTAssertEqual(
            InvitationRewardStatus(canonical: "future_reward"),
            .unknown("future_reward")
        )
        XCTAssertEqual(
            LedgerDirection(canonical: "future_direction"),
            .unknown("future_direction")
        )
        XCTAssertEqual(
            LedgerStatus(canonical: "future_status"),
            .unknown("future_status")
        )
    }

    func testInvitationCodeNormalizationTrimsWithoutChangingCase() {
        XCTAssertEqual(
            InvitationCode.normalized("  MixedCase09  "),
            "MixedCase09"
        )
        XCTAssertNil(InvitationCode.normalized(" \n "))
    }

    func testOffsetPageHasMoreUsesServerTotal() {
        let page = InvitationPage(
            items: [],
            total: 41,
            page: 2,
            limit: 20
        )

        XCTAssertTrue(page.hasMore)
        XCTAssertFalse(
            InvitationPage(items: [], total: 40, page: 2, limit: 20).hasMore
        )
    }

    func testReferralSharePayloadPrefersLinkThenCode() {
        XCTAssertEqual(
            InvitationReferral(
                code: "CodeA",
                link: "https://chorai.test/r/CodeA",
                usedCount: 2,
                nextMilestone: nil
            ).sharePayload,
            "https://chorai.test/r/CodeA"
        )
        XCTAssertEqual(
            InvitationReferral(
                code: "CodeA",
                link: "  ",
                usedCount: 2,
                nextMilestone: nil
            ).sharePayload,
            "CodeA"
        )
    }
}
