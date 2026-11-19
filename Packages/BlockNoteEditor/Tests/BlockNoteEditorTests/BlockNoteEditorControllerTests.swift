import XCTest
@testable import BlockNoteEditor

@MainActor
final class BlockNoteEditorControllerTests: XCTestCase {
    func testClosingSealsCommandsButRetainsAcceptedEventDrain() async throws {
        let controller = BlockNoteEditorController()
        let entered = expectation(description: "drain entered")
        var resume: CheckedContinuation<Void, Never>?
        var applied = false
        var closeCount = 0
        var sent = 0
        controller.attach(drainAcceptedEvents: {
            entered.fulfill()
            await withCheckedContinuation { resume = $0 }
            applied = true
        }, beginClosing: { closeCount += 1 }, commandHandler: { _ in sent += 1 })
        let binding = try XCTUnwrap(controller.attachment)
        var closing: UUID?
        controller.onAttachmentWillClose = { closing = $0.id }
        controller.beginClosing()
        controller.beginClosing()
        XCTAssertEqual(closing, binding.id)
        XCTAssertEqual(closeCount, 1)
        controller.focus()
        XCTAssertEqual(sent, 0)
        let drain = Task { await controller.drainAcceptedEvents() }
        await fulfillment(of: [entered], timeout: 3)
        XCTAssertFalse(applied)
        controller.detach()
        resume?.resume()
        await drain.value
        XCTAssertTrue(applied)
    }

    func testOldDrainDoesNotFollowReplacementAndInactiveDoesNotSeal() async throws {
        let controller = BlockNoteEditorController()
        let entered = expectation(description: "old drain entered")
        var resume: CheckedContinuation<Void, Never>?
        var oldApplied = false
        var newDrain = false
        var sent = false
        controller.attach(drainAcceptedEvents: {
            entered.fulfill()
            await withCheckedContinuation { resume = $0 }
            oldApplied = true
        }, commandHandler: { _ in })
        let old = try XCTUnwrap(controller.attachment)
        let pending = Task { await controller.drainAcceptedEvents() }
        await fulfillment(of: [entered], timeout: 3)
        controller.attach(drainAcceptedEvents: { newDrain = true }, commandHandler: { _ in sent = true })
        resume?.resume()
        await pending.value
        XCTAssertTrue(oldApplied)
        XCTAssertFalse(newDrain)
        XCTAssertNotEqual(old.id, controller.attachment?.id)
        await controller.drainAcceptedEvents()
        controller.focus()
        XCTAssertTrue(newDrain)
        XCTAssertTrue(sent)
        XCTAssertEqual(controller.attachment?.isClosing, false)
    }

    func testSnapshotCompletesOnlyForItsCorrelatedRequestID() async throws {
        let controller = BlockNoteEditorController()
        var sentCommand: BlockNoteEditorCommand?
        controller.attach { command in
            sentCommand = command
        }

        let task = Task {
            try await controller.requestSnapshot(timeoutNanoseconds: 1_000_000_000)
        }
        await Task.yield()

        guard case let .requestSnapshot(requestID)? = sentCommand else {
            return XCTFail("Expected a requestSnapshot command")
        }

        XCTAssertFalse(controller.complete(snapshot: .init(
            requestID: "different-request",
            revision: 7,
            contentJSON: "[]",
            fallbackMarkdown: "Wrong"
        )))
        XCTAssertTrue(controller.complete(snapshot: .init(
            requestID: requestID,
            revision: 8,
            contentJSON: #"[{"type":"paragraph"}]"#,
            fallbackMarkdown: "Right"
        )))

        let snapshot = try await task.value
        XCTAssertEqual(snapshot.requestID, requestID)
        XCTAssertEqual(snapshot.revision, 8)
        XCTAssertEqual(snapshot.fallbackMarkdown, "Right")
        XCTAssertEqual(controller.pendingSnapshotCount, 0)
    }

    func testSnapshotTimeoutResumesContinuationExactlyOnce() async {
        let controller = BlockNoteEditorController()
        controller.attach { _ in }

        do {
            _ = try await controller.requestSnapshot(timeoutNanoseconds: 5_000_000)
            XCTFail("Expected timeout")
        } catch let error as BlockNoteEditorFailure {
            guard case .snapshotTimedOut = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(controller.pendingSnapshotCount, 0)
        controller.failAllSnapshots(with: .tornDown)
        XCTAssertEqual(controller.pendingSnapshotCount, 0)
    }

    func testTeardownAndCompatibilityFailureResumeEachPendingSnapshotOnce() async {
        let controller = BlockNoteEditorController()
        controller.attach { _ in }

        let first = Task {
            try await controller.requestSnapshot(timeoutNanoseconds: 1_000_000_000)
        }
        let second = Task {
            try await controller.requestSnapshot(timeoutNanoseconds: 1_000_000_000)
        }
        await Task.yield()
        XCTAssertEqual(controller.pendingSnapshotCount, 2)

        controller.failAllSnapshots(with: .compatibilityBlocked(code: "unknown_block_type"))
        controller.failAllSnapshots(with: .tornDown)

        await assertFailure(first, equals: .compatibilityBlocked(code: "unknown_block_type"))
        await assertFailure(second, equals: .compatibilityBlocked(code: "unknown_block_type"))
        XCTAssertEqual(controller.pendingSnapshotCount, 0)
    }

    func testDetachedControllerFailsWithoutCreatingPendingContinuation() async {
        let controller = BlockNoteEditorController()

        do {
            _ = try await controller.requestSnapshot()
            XCTFail("Expected notAttached")
        } catch let error as BlockNoteEditorFailure {
            XCTAssertEqual(error, .notAttached)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(controller.pendingSnapshotCount, 0)
    }

    func testCancellationWinsOnceAndLateSnapshotIsIgnored() async {
        let controller = BlockNoteEditorController()
        var requestID: String?
        controller.attach { command in
            requestID = command.snapshotRequestID
        }

        let task = Task {
            try await controller.requestSnapshot(timeoutNanoseconds: 1_000_000_000)
        }
        await Task.yield()
        task.cancel()

        guard let requestID else {
            return XCTFail("Expected a request ID")
        }
        await assertFailure(task, equals: .requestCancelled(requestID: requestID))
        XCTAssertFalse(controller.complete(snapshot: .init(
            requestID: requestID,
            revision: 0,
            contentJSON: "[]",
            fallbackMarkdown: "Late"
        )))
        XCTAssertEqual(controller.pendingSnapshotCount, 0)
    }

    func testDetachWinsOnceAndLaterTimeoutHasNoContinuationToResume() async {
        let controller = BlockNoteEditorController()
        controller.attach { _ in }

        let task = Task {
            try await controller.requestSnapshot(timeoutNanoseconds: 20_000_000)
        }
        await Task.yield()
        controller.detach(with: .tornDown)

        await assertFailure(task, equals: .tornDown)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(controller.pendingSnapshotCount, 0)
    }

    func testCorrelatedStaleSnapshotFailsOnlyMatchingPendingRequestImmediately() async throws {
        let controller = BlockNoteEditorController()
        var requestIDs: [String] = []
        controller.attach { command in
            if let requestID = command.snapshotRequestID {
                requestIDs.append(requestID)
            }
        }

        let staleTask = Task {
            try await controller.requestSnapshot(timeoutNanoseconds: 1_000_000_000)
        }
        await Task.yield()
        guard let staleRequestID = requestIDs.first else {
            return XCTFail("Expected the first snapshot request")
        }

        let currentTask = Task {
            try await controller.requestSnapshot(timeoutNanoseconds: 1_000_000_000)
        }
        await Task.yield()
        guard requestIDs.count == 2 else {
            return XCTFail("Expected the second snapshot request")
        }
        let currentRequestID = requestIDs[1]

        BlockNoteBridgeOutputDispatcher(
            submitCommand: { _ in },
            emitEvent: { _ in },
            failSnapshot: { failure in
                controller.failSnapshot(
                    requestID: failure.requestID,
                    with: failure.failure
                )
            }
        ).dispatch(.init(snapshotRequestFailure: .init(
            requestID: staleRequestID,
            failure: .bridgeFailed(code: "stale_snapshot_revision")
        )))

        await assertFailure(
            staleTask,
            equals: .bridgeFailed(code: "stale_snapshot_revision")
        )
        XCTAssertEqual(controller.pendingSnapshotCount, 1)

        XCTAssertTrue(controller.complete(snapshot: .init(
            requestID: currentRequestID,
            revision: 6,
            contentJSON: "[]",
            fallbackMarkdown: "Current"
        )))
        let currentSnapshot = try await currentTask.value
        XCTAssertEqual(currentSnapshot.requestID, currentRequestID)
        XCTAssertEqual(controller.pendingSnapshotCount, 0)
    }

    private func assertFailure(
        _ task: Task<BlockNoteSnapshot, Error>,
        equals expected: BlockNoteEditorFailure
    ) async {
        do {
            _ = try await task.value
            XCTFail("Expected \(expected)")
        } catch let error as BlockNoteEditorFailure {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
