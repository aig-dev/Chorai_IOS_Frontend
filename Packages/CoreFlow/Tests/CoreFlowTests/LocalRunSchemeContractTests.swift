import Foundation
import XCTest

final class LocalRunSchemeContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func read(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func launchAction(in scheme: String) throws -> Substring {
        let start = try XCTUnwrap(scheme.range(of: "<LaunchAction"))
        let end = try XCTUnwrap(
            scheme.range(
                of: "</LaunchAction>",
                range: start.upperBound..<scheme.endIndex
            )
        )
        return scheme[start.lowerBound..<end.upperBound]
    }

    func testSharedSchemesSelectCompiledLocalAndProductionConfigurations() throws {
        let localScheme = try read(
            "ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote.xcscheme"
        )
        let productionScheme = try read(
            "ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote Production.xcscheme"
        )

        XCTAssertTrue(try launchAction(in: localScheme).contains(
            "buildConfiguration = \"Debug\""
        ))
        XCTAssertTrue(try launchAction(in: productionScheme).contains(
            "buildConfiguration = \"Debug-Production\""
        ))

        for scheme in [localScheme, productionScheme] {
            XCTAssertFalse(scheme.contains("CHORAI_API_BASE_URL"))
            XCTAssertFalse(scheme.contains("http://"))
            XCTAssertFalse(scheme.contains("https://"))
        }
    }

    func testBuildConfigurationFilesSelectNamesNotEndpointLiterals() throws {
        let local = try read("Config/Local.xcconfig")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let production = try read("Config/Production.xcconfig")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(local, "CHORAI_API_ENVIRONMENT = local")
        XCTAssertEqual(production, "CHORAI_API_ENVIRONMENT = production")

        let infoPlist = try read("ArcNote/Info.plist")
        XCTAssertTrue(infoPlist.contains("<key>ChoraiAPIEnvironment</key>"))
        XCTAssertTrue(
            infoPlist.contains("<string>$(CHORAI_API_ENVIRONMENT)</string>")
        )

        let project = try read("ArcNote.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("path = Local.xcconfig;"))
        XCTAssertTrue(project.contains("path = Production.xcconfig;"))
        XCTAssertTrue(project.contains("name = Debug-Production;"))
    }
}
