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

    func testApplicationResolvesOverrideBeforeCompiledEnvironment() throws {
        let source = try read("ArcNote/APIConfiguration.swift")
        let legacyLocalLiteral = ["127.0.0.1:", "8080"].joined()
        let baseURLStart = try XCTUnwrap(source.range(of: "static var baseURL"))
        let baseURLEnd = try XCTUnwrap(
            source.range(
                of: "static var environmentLabel",
                range: baseURLStart.upperBound..<source.endIndex
            )
        )
        let baseURLSource = source[
            baseURLStart.lowerBound..<baseURLEnd.lowerBound
        ]
        let overrideRange = try XCTUnwrap(
            baseURLSource.range(of: "overrideEnvironmentKey")
        )
        let compiledRange = try XCTUnwrap(
            baseURLSource.range(of: "return configuredEnvironment.baseURL")
        )

        XCTAssertLessThan(overrideRange.lowerBound, compiledRange.lowerBound)
        XCTAssertTrue(source.contains("APIEnvironment.normalizedBaseURL"))
        XCTAssertFalse(source.contains("#if DEBUG\n        return \"http://"))
        XCTAssertFalse(source.contains(legacyLocalLiteral))
    }

    func testRuntimeEndpointLiteralsExistOnlyInTheCatalog() throws {
        let localLiteral = ["http://", "127.0.0.1:8180"].joined()
        let productionLiteral = ["https://", "api.chorai.top"].joined()
        let legacyLocalLiteral = ["127.0.0.1:", "8080"].joined()
        let catalog = try read("ArcNote/APIEnvironment.swift")
        XCTAssertTrue(catalog.contains(localLiteral))
        XCTAssertTrue(catalog.contains(productionLiteral))

        for path in [
            "ArcNote/APIConfiguration.swift",
            "ArcNoteUITests/ArcNoteUITests.swift",
            "Config/Local.xcconfig",
            "Config/Production.xcconfig",
            "ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote.xcscheme",
            "ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote Production.xcscheme",
        ] {
            let source = try read(path)
            XCTAssertFalse(source.contains(localLiteral), path)
            XCTAssertFalse(source.contains(productionLiteral), path)
            XCTAssertFalse(source.contains(legacyLocalLiteral), path)
        }
    }
}
