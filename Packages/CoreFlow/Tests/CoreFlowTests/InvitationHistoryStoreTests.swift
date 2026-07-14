import XCTest
@testable import CoreFlow

@MainActor
final class InvitationHistoryStoreTests: XCTestCase {
    func testLoadMoreUsesServerPageAndDeduplicatesCanonicalIDs() async {
        let service = InvitationCreditServiceStub()
        await service.setInvitationResults([
            .success(.init(
                items: [record(id: "inv_1")],
                total: 3,
                page: 1,
                limit: 2
            )),
            .success(.init(
                items: [record(id: "inv_1"), record(id: "inv_2")],
                total: 3,
                page: 2,
                limit: 2
            ))
        ])
        let store = InvitationHistoryStore(service: service)

        await store.load(actorID: "act_a")
        await store.loadMore()

        let pages = await service.invitationCallPages()
        XCTAssertEqual(store.items.map(\.id), ["inv_1", "inv_2"])
        XCTAssertEqual(pages, [1, 2])
        XCTAssertFalse(store.hasMore)
        XCTAssertEqual(store.phase, .ready)
    }

    func testInitialEmptyPublishesEmptyPhase() async {
        let service = InvitationCreditServiceStub()
        await service.setInvitationResults([
            .success(.init(items: [], total: 0, page: 1, limit: 20))
        ])
        let store = InvitationHistoryStore(service: service)

        await store.load(actorID: "act_a")

        XCTAssertEqual(store.items, [])
        XCTAssertEqual(store.phase, .empty)
        XCTAssertFalse(store.hasMore)
    }

    func testLoadMoreFailureRetainsRowsAndCanRetrySamePage() async {
        let service = InvitationCreditServiceStub()
        await service.setInvitationResults([
            .success(.init(
                items: [record(id: "inv_1")],
                total: 2,
                page: 1,
                limit: 1
            )),
            .failure(InvitationCreditError.requestFailed(message: "Try again")),
            .success(.init(
                items: [record(id: "inv_2")],
                total: 2,
                page: 2,
                limit: 1
            ))
        ])
        let store = InvitationHistoryStore(service: service, pageSize: 1)
        await store.load(actorID: "act_a")

        await store.loadMore()
        XCTAssertEqual(store.items.map(\.id), ["inv_1"])
        XCTAssertEqual(
            store.paginationError,
            .requestFailed(message: "Try again")
        )

        await store.retry()

        let pages = await service.invitationCallPages()
        XCTAssertEqual(store.items.map(\.id), ["inv_1", "inv_2"])
        XCTAssertEqual(pages, [1, 2, 2])
        XCTAssertNil(store.paginationError)
    }

    private func record(id: String) -> InvitationRecord {
        .init(id: id, status: .registered, createdAt: Date(timeIntervalSince1970: 1))
    }
}
