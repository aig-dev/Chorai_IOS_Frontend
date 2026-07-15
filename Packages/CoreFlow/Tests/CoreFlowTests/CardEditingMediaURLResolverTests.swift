import CoreFlow
import Foundation
import XCTest

final class CardEditingMediaURLResolverTests: XCTestCase {
    func testResolvesSameOriginRelativeUploadPathThroughCanonicalResourceResolver() throws {
        let rawPath = "/chorai-assets/staged/note_media/act_1/med_inline_1.png"
        var resolvedPath: String?

        let url = CardEditingMediaURLResolver.resolve(
            rawPath,
            canonicalizeRelativePath: { path in
                resolvedPath = path
                return "http://127.0.0.1:9000\(path)"
            }
        )

        XCTAssertEqual(resolvedPath, rawPath)
        XCTAssertEqual(
            url,
            try XCTUnwrap(
                URL(
                    string: "http://127.0.0.1:9000/chorai-assets/staged/note_media/act_1/med_inline_1.png"
                )
            )
        )
    }

    func testPreservesAbsoluteHTTPAndHTTPSUploadURLs() throws {
        for rawURL in [
            "http://127.0.0.1:9000/chorai-assets/staged/note_media/act_1/med_local.png",
            "https://cdn.chorai.example/chorai-assets/staged/note_media/act_1/med_prod.webp"
        ] {
            var relativeResolverWasCalled = false
            let url = CardEditingMediaURLResolver.resolve(
                rawURL,
                canonicalizeRelativePath: { _ in
                    relativeResolverWasCalled = true
                    return "https://should-not-be-used.example"
                }
            )

            XCTAssertEqual(url, try XCTUnwrap(URL(string: rawURL)))
            XCTAssertFalse(relativeResolverWasCalled)
        }
    }

    func testRejectsDangerousSchemesAndAmbiguousRelativeValues() {
        for rawValue in [
            "javascript:alert(1)",
            "data:image/png;base64,AAAA",
            "file:///tmp/image.png",
            "ftp://cdn.chorai.example/image.png",
            "https://user:password@cdn.chorai.example/image.png",
            "//evil.example/image.png",
            "chorai-assets/image.png",
            ""
        ] {
            XCTAssertNil(
                CardEditingMediaURLResolver.resolve(
                    rawValue,
                    canonicalizeRelativePath: { "https://api.chorai.example\($0)" }
                ),
                rawValue
            )
        }

        XCTAssertNil(
            CardEditingMediaURLResolver.resolve(
                "/chorai-assets/image.png",
                canonicalizeRelativePath: { _ in "javascript:alert(1)" }
            )
        )
    }
}
