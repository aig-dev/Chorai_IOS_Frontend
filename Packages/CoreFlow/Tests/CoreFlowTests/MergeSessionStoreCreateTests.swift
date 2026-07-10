import XCTest
@testable import CoreFlow

@MainActor
final class MergeSessionStoreCreateTests: XCTestCase {
    func testSelectionKeepsAnchorFirstAndDistinctCompanionOrder() async {
        let service = MockCoreMergeService()
        await service.enqueueCapabilities(.success([makeMergeCapability()]))
        let store = makeStore(service: service)
        store.start()
        await waitForMergeStore { store.phase == .selection }

        store.toggleSelection(makeMergeSource("ast_b", preview: "B first"))
        store.toggleSelection(makeMergeSource("ast_anchor", preview: "Duplicate"))
        store.toggleSelection(makeMergeSource("ast_a", preview: "A"))
        store.toggleSelection(makeMergeSource("ast_b", preview: "B duplicate"))
        store.toggleSelection(makeMergeSource("ast_b", preview: "B third"))

        XCTAssertEqual(
            store.selectedSources.map(\.assetID),
            ["ast_anchor", "ast_a", "ast_b"]
        )
        XCTAssertTrue(store.canCreate)
    }

    func testCreatePersistsStableRequestBeforeServiceCall() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        let eventLog = LockedMergeEventLog()
        persistence.onSave = { _ in eventLog.append("save") }
        await service.setCreateObserver { _ in eventLog.append("create") }
        await service.enqueueCapabilities(.success([makeMergeCapability()]))
        await service.enqueueCreate(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await service.enqueueArtifact(.success(makeMergeArtifact()))
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: ["create-stable"]
        )
        store.start()
        await waitForMergeStore { store.phase == .selection }
        store.toggleSelection(makeMergeSource("ast_companion"))

        store.create()
        store.create()
        await waitForMergeStore { store.phase == .ready }

        XCTAssertEqual(eventLog.events.first, "save")
        XCTAssertEqual(eventLog.events.filter { $0 == "create" }.count, 1)
        let calls = await service.createCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.idempotencyKey, "create-stable")
        XCTAssertEqual(
            persistence.saves.first?.createRequest.idempotencyKey,
            "create-stable"
        )
        XCTAssertEqual(persistence.saves.first?.jobID, nil)
    }

    func testAmbiguousCreateRetryReusesExactRequest() async {
        let service = MockCoreMergeService()
        let persistence = InMemoryMergeSessionPersistence()
        await service.enqueueCapabilities(.success([makeMergeCapability()]))
        await service.enqueueCreate(.failure(.offline))
        await service.enqueueCreate(
            .success(makeMergeJob(status: .artifactReady, artifactID: "artifact_1"))
        )
        await service.enqueueArtifact(.success(makeMergeArtifact()))
        let store = makeStore(
            service: service,
            persistence: persistence,
            keys: ["create-stable", "must-not-be-used"]
        )
        store.start()
        await waitForMergeStore { store.phase == .selection }
        store.toggleSelection(makeMergeSource("ast_companion"))

        store.create()
        await waitForMergeStore { store.phase == .paused(.offline) }
        store.retry()
        await waitForMergeStore { store.phase == .ready }

        let calls = await service.createCalls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0], calls[1])
        XCTAssertEqual(calls[1].idempotencyKey, "create-stable")
    }

    func testUnavailableCapabilitiesDoNotExposeCreate() async {
        let service = MockCoreMergeService()
        await service.enqueueCapabilities(
            .success([
                makeMergeCapability(enabled: false),
                makeMergeCapability(
                    id: "fragment_only",
                    enabled: true,
                    outputKind: .blockFragment
                )
            ])
        )
        let store = makeStore(service: service)

        store.start()
        await waitForMergeStore {
            store.phase == .failed(.unavailable(code: "merge_disabled"))
        }

        XCTAssertFalse(store.canCreate)
        let createCalls = await service.createCalls
        XCTAssertTrue(createCalls.isEmpty)
    }

    private func makeStore(
        service: MockCoreMergeService,
        persistence: InMemoryMergeSessionPersistence = .init(),
        keys: [String] = ["create-key"]
    ) -> MergeSessionStore {
        var remainingKeys = keys
        return MergeSessionStore(
            actorID: "actor_1",
            anchor: makeMergeSource("ast_anchor", preview: "Anchor"),
            service: service,
            persistence: persistence,
            sleeper: ImmediateMergeSleeper(),
            idempotencyKey: { remainingKeys.removeFirst() },
            pollDelaysNanoseconds: [0],
            maxPollAttempts: 3
        )
    }
}
