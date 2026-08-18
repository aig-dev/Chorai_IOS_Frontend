import XCTest
@testable import CoreFlow

final class CardLevelStyleTests: XCTestCase {
    func testBoundaryRatesResolveToCanonicalSemanticLevels() {
        let cases: [(
            rate: Int,
            tier: CardLevelStyle.Tier,
            label: String,
            asset: String,
            accent: String?
        )] = [
            (-1, .basic, "Basic", "merge_bg_basic", nil),
            (0, .basic, "Basic", "merge_bg_basic", nil),
            (1, .basic, "Basic", "merge_bg_basic", nil),
            (2, .basic, "Basic", "merge_bg_basic", nil),
            (3, .notable, "Notable", "merge_bg_green", "#00FF66"),
            (8, .notable, "Notable", "merge_bg_green", "#00FF66"),
            (9, .valuable, "Valuable", "merge_bg_blue", "#0371FF"),
            (26, .valuable, "Valuable", "merge_bg_blue", "#0371FF"),
            (27, .significant, "Significant", "merge_bg_purple", "#9627D2"),
            (80, .significant, "Significant", "merge_bg_purple", "#9627D2"),
            (81, .exceptional, "Exceptional", "merge_bg_yellow", "#D97800"),
            (242, .exceptional, "Exceptional", "merge_bg_yellow", "#D97800"),
            (243, .definitive, "Definitive", "merge_bg_red", "#FF5E00"),
            (Int.max, .definitive, "Definitive", "merge_bg_red", "#FF5E00"),
        ]

        for expected in cases {
            let style = CardLevelStyle(rate: expected.rate)

            XCTAssertEqual(style.tier, expected.tier, "Unexpected tier for rate \(expected.rate)")
            XCTAssertEqual(style.label, expected.label, "Unexpected label for rate \(expected.rate)")
            XCTAssertEqual(
                style.materialAssetName,
                expected.asset,
                "Unexpected material for rate \(expected.rate)"
            )
            XCTAssertEqual(style.accentHex, expected.accent, "Unexpected accent for rate \(expected.rate)")
        }
    }

    func testReviewSensitiveSemanticNamesDoNotRegress() {
        XCTAssertEqual(CardLevelStyle(rate: 3).label, "Notable")
        XCTAssertEqual(CardLevelStyle(rate: 81).label, "Exceptional")
        XCTAssertNotEqual(CardLevelStyle(rate: 81).label, "Critical")
    }
}
