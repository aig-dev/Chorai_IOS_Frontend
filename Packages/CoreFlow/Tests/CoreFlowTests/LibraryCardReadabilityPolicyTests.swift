import XCTest
@testable import CoreFlow

final class LibraryCardReadabilityPolicyTests: XCTestCase {
    func testVeilStrengthAdaptsToAccessibilitySettings() {
        XCTAssertEqual(
            LibraryCardReadabilityPolicy.veilOpacity(
                reduceTransparency: false,
                increasedContrast: false
            ),
            0.58
        )
        XCTAssertEqual(
            LibraryCardReadabilityPolicy.veilOpacity(
                reduceTransparency: false,
                increasedContrast: true
            ),
            0.70
        )
        XCTAssertEqual(
            LibraryCardReadabilityPolicy.veilOpacity(
                reduceTransparency: true,
                increasedContrast: false
            ),
            0.74
        )
    }

    func testMetadataContrastClearsAAAgainstWorstCaseWhiteImage() {
        for increasedContrast in [false, true] {
            let veil = LibraryCardReadabilityPolicy.veilOpacity(
                reduceTransparency: false,
                increasedContrast: increasedContrast
            )
            let foregroundAlpha =
                LibraryCardReadabilityPolicy.metadataOpacity(
                    hasBackground: true,
                    increasedContrast: increasedContrast
                )
            let backgroundChannel = 1 - veil
            let foregroundChannel = foregroundAlpha
                + backgroundChannel * (1 - foregroundAlpha)

            XCTAssertGreaterThanOrEqual(
                contrastRatio(
                    foregroundChannel,
                    backgroundChannel
                ),
                4.5
            )
        }
    }

    func testCustomBackgroundTagsUseDarkSurface() {
        let veil = LibraryCardReadabilityPolicy.veilOpacity(
            reduceTransparency: false,
            increasedContrast: false
        )
        let tagOpacity = LibraryCardReadabilityPolicy.tagSurfaceOpacity(
            hasBackground: true
        )

        XCTAssertEqual(tagOpacity, 0.42)
        XCTAssertEqual(
            LibraryCardReadabilityPolicy.tagSurfaceOpacity(
                hasBackground: false
            ),
            0.20
        )
        XCTAssertGreaterThanOrEqual(
            contrastRatio(1, (1 - veil) * (1 - tagOpacity)),
            4.5
        )
    }

    func testCollectEngagementTextClearsAAOnCustomBackground() {
        let veil = LibraryCardReadabilityPolicy.veilOpacity(
            reduceTransparency: false,
            increasedContrast: false
        )
        let foregroundAlpha =
            LibraryCardReadabilityPolicy.engagementOpacity(
                hasBackground: true,
                increasedContrast: false
            )
        let backgroundChannel = 1 - veil
        let foregroundChannel = foregroundAlpha
            + backgroundChannel * (1 - foregroundAlpha)

        XCTAssertEqual(foregroundAlpha, 0.90)
        XCTAssertEqual(
            LibraryCardReadabilityPolicy.engagementOpacity(
                hasBackground: false,
                increasedContrast: false
            ),
            0.80
        )
        XCTAssertGreaterThanOrEqual(
            contrastRatio(foregroundChannel, backgroundChannel),
            4.5
        )
    }

    private func contrastRatio(_ first: Double, _ second: Double) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ channel: Double) -> Double {
        if channel <= 0.04045 {
            return channel / 12.92
        }
        return pow((channel + 0.055) / 1.055, 2.4)
    }
}
