import Foundation
import XCTest

final class NewNoteViewSourceContractTests: XCTestCase {
    func testBackgroundControlIsNotGatedByPersistedIdentity() throws {
        let sourceURL = Self.repositoryRoot
            .appendingPathComponent("ArcNote/NewNoteView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let toolbar = try XCTUnwrap(Self.formatToolbar(in: source))
        XCTAssertEqual(
            toolbar.components(separatedBy: "FormatButton(imageName: \"photo\"")
                .count - 1,
            1,
            "The card editor toolbar must render one background action"
        )

        let marker = try XCTUnwrap(
            toolbar.range(
                of: ".accessibilityIdentifier(\"cardEditorBackgroundButton\")"
            )
        )
        let ancestry = Self.openBlockHeaders(
            in: String(toolbar[..<marker.upperBound])
        )
        let identityGates = ancestry.filter(Self.isIdentityConditional)

        XCTAssertTrue(
            identityGates.isEmpty,
            "The background action must be visible before first save; "
                + "identity-gated ancestor: \(identityGates.joined(separator: " | "))"
        )
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }

    private static func formatToolbar(in source: String) -> Substring? {
        guard let start = source.range(of: "private var formatToolbar") else {
            return nil
        }
        let remainder = source[start.lowerBound...]
        guard let end = remainder.range(of: "// MARK:") else {
            return nil
        }
        return source[start.lowerBound..<end.lowerBound]
    }

    private static func openBlockHeaders(in source: String) -> [String] {
        var headers: [String] = []
        var headerStart = source.startIndex
        var index = source.startIndex
        var isInString = false
        var isEscaped = false
        var isInLineComment = false

        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)
            let nextCharacter = next < source.endIndex ? source[next] : nil

            if isInLineComment {
                if character == "\n" {
                    isInLineComment = false
                }
            } else if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
            } else if character == "/", nextCharacter == "/" {
                isInLineComment = true
                index = next
            } else if character == "\"" {
                isInString = true
            } else if character == "{" {
                headers.append(
                    String(source[headerStart..<index])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
                headerStart = source.index(after: index)
            } else if character == "}" {
                if !headers.isEmpty {
                    headers.removeLast()
                }
                headerStart = source.index(after: index)
            }

            index = source.index(after: index)
        }

        return headers
    }

    private static func isIdentityConditional(_ header: String) -> Bool {
        guard header.range(of: #"\bif\b"#, options: .regularExpression) != nil else {
            return false
        }
        return header.range(
            of: #"\b(cardID|cardId|currentNoteId)\b"#,
            options: .regularExpression
        ) != nil
    }
}
