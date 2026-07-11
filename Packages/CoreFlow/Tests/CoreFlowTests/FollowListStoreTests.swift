import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class FollowListStoreTests: XCTestCase {
    func testLoadPublishesCanonicalItemsAndEmptyState() async {
        let service = FollowListServiceStub(pages: [
            .success(.init(
                items: [.fixture("act_a")],
                nextCursor: nil,
                hasMore: false
            )),
            .success(.init(items: [], nextCursor: nil, hasMore: false))
        ])
        let store = FollowListStore(service: service)

        store.load(actorID: "act_owner", kind: .followers, viewerActorID: "act_me")
        await waitUntil { store.phase == .ready }
        XCTAssertEqual(store.items.map(\.actorID), ["act_a"])

        store.load(actorID: "act_owner", kind: .following, viewerActorID: "act_me")
        await waitUntil { store.phase == .empty }
        XCTAssertTrue(store.items.isEmpty)
    }

    func testForbiddenLoadUsesPrivateStateInsteadOfEmpty() async {
        let service = FollowListServiceStub(pages: [.failure(.forbidden)])
        let store = FollowListStore(service: service)

        store.load(actorID: "act_owner", kind: .followers, viewerActorID: "act_me")

        await waitUntil { store.phase == .privateList }
        XCTAssertTrue(store.items.isEmpty)
    }

    func testPaginationDeduplicatesAndStopsOnRepeatedCursor() async {
        let service = FollowListServiceStub(pages: [
            .success(.init(
                items: [.fixture("act_a"), .fixture("act_b")],
                nextCursor: "cursor-1",
                hasMore: true
            )),
            .success(.init(
                items: [.fixture("act_b"), .fixture("act_c")],
                nextCursor: "cursor-1",
                hasMore: true
            ))
        ])
        let store = FollowListStore(service: service)

        store.load(actorID: "act_owner", kind: .followers, viewerActorID: "act_me")
        await waitUntil { store.phase == .ready }
        store.loadMore()
        await waitUntil { store.phase == .ready && store.items.count == 3 }

        XCTAssertEqual(store.items.map(\.actorID), ["act_a", "act_b", "act_c"])
        XCTAssertFalse(store.hasMore)
        store.loadMore()
        let requests = await service.pageRequests()
        XCTAssertEqual(requests.map(\.cursor), [nil, "cursor-1"])
    }

    func testSelfRowCannotMutateAndDuplicateFollowTapSendsOneRequest() async {
        let service = FollowListServiceStub(
            pages: [.success(.init(
                items: [
                    .fixture("act_me"),
                    .fixture("act_other", isFollowing: false, followerCount: 2)
                ],
                nextCursor: nil,
                hasMore: false
            ))],
            followScripts: [.init(
                delay: 80_000_000,
                result: .success(())
            )]
        )
        let store = FollowListStore(service: service)
        store.load(actorID: "act_owner", kind: .followers, viewerActorID: "act_me")
        await waitUntil { store.phase == .ready }

        store.toggleFollow(actorID: "act_me")
        store.toggleFollow(actorID: "act_other")
        store.toggleFollow(actorID: "act_other")

        await waitUntil {
            store.items.first(where: { $0.actorID == "act_other" })?.isFollowing == true
        }
        let requests = await service.followRequests()
        XCTAssertEqual(requests, [
            .init(actorID: "act_other", following: true)
        ])
        XCTAssertEqual(
            store.items.first(where: { $0.actorID == "act_other" })?.followerCount,
            3
        )
    }

    func testFollowFailureKeepsExactRowForRetry() async {
        let service = FollowListServiceStub(
            pages: [.success(.init(
                items: [.fixture("act_a", isFollowing: true, followerCount: 0)],
                nextCursor: nil,
                hasMore: false
            ))],
            followScripts: [
                .init(delay: 0, result: .failure(.transport(code: "offline"))),
                .init(delay: 0, result: .success(()))
            ]
        )
        let store = FollowListStore(service: service)
        store.load(actorID: "act_owner", kind: .followers, viewerActorID: "act_me")
        await waitUntil { store.phase == .ready }
        let committed = store.items

        store.toggleFollow(actorID: "act_a")
        await waitUntil {
            store.phase == .failed(
                operation: .follow(actorID: "act_a"),
                error: .transport(code: "offline")
            )
        }
        XCTAssertEqual(store.items, committed)

        store.toggleFollow(actorID: "act_a")
        await waitUntil { store.phase == .ready && !store.items[0].isFollowing }
        XCTAssertEqual(store.items[0].followerCount, 0)
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

private extension CommunityActor {
    static func fixture(
        _ actorID: String,
        isFollowing: Bool = false,
        followerCount: Int = 1
    ) -> CommunityActor {
        .init(
            actorID: actorID,
            username: actorID,
            avatarURL: nil,
            bio: nil,
            followerCount: followerCount,
            followingCount: 0,
            isFollowing: isFollowing
        )
    }
}

private actor FollowListServiceStub: CoreCommunityProfileServing {
    struct PageRequest: Equatable, Sendable {
        let actorID: String
        let kind: FollowListKind
        let cursor: String?
    }
    struct FollowRequest: Equatable, Sendable {
        let actorID: String
        let following: Bool
    }
    struct FollowScript: Sendable {
        let delay: UInt64
        let result: Result<Void, CommunitySocialError>
    }

    private var pages: [Result<FollowListPage, CommunitySocialError>]
    private var followScripts: [FollowScript]
    private var recordedPages: [PageRequest] = []
    private var recordedFollows: [FollowRequest] = []

    init(
        pages: [Result<FollowListPage, CommunitySocialError>],
        followScripts: [FollowScript] = []
    ) {
        self.pages = pages
        self.followScripts = followScripts
    }

    func followList(actorID: String, kind: FollowListKind, cursor: String?, limit: Int) async throws -> FollowListPage {
        recordedPages.append(.init(actorID: actorID, kind: kind, cursor: cursor))
        return try pages.removeFirst().get()
    }

    func setFollowing(actorID: String, following: Bool) async throws {
        recordedFollows.append(.init(actorID: actorID, following: following))
        let script = followScripts.removeFirst()
        if script.delay > 0 { try await Task.sleep(nanoseconds: script.delay) }
        try script.result.get()
    }

    func profile(actorID: String) async throws -> CommunityProfile { throw CommunitySocialError.notFound }
    func blockedActors(cursor: String?, limit: Int) async throws -> BlockedActorPage { throw CommunitySocialError.notFound }
    func block(actorID: String) async throws { throw CommunitySocialError.notFound }
    func unblock(actorID: String) async throws { throw CommunitySocialError.notFound }
    func pageRequests() -> [PageRequest] { recordedPages }
    func followRequests() -> [FollowRequest] { recordedFollows }
}
