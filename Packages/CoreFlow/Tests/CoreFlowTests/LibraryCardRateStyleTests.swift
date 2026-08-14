import XCTest
@testable import CoreFlow

final class LibraryCardRateStyleTests: XCTestCase {
    func testRatesAdvanceAtPowersOfThree() {
        let cases: [(Int, LibraryCardRateStyle, String?)] = [
            (-1, .neutral, nil),
            (0, .neutral, nil),
            (1, .neutral, nil),
            (2, .neutral, nil),
            (3, .green, "#00FF66"),
            (8, .green, "#00FF66"),
            (9, .blue, "#0371FF"),
            (26, .blue, "#0371FF"),
            (27, .purple, "#9627D2"),
            (80, .purple, "#9627D2"),
            (81, .amber, "#D97800"),
            (242, .amber, "#D97800"),
            (243, .orangeRed, "#FF5E00"),
            (729, .orangeRed, "#FF5E00"),
        ]

        for (rate, expectedStyle, expectedAccent) in cases {
            let style = LibraryCardRateStyle(rate: rate)

            XCTAssertEqual(style, expectedStyle, "Unexpected style for rate \(rate)")
            XCTAssertEqual(
                style.accentHex,
                expectedAccent,
                "Unexpected accent for rate \(rate)"
            )
        }
    }
}
