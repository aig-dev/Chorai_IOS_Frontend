import CoreFlow
import Foundation
import XCTest

final class RegistrationDraftTests: XCTestCase {
    func testEmailChangeInvalidatesCodeAndResendDeadlineAndIgnoresStaleSuccess() {
        let now = Date(timeIntervalSince1970: 120)
        var draft = RegistrationDraft(email: "one@example.com")
        XCTAssertTrue(draft.markCodeSent(to: draft.email, at: now))
        draft.code = "Ab12cDextra"
        XCTAssertEqual(draft.code, "Ab12cD")
        XCTAssertTrue(draft.canContinue(.code))

        draft.email = "two@example.com"
        XCTAssertEqual(draft.code, "")
        XCTAssertEqual(draft.resendSeconds(at: now), 0)
        XCTAssertFalse(draft.markCodeSent(to: "one@example.com", at: now))
        draft.code = "123456"
        XCTAssertFalse(draft.canContinue(.code))
    }

    func testResendUsesElapsedTimeAndPreservesOtherFields() {
        let now = Date(timeIntervalSince1970: 120)
        var draft = RegistrationDraft(email: "one@example.com", username: "Chora", password: "abc12345")
        XCTAssertTrue(draft.markCodeSent(to: draft.email, at: now))
        XCTAssertEqual(draft.resendSeconds(at: now.addingTimeInterval(0.5)), 60)
        XCTAssertEqual(draft.resendSeconds(at: now.addingTimeInterval(57.5)), 3)
        XCTAssertEqual(draft.resendSeconds(at: now.addingTimeInterval(70)), 0)
        XCTAssertTrue(draft.codeWasSent)
        XCTAssertEqual(draft.username, "Chora")
        XCTAssertEqual(draft.password, "abc12345")
    }

    func testCodeFormatAndConfirmationAreSeparateFromAccountSubmission() {
        var draft = RegistrationDraft(email: "one@example.com", username: "  a ", password: "abcdefgh")
        XCTAssertTrue(draft.markCodeSent(to: draft.email, at: .distantPast))
        draft.code = "Ab12Cd"
        XCTAssertTrue(draft.canContinue(.code))
        XCTAssertFalse(draft.canContinue(.username))
        XCTAssertFalse(draft.canContinue(.password))
        draft.username = "Chora"
        draft.password = "abc12345"
        draft.confirmPassword = "wrong"
        XCTAssertTrue(draft.canContinue(.confirm))
        XCTAssertFalse(draft.canRegister)
        draft.confirmPassword = draft.password
        XCTAssertTrue(draft.canRegister)
    }
}
