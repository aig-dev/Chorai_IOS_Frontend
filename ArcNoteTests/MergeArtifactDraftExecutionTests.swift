import XCTest
@testable import CoreFlow
@testable import BlockNoteEditor
@testable import ArcNote

@MainActor
final class MergeArtifactDraftExecutionTests: XCTestCase {

    func testBodyAcceptedAfterCanonicalDrainCutoffCannotBeDiscarded() async throws {
        let fixture = try await MergeEditorFixture()
        fixture.edit("First", revision: 1)
        _ = await fixture.controller.flushAcceptedDraft()
        await fixture.service.setCanonicalTags(["Canonical"])
        let original = fixture.model
        let firstGate = MergeMailboxGate(), secondGate = MergeMailboxGate()
        let worker = BlockNoteBridgeWorker(document: original.initialDocument, editable: true, beforeApply: { input in
            if case .focusObservation(1) = input { await firstGate.wait() }
            if case .focusObservation(2) = input { await secondGate.wait() }
        })
        let mailbox = BlockNoteBridgeMailbox(worker: worker) { prepared in
            for event in prepared.output.events { original.receive(event) }
        }
        mailbox.enqueue(.navigationFinished)
        mailbox.enqueue(.message(.capture(["type": "ready", "protocolVersion": 3, "schemaVersion": 1]), focusRevision: nil))
        await mailbox.drainAcceptedEvents()
        var drainEntered = false
        original.controller.attach(drainAcceptedEvents: {
            drainEntered = true
            await mailbox.drainAcceptedEvents()
        }, hasPendingAcceptedEvents: { mailbox.pendingCount > 0 },
           beginClosing: { mailbox.close() }, commandHandler: { _ in })
        mailbox.enqueue(.focusObservation(1))
        await mergeEventually { firstGate.entered }
        _ = try await fixture.store.flushArtifactDraft()
        await mergeEventually { drainEntered }
        mailbox.enqueue(.focusObservation(2))
        mailbox.enqueue(.message(.capture(["type": "documentChanged", "revision": 2,
            "contentJSON": MergeEditorFixture.body("Accepted after watermark"), "fallbackMarkdown": "Accepted after watermark"]), focusRevision: nil))
        firstGate.open()
        await mergeEventually { secondGate.entered }
        XCTAssertFalse(fixture.controller.isPreparingProjection)
        XCTAssertTrue(fixture.model === original)
        secondGate.open()
        await mailbox.drainAcceptedEvents()
        _ = await fixture.controller.flushAcceptedDraft()
        XCTAssertTrue(String(decoding: fixture.store.artifactDraft!.documentJSON, as: UTF8.self).contains("Accepted after watermark"))
    }

    func testHiddenPendingEditorBlocksReopeningBeforeDrainFinishes() async throws {
        let gate = MergeWorkerGate(blocked: .prepareDraft)
        let fixture = try await MergeEditorFixture(worker: .init(beforeWork: { try await gate.wait($0) }))
        fixture.controller.setHostVisible(true, coordinator: fixture.coordinator)
        fixture.model.controller.attach { _ in }
        fixture.edit("Pending hidden body", revision: 1)
        await mergeEventually { gate.arrivals == 1 }
        fixture.controller.setHostVisible(false, coordinator: fixture.coordinator)
        fixture.model.controller.detach()
        fixture.coordinator.present(jobID: "job")
        XCTAssertNil(fixture.coordinator.presentation)
        XCTAssertNil(fixture.coordinator.session(jobID: "job"))
        gate.open()
        await mergeEventually { fixture.coordinator.session(jobID: "job") != nil }
        XCTAssertTrue(String(decoding: fixture.store.artifactDraft!.documentJSON, as: UTF8.self).contains("Pending hidden body"))
    }

    func testFailedHiddenEditorBlocksReopeningUntilOriginalOwnerRetries() async throws {
        let gate = MergeWorkerGate(blocked: nil)
        let fixture = try await MergeEditorFixture(worker: .init(beforeWork: { try await gate.wait($0) }))
        fixture.controller.setHostVisible(true, coordinator: fixture.coordinator)
        fixture.model.controller.attach { _ in }
        gate.failDrafts = true
        fixture.edit("Unsaved hidden owner", revision: 1)
        _ = await fixture.controller.flushAcceptedDraft()
        fixture.controller.setHostVisible(false, coordinator: fixture.coordinator)
        fixture.model.controller.detach()
        await mergeEventually { fixture.coordinator.transitionState == .failed }
        fixture.coordinator.present(jobID: "job")
        XCTAssertNil(fixture.coordinator.presentation)
        XCTAssertNil(fixture.coordinator.session(jobID: "job"))
        gate.failDrafts = false
        fixture.coordinator.retryEditorDrain()
        await mergeEventually { fixture.coordinator.isReady(for: "alice") }
        let persisted = fixture.persistence.collection(actorID: "alice").tasks["job"]?.snapshot.artifactDraft?.documentJSON
        XCTAssertTrue(String(decoding: try XCTUnwrap(persisted), as: UTF8.self).contains("Unsaved hidden owner"))
        XCTAssertFalse(fixture.coordinator.session(jobID: "job") === fixture.store)
    }

    func testCanonicalAcknowledgementWaitsForAcceptedBridgeBodyBeforeReprojection() async throws {
        let fixture = try await MergeEditorFixture()
        fixture.edit("First", revision: 1)
        _ = await fixture.controller.flushAcceptedDraft()
        await fixture.service.setCanonicalTags(["Server normalized"])
        let original = fixture.model
        let gate = EditorExecutionGate()
        var entered = false
        original.controller.attach(drainAcceptedEvents: {
            entered = true
            await gate.wait()
            original.receive(.documentChanged(.init(revision: 2,
                contentJSON: MergeEditorFixture.body("Queued bridge body"), fallbackMarkdown: "Queued bridge body")))
        }, commandHandler: { _ in })
        _ = try await fixture.store.flushArtifactDraft()
        await mergeEventually { entered }
        XCTAssertFalse(fixture.controller.isPreparingProjection)
        XCTAssertTrue(fixture.model === original)
        gate.open()
        _ = await fixture.controller.flushAcceptedDraft()
        XCTAssertTrue(String(decoding: fixture.store.artifactDraft!.documentJSON, as: UTF8.self).contains("Queued bridge body"))
        XCTAssertEqual(fixture.store.artifactDraft?.tags, ["Server normalized"])
    }
    func testPendingLocalEditBlocksCanonicalReloadAndOlderConversionCannotReplaceLatestBody() async throws {
        let gate = MergeWorkerGate(blocked: .prepareDraft)
        let fixture = try await MergeEditorFixture(worker: .init(beforeWork: { try await gate.wait($0) }))
        let original = fixture.model
        fixture.edit("First", revision: 1)
        await mergeEventually { gate.arrivals == 1 }
        fixture.store.objectWillChange.send()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(fixture.model === original)
        XCTAssertFalse(fixture.controller.canAccept)
        fixture.edit("Latest", revision: 2)
        fixture.controller.beginTag()
        fixture.controller.tagInput = "Current tag"
        fixture.controller.completeTag()
        gate.open()
        let saved = await fixture.controller.flushAcceptedDraft()
        XCTAssertTrue(saved)
        let document = String(decoding: try XCTUnwrap(fixture.store.artifactDraft?.documentJSON), as: UTF8.self)
        XCTAssertTrue(document.contains("Latest"))
        XCTAssertFalse(document.contains("First"))
        XCTAssertEqual(fixture.store.artifactDraft?.tags, ["Current tag"])
        XCTAssertTrue(fixture.model === original)
    }

    func testAcceptLocksInputAndWaitsForExactSnapshotConversionBeforeFlushAndCommit() async throws {
        let gate = MergeWorkerGate(blocked: .prepareDraft)
        let fixture = try await MergeEditorFixture(worker: .init(beforeWork: { try await gate.wait($0) }))
        installSnapshot(fixture, text: "Exact snapshot")
        fixture.controller.beginTag()
        fixture.controller.tagInput = "Pending tag"
        fixture.controller.accept()
        XCTAssertFalse(fixture.controller.canEdit)
        XCTAssertFalse(fixture.controller.canDiscard)
        await mergeEventually { gate.arrivals == 1 }
        let before = await fixture.service.events
        XCTAssertTrue(before.isEmpty)
        XCTAssertFalse(String(decoding: fixture.store.artifactDraft!.documentJSON, as: UTF8.self).contains("Exact snapshot"))
        gate.open()
        await mergeEventually { if case .completed = fixture.store.phase { return true }; return false }
        let events = await fixture.service.events
        let saves = await fixture.service.saves
        XCTAssertEqual(events, ["save", "commit"])
        XCTAssertTrue(String(decoding: try XCTUnwrap(saves.last?.documentJSON), as: UTF8.self).contains("Exact snapshot"))
        XCTAssertEqual(saves.last?.tags, ["Pending tag"])
    }

    func testBackWaitsForExactSnapshotAndPendingTagWithoutWaitingForCloud() async throws {
        let gate = MergeWorkerGate(blocked: .prepareDraft)
        let fixture = try await MergeEditorFixture(worker: .init(beforeWork: { try await gate.wait($0) }))
        installSnapshot(fixture, text: "Back snapshot")
        fixture.controller.beginTag()
        fixture.controller.tagInput = "Back tag"
        var minimized = false
        fixture.controller.back { minimized = true }
        await mergeEventually { gate.arrivals == 1 }
        XCTAssertFalse(minimized)
        XCTAssertFalse(fixture.controller.canEdit)
        gate.open()
        await mergeEventually { minimized }
        XCTAssertTrue(String(decoding: fixture.store.artifactDraft!.documentJSON, as: UTF8.self).contains("Back snapshot"))
        XCTAssertEqual(fixture.store.artifactDraft?.tags, ["Back tag"])
        let events = await fixture.service.events
        XCTAssertTrue(events.isEmpty)
    }

    func testFailedOldInstanceConversionCanRetryWithReplacementOwner() async throws {
        let gate = MergeWorkerGate(blocked: .prepareDraft)
        let fixture = try await MergeEditorFixture(worker: .init(beforeWork: { try await gate.wait($0) }))
        fixture.model.controller.attach { _ in }
        fixture.edit("Accepted through failure", revision: 1)
        await mergeEventually { gate.arrivals == 1 }
        fixture.model.receive(.bridgeError(code: "injected"))
        fixture.model.retryAfterBridgeFailure()
        gate.failDrafts = true
        gate.open()
        let failed = await fixture.controller.flushAcceptedDraft()
        XCTAssertFalse(failed)
        gate.failDrafts = false
        let retried = await fixture.controller.flushAcceptedDraft()
        XCTAssertTrue(retried)
        XCTAssertTrue(String(decoding: fixture.store.artifactDraft!.documentJSON, as: UTF8.self).contains("Accepted through failure"))
    }

    func testBridgeRetryPreservesProfileAndRebindsAcceptedConversion() async throws {
        let gate = MergeWorkerGate(blocked: .prepareDraft)
        let fixture = try await MergeEditorFixture(worker: .init(beforeWork: { try await gate.wait($0) }))
        fixture.model.controller.attach { _ in }
        fixture.edit("Accepted before retry", revision: 1)
        await mergeEventually { gate.arrivals == 1 }
        let original = fixture.model.editorInstanceID
        fixture.model.receive(.bridgeError(code: "injected"))
        fixture.model.retryAfterBridgeFailure()
        XCTAssertNotEqual(fixture.model.editorInstanceID, original)
        XCTAssertEqual(fixture.model.initialDocument.profile, .mergeArtifact)
        gate.open()
        let saved = await fixture.controller.flushAcceptedDraft()
        XCTAssertTrue(saved)
        XCTAssertTrue(String(decoding: fixture.store.artifactDraft!.documentJSON, as: UTF8.self).contains("Accepted before retry"))
    }

    func testExplicitReloadRejectsOlderProjectionAndOldEditorCallbacks() async throws {
        let gate = MergeWorkerGate(blocked: nil)
        let fixture = try await MergeEditorFixture(worker: .init(beforeWork: { try await gate.wait($0) }))
        let oldModel = fixture.model
        gate.blocked = .project
        fixture.controller.reloadFromStore(preservePendingTagInput: false)
        await mergeEventually { gate.arrivals == 1 }
        let latest = Data(#"{"schemaVersion":"card_doc.v1","meta":{},"blocks":[{"id":"blk_test","type":"paragraph","content":[{"type":"text","text":"Server latest"}]}]}"#.utf8)
        fixture.store.updateArtifactDraft(documentJSON: latest, preservationManifest: Data())
        fixture.controller.reloadFromStore(preservePendingTagInput: false)
        await mergeEventually { gate.arrivals == 2 }
        oldModel.receive(.documentChanged(.init(revision: 99, contentJSON: MergeEditorFixture.body("Old callback"), fallbackMarkdown: "Old callback")))
        gate.open()
        await fixture.controller.waitUntilPrepared()
        XCTAssertTrue(fixture.model.contentJSON?.contains("Server latest") == true)
        XCTAssertEqual(fixture.store.artifactDraft?.documentJSON, latest)
        XCTAssertFalse(fixture.model === oldModel)
    }

    func testLosslessFailureKeepsDraftAndRetirementOwnerUntilRetry() async throws {
        let gate = MergeWorkerGate(blocked: nil)
        let fixture = try await MergeEditorFixture(worker: .init(beforeWork: { try await gate.wait($0) }))
        fixture.controller.setHostVisible(true, coordinator: fixture.coordinator)
        fixture.model.controller.attach { _ in }
        let original = fixture.store.artifactDraft?.documentJSON
        gate.failDrafts = true
        fixture.edit("Retain me", revision: 1)
        let saved = await fixture.controller.flushAcceptedDraft()
        XCTAssertFalse(saved)
        XCTAssertEqual(fixture.store.artifactDraft?.documentJSON, original)
        XCTAssertFalse(fixture.controller.canAccept)
        fixture.coordinator.deactivate()
        await mergeEventually { fixture.coordinator.transitionState == .failed }
        gate.failDrafts = false
        fixture.coordinator.activate(actorID: "bob")
        fixture.coordinator.retryEditorDrain()
        await mergeEventually { fixture.coordinator.isReady(for: "bob") }
        let persisted = fixture.persistence.collection(actorID: "alice").tasks["job"]?.snapshot.artifactDraft?.documentJSON
        XCTAssertTrue(String(decoding: try XCTUnwrap(persisted), as: UTF8.self).contains("Retain me"))
    }

    func testRetirementCancelsPendingAcceptButDrainsItsAcceptedConversion() async throws {
        let gate = MergeWorkerGate(blocked: .prepareDraft)
        let fixture = try await MergeEditorFixture(worker: .init(beforeWork: { try await gate.wait($0) }))
        fixture.controller.setHostVisible(true, coordinator: fixture.coordinator)
        installSnapshot(fixture, text: "Accepted before switch")
        fixture.controller.accept()
        await mergeEventually { gate.arrivals == 1 }
        fixture.coordinator.activate(actorID: "bob")
        XCTAssertEqual(fixture.coordinator.transitionState, .draining)
        gate.open()
        await mergeEventually { fixture.coordinator.isReady(for: "bob") }
        let events = await fixture.service.events
        XCTAssertFalse(events.contains("commit"))
        let persisted = fixture.persistence.collection(actorID: "alice").tasks["job"]?.snapshot.artifactDraft?.documentJSON
        XCTAssertTrue(String(decoding: try XCTUnwrap(persisted), as: UTF8.self).contains("Accepted before switch"))
    }

    private func installSnapshot(_ fixture: MergeEditorFixture, text: String) {
        let controller = fixture.model.controller
        controller.attach { [weak controller] command in
            guard let id = command.snapshotRequestID else { return }
            controller?.complete(snapshot: .init(requestID: id, revision: 1,
                contentJSON: MergeEditorFixture.body(text), fallbackMarkdown: text))
        }
    }
}

@MainActor
final class MergeWorkerGate {
    var blocked: MergeArtifactEditorWorker.Work?
    var failDrafts = false
    private(set) var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(blocked: MergeArtifactEditorWorker.Work?) { self.blocked = blocked }
    func wait(_ work: MergeArtifactEditorWorker.Work) async throws {
        if work == blocked { arrivals += 1; await withCheckedContinuation { waiters.append($0) } }
        if work == .prepareDraft, failDrafts { throw MergeArtifactEditorCodecError.losslessRoundTripFailed }
    }
    func open() { blocked = nil; let pending = waiters; waiters = []; pending.forEach { $0.resume() } }
}

@MainActor
private final class MergeMailboxGate {
    private let gate = EditorExecutionGate()
    private(set) var entered = false
    func wait() async { entered = true; await gate.wait() }
    func open() { gate.open() }
}
