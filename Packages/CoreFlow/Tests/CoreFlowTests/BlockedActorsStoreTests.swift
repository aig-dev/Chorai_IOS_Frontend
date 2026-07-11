import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class BlockedActorsStoreTests: XCTestCase {
    func testLoadAndPaginationDeduplicateCanonicalOrder() async {
        let service = BlockedActorsServiceStub(pages: [
            .init(result: .success(.init(
                items: [.fixture("act_a"), .fixture("act_b")],
                nextCursor: "cursor-1",
                hasMore: true
            ))),
            .init(result: .success(.init(
                items: [.fixture("act_b"), .fixture("act_c")],
                nextCursor: nil,
                hasMore: false
            )))
        ])
        let store = BlockedActorsStore(service: service)

        store.load()
        await waitUntil { store.phase == .ready }
        store.loadMore()
        await waitUntil { store.phase == .ready && store.items.count == 3 }

        XCTAssertEqual(store.items.map(\.actorID), ["act_a", "act_b", "act_c"])
        XCTAssertFalse(store.hasMore)
    }

    func testSecondLoadRejectsStaleFirstResponse() async {
        let service = BlockedActorsServiceStub(pages: [
            .init(
                delay: 120_000_000,
                result: .success(.init(
                    items: [.fixture("act_old")],
                    nextCursor: nil,
                    hasMore: false
                ))
            ),
            .init(result: .success(.init(
                items: [.fixture("act_new")],
                nextCursor: nil,
                hasMore: false
            )))
        ])
        let store = BlockedActorsStore(service: service)

        store.load()
        await Task.yield()
        store.load()

        await waitUntil { store.items.map(\.actorID) == ["act_new"] }
        try? await Task.sleep(nanoseconds: 160_000_000)
        XCTAssertEqual(store.items.map(\.actorID), ["act_new"])
    }

    func testUnblockFailureRetainsRowThenSuccessRemovesItAndLocksDuplicates() async {
        let service = BlockedActorsServiceStub(
            pages: [.init(result: .success(.init(
                items: [.fixture("act_a")],
                nextCursor: nil,
                hasMore: false
            )))],
            unblockScripts: [
                .init(delay: 0, result: .failure(.transport(code: "offline"))),
                .init(delay: 80_000_000, result: .success(()))
            ]
        )
        let store = BlockedActorsStore(service: service)
        store.load()
        await waitUntil { store.phase == .ready }

        store.unblock(actorID: "act_a")
        await waitUntil {
            store.phase == .failed(
                operation: .unblock(actorID: "act_a"),
                error: .transport(code: "offline")
            )
        }
        XCTAssertEqual(store.items.map(\.actorID), ["act_a"])

        store.unblock(actorID: "act_a")
        store.unblock(actorID: "act_a")
        await waitUntil { store.phase == .empty }
        XCTAssertTrue(store.items.isEmpty)
        let requestCount = await service.requestCount()
        XCTAssertEqual(requestCount, 2)
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline { await Task.yield() }
        XCTAssertTrue(predicate())
    }
}

private extension BlockedActor {
    static func fixture(_ actorID: String) -> BlockedActor {
        .init(
            actorID: actorID,
            username: actorID,
            avatarURL: nil,
            bio: nil,
            blockedAt: "2026-07-11T12:00:00Z"
        )
    }
}

private actor BlockedActorsServiceStub: CoreCommunityProfileServing {
    struct PageScript: Sendable {
        let delay: UInt64
        let result: Result<BlockedActorPage, CommunitySocialError>

        init(
            delay: UInt64 = 0,
            result: Result<BlockedActorPage, CommunitySocialError>
        ) {
            self.delay = delay
            self.result = result
        }
    }
    struct UnblockScript: Sendable {
        let delay: UInt64
        let result: Result<Void, CommunitySocialError>
    }

    private var pages: [PageScript]
    private var unblockScripts: [UnblockScript]
    private var unblocks = 0

    init(pages: [PageScript], unblockScripts: [UnblockScript] = []) {
        self.pages = pages
        self.unblockScripts = unblockScripts
    }

    func blockedActors(cursor: String?, limit: Int) async throws -> BlockedActorPage {
        let script = pages.removeFirst()
        if script.delay > 0 { try await Task.sleep(nanoseconds: script.delay) }
        return try script.result.get()
    }

    func unblock(actorID: String) async throws {
        unblocks += 1
        let script = unblockScripts.removeFirst()
        if script.delay > 0 { try await Task.sleep(nanoseconds: script.delay) }
        try script.result.get()
    }

    func profile(actorID: String) async throws -> CommunityProfile { throw CommunitySocialError.notFound }
    func setFollowing(actorID: String, following: Bool) async throws { throw CommunitySocialError.notFound }
    func followList(actorID: String, kind: FollowListKind, cursor: String?, limit: Int) async throws -> FollowListPage { throw CommunitySocialError.notFound }
    func block(actorID: String) async throws { throw CommunitySocialError.notFound }
    func requestCount() -> Int { unblocks }
}
