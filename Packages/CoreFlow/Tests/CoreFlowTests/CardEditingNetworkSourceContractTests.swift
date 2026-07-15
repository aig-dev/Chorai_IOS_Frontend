import Foundation
import XCTest

final class CardEditingNetworkSourceContractTests: XCTestCase {
    func testCardDetailDecoderAcceptsMissingAndNullTitle() throws {
        let source = try source("ArcNote/Models/CardDetailModels.swift")

        XCTAssertTrue(
            source.contains(
                "title = try container.decodeIfPresent(String.self, forKey: .title)"
            ),
            "CardDetail must decode an omitted or null title"
        )
        XCTAssertFalse(
            source.contains(
                "title = try container.decode(String.self, forKey: .title)"
            )
        )
    }

    func testCardWritePathsUseOptionalTitleParameters() throws {
        let source = try source("ArcNote/NetworkManager.swift")

        let signatures = [
            "func createCard(",
            "func updateCard(id: String,",
            "func updateCard(cardId: String,",
            "func updateCardForEditing("
        ]
        for signature in signatures {
            let body = try XCTUnwrap(functionBody(in: source, signature: signature))
            XCTAssertTrue(
                body.contains("addCardEditingTitle("),
                "\(signature) must use the shared optional-title parameter helper"
            )
        }
        XCTAssertTrue(source.contains("private func addCardEditingTitle("))
        XCTAssertFalse(source.contains(#""title": request.title ?? """#))
        XCTAssertFalse(source.contains(#""title": title ?? """#))
    }

    func testInlineImageUploadUsesCanonicalUploadDTOAndRejectsIncompleteResponse() throws {
        let serviceSource = try source(
            "ArcNote/CoreFlow/NetworkCoreCardEditingService.swift"
        )
        let body = try XCTUnwrap(
            functionBody(in: serviceSource, signature: "func uploadInlineImage(")
        )

        XCTAssertTrue(body.contains("network.uploadCardMedia("))
        XCTAssertTrue(body.contains("guard upload.success"))
        XCTAssertTrue(body.contains("uploaded.mediaRef"))
        XCTAssertTrue(body.contains("uploaded.publicURL"))
        XCTAssertTrue(body.contains("CardEditingMediaURLResolver.resolve("))
        XCTAssertTrue(
            body.contains(
                "canonicalizeRelativePath: APIConfiguration.resourceURLString"
            )
        )
        XCTAssertTrue(body.contains("CardEditingInlineImageUpload("))
        XCTAssertTrue(body.contains("card_inline_image_url_missing"))

        let modelsSource = try source("ArcNote/NetworkModels.swift")
        XCTAssertTrue(modelsSource.contains("let publicURL: String"))
        XCTAssertTrue(modelsSource.contains(#"case publicURL = "public_url""#))
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }

    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func functionBody(in source: String, signature: String) -> Substring? {
        guard let signatureRange = source.range(of: signature),
              let openingBrace = source[signatureRange.lowerBound...]
                .firstIndex(of: "{") else {
            return nil
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return source[openingBrace...index]
                }
            default:
                break
            }
            index = source.index(after: index)
        }
        return nil
    }
}
