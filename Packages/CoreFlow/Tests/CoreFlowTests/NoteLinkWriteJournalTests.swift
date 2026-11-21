import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class NoteLinkWriteJournalTests: XCTestCase {
    private func directory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func receipt(_ attempt: NoteLinkWriteAttempt, requestID: String? = nil, noteLinkID: String? = nil) -> NoteLinkWriteReceipt {
        NoteLinkWriteReceipt(requestID: requestID ?? attempt.requestID, sourceID: attempt.sourceID,
            targetID: attempt.targetID, noteLinkID: noteLinkID ?? attempt.noteLinkID ?? "created_link",
            activityID: "original_activity", actionLogID: "original_action_log",
            state: attempt.operation == .link ? .active : .ended)
    }

    func testMismatchedSuccessCannotDiscardThePendingCommand() async throws {
        let journal = NoteLinkWriteJournal(directory: directory())
        let first = try await journal.begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .unlink, sourceID: "source", targetID: "target", noteLinkID: "exact_link")
        for invalid in [receipt(first, requestID: "wrong_request"), receipt(first, noteLinkID: "other_link")] {
            do { try await journal.complete(first, receipt: invalid); XCTFail("Mismatched success must retain the request") } catch {}
        }
        let retry = try await journal.begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .unlink, sourceID: "source", targetID: "target", noteLinkID: "exact_link")
        XCTAssertEqual(first, retry)
    }

    func testOnlyProvedTerminalRejectionClearsThePendingCommand() async throws {
        let journal = NoteLinkWriteJournal(directory: directory())
        let first = try await journal.begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .link, sourceID: "source", targetID: "target")
        for reason in ["note_action_outcome_unknown", "NOTE_ACTION_IDEMPOTENCY_MISMATCH", "unauthorized"] {
            try await journal.reject(first, reason: reason)
            let retry = try await journal.begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .link, sourceID: "source", targetID: "target")
            XCTAssertEqual(first, retry)
        }
        try await journal.reject(first, reason: "NOTE_LINK_ACTIVE_CONFLICT")
        let next = try await journal.begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .link, sourceID: "source", targetID: "target")
        XCTAssertNotEqual(first.requestID, next.requestID)
    }

    func testReopenRetainsFrozenIdentityUntilMatchingReceiptCompletesIt() async throws {
        let root = directory()
        let first = try await NoteLinkWriteJournal(directory: root).begin(
            apiBaseURL: "https://one.invalid", actorID: "actor", operation: .link,
            sourceID: "source", targetID: "target"
        )
        let reopened = NoteLinkWriteJournal(directory: root)
        let retry = try await reopened.begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .link, sourceID: "source", targetID: "target")
        XCTAssertEqual(first, retry)
        try await reopened.complete(first, receipt: receipt(first))
        let next = try await reopened.begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .link, sourceID: "source", targetID: "target")
        XCTAssertNotEqual(first.requestID, next.requestID)
        // A late duplicate completion must not clear the new intent.
        try await reopened.complete(first, receipt: receipt(first))
        let retained = try await NoteLinkWriteJournal(directory: root).begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .link, sourceID: "source", targetID: "target")
        XCTAssertEqual(next, retained)
    }

    func testUnresolvedUnlinkKeepsTheOriginalExactAssociationAfterRelink() async throws {
        let journal = NoteLinkWriteJournal(directory: directory())
        let first = try await journal.begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .unlink, sourceID: "source", targetID: "target", noteLinkID: "original_link")
        let recovered = try await journal.begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .unlink, sourceID: "source", targetID: "target", noteLinkID: "replacement_link")
        XCTAssertEqual(first, recovered)
        XCTAssertEqual(recovered.noteLinkID, "original_link")
        try await journal.complete(recovered, receipt: receipt(recovered))
        let next = try await journal.begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .unlink, sourceID: "source", targetID: "target", noteLinkID: "replacement_link")
        XCTAssertEqual(next.noteLinkID, "replacement_link")
        XCTAssertNotEqual(first.requestID, next.requestID)
    }

    func testAccountEnvironmentAndActionCannotAdoptEachOthersPendingRequest() async throws {
        let journal = NoteLinkWriteJournal(directory: directory())
        var identities = Set<String>()
        for (api, actor, operation) in [
            ("https://one.invalid", "actor", NoteLinkWriteAttempt.Operation.link),
            ("https://two.invalid", "actor", .link),
            ("https://one.invalid", "other", .link),
            ("https://one.invalid", "actor", .unlink)
        ] {
            let attempt = try await journal.begin(apiBaseURL: api, actorID: actor, operation: operation, sourceID: "source", targetID: "target", noteLinkID: operation == .unlink ? "exact_link" : nil)
            identities.insert(attempt.requestID)
        }
        XCTAssertEqual(identities.count, 4)
    }

    func testConcurrentBeginsReuseOneDurableRequest() async throws {
        let journal = NoteLinkWriteJournal(directory: directory())
        let identities = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try await journal.begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .link, sourceID: "source", targetID: "target").requestID
                }
            }
            var result = Set<String>()
            for try await identity in group { result.insert(identity) }
            return result
        }
        XCTAssertEqual(identities.count, 1)
    }

    func testCorruptRecordCannotSilentlyProduceANewOperation() async throws {
        let root = directory()
        let journal = NoteLinkWriteJournal(directory: root)
        _ = try await journal.begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .link, sourceID: "source", targetID: "target")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        try Data("broken".utf8).write(to: files[0], options: .atomic)
        do {
            _ = try await journal.begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .link, sourceID: "source", targetID: "target")
            XCTFail("A corrupted unresolved write must not create a new identity")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: files[0]), Data("broken".utf8))
    }

    func testMissingUnlinkIdentityAndUnwritableJournalFailBeforeIssuingAnAttempt() async throws {
        let root = directory()
        let journal = NoteLinkWriteJournal(directory: root)
        do {
            _ = try await journal.begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .unlink, sourceID: "source", targetID: "target")
            XCTFail("Unlink must preserve the exact association")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        try Data("file prevents directory creation".utf8).write(to: root)
        do {
            _ = try await journal.begin(apiBaseURL: "https://one.invalid", actorID: "actor", operation: .link, sourceID: "source", targetID: "target")
            XCTFail("A write without a retained identity must not be sent")
        } catch {}
    }
}
