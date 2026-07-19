import XCTest
@testable import CoreFlow

final class CardEditingDraftCommitEquivalenceTests: XCTestCase {
    func testEnvelopeWithNonArrayBlocksFailsClosed() {
        let malformed = CardEditingDraft(
            title: nil,
            content: "Body",
            contentJSON: #"{"schema_version":1,"blocks":"corrupt"}"#,
            tags: [],
            isPublic: false
        )
        let reordered = CardEditingDraft(
            title: nil,
            content: "Body",
            contentJSON: #"{"blocks":"corrupt","schema_version":1}"#,
            tags: [],
            isPublic: false
        )

        XCTAssertEqual(
            malformed.validationError,
            .invalidDraft(code: "invalid_content_json")
        )
        XCTAssertEqual(
            reordered.validationError,
            .invalidDraft(code: "invalid_content_json")
        )
        XCTAssertFalse(malformed.isCommitEquivalent(to: reordered))
    }
}
