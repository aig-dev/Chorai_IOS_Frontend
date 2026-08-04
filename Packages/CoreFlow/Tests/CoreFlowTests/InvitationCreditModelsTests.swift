import XCTest
@testable import CoreFlow

final class InvitationCreditModelsTests: XCTestCase {
    func testCreditBalanceRepresentsOneWallet() {
        let updatedAt = Date(timeIntervalSince1970: 1_722_772_800)

        let balance = CreditBalance(balance: 230, updatedAt: updatedAt)

        XCTAssertEqual(
            balance,
            CreditBalance(balance: 230, updatedAt: updatedAt)
        )
    }

    func testUnknownCanonicalValuesRemainLossless() {
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

    func testRewardMilestonePresentationDerivesFromThreshold() {
        let createdAt = Date(timeIntervalSince1970: 1_722_772_800)
        let baseReward = InvitationReward(
            id: "rew_base",
            recipientRole: "inviter",
            amount: 5,
            milestoneThreshold: 0,
            status: .issued,
            createdAt: createdAt
        )
        let milestoneReward = InvitationReward(
            id: "rew_milestone",
            recipientRole: "invitee",
            amount: 20,
            milestoneThreshold: 10,
            status: .pending,
            createdAt: createdAt
        )

        XCTAssertFalse(baseReward.isMilestoneBonus)
        XCTAssertTrue(milestoneReward.isMilestoneBonus)
    }

    func testLedgerEntryCarriesCompleteAuditContract() {
        let createdAt = Date(timeIntervalSince1970: 1_722_772_800)
        let settledAt = createdAt.addingTimeInterval(5)
        let refundedAt = createdAt.addingTimeInterval(10)

        let entry = CreditLedgerEntry(
            id: "log_1",
            transactionID: "tx_1",
            account: "actor",
            direction: .earn,
            delta: 25,
            runningBalance: 230,
            status: .refunded,
            ruleID: "rule_invitation",
            actionType: "INVITATION_REWARD",
            category: "growth",
            referenceID: "inv_1",
            referenceType: "invitation",
            activityID: "activity_1",
            createdAt: createdAt,
            settledAt: settledAt,
            refundedAt: refundedAt
        )

        XCTAssertEqual(entry.id, "log_1")
        XCTAssertEqual(entry.transactionID, "tx_1")
        XCTAssertEqual(entry.account, "actor")
        XCTAssertEqual(entry.direction, .earn)
        XCTAssertEqual(entry.delta, 25)
        XCTAssertEqual(entry.runningBalance, 230)
        XCTAssertEqual(entry.status, .refunded)
        XCTAssertEqual(entry.ruleID, "rule_invitation")
        XCTAssertEqual(entry.actionType, "INVITATION_REWARD")
        XCTAssertEqual(entry.category, "growth")
        XCTAssertEqual(entry.referenceID, "inv_1")
        XCTAssertEqual(entry.referenceType, "invitation")
        XCTAssertEqual(entry.activityID, "activity_1")
        XCTAssertEqual(entry.createdAt, createdAt)
        XCTAssertEqual(entry.settledAt, settledAt)
        XCTAssertEqual(entry.refundedAt, refundedAt)
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
