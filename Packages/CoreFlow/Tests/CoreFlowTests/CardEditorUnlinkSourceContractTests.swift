import Foundation
import XCTest

final class CardEditorUnlinkSourceContractTests: XCTestCase {
    func testLinkItemCarriesDirectedIdentityAndDefaultsToFailClosed() throws {
        let metadata = try source(
            at: "ArcNote/CardEditor/CardEditorMetadataRows.swift"
        )
        let item = try body(
            in: metadata,
            after: "struct CardEditorLinkItem: Identifiable, Equatable"
        )

        XCTAssertTrue(item.contains("let sourceCardID: String"))
        XCTAssertTrue(item.contains("let targetCardID: String"))
        XCTAssertTrue(item.contains("let canRemove: Bool"))
        XCTAssertTrue(item.contains("canRemove: Bool = false"))
        XCTAssertTrue(
            item.contains(#"self.id = "\(sourceCardID)->\(targetCardID)""#)
        )
    }

    func testLinkRowNestsIndependentUnlinkActionInsideCapability() throws {
        let metadata = try source(
            at: "ArcNote/CardEditor/CardEditorMetadataRows.swift"
        )
        let row = try body(in: metadata, after: "struct CardEditorLinkRow: View")
        let removable = try body(in: String(row), after: "if link.canRemove")
        let progress = try body(
            in: String(removable),
            after: "if unlinkingLinkID == link.id"
        )

        XCTAssertTrue(row.contains("let isRemovalEnabled: Bool"))
        XCTAssertTrue(row.contains("let onRemove: (CardEditorLinkItem) -> Void"))
        XCTAssertTrue(row.contains("CardMetadataRelatedRow("))
        XCTAssertEqual(
            occurrenceCount(".accessibilityElement(children: .combine)", in: row),
            1,
            "Only relation content should combine its accessibility children"
        )
        XCTAssertFalse(
            removable.contains(".accessibilityElement(children: .combine)"),
            "The unlink control must remain independent from relation content"
        )
        XCTAssertTrue(removable.contains("Button {"))
        XCTAssertTrue(removable.contains("onRemove(link)"))
        XCTAssertTrue(removable.contains("Image(systemName: \"xmark\")"))
        XCTAssertTrue(removable.contains(".frame(width: 44, height: 44)"))
        XCTAssertTrue(removable.contains(".disabled(!isRemovalEnabled)"))
        XCTAssertTrue(
            removable.contains(#".accessibilityLabel("Unlink \(link.title)")"#)
        )
        XCTAssertTrue(
            removable.contains(
                ".accessibilityHint(\"Removes this link without deleting either note\")"
            )
        )
        XCTAssertEqual(
            occurrenceCount("cardEditorRemoveLink.", in: row),
            occurrenceCount("cardEditorRemoveLink.", in: removable),
            "Removal identifiers must exist only inside if link.canRemove"
        )
        XCTAssertEqual(
            occurrenceCount("onRemove(link)", in: row),
            occurrenceCount("onRemove(link)", in: removable),
            "The removal callback must exist only inside if link.canRemove"
        )
        XCTAssertEqual(
            occurrenceCount("Image(systemName: \"xmark\")", in: row),
            occurrenceCount("Image(systemName: \"xmark\")", in: removable),
            "The xmark must exist only inside if link.canRemove"
        )
        XCTAssertTrue(progress.contains("ProgressView()"))
        XCTAssertTrue(progress.contains(".frame(width: 44, height: 44)"))
        XCTAssertFalse(row.contains("confirmationDialog"))
        XCTAssertFalse(row.contains("CardEditorLinkManagementSheet"))
    }

    func testShellForwardsExplicitRemovalCapabilityAndIndependentChildren() throws {
        let shellSource = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")
        let shell = try body(in: shellSource, after: "struct CardEditorShell: View")

        XCTAssertTrue(shell.contains("let isLinkRemovalEnabled: Bool"))
        XCTAssertTrue(shell.contains("let onRemoveLink: (CardEditorLinkItem) -> Void"))
        XCTAssertTrue(shell.contains("isLinkRemovalEnabled: Bool"))
        XCTAssertTrue(
            shell.contains("onRemoveLink: @escaping (CardEditorLinkItem) -> Void")
        )
        XCTAssertTrue(shell.contains("self.isLinkRemovalEnabled = isLinkRemovalEnabled"))
        XCTAssertTrue(shell.contains("self.onRemoveLink = onRemoveLink"))
        XCTAssertTrue(shell.contains("isRemovalEnabled: isMetadataEditable"))
        XCTAssertTrue(shell.contains("&& isLinkRemovalEnabled"))
        XCTAssertTrue(shell.contains("onRemove: onRemoveLink"))
        XCTAssertTrue(shell.contains(".accessibilityElement(children: .contain)"))
        XCTAssertFalse(shell.contains("CardEditorLinkManagementSheet"))
    }

    func testSessionDeduplicatesEdgesAndDeletesOnlyCanonicalOutgoingEdge() throws {
        let sessionSource = try source(at: "ArcNote/NewNoteView.swift")
        let session = try body(
            in: sessionSource,
            after: "private struct CardEditorSessionView: View"
        )
        let items = try body(
            in: String(session),
            after: "private var editorLinkItems: [CardEditorLinkItem]"
        )
        let remove = try body(
            in: String(session),
            after: "private func removeOntologyLink(_ item: CardEditorLinkItem)"
        )
        let shellCall = try arguments(
            in: String(session),
            after: "CardEditorShell"
        )

        XCTAssertTrue(
            containsInOrder(
                [
                    "isLinkRemovalEnabled: bodyModel.canMutate",
                    "&& !isBusy",
                    "&& unlinkingLinkID == nil",
                    "onRemoveLink: removeOntologyLink",
                ],
                in: shellCall
            )
        )

        XCTAssertTrue(items.contains("var seenEdges = Set<CardEditorLinkEdge>()"))
        XCTAssertTrue(items.contains("editingStore.links.compactMap"))
        XCTAssertTrue(items.contains("let edge = CardEditorLinkEdge("))
        XCTAssertTrue(items.contains("guard seenEdges.insert(edge).inserted else"))
        XCTAssertTrue(items.contains("sourceCardID: link.sourceCardID"))
        XCTAssertTrue(items.contains("targetCardID: link.targetCardID"))
        XCTAssertTrue(items.contains("canRemove: link.sourceCardID == cardID"))

        XCTAssertTrue(remove.contains("guard bodyModel.canMutate,"))
        XCTAssertTrue(remove.contains("!isBusy,"))
        XCTAssertTrue(remove.contains("item.canRemove,"))
        XCTAssertTrue(remove.contains("unlinkingLinkID == nil,"))
        XCTAssertTrue(remove.contains("let cardID = editingStore.cardID,"))
        XCTAssertTrue(remove.contains("cardID == item.sourceCardID,"))
        XCTAssertTrue(
            remove.contains("let link = editingStore.links.first(where: {")
        )
        XCTAssertTrue(remove.contains("$0.sourceCardID == item.sourceCardID"))
        XCTAssertTrue(remove.contains("$0.targetCardID == item.targetCardID"))
        XCTAssertTrue(
            remove.contains("let didDelete = await editingStore.deleteLink(link)")
        )
        XCTAssertTrue(remove.contains("saveMessage = \"Couldn't unlink. Try again.\""))
        XCTAssertFalse(remove.contains("links.remove"))
    }

    func testFixturesIncludeOutgoingActionsIncomingStaticRowAndFailClosedBlockedRow() throws {
        let shellSource = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")
        let fixtures = try body(
            in: shellSource,
            after: "var fixtureLinks: [CardEditorLinkItem]"
        )

        XCTAssertTrue(
            containsInOrder(
                [
                    "sourceCardID: \"ast_blocked\"",
                    "targetCardID: \"ast_blocked_target\"",
                    "title: \"Preserved relation\"",
                ],
                in: fixtures
            )
        )
        XCTAssertTrue(
            containsInOrder(
                [
                    "sourceCardID: \"ast_fixture_source\"",
                    "targetCardID: \"ast_fixture_a\"",
                    "title: \"Ada\"",
                    "canRemove: true",
                ],
                in: fixtures
            )
        )
        XCTAssertTrue(
            containsInOrder(
                [
                    "sourceCardID: \"ast_fixture_c\"",
                    "targetCardID: \"ast_fixture_source\"",
                    "title: \"Chen\"",
                    "canRemove: false",
                ],
                in: fixtures
            )
        )

        let blockedStart = try XCTUnwrap(fixtures.range(of: "if self == .blocked"))
        let populatedStart = try XCTUnwrap(
            fixtures.range(of: "guard self == .populated")
        )
        let blocked = fixtures[blockedStart.lowerBound..<populatedStart.lowerBound]
        XCTAssertFalse(blocked.contains("canRemove: true"))
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func body(in source: String, after marker: String) throws -> Substring {
        try enclosed(
            in: source,
            after: marker,
            opening: "{",
            closing: "}"
        )
    }

    private func arguments(
        in source: String,
        after marker: String
    ) throws -> Substring {
        try enclosed(
            in: source,
            after: marker,
            opening: "(",
            closing: ")"
        )
    }

    private func enclosed(
        in source: String,
        after marker: String,
        opening: Character,
        closing: Character
    ) throws -> Substring {
        let markerRange = try XCTUnwrap(source.range(of: marker))
        let openingIndex = try XCTUnwrap(
            source[markerRange.upperBound...].firstIndex(of: opening)
        )
        var index = source.index(after: openingIndex)
        var depth = 1
        var isInString = false
        var isEscaped = false

        while index < source.endIndex {
            let character = source[index]
            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
            } else if character == "\"" {
                isInString = true
            } else if character == opening {
                depth += 1
            } else if character == closing {
                depth -= 1
                if depth == 0 {
                    return source[source.index(after: openingIndex)..<index]
                }
            }
            index = source.index(after: index)
        }

        XCTFail("Unbalanced declaration after marker: \(marker)")
        return ""
    }

    private func occurrenceCount(
        _ needle: String,
        in source: some StringProtocol
    ) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    private func containsInOrder(
        _ markers: [String],
        in source: some StringProtocol
    ) -> Bool {
        let source = String(source)
        var lowerBound = source.startIndex
        for marker in markers {
            guard let range = source.range(
                of: marker,
                range: lowerBound..<source.endIndex
            ) else {
                return false
            }
            lowerBound = range.upperBound
        }
        return true
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
