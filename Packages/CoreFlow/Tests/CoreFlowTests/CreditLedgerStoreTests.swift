import XCTest
@testable import CoreFlow

@MainActor
final class CreditLedgerStoreTests: XCTestCase {
    func testAppendDeduplicatesLogIDsAndUsesReturnedCursor() async {
        let service = InvitationCreditServiceStub()
        await service.setLedgerResults([
            .success(.init(
                entries: [entry(id: "log_1")],
                cursor: "cursor_1",
                hasMore: true
            )),
            .success(.init(
                entries: [entry(id: "log_1"), entry(id: "log_2")],
                cursor: nil,
                hasMore: false
            ))
        ])
        let store = CreditLedgerStore(service: service)

        await store.load(actorID: "act_a")
        await store.loadMore()

        let cursors = await service.ledgerCallCursors()
        XCTAssertEqual(store.entries.map(\.id), ["log_1", "log_2"])
        XCTAssertEqual(cursors, [nil, "cursor_1"])
        XCTAssertFalse(store.hasMore)
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.entries.last?.account, "actor")
        XCTAssertEqual(store.entries.last?.ruleID, "rule_invitation")
        XCTAssertEqual(store.entries.last?.referenceID, "invitation_1")
    }

    func testLoadMoreFailureRetainsEntriesAndCursorForRetry() async {
        let service = InvitationCreditServiceStub()
        await service.setLedgerResults([
            .success(.init(
                entries: [entry(id: "log_1")],
                cursor: "cursor_1",
                hasMore: true
            )),
            .failure(InvitationCreditError.requestFailed(message: nil)),
            .success(.init(
                entries: [entry(id: "log_2")],
                cursor: nil,
                hasMore: false
            ))
        ])
        let store = CreditLedgerStore(service: service)
        await store.load(actorID: "act_a")

        await store.loadMore()
        XCTAssertEqual(store.entries.map(\.id), ["log_1"])
        XCTAssertEqual(
            store.paginationError,
            .requestFailed(message: nil)
        )

        await store.retry()

        let cursors = await service.ledgerCallCursors()
        XCTAssertEqual(store.entries.map(\.id), ["log_1", "log_2"])
        XCTAssertEqual(cursors, [nil, "cursor_1", "cursor_1"])
    }

    func testHasMoreWithoutCursorIsContractFailure() async {
        let service = InvitationCreditServiceStub()
        await service.setLedgerResults([
            .success(.init(
                entries: [entry(id: "log_1")],
                cursor: nil,
                hasMore: true
            ))
        ])
        let store = CreditLedgerStore(service: service)

        await store.load(actorID: "act_a")

        XCTAssertEqual(
            store.phase,
            .failed(.contract(code: "missing_ledger_cursor"))
        )
        XCTAssertEqual(store.entries, [])
    }

    private func entry(id: String) -> CreditLedgerEntry {
        .init(
            id: id,
            transactionID: "tx_\(id)",
            account: "actor",
            direction: .earn,
            delta: 5,
            runningBalance: 10,
            status: .settled,
            ruleID: "rule_invitation",
            actionType: "INVITATION_REWARD",
            category: "growth",
            referenceID: "invitation_1",
            referenceType: "invitation",
            activityID: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            settledAt: Date(timeIntervalSince1970: 2),
            refundedAt: nil
        )
    }
}
