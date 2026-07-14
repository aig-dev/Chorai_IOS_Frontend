import XCTest
@testable import CoreFlow

@MainActor
final class InvitationCreditOverviewStoreTests: XCTestCase {
    func testLoadPublishesReferralAndBalancesIndependently() async {
        let service = InvitationCreditServiceStub()
        await service.setReferralResults([.success(referral(code: "CodeA"))])
        await service.setBalanceResults([.success(.init(regular: 7, premium: 2))])
        let store = InvitationCreditOverviewStore(service: service)

        await store.load(actorID: "act_a")

        XCTAssertEqual(store.referral?.code, "CodeA")
        XCTAssertEqual(store.balances, .init(regular: 7, premium: 2))
        XCTAssertEqual(store.referralPhase, .ready)
        XCTAssertEqual(store.balancePhase, .ready)
    }

    func testReferralFailureDoesNotClearSuccessfulBalances() async {
        let service = InvitationCreditServiceStub()
        await service.setReferralResults([
            .failure(InvitationCreditError.requestFailed(message: "Referral unavailable"))
        ])
        await service.setBalanceResults([.success(.init(regular: 7, premium: 2))])
        let store = InvitationCreditOverviewStore(service: service)

        await store.load(actorID: "act_a")

        XCTAssertNil(store.referral)
        XCTAssertEqual(store.balances, .init(regular: 7, premium: 2))
        XCTAssertEqual(
            store.referralPhase,
            .failed(.requestFailed(message: "Referral unavailable"))
        )
        XCTAssertEqual(store.balancePhase, .ready)
    }

    func testBalanceFailureDoesNotClearSuccessfulReferral() async {
        let service = InvitationCreditServiceStub()
        await service.setReferralResults([.success(referral(code: "CodeA"))])
        await service.setBalanceResults([
            .failure(InvitationCreditError.requestFailed(message: nil))
        ])
        let store = InvitationCreditOverviewStore(service: service)

        await store.load(actorID: "act_a")

        XCTAssertEqual(store.referral?.code, "CodeA")
        XCTAssertNil(store.balances)
        XCTAssertEqual(store.referralPhase, .ready)
        XCTAssertEqual(
            store.balancePhase,
            .failed(.requestFailed(message: nil))
        )
    }

    func testRefreshFailureRetainsLastCommittedReferral() async {
        let service = InvitationCreditServiceStub()
        await service.setReferralResults([
            .success(referral(code: "CodeA")),
            .failure(InvitationCreditError.requestFailed(message: nil))
        ])
        await service.setBalanceResults([
            .success(.init(regular: 7, premium: 2)),
            .success(.init(regular: 8, premium: 3))
        ])
        let store = InvitationCreditOverviewStore(service: service)
        await store.load(actorID: "act_a")

        await store.refresh()

        XCTAssertEqual(store.referral?.code, "CodeA")
        XCTAssertEqual(store.balances, .init(regular: 8, premium: 3))
        XCTAssertEqual(
            store.referralPhase,
            .failed(.requestFailed(message: nil))
        )
        XCTAssertEqual(store.balancePhase, .ready)
    }

    func testActorChangeRejectsDelayedPreviousReferral() async {
        let service = InvitationCreditServiceStub()
        await service.setReferralResults([
            .success(referral(code: "OldCode")),
            .success(referral(code: "NewCode"))
        ])
        await service.setBalanceResults([
            .success(.init(regular: 1, premium: 0)),
            .success(.init(regular: 2, premium: 0))
        ])
        await service.setReferralDelay(nanoseconds: 80_000_000)
        let store = InvitationCreditOverviewStore(service: service)

        let oldLoad = Task { await store.load(actorID: "act_old") }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await store.load(actorID: "act_new")
        await oldLoad.value

        XCTAssertEqual(store.actorID, "act_new")
        XCTAssertEqual(store.referral?.code, "NewCode")
        XCTAssertEqual(store.balances?.regular, 2)
    }

    func testInvalidActorFailsBothSectionsWithoutRequest() async {
        let service = InvitationCreditServiceStub()
        let store = InvitationCreditOverviewStore(service: service)

        await store.load(actorID: " ")

        XCTAssertEqual(store.referralPhase, .failed(.invalidActor))
        XCTAssertEqual(store.balancePhase, .failed(.invalidActor))
    }

    private func referral(code: String) -> InvitationReferral {
        InvitationReferral(
            code: code,
            link: "https://chorai.test/r/\(code)",
            usedCount: 0,
            nextMilestone: nil
        )
    }
}
