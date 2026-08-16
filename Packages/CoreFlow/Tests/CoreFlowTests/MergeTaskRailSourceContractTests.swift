import Foundation
import XCTest

final class MergeTaskRailSourceContractTests: XCTestCase {
    func testRailIsIconOnlyAccessibleAndReduceMotionAware() throws {
        let source = try source(at: "ArcNote/CoreFlow/MergeTaskRail.swift")
        XCTAssertTrue(source.contains("accessibilityReduceMotion"))
        XCTAssertTrue(source.contains("accessibilityReduceTransparency"))
        XCTAssertTrue(source.contains("frame(width: 44, height: 44)"))
        XCTAssertTrue(source.contains("Image(\"menu_merge\")"))
        XCTAssertTrue(source.contains("Image(systemName: \"checkmark\")"))
        XCTAssertTrue(source.contains("accessibilityLabel"))
        XCTAssertTrue(source.contains("accessibilityValue"))
        XCTAssertFalse(source.contains("Text(\"Weaving\")"))
        XCTAssertFalse(source.contains("Text(\"Preview\")"))
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
