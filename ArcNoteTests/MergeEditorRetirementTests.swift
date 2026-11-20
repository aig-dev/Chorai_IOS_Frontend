import XCTest
@testable import CoreFlow
@testable import BlockNoteEditor
@testable import ArcNote

@MainActor
final class MergeEditorRetirementTests: XCTestCase {
    func testControllerRetainsAcceptedBodyUntilOldActorPersistenceCompletes() async throws {
        let fixture = try await MergeEditorFixture()
        let gate = EditorExecutionGate()
        let entered = expectation(description: "original binding drain")
        fixture.controller.setHostVisible(true, coordinator: fixture.coordinator)
        var didEnter = false
        fixture.model.controller.attach(drainAcceptedEvents: {
            if !didEnter { didEnter = true; entered.fulfill() }
            await gate.wait()
            fixture.edit("Final accepted body", revision: 1)
        }, commandHandler: { _ in })
        fixture.coordinator.activate(actorID: "bob")
        await fulfillment(of: [entered], timeout: 3)
        XCTAssertEqual(fixture.coordinator.transitionState, .draining)
        XCTAssertTrue(fixture.coordinator.summaries.isEmpty)
        fixture.coordinator.activate(actorID: "carol")
        gate.open()
        await mergeEventually { fixture.coordinator.isReady(for: "carol") }
        let saved = fixture.persistence.collection(actorID: "alice").tasks["job"]?.snapshot.artifactDraft
        XCTAssertTrue(String(decoding: try XCTUnwrap(saved?.documentJSON), as: UTF8.self).contains("Final accepted body"))
        XCTAssertFalse(fixture.coordinator.isReady(for: "bob"))
    }

    func testViewDisappearingBeforeDismantleStillFlushesFinalBody() async throws {
        let fixture = try await MergeEditorFixture()
        fixture.controller.setHostVisible(true, coordinator: fixture.coordinator)
        fixture.model.controller.attach(drainAcceptedEvents: {
            fixture.edit("After view disappeared", revision: 1)
        }, commandHandler: { _ in })
        fixture.controller.setHostVisible(false, coordinator: fixture.coordinator)
        fixture.model.controller.detach()
        await mergeEventually {
            String(decoding: fixture.store.artifactDraft?.documentJSON ?? Data(), as: UTF8.self)
                .contains("After view disappeared")
        }
        XCTAssertTrue(fixture.coordinator.isReady(for: "alice"))
    }

    func testInactiveFlushDoesNotCloseOriginalEditor() async throws {
        let fixture = try await MergeEditorFixture()
        fixture.controller.setHostVisible(true, coordinator: fixture.coordinator)
        fixture.model.controller.attach { _ in }
        fixture.edit("First", revision: 1)
        fixture.coordinator.setApplicationActive(false)
        let first = await fixture.controller.flushAcceptedDraft()
        XCTAssertTrue(first)
        fixture.coordinator.setApplicationActive(true)
        fixture.edit("Second", revision: 2)
        let second = await fixture.controller.flushAcceptedDraft()
        XCTAssertTrue(second)
        XCTAssertEqual(fixture.model.controller.attachment?.isClosing, false)
        XCTAssertTrue(String(decoding: fixture.store.artifactDraft?.documentJSON ?? Data(), as: UTF8.self).contains("Second"))
    }
}

@MainActor
final class MergeEditorFixture {
    let service = MergeEditorTestService()
    let persistence: UserDefaultsMergeTaskStore
    let coordinator: MergeTaskCoordinator
    let store: MergeSessionStore
    let controller: MergeArtifactDraftController
    var model: BlockNoteCardEditorModel { controller.bodyModel }
    private let defaults: UserDefaults
    private let suite: String

    init(worker: MergeArtifactEditorWorker = MergeArtifactEditorWorker()) async throws {
        suite = "merge-execution-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        persistence = UserDefaultsMergeTaskStore(defaults: defaults, keyPrefix: "tasks",
            legacy: UserDefaultsMergeSessionStore(defaults: defaults, keyPrefix: "legacy"))
        let anchor = MergeSource(assetID: "anchor", versionID: nil, preview: "Anchor")
        let snapshot = MergeSessionSnapshot(actorID: "alice", anchorAssetID: "anchor", anchorPreview: "Anchor",
            createRequest: MergeCreateRequest(sources: [anchor, MergeSource(assetID: "companion", versionID: nil, preview: "Companion")], capability: "auto", idempotencyKey: "create", context: [:]),
            selectedCapability: nil, jobID: "job", lastStatus: .artifactReady, artifactID: "artifact",
            commitRequest: nil, committedAssetID: nil)
        var collection = MergeTaskCollection.empty(actorID: "alice")
        collection.tasks["job"] = MergeTaskRecord(operationID: "operation", snapshot: snapshot,
            createdAt: Date(), updatedAt: Date(), replacesJobID: nil)
        persistence.save(collection)
        coordinator = MergeTaskCoordinator(service: service, persistence: persistence, sleeper: MergeEditorSleeper())
        coordinator.activate(actorID: "alice")
        store = try XCTUnwrap(coordinator.session(jobID: "job"))
        let store = store
        await mergeEventually { store.phase == .ready }
        controller = MergeArtifactDraftController(store: store, worker: worker)
        await controller.waitUntilPrepared()
        model.receive(.availabilityChanged(.ready))
    }
    isolated deinit { defaults.removePersistentDomain(forName: suite) }
    func edit(_ text: String, revision: Int) {
        model.receive(.documentChanged(.init(revision: revision, contentJSON: Self.body(text), fallbackMarkdown: text)))
    }
    static func body(_ text: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [["id": "blk_test", "type": "paragraph", "props": [:],
            "content": [["type": "text", "text": text, "styles": [:]]], "children": []]])
        return String(decoding: data, as: UTF8.self)
    }
}

struct MergeEditorSleeper: MergeSleeping {
    func sleep(nanoseconds: UInt64) async throws { try await Task.sleep(nanoseconds: 3_600_000_000_000) }
}

actor MergeEditorTestService: CoreMergeServing {
    private(set) var events: [String] = []
    private var canonicalTags: [String]?
    func setCanonicalTags(_ tags: [String]) { canonicalTags = tags }
    private(set) var saves: [MergeArtifactSaveRequest] = []
    func capabilities() async throws -> [MergeCapability] { [] }
    func createJob(_ request: MergeCreateRequest) async throws -> MergeJob { throw CoreMergeError.interrupted }
    func job(id: String) async throws -> MergeJob {
        MergeJob(jobID: "job", status: .artifactReady, capability: "auto", selectedCapability: "structured_text",
            planScore: 1, artifactID: "artifact", latestCommit: nil, failureStage: nil, errorCode: nil, failureReason: nil)
    }
    func artifact(jobID: String) async throws -> MergeArtifact {
        MergeArtifact(artifactID: "artifact", jobID: "job", capabilityID: "structured_text", outputKind: .document,
            document: MergeDocument(schemaVersion: "1.0", title: "", subtitle: nil, blocks: [], metadata: [:]),
            fragments: [], metadata: [:], latestRevision: 1, latestHash: "hash-1",
            documentJSON: Data(#"{"schemaVersion":"card_doc.v1","meta":{},"blocks":[{"id":"blk_test","type":"paragraph","content":[{"type":"text","text":"Original"}]}]}"#.utf8),
            presentationHash: "presentation-1", presentation: .init(schemaVersion: "merge_artifact_presentation.v1", tags: [], rate: 1))
    }
    func saveArtifact(jobID: String, request: MergeArtifactSaveRequest) async throws -> MergeArtifactSaveResult {
        events.append("save"); saves.append(request)
        return .init(artifactID: "artifact", revision: request.baseRevision + 1, documentHash: "hash-\(request.baseRevision + 1)",
            presentationHash: "presentation", presentation: .init(schemaVersion: "merge_artifact_presentation.v1", tags: canonicalTags ?? request.tags, rate: 1))
    }
    func cancel(jobID: String) async throws -> MergeJob { throw CoreMergeError.interrupted }
    func commit(jobID: String, request: MergeCommitRequest) async throws -> MergeCommitResult {
        events.append("commit")
        return .init(commitID: "commit", status: "COMMITTED", targetType: "new_card", assetID: "result",
            versionID: "v", activityID: nil, logID: nil, errorCode: nil, backgroundMediaReference: nil)
    }
}

@MainActor
func mergeEventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    let deadline = Date().addingTimeInterval(5)
    while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
    XCTAssertTrue(condition(), file: file, line: line)
}
