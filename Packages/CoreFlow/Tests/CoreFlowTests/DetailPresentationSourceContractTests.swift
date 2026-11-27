import Foundation
import XCTest

final class DetailPresentationSourceContractTests: XCTestCase {
    func testReaderKeepsFullAuthoredDocumentAndGradeWithoutAnEnclosingCard() throws {
        let source = try detailSource()
        let body = try section(source, from: "private var readerCard: some View", to: "private var readerAuthorRow: some View")
        XCTAssertTrue(body.contains("ChoraiReadingIdentity(rate: cardDetail.rate)"))
        XCTAssertTrue(body.contains("readerAuthorRow"))
        XCTAssertTrue(body.contains("NoteReaderDocument(card: cardDetail)"))
        let reader = try String(contentsOf: rootURL().appendingPathComponent("ArcNote/HTMLWebView.swift"), encoding: .utf8)
        XCTAssertTrue(reader.contains("if auth.cardReadSession == nil"))
        XCTAssertTrue(reader.contains("guard auth.cardReadSession != nil else"))
        XCTAssertFalse(body.contains("AdaptiveHTMLWebView(htmlContent: cardDetail.content"),
                       "A text summary cannot replace the authored structured document")
        XCTAssertFalse(body.contains(".choraiCardLevel"), "Full reading must not be boxed in a grade card")
        XCTAssertFalse(body.contains("cardDetail.title"), "Only authored heading blocks determine document headings")
        XCTAssertFalse(body.contains(".padding(22)"), "The document uses page margins, not another nested content inset")
        XCTAssertFalse(source.contains("DragGesture()"), "System back navigation must not intercept reading gestures")
    }

    func testQuietAuthorRowPreservesProfileFollowAndConversationActions() throws {
        let source = try detailSource()
        let row = try section(source, from: "private var readerAuthorRow: some View", to: "private var readerAuthorAvatar: some View")
        for action in ["navigateToUserProfile = true", "createConversation", "toggleFollow"] {
            XCTAssertTrue(row.contains(action), "The visual correction must preserve \(action)")
        }
        for identifier in ["detail.author", "detail.author.chat", "detail.author.follow"] {
            XCTAssertTrue(row.contains(identifier))
        }
        XCTAssertTrue(row.contains(".frame(minHeight: 44)"))
        XCTAssertFalse(row.contains(".frame(width: 44, height: 44)"),
                       "Reader actions must be able to grow with accessibility text")
        XCTAssertTrue(row.contains(".frame(minWidth: 44, minHeight: 44)"))
        XCTAssertTrue(row.contains(".disabled(isFollowLoading"))
        XCTAssertFalse(row.contains(".choraiGlassSurface"), "Author actions stay quiet inside the reading surface")
        XCTAssertFalse(source.contains("Image(\"avatar\")"), "Missing author photos must not impersonate an account with an unrelated stock avatar")
        XCTAssertTrue(source.contains("Text(readerAuthorInitials)"))
        XCTAssertTrue(source.contains("APIConfiguration.resourceURLString(rawURL)"))
    }

    func testTabBarVisibilityBelongsToTheCompleteReaderDestination() throws {
        let source = try detailSource()
        let body = try section(source, from: "var body: some View", to: "private var readerCard: some View")
        let hide = try XCTUnwrap(body.range(of: ".toolbar(.hidden, for: .tabBar)"))
        let lastRoute = try XCTUnwrap(body.range(of: ".navigationDestination(isPresented: $navigateToRelatedDetail)"))
        let popup = try XCTUnwrap(body.range(of: ".popupMenu("))
        XCTAssertGreaterThan(hide.lowerBound, popup.lowerBound)
        XCTAssertGreaterThan(hide.lowerBound, lastRoute.lowerBound, "The full destination must own tab visibility after its nested route modifiers")
        XCTAssertFalse(body.contains("UITabBar.appearance"), "A reader must not change every tab bar globally")
    }

    private func rootURL() -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root
    }

    private func detailSource() throws -> String {
        try String(contentsOf: rootURL().appendingPathComponent("ArcNote/DetailView.swift"), encoding: .utf8)
    }

    private func section(_ source: String, from start: String, to end: String) throws -> String {
        let lower = try XCTUnwrap(source.range(of: start))
        let upper = try XCTUnwrap(source.range(of: end, range: lower.upperBound..<source.endIndex))
        return String(source[lower.lowerBound..<upper.lowerBound])
    }
}
