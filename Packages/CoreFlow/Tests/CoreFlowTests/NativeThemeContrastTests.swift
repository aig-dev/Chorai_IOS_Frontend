import Foundation
import XCTest

final class NativeThemeContrastTests: XCTestCase {
    private var root: URL {
        var value = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { value.deleteLastPathComponent() }
        return value
    }

    func testProfileActionsDoNotPlaceAdaptiveLightInkOnFixedWhite() throws {
        for file in ["UserProfileView.swift", "FollowListView.swift", "BlockedActorsView.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent("ArcNote/\(file)"), encoding: .utf8)
            XCTAssertFalse(source.contains(".fill(Color.white)"), "\(file): dark-mode adaptive ink requires a matching adaptive button surface")
        }
    }

    func testApprovedReadingAndActionColorsMeetTextContrastInBothAppearances() throws {
        let source = try String(contentsOf: root.appendingPathComponent("ArcNote/ChoraiTheme.swift"), encoding: .utf8)
        func pair(_ name: String) throws -> [UInt32] {
            let pattern = "static let \(name) = color\\(light: 0x([0-9A-F]+), dark: 0x([0-9A-F]+)\\)"
            let match = try XCTUnwrap(NSRegularExpression(pattern: pattern).firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
            return try [1, 2].map { index in
                let range = try XCTUnwrap(Range(match.range(at: index), in: source))
                return try XCTUnwrap(UInt32(source[range], radix: 16))
            }
        }
        func luminance(_ hex: UInt32) -> Double {
            let channels: [Double] = [16, 8, 0].map { Double((hex >> $0) & 255) / 255 }
            let values: [Double] = channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return zip(values, [0.2126, 0.7152, 0.0722]).reduce(0.0) { $0 + $1.0 * $1.1 }
        }
        for (foreground, background) in [("ink", "background"), ("secondaryInk", "surface"), ("tertiaryInk", "surface"), ("gold", "surface"), ("onAccent", "ink")] {
            let fg = try pair(foreground), bg = try pair(background)
            for index in 0..<2 {
                let a = luminance(fg[index]), b = luminance(bg[index])
                XCTAssertGreaterThanOrEqual((max(a,b)+0.05)/(min(a,b)+0.05), 4.5, "\(foreground)/\(background), appearance \(index)")
            }
        }
    }
}
