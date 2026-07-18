import XCTest
@testable import CoreFlow

final class CardEditingTagTests: XCTestCase {
    func testNormalizedCandidateTrimsAndRemovesLeadingHashes() {
        XCTAssertEqual(CardEditingTag.normalized("  ##  idea  "), "idea")
        XCTAssertEqual(CardEditingTag.normalized("research"), "research")
        XCTAssertNil(CardEditingTag.normalized("  \n "))
        XCTAssertNil(CardEditingTag.normalized(" ###  "))
    }

    func testNormalizeDeduplicatesInOrderAndCapsAtTen() {
        let values = [
            "#one", " one ", "two", "three", "four", "five", "six",
            "seven", "eight", "nine", "ten", "eleven",
        ]

        XCTAssertEqual(
            CardEditingTag.normalize(values),
            ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        )
    }

    func testAppendingReturnsOnlyARealNewCandidate() {
        XCTAssertEqual(
            CardEditingTag.appending(" ## work ", to: ["idea"]),
            ["idea", "work"]
        )
        XCTAssertNil(CardEditingTag.appending("#idea", to: ["idea"]))
        XCTAssertNil(CardEditingTag.appending("###", to: ["idea"]))
        XCTAssertNil(
            CardEditingTag.appending(
                "eleven",
                to: (1...CardEditingTag.maximumCount).map(String.init)
            )
        )
    }

    func testDraftUsesTheSharedListNormalizer() {
        let draft = CardEditingDraft(
            title: nil,
            content: "Body",
            tags: ["## idea ", "idea", "work"],
            isPublic: false
        )

        XCTAssertEqual(draft.tags, ["idea", "work"])
    }
}
