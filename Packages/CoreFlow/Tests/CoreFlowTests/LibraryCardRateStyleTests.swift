import XCTest
@testable import CoreFlow

final class LibraryCardRateStyleTests: XCTestCase {
    func testCanonicalBackendRatesMapToLibraryAccents() {
        let cases: [(Int, LibraryCardRateStyle, String?)] = [
            (1, .neutral, nil),
            (2, .green, "#00FF66"),
            (3, .blue, "#0371FF"),
            (4, .purple, "#9627D2"),
            (5, .amber, "#D97800"),
            (6, .orangeRed, "#FF5E00"),
            (0, .neutral, nil),
            (7, .neutral, nil),
            (243, .neutral, nil),
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
