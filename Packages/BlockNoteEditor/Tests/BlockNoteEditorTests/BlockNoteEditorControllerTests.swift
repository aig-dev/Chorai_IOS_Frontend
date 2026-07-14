import XCTest
@testable import BlockNoteEditor

@MainActor
final class BlockNoteEditorControllerTests: XCTestCase {
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
