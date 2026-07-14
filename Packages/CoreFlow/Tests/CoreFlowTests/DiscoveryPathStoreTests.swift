import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class DiscoveryPathStoreTests: XCTestCase {
    func testSnapshotOrdersDirectPredecessorToOriginAndDeduplicates() {
        let collected = DiscoveryPathCard.fixture("ast_collected")
        let snapshot = DiscoveryPathSnapshot(
            collected: collected,
            nodes: [
                .fixture("ast_origin", depth: 0),
                .fixture("ast_collected", depth: 2),
                .fixture("ast_direct", depth: 0),
                .fixture("ast_direct", depth: 1)
            ],
            pathLength: 4
        )

        XCTAssertEqual(
            snapshot.ancestors.map(\.card.id),
            ["ast_direct", "ast_origin"]
        )
        XCTAssertEqual(snapshot.pathLength, 4)
    }

    func testLoadPublishesReadyAndEmptySnapshots() async {
        let ready = DiscoveryPathSnapshot(
            collected: .fixture("ast_collected"),
            nodes: [.fixture("ast_origin", depth: 0)],
            pathLength: 2
        )
        let empty = DiscoveryPathSnapshot(
            collected: .fixture("ast_plain"),
            nodes: [],
            pathLength: 0
        )
        let service = DiscoveryPathServiceStub(scripts: [
            .init(result: .success(ready)),
            .init(result: .success(empty))
        ])
        let store = DiscoveryPathStore(service: service)

        await store.load(cardID: " ast_collected ")
        XCTAssertEqual(store.cardID, "ast_collected")
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.snapshot, ready)

        await store.load(cardID: "ast_plain")
        XCTAssertEqual(store.phase, .empty)
        XCTAssertEqual(store.snapshot, empty)
    }

    func testSecondLoadRejectsStaleFirstResponse() async {
        let service = DiscoveryPathServiceStub(scripts: [
            .init(
                delay: 120_000_000,
                result: .success(.init(
                    collected: .fixture("ast_old"),
                    nodes: [],
                    pathLength: 0
                ))
            ),
            .init(result: .success(.init(
                collected: .fixture("ast_new"),
                nodes: [],
                pathLength: 0
            )))
        ])
        let store = DiscoveryPathStore(service: service)

        async let first: Void = store.load(cardID: "ast_old")
        await Task.yield()
        await store.load(cardID: "ast_new")
        _ = await first

        XCTAssertEqual(store.cardID, "ast_new")
        XCTAssertEqual(store.snapshot?.collected.id, "ast_new")
        XCTAssertEqual(store.phase, .empty)
    }

    func testInvalidCardAndFailureAreRetryable() async {
        let recovered = DiscoveryPathSnapshot(
            collected: .fixture("ast_recovered"),
            nodes: [],
            pathLength: 0
        )
        let service = DiscoveryPathServiceStub(scripts: [
            .init(result: .failure(.requestFailed(message: "Offline"))),
            .init(result: .success(recovered))
        ])
        let store = DiscoveryPathStore(service: service)

        await store.load(cardID: "  ")
        XCTAssertEqual(store.phase, .failed(.invalidCard))

        await store.load(cardID: "ast_recovered")
        XCTAssertEqual(
            store.phase,
            .failed(.requestFailed(message: "Offline"))
        )
        await store.retry()
        XCTAssertEqual(store.phase, .empty)
        XCTAssertEqual(store.snapshot, recovered)
    }
}

private extension DiscoveryPathCard {
    static func fixture(_ id: String) -> DiscoveryPathCard {
        .init(
            id: id,
            title: id,
            content: "Content for \(id)",
            tags: ["fixture"],
            createdAt: "2026-07-14T00:00:00Z",
            authorActorID: "act_fixture",
            authorName: "Fixture",
            avatarURL: nil,
            rate: 3
        )
    }
}

private extension DiscoveryPathNode {
    static func fixture(_ id: String, depth: Int) -> DiscoveryPathNode {
        .init(
            card: .fixture(id),
            versionID: "ver_\(id)",
            activityID: "actv_\(id)",
            depth: depth
        )
    }
}

private actor DiscoveryPathServiceStub: CoreDiscoveryPathServing {
    struct Script: Sendable {
        let delay: UInt64
        let result: Result<DiscoveryPathSnapshot, DiscoveryPathError>

        init(
            delay: UInt64 = 0,
            result: Result<DiscoveryPathSnapshot, DiscoveryPathError>
        ) {
            self.delay = delay
            self.result = result
        }
    }

    private var scripts: [Script]

    init(scripts: [Script]) {
        self.scripts = scripts
    }

    func discoveryPath(cardID: String) async throws -> DiscoveryPathSnapshot {
        let script = scripts.removeFirst()
        if script.delay > 0 {
            try await Task.sleep(nanoseconds: script.delay)
        }
        return try script.result.get()
    }
}
