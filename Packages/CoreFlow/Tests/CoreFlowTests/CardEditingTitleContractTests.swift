import XCTest
@testable import CoreFlow

final class CardEditingTitleContractTests: XCTestCase {
    func testDraftNormalizesMissingOrBlankTitleToNil() {
        XCTAssertNil(makeDraft(title: nil).title)
        XCTAssertNil(makeDraft(title: "").title)
        XCTAssertNil(makeDraft(title: "  \n\t ").title)
    }

    func testDraftPreservesNonblankLegacyTitleExactly() {
        XCTAssertEqual(makeDraft(title: "  Legacy title  ").title, "  Legacy title  ")
    }

    func testSnapshotUsesTheSameTitleNormalizationContract() {
        XCTAssertNil(makeSnapshot(title: " \n ").title)
        XCTAssertEqual(
            makeSnapshot(title: "  Preserved title  ").title,
            "  Preserved title  "
        )
    }

    func testNormalizerReturnsNilForMissingOrBlankTitle() {
        XCTAssertNil(CardEditingTitle.normalized(nil))
        XCTAssertNil(CardEditingTitle.normalized(" \n "))
    }

    func testNormalizerPreservesNonblankLegacyTitleExactly() {
        XCTAssertEqual(
            CardEditingTitle.normalized("  Legacy title  "),
            "  Legacy title  "
        )
    }

    private func makeDraft(title: String?) -> CardEditingDraft {
        CardEditingDraft(
            title: title,
            content: "Body",
            tags: [],
            isPublic: false
        )
    }

    private func makeSnapshot(title: String?) -> CardEditingSnapshot {
        CardEditingSnapshot(
            id: "ast_title_contract",
            title: title,
            content: "Body",
            tags: [],
            isPublic: false,
            backgroundMediaRef: nil
        )
    }
}
