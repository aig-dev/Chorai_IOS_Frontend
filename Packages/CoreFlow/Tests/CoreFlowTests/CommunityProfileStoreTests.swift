import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class CommunityProfileStoreTests: XCTestCase {
    func testLoadPublishesCanonicalProfile() async {
        let service = ScriptedCommunityService(profiles: [
            "act_a": .init(delay: 0, result: .success(.fixture(actorID: "act_a")))
        ])
        let store = CommunityProfileStore(service: service)

        store.load(actorID: "act_a")

        await waitUntil { store.phase == .ready }
        XCTAssertEqual(store.profile, .fixture(actorID: "act_a"))
    }

    func testInvalidActorFailsWithoutCallingService() async {
        let service = ScriptedCommunityService()
        let store = CommunityProfileStore(service: service)

        store.load(actorID: "  ")

        XCTAssertEqual(
            store.phase,
            .failed(operation: .load, error: .invalidActor)
        )
        XCTAssertNil(store.profile)
        let requests = await service.profileRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testActorChangeRejectsStaleProfileResponse() async {
        let service = ScriptedCommunityService(profiles: [
            "act_old": .init(
                delay: 120_000_000,
                result: .success(.fixture(actorID: "act_old"))
            ),
            "act_new": .init(
                delay: 0,
                result: .success(.fixture(actorID: "act_new"))
            )
        ])
        let store = CommunityProfileStore(service: service)

        store.load(actorID: "act_old")
        await Task.yield()
        store.load(actorID: "act_new")

        await waitUntil { store.profile?.actorID == "act_new" }
        try? await Task.sleep(nanoseconds: 160_000_000)
        XCTAssertEqual(store.profile?.actorID, "act_new")
        XCTAssertEqual(store.phase, .ready)
    }

    func testFollowCommitsAfterSuccessAndLocksDuplicateTaps() async {
        let initial = CommunityProfile.fixture(
            actorID: "act_a",
            isFollowing: false,
            followerCount: 4
        )
        let service = ScriptedCommunityService(
            profiles: ["act_a": .init(delay: 0, result: .success(initial))],
            followScripts: [
                .init(delay: 80_000_000, result: .success(()))
            ]
        )
        let store = CommunityProfileStore(service: service)
        store.load(actorID: "act_a")
        await waitUntil { store.phase == .ready }

        store.toggleFollow()
        store.toggleFollow()

        XCTAssertEqual(store.profile, initial)
        await waitUntil { store.profile?.isFollowing == true }
        XCTAssertEqual(store.profile?.followerCount, 5)
        let requests = await service.followRequests()
        XCTAssertEqual(requests, [
            .init(actorID: "act_a", following: true)
        ])
    }

    func testUnfollowFailurePreservesStateAndCountForRetry() async {
        let initial = CommunityProfile.fixture(
            actorID: "act_a",
            isFollowing: true,
            followerCount: 0
        )
        let service = ScriptedCommunityService(
            profiles: ["act_a": .init(delay: 0, result: .success(initial))],
            followScripts: [
                .init(
                    delay: 0,
                    result: .failure(.transport(code: "offline"))
                ),
                .init(delay: 0, result: .success(()))
            ]
        )
        let store = CommunityProfileStore(service: service)
        store.load(actorID: "act_a")
        await waitUntil { store.phase == .ready }

        store.toggleFollow()
        await waitUntil {
            store.phase == .failed(
                operation: .follow,
                error: .transport(code: "offline")
            )
        }
        XCTAssertEqual(store.profile, initial)

        store.toggleFollow()
        await waitUntil { store.phase == .ready && store.profile?.isFollowing == false }
        XCTAssertEqual(store.profile?.followerCount, 0)
    }

    func testBlockIsSuccessGatedAndFailureKeepsProfileVisible() async {
        let initial = CommunityProfile.fixture(actorID: "act_a")
        let service = ScriptedCommunityService(
            profiles: ["act_a": .init(delay: 0, result: .success(initial))],
            blockScripts: [
                .failure(.transport(code: "offline")),
                .success(())
            ]
        )
        let store = CommunityProfileStore(service: service)
        store.load(actorID: "act_a")
        await waitUntil { store.phase == .ready }

        store.block()
        await waitUntil {
            store.phase == .failed(
                operation: .block,
                error: .transport(code: "offline")
            )
        }
        XCTAssertEqual(store.profile, initial)
        XCTAssertFalse(store.didBlock)

        store.block()
        await waitUntil { store.phase == .blocked }
        XCTAssertTrue(store.didBlock)
        let requests = await service.blockRequests()
        XCTAssertEqual(requests, ["act_a", "act_a"])
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            await Task.yield()
        }
        XCTAssertTrue(predicate())
    }
}

private extension CommunityProfile {
    static func fixture(
        actorID: String,
        isFollowing: Bool = false,
        followerCount: Int = 3
    ) -> CommunityProfile {
        .init(
            actorID: actorID,
            username: "User \(actorID)",
            avatarURL: "/avatar.png",
            bio: "Bio",
            followerCount: followerCount,
            followingCount: 2,
            isFollowing: isFollowing
        )
    }
}

private actor ScriptedCommunityService: CoreCommunityProfileServing {
    struct ProfileScript: Sendable {
        let delay: UInt64
        let result: Result<CommunityProfile, CommunitySocialError>
    }

    struct VoidScript: Sendable {
        let delay: UInt64
        let result: Result<Void, CommunitySocialError>
    }

    struct FollowRequest: Equatable, Sendable {
        let actorID: String
        let following: Bool
    }

    private var profiles: [String: ProfileScript]
    private var followScripts: [VoidScript]
    private var blockScripts: [Result<Void, CommunitySocialError>]
    private var recordedProfiles: [String] = []
    private var recordedFollows: [FollowRequest] = []
    private var recordedBlocks: [String] = []

    init(
        profiles: [String: ProfileScript] = [:],
        followScripts: [VoidScript] = [],
        blockScripts: [Result<Void, CommunitySocialError>] = []
    ) {
        self.profiles = profiles
        self.followScripts = followScripts
        self.blockScripts = blockScripts
    }

    func profile(actorID: String) async throws -> CommunityProfile {
        recordedProfiles.append(actorID)
        guard let script = profiles[actorID] else {
            throw CommunitySocialError.notFound
        }
        if script.delay > 0 {
            try await Task.sleep(nanoseconds: script.delay)
        }
        return try script.result.get()
    }

    func setFollowing(actorID: String, following: Bool) async throws {
        recordedFollows.append(.init(actorID: actorID, following: following))
        let script = followScripts.removeFirst()
        if script.delay > 0 {
            try await Task.sleep(nanoseconds: script.delay)
        }
        try script.result.get()
    }

    func block(actorID: String) async throws {
        recordedBlocks.append(actorID)
        try blockScripts.removeFirst().get()
    }

    func followList(
        actorID: String,
        kind: FollowListKind,
        cursor: String?,
        limit: Int
    ) async throws -> FollowListPage {
        throw CommunitySocialError.notFound
    }

    func blockedActors(cursor: String?, limit: Int) async throws -> BlockedActorPage {
        throw CommunitySocialError.notFound
    }

    func unblock(actorID: String) async throws {
        throw CommunitySocialError.notFound
    }

    func profileRequests() -> [String] { recordedProfiles }
    func followRequests() -> [FollowRequest] { recordedFollows }
    func blockRequests() -> [String] { recordedBlocks }
}
