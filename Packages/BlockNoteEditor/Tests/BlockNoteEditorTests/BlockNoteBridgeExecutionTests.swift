import Foundation
import XCTest
@testable import BlockNoteEditor

@MainActor
final class BlockNoteBridgeExecutionTests: XCTestCase {
    private let document = BlockNoteInitialDocument(contentJSON: #"[{"id":"p","type":"paragraph","props":{},"content":[{"type":"text","text":"Original","styles":{}}],"children":[]}]"#, fallbackMarkdown: "Original")

    func testBlockedFirstWorkPreservesInputOrderAndDispatchOrder() async throws {
        let gate = BridgeExecutionGate()
        let started = expectation(description: "first work")
        let worker = BlockNoteBridgeWorker(document: document, editable: true, probe: { _ in XCTAssertFalse(Thread.isMainThread) }, beforeApply: { input in
            if case .navigationFinished = input { started.fulfill(); await gate.wait() }
        })
        var trace = [String]()
        let mailbox = BlockNoteBridgeMailbox(worker: worker) { prepared in
            XCTAssertTrue(Thread.isMainThread)
            for command in prepared.commands {
                switch command.command {
                case .initialize: trace.append("initialize")
                case .focus: trace.append("focus")
                case .applyFormat: trace.append("bold")
                default: break
                }
                XCTAssertTrue(command.script.contains("receiveCommand("))
            }
            if let snapshot = prepared.output.snapshot { trace.append("snapshot:\(snapshot.revision)") }
            for event in prepared.output.events {
                switch event {
                case .availabilityChanged(.ready): trace.append("ready")
                case .documentChanged(let value): trace.append("document:\(value.revision)")
                default: break
                }
            }
        }
        mailbox.enqueue(.navigationFinished)
        await fulfillment(of: [started], timeout: 3)
        mailbox.enqueue(.command(.focus))
        mailbox.enqueue(.message(.capture(["type": "ready", "protocolVersion": 3, "schemaVersion": 1]), focusRevision: nil))
        mailbox.enqueue(.message(.capture(["type": "documentChanged", "revision": 1, "contentJSON": document.contentJSON!, "fallbackMarkdown": "One"]), focusRevision: nil))
        mailbox.enqueue(.command(.applyFormat(.bold)))
        mailbox.enqueue(.message(.capture(["type": "snapshot", "requestID": "s", "revision": 1, "contentJSON": document.contentJSON!, "fallbackMarkdown": "One"]), focusRevision: nil))
        XCTAssertTrue(trace.isEmpty)
        await gate.open()
        await mailbox.drainAcceptedEvents()
        XCTAssertEqual(trace, ["initialize", "focus", "ready", "document:1", "bold", "snapshot:1"])
        XCTAssertEqual(mailbox.pendingCount, 0)
        XCTAssertEqual(mailbox.pendingBytes, 0)
    }

    func testClosingStillAppliesAcceptedBodyAndReleasesDeliveryCapture() async {
        let gate = BridgeExecutionGate()
        let worker = BlockNoteBridgeWorker(document: document, editable: true, beforeApply: { input in
            if case .navigationFinished = input { await gate.wait() }
        })
        var retained: BridgeLifetimeProbe? = BridgeLifetimeProbe()
        weak var weakProbe = retained
        var revisions = [Int]()
        let mailbox = BlockNoteBridgeMailbox(worker: worker) { [probe = retained!] output in
            _ = probe
            for event in output.output.events {
                if case .documentChanged(let document) = event { revisions.append(document.revision) }
            }
        }
        retained = nil
        mailbox.enqueue(.navigationFinished)
        mailbox.enqueue(.message(.capture(["type": "ready", "protocolVersion": 3, "schemaVersion": 1]), focusRevision: nil))
        mailbox.enqueue(.message(.capture(["type": "documentChanged", "revision": 1, "contentJSON": document.contentJSON!, "fallbackMarkdown": "Accepted"]), focusRevision: nil))
        mailbox.close()
        XCTAssertNil(mailbox.enqueue(.message(.capture(["type": "documentChanged", "revision": 2, "contentJSON": "[]", "fallbackMarkdown": "Too late"]), focusRevision: nil)))
        await gate.open()
        await mailbox.drainAcceptedEvents()
        XCTAssertEqual(revisions, [1])
        XCTAssertNil(weakProbe)
        XCTAssertEqual(mailbox.pendingBytes, 0)
    }

    func testFocusImmediatelyAfterQueuedReadyAndOlderDOMProbe() async {
        let worker = BlockNoteBridgeWorker(document: document, editable: true)
        var focuses = [Bool]()
        let mailbox = BlockNoteBridgeMailbox(worker: worker) { result in
            for event in result.output.events {
                if case .bodyFocusChanged(let value) = event { focuses.append(value) }
            }
        }
        mailbox.enqueue(.navigationFinished)
        mailbox.enqueue(.message(.capture(["type": "ready", "protocolVersion": 3, "schemaVersion": 1]), focusRevision: nil))
        mailbox.enqueue(.focusObservation(1))
        mailbox.enqueue(.message(.capture(["type": "bodyFocusChanged", "isFocused": true]), focusRevision: 2))
        mailbox.enqueue(.focusProbe(isFocused: false, revision: 1))
        await mailbox.drainAcceptedEvents()
        XCTAssertEqual(focuses, [true])
    }

    func testSnapshotDeadlineIncludesWorkerQueueAndLateResultCompletesOnce() async {
        let gate = BridgeExecutionGate()
        let worker = BlockNoteBridgeWorker(document: document, editable: true, beforeApply: { input in
            if case .navigationFinished = input { await gate.wait() }
        })
        let controller = BlockNoteEditorController()
        var lateAccepted = false
        let mailbox = BlockNoteBridgeMailbox(worker: worker) { output in
            if let snapshot = output.output.snapshot { lateAccepted = controller.complete(snapshot: snapshot) }
            if let failure = output.output.snapshotFailure { controller.failAllSnapshots(with: failure) }
        }
        var requestID: String?
        controller.attach(drainAcceptedEvents: { await mailbox.drainAcceptedEvents() }, beginClosing: { mailbox.close() }) {
            requestID = $0.snapshotRequestID
            mailbox.enqueue(.command($0))
        }
        mailbox.enqueue(.navigationFinished)
        do { _ = try await controller.requestSnapshot(timeoutNanoseconds: 5_000_000); XCTFail("Deadline reset while queued") }
        catch let error as BlockNoteEditorFailure {
            guard case .snapshotTimedOut = error else { return XCTFail("\(error)") }
        } catch { XCTFail("\(error)") }
        mailbox.enqueue(.message(.capture(["type": "ready", "protocolVersion": 3, "schemaVersion": 1]), focusRevision: nil))
        mailbox.enqueue(.message(.capture(["type": "snapshot", "requestID": requestID ?? "", "revision": 1, "contentJSON": "[]", "fallbackMarkdown": "Late"]), focusRevision: nil))
        await gate.open()
        await mailbox.drainAcceptedEvents()
        XCTAssertFalse(lateAccepted)
        XCTAssertEqual(controller.pendingSnapshotCount, 0)
        controller.beginClosing()
        await controller.drainAcceptedEvents()
    }

    func testReadOnlyAndMalformedScalarCannotMutate() async {
        let worker = BlockNoteBridgeWorker(document: document, editable: false)
        _ = await worker.apply(.navigationFinished)
        _ = await worker.apply(.message(.capture(["type": "ready", "protocolVersion": 3, "schemaVersion": 1]), focusRevision: nil))
        let mutation = await worker.apply(.command(.applyFormat(.bold)))
        XCTAssertTrue(mutation.commands.isEmpty)
        XCTAssertTrue(mutation.output.events.contains(.bridgeError(code: "read_only")))
        // Bool is not a valid integer revision, even though NSNumber can cast it to Int.
        let malformed = await worker.apply(.message(.capture(["type": "documentChanged", "revision": true, "contentJSON": "[]", "fallbackMarkdown": "Bad"]), focusRevision: nil))
        XCTAssertTrue(malformed.output.events.contains(.bridgeError(code: "malformed_message")))
    }

    func testStatefulAdapterKeepsAssignedIDsAcrossRevisions() async throws {
        let worker = BlockNoteBridgeWorker(document: document, editable: true, probe: { _ in XCTAssertFalse(Thread.isMainThread) })
        _ = await worker.apply(.navigationFinished)
        _ = await worker.apply(.message(.capture(["type": "ready", "protocolVersion": 3, "schemaVersion": 1]), focusRevision: nil))
        let incoming = #"[{"id":"new-runtime-block","type":"paragraph","props":{},"content":[{"type":"text","text":"New","styles":{}}],"children":[]}]"#
        var identities = [String]()
        for revision in 1...2 {
            let output = await worker.apply(.message(.capture(["type": "documentChanged", "revision": revision, "contentJSON": incoming, "fallbackMarkdown": "New"]), focusRevision: nil))
            let event = try XCTUnwrap(output.output.events.first)
            guard case .documentChanged(let document) = event else { return XCTFail("Adapter failed") }
            let blocks = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(document.contentJSON.utf8)) as? [[String: Any]])
            identities.append(try XCTUnwrap(blocks.first?["id"] as? String))
        }
        XCTAssertEqual(identities.count, 2)
        XCTAssertEqual(identities[0], identities[1])
    }

    func testIndependentAttachmentsNeverPublishIntoEachOther() async {
        let gate = BridgeExecutionGate()
        let old = BlockNoteBridgeWorker(document: document, editable: true, beforeApply: { _ in await gate.wait() })
        let fresh = BlockNoteBridgeWorker(document: document, editable: true)
        var oldCount = 0
        var newCount = 0
        let oldMailbox = BlockNoteBridgeMailbox(worker: old) { _ in oldCount += 1 }
        let newMailbox = BlockNoteBridgeMailbox(worker: fresh) { _ in newCount += 1 }
        XCTAssertNotEqual(oldMailbox.generation, newMailbox.generation)
        oldMailbox.enqueue(.navigationFinished)
        newMailbox.enqueue(.navigationFinished)
        await newMailbox.drainAcceptedEvents()
        XCTAssertEqual(newCount, 1)
        XCTAssertEqual(oldCount, 0)
        await gate.open()
        await oldMailbox.drainAcceptedEvents()
        XCTAssertEqual(newCount, 1)
        XCTAssertEqual(oldCount, 1)
    }

    func testLongDocumentBurstDrainsEveryRevisionAndReleasesQueuedBytes() async throws {
        let blocks: [[String: Any]] = (0..<1000).map { ["id": "p-\($0)", "type": "paragraph", "props": [:], "content": [["type": "text", "text": "Synthetic \($0)", "styles": [:]]], "children": []] }
        let json = String(decoding: try JSONSerialization.data(withJSONObject: blocks), as: UTF8.self)
        let worker = BlockNoteBridgeWorker(document: .init(contentJSON: json, fallbackMarkdown: ""), editable: true)
        var revisions = [Int]()
        let mailbox = BlockNoteBridgeMailbox(worker: worker) { output in
            for event in output.output.events {
                if case .documentChanged(let value) = event { revisions.append(value.revision) }
            }
        }
        let start = ProcessInfo.processInfo.systemUptime
        mailbox.enqueue(.navigationFinished)
        mailbox.enqueue(.message(.capture(["type": "ready", "protocolVersion": 3, "schemaVersion": 1]), focusRevision: nil))
        for revision in 1...40 {
            mailbox.enqueue(.message(.capture(["type": "documentChanged", "revision": revision, "contentJSON": json, "fallbackMarkdown": "Revision \(revision)"]), focusRevision: nil))
            if revision % 10 == 0 {
                mailbox.enqueue(.message(.capture(["type": "snapshot", "requestID": "s-\(revision)", "revision": revision, "contentJSON": json, "fallbackMarkdown": ""]), focusRevision: nil))
            }
        }
        mailbox.close()
        await mailbox.drainAcceptedEvents()
        XCTAssertEqual(revisions, Array(1...40))
        XCTAssertEqual(mailbox.pendingCount, 0)
        XCTAssertEqual(mailbox.pendingBytes, 0)
        print("EXECUTION_METRIC bridge_1000_blocks_40_revisions duration_ms=\((ProcessInfo.processInfo.systemUptime-start)*1000) peak_entries=\(mailbox.peakPendingCount) peak_queued_bytes=\(mailbox.peakPendingBytes)")
    }
}

private actor BridgeExecutionGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async { if opened { return }; await withCheckedContinuation { waiters.append($0) } }
    func open() { opened = true; let pending = waiters; waiters = []; pending.forEach { $0.resume() } }
}
private final class BridgeLifetimeProbe {}
