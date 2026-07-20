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
            "## API Environments",
            "ArcNote Production",
            "Archive / Release | production",
            "make run-stack",
            "make env-show",
            "127.0.0.1:8180/health",
            "single source of truth",
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
