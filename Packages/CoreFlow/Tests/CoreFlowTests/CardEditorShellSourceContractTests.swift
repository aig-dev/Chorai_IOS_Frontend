import Foundation
import XCTest

final class CardEditorShellSourceContractTests: XCTestCase {
    private let cardEditorFiles = [
        "BlockNoteCardEditor.swift",
        "CardEditorShell.swift",
        "CardEditorMetadataRows.swift",
        "CardEditorFormattingBar.swift",
        "CardEditorBackground.swift",
    ]

    func testAppTargetOwnsTheFiveFocusedCardEditorFiles() throws {
        let project = try source(at: "ArcNote.xcodeproj/project.pbxproj")

        for filename in cardEditorFiles {
            let fileURL = Self.repositoryRoot
                .appendingPathComponent("ArcNote/CardEditor")
                .appendingPathComponent(filename)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: fileURL.path),
                "Missing CardEditor source file: \(filename)"
            )
            XCTAssertTrue(
                project.contains("/* \(filename) in Sources */"),
                "\(filename) must belong to the ArcNote Sources build phase"
            )
        }
    }

    func testShellUsesStableBodyTagLinkHierarchyWithoutHeaderOrLazyStack() throws {
        let shell = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")

        XCTAssertTrue(shell.contains("VStack(alignment: .leading, spacing: 14)"))
        XCTAssertFalse(
            shell.contains("LazyVStack"),
            "The embedded WebView must not be recycled by a lazy stack"
        )
        XCTAssertFalse(shell.contains("cardEditorHeader"))
        XCTAssertFalse(shell.contains("cardEditorTitleField"))

        let body = try XCTUnwrap(shell.range(of: "CardEditorBackground("))
        let tags = try XCTUnwrap(shell.range(of: "CardEditorTagRow("))
        let links = try XCTUnwrap(shell.range(of: "CardEditorLinkRow("))
        XCTAssertLessThan(body.lowerBound, tags.lowerBound)
        XCTAssertLessThan(tags.lowerBound, links.lowerBound)
        XCTAssertTrue(shell.contains("cardEditorFloatingBack"))
        XCTAssertTrue(shell.contains("cardEditorMoreButton"))
        XCTAssertTrue(
            shell.contains("onOpenCardActions: (() -> Void)? = nil")
        )
        XCTAssertTrue(shell.contains("if let onOpenCardActions"))
        XCTAssertTrue(shell.contains("Label(\"Card Actions\""))
        XCTAssertTrue(shell.contains("cardEditorCardActionsButton"))
    }

    func testBodyAdapterKeepsNativeAndNetworkStateOutsideBridge() throws {
        let adapter = try source(
            at: "ArcNote/CardEditor/BlockNoteCardEditor.swift"
        )

        XCTAssertTrue(adapter.contains("import BlockNoteEditor"))
        XCTAssertFalse(adapter.contains("import CoreFlow"))
        for forbidden in [
            "NetworkManager",
            "URLSession",
            "authToken",
            "cardID",
            "backgroundMediaRef",
            "apiURL",
            "uploadBytes",
        ] {
            XCTAssertFalse(
                adapter.contains(forbidden),
                "The body-only adapter must not bridge native state: \(forbidden)"
            )
        }

        XCTAssertTrue(adapter.contains("compatibilityBlocked"))
        XCTAssertTrue(adapter.contains("guard canMutate else"))
        XCTAssertTrue(adapter.contains("guard canSave else"))
        XCTAssertTrue(adapter.contains("cardEditorCompatibilityNotice"))
    }

    func testCompatibilityBlockKeepsFallbackAndFocusTracksWebBody() throws {
        let adapter = try source(
            at: "ArcNote/CardEditor/BlockNoteCardEditor.swift"
        )

        XCTAssertTrue(adapter.contains("Text(model.fallbackMarkdown)"))
        XCTAssertTrue(adapter.contains("cardEditorReadOnlyFallback"))
        XCTAssertTrue(adapter.contains("case let .bodyFocusChanged(isFocused)"))
        XCTAssertFalse(adapter.contains("keyboardWillShowNotification"))
        XCTAssertTrue(adapter.contains("keyboardWillHideNotification"))
        XCTAssertTrue(adapter.contains("func keyboardDidHide()"))
        XCTAssertTrue(adapter.contains("guard isBodyFocused else"))

        let focusBody = try XCTUnwrap(adapter.range(of: "func focusBody()"))
        let keyboardDidHide = try XCTUnwrap(
            adapter.range(of: "func keyboardDidHide()")
        )
        let dismissKeyboard = try XCTUnwrap(
            adapter.range(of: "func dismissKeyboard()")
        )
        let focusImplementation = adapter[
            focusBody.lowerBound..<keyboardDidHide.lowerBound
        ]
        let keyboardHideImplementation = adapter[
            keyboardDidHide.lowerBound..<dismissKeyboard.lowerBound
        ]
        XCTAssertFalse(
            focusImplementation.contains("isBodyFocused = true"),
            "A tap request alone must not claim keyboard focus"
        )
        XCTAssertTrue(keyboardHideImplementation.contains("controller.blur()"))
    }

    func testMetadataRowsKeepActionsTrailingAndLinksCompact() throws {
        let metadata = try source(
            at: "ArcNote/CardEditor/CardEditorMetadataRows.swift"
        )

        let tagChip = try XCTUnwrap(metadata.range(of: "ForEach(tags"))
        let addTag = try XCTUnwrap(metadata.range(of: "cardEditorAddTag"))
        XCTAssertLessThan(tagChip.lowerBound, addTag.lowerBound)

        XCTAssertTrue(metadata.contains("Array(links.prefix(2))"))
        XCTAssertTrue(metadata.contains("links.count - 2"))
        let linkPrefix = try XCTUnwrap(metadata.range(of: "Array(links.prefix(2))"))
        let addLink = try XCTUnwrap(metadata.range(of: "cardEditorAddLink"))
        XCTAssertLessThan(linkPrefix.lowerBound, addLink.lowerBound)
        XCTAssertTrue(metadata.contains("let canRemove: Bool"))
        XCTAssertTrue(metadata.contains("if link.canRemove && isEditable"))
        XCTAssertTrue(metadata.contains(".disabled(!isEditable)"))
        XCTAssertTrue(metadata.contains("cardEditorRemoveLink."))
        XCTAssertTrue(
            metadata.contains(
                "ProposedViewSize(width: availableWidth, height: nil)"
            ),
            "Flow children must receive the row width so long chips can compress"
        )
    }

    func testFormattingDismissIsFixedAndTypedCommandsScrollHorizontally() throws {
        let formatting = try source(
            at: "ArcNote/CardEditor/CardEditorFormattingBar.swift"
        )

        let dismiss = try XCTUnwrap(
            formatting.range(of: "cardEditorKeyboardDismiss")
        )
        let commandScroll = try XCTUnwrap(
            formatting.range(of: "ScrollView(.horizontal")
        )
        XCTAssertLessThan(dismiss.lowerBound, commandScroll.lowerBound)
        XCTAssertTrue(formatting.contains("enum CardEditorFormattingCommand"))
        XCTAssertTrue(formatting.contains("isSelected"))
        XCTAssertTrue(formatting.contains("frame(minWidth: 45, minHeight: 44)"))
        let shell = try source(
            at: "ArcNote/CardEditor/CardEditorShell.swift"
        )
        XCTAssertTrue(shell.contains("DragGesture(minimumDistance: 12)"))
        XCTAssertTrue(shell.contains("vertical >= 24"))
        XCTAssertTrue(shell.contains("vertical > horizontal"))
        XCTAssertTrue(shell.contains("bodyModel.dismissKeyboard()"))
        XCTAssertTrue(shell.contains("saveActionTitle: String = \"Save\""))
        XCTAssertTrue(
            shell.contains("Text(isSaving ? \"Saving\" : saveActionTitle)")
        )
    }

    func testBackgroundSupportsLocalAndRemoteImagesInsideBodySurface() throws {
        let background = try source(
            at: "ArcNote/CardEditor/CardEditorBackground.swift"
        )

        XCTAssertTrue(background.contains("case local(Data)"))
        XCTAssertTrue(background.contains("case remote(URL)"))
        XCTAssertTrue(background.contains("cardEditorBodyBackground"))
        XCTAssertTrue(background.contains("cardEditorBodyBackgroundVeil"))
        XCTAssertTrue(background.contains("cardEditorPendingBackgroundImage"))
        XCTAssertTrue(background.contains("cardEditorBackgroundImage"))
        XCTAssertTrue(
            background.contains(".background {"),
            "The image must decorate the body instead of determining its ideal size"
        )
        XCTAssertTrue(background.contains(".clipped()"))
    }

    func testDebugAppRouteExposesDeterministicCardEditorFixture() throws {
        let app = try source(at: "ArcNote/ArcNoteApp.swift")
        let fixture = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")

        XCTAssertTrue(app.contains("--ui-test-card-editor-shell"))
        XCTAssertTrue(app.contains("CardEditorShellFixtureScreen"))
        XCTAssertTrue(fixture.contains("CHORAI_CARD_EDITOR_FIXTURE_MODE"))
        XCTAssertTrue(fixture.contains("cardEditorBackgroundButton"))
        XCTAssertTrue(fixture.contains("cardEditorCardActionsRequested"))
        XCTAssertTrue(
            fixture.contains(
                "onOpenCardActions: { didRequestCardActions = true }"
            )
        )
        XCTAssertTrue(fixture.contains("isMetadataEditable: bodyModel.canMutate"))
        XCTAssertTrue(fixture.contains("case longTag = \"long-tag\""))
        XCTAssertTrue(fixture.contains(#""backgroundColor":"default""#))
        XCTAssertTrue(fixture.contains(#""textAlignment":"left""#))
        XCTAssertTrue(fixture.contains("let inlineContentJSON = text.isEmpty"))
        XCTAssertTrue(
            fixture.contains("? \"[]\""),
            "An empty paragraph must not contain an invalid empty text run"
        )
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
