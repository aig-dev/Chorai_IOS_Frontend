import XCTest
@testable import CoreFlow

@MainActor
final class InvitationCreditOverviewStoreTests: XCTestCase {
    func testLoadPublishesReferralAndBalanceIndependently() async {
        let service = InvitationCreditServiceStub()
        await service.setReferralResults([.success(referral(code: "CodeA"))])
        await service.setBalanceResults([.success(.init(balance: 230, updatedAt: nil))])
        let store = InvitationCreditOverviewStore(service: service)

        await store.load(actorID: "act_a")

        XCTAssertEqual(store.referral?.code, "CodeA")
        XCTAssertEqual(store.balance, .init(balance: 230, updatedAt: nil))
        XCTAssertEqual(store.referralPhase, .ready)
        XCTAssertEqual(store.balancePhase, .ready)
        let actorIDs = await service.balanceCallActorIDs()
        XCTAssertEqual(actorIDs, ["act_a"])
    }

    func testReferralFailureDoesNotClearSuccessfulBalance() async {
        let service = InvitationCreditServiceStub()
        await service.setReferralResults([
            .failure(InvitationCreditError.requestFailed(message: "Referral unavailable"))
        ])
        await service.setBalanceResults([.success(.init(balance: 230, updatedAt: nil))])
        let store = InvitationCreditOverviewStore(service: service)

        await store.load(actorID: "act_a")

        XCTAssertNil(store.referral)
        XCTAssertEqual(store.balance, .init(balance: 230, updatedAt: nil))
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
        XCTAssertNil(store.balance)
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
            .success(.init(balance: 230, updatedAt: nil)),
            .success(.init(balance: 231, updatedAt: nil))
        ])
        let store = InvitationCreditOverviewStore(service: service)
        await store.load(actorID: "act_a")

        await store.refresh()

        XCTAssertEqual(store.referral?.code, "CodeA")
        XCTAssertEqual(store.balance, .init(balance: 231, updatedAt: nil))
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
            .success(.init(balance: 1, updatedAt: nil)),
            .success(.init(balance: 2, updatedAt: nil))
        ])
        await service.setReferralDelay(nanoseconds: 80_000_000)
        let store = InvitationCreditOverviewStore(service: service)

        let oldLoad = Task { await store.load(actorID: "act_old") }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await store.load(actorID: "act_new")
        await oldLoad.value

        XCTAssertEqual(store.actorID, "act_new")
        XCTAssertEqual(store.referral?.code, "NewCode")
        XCTAssertEqual(store.balance?.balance, 2)
    }

    func testActorChangeRejectsDelayedPreviousBalance() async {
        let service = InvitationCreditServiceStub()
        await service.setReferralResults([
            .success(referral(code: "OldCode")),
            .success(referral(code: "NewCode"))
        ])
        await service.setBalanceResults([
            .success(.init(balance: 1, updatedAt: nil)),
            .success(.init(balance: 230, updatedAt: nil))
        ])
        await service.setBalanceDelay(nanoseconds: 80_000_000)
        let store = InvitationCreditOverviewStore(service: service)

        let oldLoad = Task { await store.load(actorID: "act_old") }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await store.load(actorID: "act_new")
        await oldLoad.value

        XCTAssertEqual(store.actorID, "act_new")
        XCTAssertEqual(store.balance?.balance, 230)
    }

    func testRetryBalanceRetainsLastCommittedValueOnFailure() async {
        let service = InvitationCreditServiceStub()
        await service.setReferralResults([.success(referral(code: "CodeA"))])
        await service.setBalanceResults([
            .success(.init(balance: 230, updatedAt: nil)),
            .failure(InvitationCreditError.requestFailed(message: "Balance unavailable"))
        ])
        let store = InvitationCreditOverviewStore(service: service)
        await store.load(actorID: "act_a")

        await store.retryBalance()

        XCTAssertEqual(store.balance, .init(balance: 230, updatedAt: nil))
        XCTAssertEqual(
            store.balancePhase,
            .failed(.requestFailed(message: "Balance unavailable"))
        )
    }

    func testInvalidActorFailsBothSectionsWithoutRequest() async {
        let service = InvitationCreditServiceStub()
        let store = InvitationCreditOverviewStore(service: service)

        await store.load(actorID: " ")

        XCTAssertEqual(store.referralPhase, .failed(.invalidActor))
        XCTAssertEqual(store.balancePhase, .failed(.invalidActor))
        let actorIDs = await service.balanceCallActorIDs()
        XCTAssertEqual(actorIDs, [])
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
