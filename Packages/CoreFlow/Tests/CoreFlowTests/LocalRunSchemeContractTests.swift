import Foundation
import XCTest

final class LocalRunSchemeContractTests: XCTestCase {
    private struct ProjectObject {
        let body: Substring
    }

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

    private func action(named name: String, in scheme: String) throws -> Substring {
        let start = try XCTUnwrap(scheme.range(of: "<\(name)"))
        let end = try XCTUnwrap(
            scheme.range(
                of: "</\(name)>",
                range: start.upperBound..<scheme.endIndex
            )
        )
        return scheme[start.lowerBound..<end.upperBound]
    }

    private func capture(
        _ pattern: String,
        in source: some StringProtocol
    ) throws -> String? {
        let source = String(source)
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..., in: source)
        guard let match = expression.firstMatch(in: source, range: range),
              let captureRange = Range(match.range(at: 1), in: source)
        else {
            return nil
        }
        return String(source[captureRange])
    }

    private func firstCapture(
        _ pattern: String,
        in source: some StringProtocol
    ) throws -> String {
        try XCTUnwrap(try capture(pattern, in: source))
    }

    private func projectObject(
        identifier: String,
        in project: String
    ) throws -> ProjectObject {
        let escapedIdentifier = NSRegularExpression.escapedPattern(
            for: identifier
        )
        let expression = try NSRegularExpression(
            pattern: "(?m)^[\\t ]*\(escapedIdentifier) /\\*.*\\*/ = \\{"
        )
        let match = try XCTUnwrap(
            expression.firstMatch(
                in: project,
                range: NSRange(project.startIndex..., in: project)
            )
        )
        let matchRange = try XCTUnwrap(Range(match.range, in: project))
        let openingBrace = try XCTUnwrap(
            project[matchRange].firstIndex(of: "{")
        )

        var depth = 0
        var cursor = openingBrace
        while cursor < project.endIndex {
            switch project[cursor] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return ProjectObject(
                        body: project[openingBrace...cursor]
                    )
                }
            default:
                break
            }
            cursor = project.index(after: cursor)
        }

        XCTFail("Unterminated project object \(identifier)")
        throw CocoaError(.fileReadCorruptFile)
    }

    private func projectFileName(
        identifier: String,
        in project: String
    ) throws -> String {
        let fileReference = try projectObject(
            identifier: identifier,
            in: project
        )
        guard fileReference.body.contains("isa = PBXFileReference;") else {
            XCTFail("Expected PBXFileReference object for \(identifier)")
            throw CocoaError(.fileReadCorruptFile)
        }
        let rawValue = try XCTUnwrap(
            try capture(
                #"(?:^|[;{])\s*path = ([^;]+);"#,
                in: fileReference.body
            ) ?? capture(
                #"(?:^|[;{])\s*name = ([^;]+);"#,
                in: fileReference.body
            )
        )
        let trimmed = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let unquoted = if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
            String(trimmed.dropFirst().dropLast())
        } else {
            trimmed
        }
        return URL(fileURLWithPath: unquoted).lastPathComponent
    }

    private func arcNoteConfigurationBindings(
        in project: String
    ) throws -> [String: String] {
        let nativeTargets = try XCTUnwrap(
            project.range(
                of: "/* Begin PBXNativeTarget section */"
            ).flatMap { start in
                project.range(
                    of: "/* End PBXNativeTarget section */",
                    range: start.upperBound..<project.endIndex
                ).map { end in project[start.upperBound..<end.lowerBound] }
            }
        )
        let targetIdentifier = try firstCapture(
            #"(?m)^\s*([A-F0-9]+) /\* ArcNote \*/ = \{"#,
            in: nativeTargets
        )
        let target = try projectObject(
            identifier: targetIdentifier,
            in: project
        )
        let configurationListIdentifier = try firstCapture(
            #"buildConfigurationList = ([A-F0-9]+) /\*"#,
            in: target.body
        )
        let configurationList = try projectObject(
            identifier: configurationListIdentifier,
            in: project
        )
        let configurationIdentifiers = try firstCapture(
            #"buildConfigurations = \(([\s\S]*?)\);"#,
            in: configurationList.body
        )
            .split(separator: "\n")
            .compactMap { line -> String? in
                let source = String(line)
                let expression = try? NSRegularExpression(
                    pattern: #"^\s*([A-F0-9]+) /\*"#
                )
                guard let match = expression?.firstMatch(
                    in: source,
                    range: NSRange(source.startIndex..., in: source)
                ),
                let range = Range(match.range(at: 1), in: source)
                else {
                    return nil
                }
                return String(source[range])
            }

        return try Dictionary(
            uniqueKeysWithValues: configurationIdentifiers.map { identifier in
                let configuration = try projectObject(
                    identifier: identifier,
                    in: project
                )
                let name = try firstCapture(
                    #"(?m)^\s*name = ([^;]+);"#,
                    in: configuration.body
                )
                let fileReferenceIdentifier = try firstCapture(
                    #"baseConfigurationReference = ([A-F0-9]+) /\*"#,
                    in: configuration.body
                )
                let file = try projectFileName(
                    identifier: fileReferenceIdentifier,
                    in: project
                )
                return (name, file)
            }
        )
    }

    private func relevantRuntimeAndConfigFiles() throws -> [URL] {
        let fileManager = FileManager.default
        var files = [
            repositoryRoot.appendingPathComponent("ArcNote/Info.plist"),
            repositoryRoot.appendingPathComponent(
                "ArcNote.xcodeproj/project.pbxproj"
            ),
        ]
        for (directory, pathExtension) in [
            ("ArcNote", "swift"),
            ("ArcNoteUITests", "swift"),
            ("Config", "xcconfig"),
            ("ArcNote.xcodeproj/xcshareddata/xcschemes", "xcscheme"),
        ] {
            let root = repositoryRoot.appendingPathComponent(directory)
            let enumerator = try XCTUnwrap(
                fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey]
                )
            )
            for case let file as URL in enumerator
            where file.pathExtension == pathExtension {
                files.append(file)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func relativePath(of file: URL) -> String {
        file.path.replacingOccurrences(
            of: repositoryRoot.path + "/",
            with: ""
        )
    }

    func testSharedSchemesSelectCompiledLocalAndProductionConfigurations() throws {
        let localScheme = try read(
            "ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote.xcscheme"
        )
        let productionScheme = try read(
            "ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote Production.xcscheme"
        )

        XCTAssertTrue(try action(named: "LaunchAction", in: localScheme).contains(
            "buildConfiguration = \"Debug\""
        ))
        XCTAssertTrue(try action(named: "LaunchAction", in: productionScheme).contains(
            "buildConfiguration = \"Debug-Production\""
        ))
        XCTAssertTrue(try action(named: "ArchiveAction", in: localScheme).contains(
            "buildConfiguration = \"Release\""
        ))
        XCTAssertTrue(try action(named: "ArchiveAction", in: productionScheme).contains(
            "buildConfiguration = \"Release\""
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
        let bindings = try arcNoteConfigurationBindings(in: project)
        XCTAssertEqual(Set(bindings.keys), ["Debug", "Debug-Production", "Release"])
        XCTAssertEqual(bindings["Debug"], "Local.xcconfig")
        XCTAssertEqual(bindings["Debug-Production"], "Production.xcconfig")
        XCTAssertEqual(bindings["Release"], "Production.xcconfig")
    }

    func testApplicationResolvesOverrideBeforeCompiledEnvironment() throws {
        let source = try read("ArcNote/APIConfiguration.swift")
        let catalog = try read("ArcNote/APIEnvironment.swift")
        let legacyLocalLiteral = ["127.0.0.1:", "8080"].joined()
        let overrideRange = try XCTUnwrap(
            catalog.range(of: "let rawOverride = processEnvironment")
        )
        let compiledRange = try XCTUnwrap(
            catalog.range(of: "guard let rawCompiledEnvironment")
        )

        XCTAssertLessThan(overrideRange.lowerBound, compiledRange.lowerBound)
        XCTAssertTrue(source.contains("APIBaseURLResolver.resolve"))
        XCTAssertTrue(source.contains("preconditionFailure"))
        XCTAssertTrue(catalog.contains("APIEnvironment.normalizedBaseURL"))
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

        for file in try relevantRuntimeAndConfigFiles() {
            let path = relativePath(of: file)
            let source = try String(contentsOf: file, encoding: .utf8)
            if path != "ArcNote/APIEnvironment.swift" {
                XCTAssertFalse(source.contains(localLiteral), path)
                XCTAssertFalse(source.contains(productionLiteral), path)
            }
            XCTAssertFalse(source.contains(legacyLocalLiteral), path)
        }
    }
}
