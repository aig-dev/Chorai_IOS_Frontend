import Foundation
import XCTest

final class IOSProjectGuidanceContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testGuideCoversEnvironmentDesignAndDeliveryContracts() throws {
        let guide = try String(
            contentsOf: repositoryRoot.appendingPathComponent("AGENTS.md"),
            encoding: .utf8
        )

        for requiredText in [
            "iOS 16.0+, iPhone-only",
            "## API Environments",
            "ArcNote Production",
            "Archive / Release | production",
            "make run-stack",
            "make env-show",
            "127.0.0.1:8180/health",
            "single source of truth",
            "Complete runtime endpoint literals",
            "Focused catalog contract/tests may assert or assemble expected endpoint components",
            "temporary physical-device diagnostics",
            "reserved for tests and temporary diagnostics",
            "Do not add a customer-facing environment switch.",
            "## Zen Aesthetic",
            "Dynamic Type",
            "44 x 44 pt",
            "VoiceOver",
            "Reduce Motion",
            "## Definition of Done",
        ] {
            XCTAssertTrue(guide.contains(requiredText), requiredText)
        }

        XCTAssertFalse(guide.contains("8080"))
        XCTAssertLessThan(guide.split(separator: "\n").count, 150)
    }
}
