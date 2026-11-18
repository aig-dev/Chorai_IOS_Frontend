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

        let first = Task { await store.load(cardID: "ast_old") }
        while await service.requestCount() == 0 {
            await Task.yield()
        }
        await store.load(cardID: "ast_new")
        await first.value

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

    func testReadInvalidationRemovesAncestorAndThenTarget() async {
        let value = DiscoveryPathSnapshot(
            collected: .fixture("target"),
            nodes: [.fixture("first", depth: 1), .fixture("second", depth: 0)],
            pathLength: 3
        )
        let store = DiscoveryPathStore(service: DiscoveryPathServiceStub(scripts: [
            .init(result: .success(value))
        ]))
        await store.load(cardID: "target")

        NotificationCenter.default.post(name: .cardReadInvalidated, object: "first")
        XCTAssertEqual(store.snapshot?.ancestors.map(\.id), ["second"])

        NotificationCenter.default.post(name: .cardReadInvalidated, object: "target")
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.phase, .failed(.forbidden))
    }

    func testSessionChangeRejectsInFlightPath() async {
        let value = DiscoveryPathSnapshot(collected: .fixture("old"), nodes: [], pathLength: 0)
        let service = DiscoveryPathServiceStub(scripts: [
            .init(delay: 80_000_000, result: .success(value))
        ])
        let store = DiscoveryPathStore(service: service)
        let load = Task { await store.load(cardID: "old") }
        while await service.requestCount() == 0 { await Task.yield() }

        NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
        await load.value
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.phase, .failed(.requestFailed(message: nil)))
    }

    func testInvalidationKeepsTheTargetReadStatus() async {
        for (status, expected) in [(401, DiscoveryPathError.unauthorized), (404, .invalidCard), (410, .invalidCard), (403, .forbidden)] {
            let value = DiscoveryPathSnapshot(collected: .fixture("target"), nodes: [], pathLength: 0)
            let store = DiscoveryPathStore(service: DiscoveryPathServiceStub(scripts: [.init(result: .success(value))]))
            await store.load(cardID: "target")
            NotificationCenter.default.post(name: .cardReadInvalidated, object: "target", userInfo: [CardReadInvalidation.statusKey: status])
            XCTAssertNil(store.snapshot)
            XCTAssertEqual(store.phase, .failed(expected))
        }
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
    private var requests = 0

    init(scripts: [Script]) {
        self.scripts = scripts
    }

    func discoveryPath(cardID: String) async throws -> DiscoveryPathSnapshot {
        requests += 1
        let script = scripts.removeFirst()
        if script.delay > 0 {
            try await Task.sleep(nanoseconds: script.delay)
        }
        return try script.result.get()
    }

    func requestCount() -> Int { requests }
}
