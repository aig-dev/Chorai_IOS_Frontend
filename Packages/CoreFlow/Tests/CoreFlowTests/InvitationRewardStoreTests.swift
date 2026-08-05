import XCTest
@testable import CoreFlow

@MainActor
final class InvitationRewardStoreTests: XCTestCase {
    func testRewardPagesDeduplicateAndRetainMilestoneState() async {
        let service = InvitationCreditServiceStub()
        await service.setRewardResults([
            .success(.init(
                items: [reward(id: "rew_1", milestoneThreshold: 10)],
                total: 2,
                page: 1,
                limit: 1
            )),
            .success(.init(
                items: [
                    reward(id: "rew_1", milestoneThreshold: 10),
                    reward(id: "rew_2", milestoneThreshold: 0)
                ],
                total: 2,
                page: 2,
                limit: 1
            ))
        ])
        let store = InvitationRewardStore(service: service, pageSize: 1)

        await store.load(actorID: "act_a")
        await store.loadMore()

        let pages = await service.rewardCallPages()
        XCTAssertEqual(store.items.map(\.id), ["rew_1", "rew_2"])
        XCTAssertEqual(store.items.map(\.isMilestoneBonus), [true, false])
        XCTAssertEqual(pages, [1, 2])
        XCTAssertFalse(store.hasMore)
    }

    func testInitialRewardFailureDoesNotBecomeEmpty() async {
        let service = InvitationCreditServiceStub()
        await service.setRewardResults([
            .failure(InvitationCreditError.requestFailed(message: nil))
        ])
        let store = InvitationRewardStore(service: service)

        await store.load(actorID: "act_a")

        XCTAssertEqual(
            store.phase,
            .failed(.requestFailed(message: nil))
        )
        XCTAssertEqual(store.items, [])
    }

    func testLoadMoreFailureRetainsRewardsAndRetriesSamePage() async {
        let service = InvitationCreditServiceStub()
        await service.setRewardResults([
            .success(.init(
                items: [reward(id: "rew_1", milestoneThreshold: 10)],
                total: 2,
                page: 1,
                limit: 1
            )),
            .failure(InvitationCreditError.requestFailed(message: nil)),
            .success(.init(
                items: [
                    reward(id: "rew_1", milestoneThreshold: 10),
                    reward(id: "rew_2", milestoneThreshold: 0)
                ],
                total: 2,
                page: 2,
                limit: 1
            ))
        ])
        let store = InvitationRewardStore(service: service, pageSize: 1)
        await store.load(actorID: "act_a")

        await store.loadMore()
        XCTAssertEqual(store.items.map(\.id), ["rew_1"])
        XCTAssertEqual(
            store.paginationError,
            .requestFailed(message: nil)
        )

        await store.retry()

        let pages = await service.rewardCallPages()
        XCTAssertEqual(store.items.map(\.id), ["rew_1", "rew_2"])
        XCTAssertEqual(store.items.map(\.isMilestoneBonus), [true, false])
        XCTAssertEqual(pages, [1, 2, 2])
        XCTAssertNil(store.paginationError)
        XCTAssertFalse(store.hasMore)
    }

    private func reward(id: String, milestoneThreshold: Int) -> InvitationReward {
        .init(
            id: id,
            recipientRole: "inviter",
            amount: 5,
            milestoneThreshold: milestoneThreshold,
            status: .issued,
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }
}
