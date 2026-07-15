import Foundation
import XCTest

final class LinkPopupSelectionSourceContractTests: XCTestCase {
    func testSelectionOnlyReturnsTheCandidateBeforeAnyLinkMutation() throws {
        let source = try Self.linkPopupSource()

        XCTAssertTrue(
            source.contains("case selectionOnly"),
            "The picker needs an explicit selection-only presentation mode"
        )
        XCTAssertTrue(
            source.contains(
                "mode: LinkPopupPresentationMode = .createLink"
            ),
            "Existing callers must retain link-creation behavior by default"
        )

        let selectionBranch = try XCTUnwrap(
            Self.selectionOnlyBranch(in: source)
        )
        XCTAssertTrue(selectionBranch.contains("onCardSelected?(linkItem)"))
        XCTAssertTrue(selectionBranch.contains("hide()"))
        XCTAssertTrue(selectionBranch.contains("return"))
        XCTAssertFalse(selectionBranch.contains("NetworkManager"))
        XCTAssertFalse(selectionBranch.contains("NotificationCenter"))

        let linkAction = try XCTUnwrap(Self.linkCardBody(in: source))
        let selection = try XCTUnwrap(
            linkAction.range(of: "presentationMode == .selectionOnly")
        )
        let authentication = try XCTUnwrap(
            linkAction.range(of: "AuthManager.shared.currentUser")
        )
        let mutation = try XCTUnwrap(
            linkAction.range(of: "NetworkManager.shared.createCardLink")
        )
        XCTAssertLessThan(selection.lowerBound, authentication.lowerBound)
        XCTAssertLessThan(selection.lowerBound, mutation.lowerBound)
    }

    func testCancelDismissesWithoutReturningOrMutatingACard() throws {
        let source = try Self.linkPopupSource()
        let hideAction = try XCTUnwrap(Self.hideBody(in: source))

        XCTAssertFalse(hideAction.contains("onCardSelected"))
        XCTAssertFalse(hideAction.contains("createCardLink"))
        XCTAssertFalse(hideAction.contains("NotificationCenter"))

        XCTAssertTrue(
            source.contains(
                "Button(\"Cancel\") {\n"
                    + "                                isTextFieldFocused = false\n"
                    + "                                manager.hide()"
            ),
            "Cancel must only dismiss the picker"
        )
    }

    func testDefaultModeReturnsOnlyAfterCanonicalLinkSuccess() throws {
        let source = try Self.linkPopupSource()
        let canonicalBranch = try XCTUnwrap(
            Self.canonicalLinkBranch(in: source)
        )

        let mutation = try XCTUnwrap(
            canonicalBranch.range(of: "NetworkManager.shared.createCardLink")
        )
        let success = try XCTUnwrap(
            canonicalBranch.range(of: "if response.success")
        )
        let callback = try XCTUnwrap(
            canonicalBranch.range(of: "self.onCardSelected?(linkItem)")
        )
        XCTAssertLessThan(mutation.lowerBound, success.lowerBound)
        XCTAssertLessThan(success.lowerBound, callback.lowerBound)

        let transportFailure = try XCTUnwrap(
            Self.slice(
                canonicalBranch,
                from: "if case .failure(let error) = completion",
                through: "receiveValue:"
            )
        )
        XCTAssertFalse(transportFailure.contains("onCardSelected"))

        let rejectedResponse = try XCTUnwrap(
            Self.slice(
                canonicalBranch,
                from: "} else {\n                            print(\"失败:",
                through: ".store(in: &cancellables)"
            )
        )
        XCTAssertFalse(rejectedResponse.contains("onCardSelected"))
    }

    private static func linkPopupSource() throws -> String {
        try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("ArcNote/LinkPopupView.swift"),
            encoding: .utf8
        )
    }

    private static func linkCardBody(in source: String) -> Substring? {
        guard let start = source.range(
            of: "func linkCard(linkItem: LinkItem)"
        ) else {
            return nil
        }
        let remainder = source[start.lowerBound...]
        guard let end = remainder.range(of: "// 搜索卡片") else {
            return nil
        }
        return source[start.lowerBound..<end.lowerBound]
    }

    private static func selectionOnlyBranch(in source: String) -> Substring? {
        guard let action = linkCardBody(in: source),
              let start = action.range(
                  of: "if presentationMode == .selectionOnly {"
              ) else {
            return nil
        }
        let remainder = action[start.lowerBound...]
        guard let end = remainder.range(of: "\n        }") else {
            return nil
        }
        return remainder[..<end.upperBound]
    }

    private static func hideBody(in source: String) -> Substring? {
        guard let start = source.range(of: "func hide()") else {
            return nil
        }
        let remainder = source[start.lowerBound...]
        guard let end = remainder.range(of: "// MARK: - Link ") else {
            return nil
        }
        return source[start.lowerBound..<end.lowerBound]
    }

    private static func canonicalLinkBranch(
        in source: String
    ) -> Substring? {
        guard let action = linkCardBody(in: source),
              let start = action.range(of: "if let cardId = currentCardId {")
        else {
            return nil
        }
        let remainder = action[start.lowerBound...]
        guard let end = remainder.range(
            of: "} else {\n            print(\"选择卡片:"
        ) else {
            return nil
        }
        return remainder[..<end.lowerBound]
    }

    private static func slice(
        _ source: Substring,
        from startMarker: String,
        through endMarker: String
    ) -> Substring? {
        guard let start = source.range(of: startMarker) else {
            return nil
        }
        let remainder = source[start.lowerBound...]
        guard let end = remainder.range(of: endMarker) else {
            return nil
        }
        return remainder[..<end.upperBound]
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
