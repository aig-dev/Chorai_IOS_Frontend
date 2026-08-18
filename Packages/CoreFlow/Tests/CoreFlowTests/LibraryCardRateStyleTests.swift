import XCTest
@testable import CoreFlow

final class LibraryCardRateStyleTests: XCTestCase {
    func testSemanticTierRawValuesRoundTrip() throws {
        let cases: [(CardLevelStyle.Tier, String)] = [
            (.basic, "basic"),
            (.notable, "notable"),
            (.valuable, "valuable"),
            (.significant, "significant"),
            (.exceptional, "exceptional"),
            (.definitive, "definitive"),
        ]

        for (tier, rawValue) in cases {
            let encoded = try JSONEncoder().encode(tier)

            XCTAssertEqual(
                String(decoding: encoded, as: UTF8.self),
                "\"\(rawValue)\""
            )
            XCTAssertEqual(
                try JSONDecoder().decode(CardLevelStyle.Tier.self, from: encoded),
                tier
            )
        }
    }
}
