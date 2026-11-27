import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class ChatSendRecoveryTests: XCTestCase {
    private func fixture() throws -> (UserDefaults, String) {
        let suite = "ChatSendRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (defaults, suite)
    }

    private func attempt(content: String = "Original draft", reference: String? = "note") -> ChatSendAttempt {
        ChatSendAttempt(actorID: "human", conversationID: "conversation", content: content, referencedAssetID: reference)
    }

    func testReopeningPreservesOriginalBodyAttachmentAndKey() throws {
        let (defaults, scope) = try fixture()
        let original = attempt()
        try UserDefaultsChatSendAttemptStore(defaults: defaults, keyPrefix: scope).save(original, replacing: nil)
        let reopened = UserDefaultsChatSendAttemptStore(defaults: defaults, keyPrefix: scope)
        XCTAssertEqual(try reopened.load(actorID: "human", conversationID: "conversation"), original)
        XCTAssertNil(try reopened.load(actorID: "other", conversationID: "conversation"))
        XCTAssertNil(try reopened.load(actorID: "human", conversationID: "other"))
        XCTAssertNil(try UserDefaultsChatSendAttemptStore(defaults: defaults, keyPrefix: scope + ".other-origin").load(actorID: "human", conversationID: "conversation"))
    }

    func testUnknownResultCannotBeReplacedWithAnotherKeyOrBody() throws {
        let (defaults, scope) = try fixture()
        let store = UserDefaultsChatSendAttemptStore(defaults: defaults, keyPrefix: scope)
        let original = attempt()
        try store.save(original, replacing: nil)
        XCTAssertThrowsError(try store.save(attempt(), replacing: original))
        XCTAssertThrowsError(try store.save(attempt(content: "Replacement"), replacing: original))
        XCTAssertEqual(try store.load(actorID: "human", conversationID: "conversation"), original)
    }

    func testConfirmedRejectionAllowsAnEditedAttemptAndStaleAckCannotClearIt() throws {
        let (defaults, scope) = try fixture()
        let store = UserDefaultsChatSendAttemptStore(defaults: defaults, keyPrefix: scope)
        let original = attempt()
        try store.save(original, replacing: nil)
        let rejected = original.rejected()
        try store.save(rejected, replacing: original)
        let edited = attempt(content: "Corrected draft", reference: nil)
        try store.save(edited, replacing: rejected)
        XCTAssertThrowsError(try store.remove(original))
        XCTAssertEqual(try store.load(actorID: "human", conversationID: "conversation"), edited)
        try store.remove(edited)
        try store.remove(edited)
        XCTAssertNil(try store.load(actorID: "human", conversationID: "conversation"))
    }

    func testRetryBeforeFirstResponsePreventsAFalseDefinitiveRejection() throws {
        let (defaults, scope) = try fixture()
        let first = UserDefaultsChatSendAttemptStore(defaults: defaults, keyPrefix: scope)
        let retry = UserDefaultsChatSendAttemptStore(defaults: defaults, keyPrefix: scope)
        let original = attempt()
        try first.save(original, replacing: nil)
        // A second view must mark uncertainty before resending the same key.
        try retry.save(original.uncertain(), replacing: original)
        XCTAssertThrowsError(try first.save(original.rejected(), replacing: original))
        XCTAssertThrowsError(try retry.save(original.rejected(), replacing: original.uncertain()))
        XCTAssertEqual(try first.load(actorID: "human", conversationID: "conversation"), original.uncertain())
        // An exact successful ACK settles either request's copy of that send.
        try first.remove(original)
        XCTAssertNil(try retry.load(actorID: "human", conversationID: "conversation"))
    }

    func testOtherViewCannotOverwriteOrClearNewerAttempt() throws {
        let (defaults, scope) = try fixture()
        let first = UserDefaultsChatSendAttemptStore(defaults: defaults, keyPrefix: scope)
        let second = UserDefaultsChatSendAttemptStore(defaults: defaults, keyPrefix: scope)
        let original = attempt()
        try first.save(original, replacing: nil)
        XCTAssertThrowsError(try second.save(attempt(), replacing: nil))
        try first.remove(original)
        let newer = attempt(content: "Next message")
        try second.save(newer, replacing: nil)
        XCTAssertThrowsError(try first.remove(original))
        XCTAssertEqual(try first.load(actorID: "human", conversationID: "conversation"), newer)
    }

    func testCorruptOrWrongOwnerRecordIsRetainedAndBlocksANewSend() throws {
        let (defaults, scope) = try fixture()
        let key = "\(scope).human.conversation"
        let store = UserDefaultsChatSendAttemptStore(defaults: defaults, keyPrefix: scope)
        for value in [Data("not-json".utf8), try JSONEncoder().encode(ChatSendAttempt(actorID: "other", conversationID: "conversation", content: "Private draft"))] {
            defaults.set(value, forKey: key)
            XCTAssertThrowsError(try store.load(actorID: "human", conversationID: "conversation"))
            XCTAssertThrowsError(try store.save(attempt(), replacing: nil))
            XCTAssertEqual(defaults.data(forKey: key), value)
        }
    }

    func testBackendAcceptedWhitespaceBoundaryRetainsOriginalDraft() throws {
        let (defaults, scope) = try fixture()
        let store = UserDefaultsChatSendAttemptStore(defaults: defaults, keyPrefix: scope)
        let original = attempt(content: String(repeating: "中", count: 333) + "  ")
        try store.save(original, replacing: nil)
        XCTAssertEqual(try store.load(actorID: "human", conversationID: "conversation"), original)
    }

    func testCanonicalContentUsesBackendWhitespaceWithoutChangingStoredBody() {
        for scalar: UInt32 in [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0,
                               0x1680, 0x2000, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000] {
            let space = String(Unicode.Scalar(scalar)!)
            let record = attempt(content: space + "body" + space)
            XCTAssertEqual(record.normalizedContent, "body")
            XCTAssertEqual(record.content, space + "body" + space)
        }
        XCTAssertEqual(attempt(content: "\u{200B}body\u{200B}").normalizedContent, "\u{200B}body\u{200B}")
        XCTAssertEqual(attempt(content: "\u{FEFF}body\u{FEFF}").normalizedContent, "\u{FEFF}body\u{FEFF}")
    }

    func testInvalidPayloadDoesNotCreateAnAttempt() throws {
        let (defaults, scope) = try fixture()
        let store = UserDefaultsChatSendAttemptStore(defaults: defaults, keyPrefix: scope)
        for value in [attempt(content: "   "), attempt(content: String(repeating: "字", count: 334)), attempt(content: String(repeating: " ", count: 1_000) + "a"), attempt(reference: "../other")] {
            XCTAssertThrowsError(try store.save(value, replacing: nil))
            XCTAssertNil(try store.load(actorID: "human", conversationID: "conversation"))
        }
    }
}
