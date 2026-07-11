import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class NotificationInboxStoreTests: XCTestCase {
    func testInitialLoadPublishesCanonicalPageAndServerUnreadCount() async {
        let service = NotificationServiceStub(pages: [
            .success(.init(
                items: [.fixture("ntf_a"), .fixture("ntf_b", isRead: true)],
                page: 1,
                perPage: 20,
                total: 2,
                unreadCount: 7
            ))
        ])
        let store = NotificationInboxStore(service: service)

        store.load(actorID: " act_owner ")
        await waitUntil { store.phase == .ready }

        XCTAssertEqual(store.items.map(\.id), ["ntf_a", "ntf_b"])
        XCTAssertEqual(store.unreadCount, 7, "server unread count is canonical")
        XCTAssertFalse(store.hasMore)
        let requests = await service.pageRequests()
        XCTAssertEqual(requests, [.init(page: 1, perPage: 20)])
    }

    func testPaginationDeduplicatesAndStopsAtLastPage() async {
        let service = NotificationServiceStub(pages: [
            .success(.init(
                items: [.fixture("ntf_a"), .fixture("ntf_b")],
                page: 1,
                perPage: 20,
                total: 3,
                unreadCount: 3
            )),
            .success(.init(
                items: [.fixture("ntf_b"), .fixture("ntf_c")],
                page: 2,
                perPage: 20,
                total: 3,
                unreadCount: 3
            ))
        ])
        let store = NotificationInboxStore(service: service)

        store.load(actorID: "act_owner")
        await waitUntil { store.phase == .ready }
        XCTAssertTrue(store.hasMore)

        store.loadMore()
        await waitUntil { store.phase == .ready && store.items.count == 3 }

        XCTAssertEqual(store.items.map(\.id), ["ntf_a", "ntf_b", "ntf_c"])
        XCTAssertFalse(store.hasMore)
        store.loadMore()
        let requests = await service.pageRequests()
        XCTAssertEqual(requests.map(\.page), [1, 2])
    }

    func testReloadAndActorChangeRejectStaleResponses() async {
        let service = NotificationServiceStub(pageScripts: [
            .init(
                delay: 150_000_000,
                result: .success(.init(
                    items: [.fixture("ntf_old")], page: 1, perPage: 20,
                    total: 1, unreadCount: 1
                ))
            ),
            .init(result: .success(.init(
                items: [.fixture("ntf_new")], page: 1, perPage: 20,
                total: 1, unreadCount: 1
            ))),
            .init(result: .success(.init(
                items: [.fixture("ntf_reloaded", isRead: true)],
                page: 1, perPage: 20, total: 1, unreadCount: 0
            )))
        ])
        let store = NotificationInboxStore(service: service)

        store.load(actorID: "act_old")
        await Task.yield()
        store.load(actorID: "act_new")
        await waitUntil { store.items.map(\.id) == ["ntf_new"] }
        try? await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertEqual(store.items.map(\.id), ["ntf_new"])

        store.reload()
        await waitUntil { store.items.map(\.id) == ["ntf_reloaded"] }
        XCTAssertEqual(store.unreadCount, 0)
    }

    func testFiltersSeparateUnreadActivityAndSystem() async {
        let service = NotificationServiceStub(pages: [
            .success(.init(
                items: [
                    .fixture("follow", kind: .follow),
                    .fixture("like", kind: .like, isRead: true),
                    .fixture("comment", kind: .comment),
                    .fixture("system", kind: .system),
                    .fixture("legacy", kind: .legacy)
                ],
                page: 1, perPage: 20, total: 5, unreadCount: 4
            ))
        ])
        let store = NotificationInboxStore(service: service)
        store.load(actorID: "act_owner")
        await waitUntil { store.phase == .ready }

        XCTAssertEqual(store.filteredItems(.all).count, 5)
        XCTAssertEqual(store.filteredItems(.unread).map(\.id), ["follow", "comment", "system", "legacy"])
        XCTAssertEqual(store.filteredItems(.activity).map(\.id), ["follow", "like", "comment"])
        XCTAssertEqual(store.filteredItems(.system).map(\.id), ["system", "legacy"])
    }

    func testMarkReadOptimisticallyUpdatesAndLocksDuplicateRequests() async {
        let service = NotificationServiceStub(
            pages: [.success(.init(
                items: [.fixture("ntf_a")], page: 1, perPage: 20,
                total: 1, unreadCount: 1
            ))],
            marks: [.init(
                expectedID: "ntf_a",
                delay: 100_000_000,
                result: .success(())
            )]
        )
        let store = NotificationInboxStore(service: service)
        store.load(actorID: "act_owner")
        await waitUntil { store.phase == .ready }

        store.markRead(notificationID: "ntf_a")
        store.markRead(notificationID: "ntf_a")

        XCTAssertTrue(store.items[0].isRead)
        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertEqual(store.mutatingIDs, ["ntf_a"])
        await waitUntil { store.mutatingIDs.isEmpty }
        let requests = await service.markRequests()
        XCTAssertEqual(requests, ["ntf_a"])
        XCTAssertNil(store.actionFailure)
    }

    func testMarkReadFailureRestoresExactUnreadState() async {
        let initial = CommunityNotification.fixture("ntf_a")
        let service = NotificationServiceStub(
            pages: [.success(.init(
                items: [initial], page: 1, perPage: 20,
                total: 1, unreadCount: 5
            ))],
            marks: [.init(
                expectedID: "ntf_a",
                result: .failure(.transport(code: "offline"))
            )]
        )
        let store = NotificationInboxStore(service: service)
        store.load(actorID: "act_owner")
        await waitUntil { store.phase == .ready }

        store.markRead(notificationID: "ntf_a")
        await waitUntil { store.actionFailure != nil }

        XCTAssertEqual(store.items, [initial])
        XCTAssertFalse(store.items[0].isRead)
        XCTAssertEqual(store.unreadCount, 5)
        XCTAssertEqual(
            store.actionFailure,
            .init(
                operation: .markRead(id: "ntf_a"),
                error: .transport(code: "offline")
            )
        )
    }

    func testReadAllLoadedSuccessCommitsEveryLoadedRow() async {
        let service = NotificationServiceStub(
            pages: [.success(.init(
                items: [
                    .fixture("ntf_a"),
                    .fixture("ntf_b"),
                    .fixture("ntf_read", isRead: true)
                ],
                page: 1, perPage: 20, total: 3, unreadCount: 2
            ))],
            marks: [
                .init(expectedID: "ntf_a", result: .success(())),
                .init(expectedID: "ntf_b", result: .success(()))
            ]
        )
        let store = NotificationInboxStore(service: service)
        store.load(actorID: "act_owner")
        await waitUntil { store.phase == .ready }

        store.markAllLoadedRead()
        await waitUntil { !store.isMarkingAll }

        XCTAssertTrue(store.items.allSatisfy(\.isRead))
        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertNil(store.actionFailure)
        let requests = await service.markRequests()
        XCTAssertEqual(requests, ["ntf_a", "ntf_b"])
    }

    func testReadAllPartialFailureRestoresThenReloadsCanonicalPages() async {
        let initialA = CommunityNotification.fixture("ntf_a")
        let initialB = CommunityNotification.fixture("ntf_b")
        let initialC = CommunityNotification.fixture("ntf_c")
        let canonicalA = CommunityNotification.fixture("ntf_a", isRead: true)
        let service = NotificationServiceStub(
            pages: [
                .success(.init(
                    items: [initialA, initialB], page: 1, perPage: 20,
                    total: 3, unreadCount: 3
                )),
                .success(.init(
                    items: [initialC], page: 2, perPage: 20,
                    total: 3, unreadCount: 3
                )),
                .success(.init(
                    items: [canonicalA, initialB], page: 1, perPage: 20,
                    total: 3, unreadCount: 2
                )),
                .success(.init(
                    items: [initialC], page: 2, perPage: 20,
                    total: 3, unreadCount: 2
                ))
            ],
            marks: [
                .init(expectedID: "ntf_a", result: .success(())),
                .init(
                    expectedID: "ntf_b",
                    result: .failure(.transport(code: "partial"))
                )
            ]
        )
        let store = NotificationInboxStore(service: service)
        store.load(actorID: "act_owner")
        await waitUntil { store.phase == .ready }
        store.loadMore()
        await waitUntil { store.items.count == 3 && store.phase == .ready }

        store.markAllLoadedRead()
        await waitUntil { !store.isMarkingAll && store.actionFailure != nil }

        XCTAssertEqual(store.items, [canonicalA, initialB, initialC])
        XCTAssertEqual(store.unreadCount, 2)
        XCTAssertEqual(
            store.actionFailure,
            .init(
                operation: .markAllRead,
                error: .transport(code: "partial")
            )
        )
        let pages = await service.pageRequests()
        XCTAssertEqual(pages.map(\.page), [1, 2, 1, 2])
    }

    func testLegacyNotificationNeverExposesTarget() async {
        let legacy = CommunityNotification(
            id: "legacy",
            kind: .legacy,
            displayText: "Legacy notice",
            sourceActor: nil,
            target: .actor("act_should_not_escape"),
            isRead: false,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let system = CommunityNotification(
            id: "system",
            kind: .system,
            displayText: "System notice",
            sourceActor: nil,
            target: .asset("ast_should_not_escape"),
            isRead: false,
            createdAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(legacy.target, .legacy)
        XCTAssertEqual(system.target, .legacy)

        let raw = Data(#"""
        {
            "id":"decoded-system",
            "kind":"system",
            "displayText":"Decoded system",
            "sourceActor":null,
            "target":{"actor":{"_0":"act_should_not_escape"}},
            "isRead":false,
            "createdAt":0
        }
        """#.utf8)
        let decoded = try? JSONDecoder().decode(
            CommunityNotification.self,
            from: raw
        )
        XCTAssertEqual(decoded?.target, .legacy)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline { await Task.yield() }
        XCTAssertTrue(predicate())
    }
}

private extension CommunityNotification {
    static func fixture(
        _ id: String,
        kind: CommunityNotificationKind = .follow,
        isRead: Bool = false
    ) -> CommunityNotification {
        .init(
            id: id,
            kind: kind,
            displayText: id,
            sourceActor: nil,
            target: kind == .follow ? .actor("act_\(id)") : .asset("ast_\(id)"),
            isRead: isRead,
            createdAt: Date(timeIntervalSince1970: TimeInterval(abs(id.hashValue % 1_000)))
        )
    }
}

private actor NotificationServiceStub: CoreNotificationServing {
    struct PageRequest: Equatable, Sendable {
        let page: Int
        let perPage: Int
    }

    struct PageScript: Sendable {
        let delay: UInt64
        let result: Result<NotificationPage, NotificationInboxError>

        init(
            delay: UInt64 = 0,
            result: Result<NotificationPage, NotificationInboxError>
        ) {
            self.delay = delay
            self.result = result
        }
    }

    struct MarkScript: Sendable {
        let expectedID: String
        let delay: UInt64
        let result: Result<Void, NotificationInboxError>

        init(
            expectedID: String,
            delay: UInt64 = 0,
            result: Result<Void, NotificationInboxError>
        ) {
            self.expectedID = expectedID
            self.delay = delay
            self.result = result
        }
    }

    private var pages: [PageScript]
    private var marks: [MarkScript]
    private var recordedPages: [PageRequest] = []
    private var recordedMarks: [String] = []

    init(
        pages: [Result<NotificationPage, NotificationInboxError>],
        marks: [MarkScript] = []
    ) {
        self.pages = pages.map { PageScript(result: $0) }
        self.marks = marks
    }

    init(
        pageScripts: [PageScript],
        marks: [MarkScript] = []
    ) {
        self.pages = pageScripts
        self.marks = marks
    }

    func notifications(page: Int, perPage: Int) async throws -> NotificationPage {
        recordedPages.append(.init(page: page, perPage: perPage))
        let script = pages.removeFirst()
        if script.delay > 0 { try await Task.sleep(nanoseconds: script.delay) }
        return try script.result.get()
    }

    func markRead(notificationID: String) async throws {
        recordedMarks.append(notificationID)
        let script = marks.removeFirst()
        precondition(script.expectedID == notificationID)
        if script.delay > 0 { try await Task.sleep(nanoseconds: script.delay) }
        try script.result.get()
    }

    func pageRequests() -> [PageRequest] { recordedPages }
    func markRequests() -> [String] { recordedMarks }
}
