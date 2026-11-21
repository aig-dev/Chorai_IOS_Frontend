import Foundation
import XCTest

final class CardEditorShellSourceContractTests: XCTestCase {
    private let cardEditorFiles = [
        "BlockNoteCardEditor.swift",
        "CardEditorShell.swift",
        "CardEditorMetadataRows.swift",
        "CardMetadataPresentation.swift",
        "CardEditorFormattingBar.swift",
        "CardEditorBackground.swift",
        "CardEditorBackgroundActions.swift",
        "CardEditorInlineImageSource.swift",
        "CardEditorGlassSurface.swift",
        "CardEditorAmbientBackdrop.swift",
    ]

    func testSharedActionBoxOwnsMainstreamSurfaceAndSemanticTiles() throws {
        let project = try source(at: "ArcNote.xcodeproj/project.pbxproj")
        let actionBox = try source(at: "ArcNote/ActionBoxView.swift")
        let popup = try source(at: "ArcNote/PopupMenuView.swift")

        XCTAssertTrue(project.contains("/* ActionBoxView.swift in Sources */"))
        XCTAssertTrue(actionBox.contains("struct ActionBoxOverlay<Content: View>: View"))
        XCTAssertTrue(actionBox.contains("static let surfaceScale: CGFloat = 0.9"))
        XCTAssertTrue(actionBox.contains("let availableHeight = max("))
        XCTAssertTrue(actionBox.contains("let surfaceSide = min("))
        XCTAssertTrue(actionBox.contains("geometry.safeAreaInsets.top"))
        XCTAssertTrue(actionBox.contains("geometry.safeAreaInsets.bottom"))
        XCTAssertTrue(actionBox.contains("RoundedRectangle(cornerRadius: 20)"))
        XCTAssertTrue(actionBox.contains(".choraiGlassSurface(cornerRadius: 24)"))
        XCTAssertTrue(actionBox.contains(".spring(response: 0.3, dampingFraction: 0.8)"))
        XCTAssertTrue(actionBox.contains("let rowCount: Int"))
        XCTAssertTrue(
            actionBox.contains("static let standardTileSize: CGFloat = 90")
        )
        XCTAssertTrue(
            actionBox.contains(
                "static let contentBottomPadding: CGFloat = 16"
            )
        )
        XCTAssertFalse(actionBox.contains("headerHeight"))
        XCTAssertFalse(actionBox.contains("reservesCloseHeader"))
        XCTAssertTrue(actionBox.contains("static func tileSize("))
        XCTAssertTrue(
            actionBox.contains(".environment(\\.actionBoxTileSize, tileSize)")
        )
        XCTAssertTrue(
            actionBox.contains(
                ".accessibilityIdentifier(\"\\(accessibilityIdentifier).surface\")"
            )
        )
        XCTAssertTrue(actionBox.contains("struct ActionBoxTile: View"))
        XCTAssertTrue(actionBox.contains("Button(role: role, action: action)"))
        XCTAssertEqual(
            actionBox.components(
                separatedBy: ".frame(width: tileSize, height: tileSize)"
            ).count - 1,
            1,
            "Only semantic action tiles should consume grid positions"
        )
        XCTAssertFalse(actionBox.contains("struct ActionBoxEmptyTile"))
        XCTAssertTrue(actionBox.contains(".frame(width: 38, height: 33)"))
        XCTAssertTrue(actionBox.contains(".font(.system(size: min(scaledLabelSize, 18), weight: .medium))"))
        XCTAssertTrue(actionBox.contains(".minimumScaleFactor(0.65)"))
        XCTAssertTrue(actionBox.contains(".allowsTightening(true)"))
        XCTAssertTrue(actionBox.contains("RoundedRectangle(cornerRadius: 12)"))
        XCTAssertTrue(actionBox.contains("@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertTrue(actionBox.contains(".accessibilityAddTraits(.isModal)"))
        XCTAssertTrue(actionBox.contains(".accessibilityAction(.escape)"))
        XCTAssertFalse(actionBox.contains("closeAccessibilityIdentifier"))
        XCTAssertFalse(actionBox.contains("private var closeButton"))
        XCTAssertTrue(
            actionBox.contains(".ignoresSafeArea(.keyboard, edges: .bottom)")
        )
        XCTAssertTrue(
            actionBox.contains("#selector(UIResponder.resignFirstResponder)")
        )
        XCTAssertTrue(
            actionBox.contains(
                "UIAccessibility.post(notification: .screenChanged, argument: nil)"
            )
        )
        XCTAssertTrue(popup.contains("ActionBoxOverlay("))
        XCTAssertTrue(popup.contains("rowCount: layout.rowCount"))
        XCTAssertTrue(popup.contains("ActionBoxTile("))
        XCTAssertFalse(popup.contains(".accessibilityHidden(isPresented)"))
        XCTAssertFalse(popup.contains(".onTapGesture"))
    }

    func testEditorActionBoxFillsRowsFromTheLeadingEdge() throws {
        let editorActionBox = try source(
            at: "ArcNote/CardEditor/CardEditorActionBox.swift"
        )

        XCTAssertTrue(
            editorActionBox.contains(
                "VStack(alignment: .leading, spacing: 15)"
            )
        )
        XCTAssertFalse(editorActionBox.contains("ActionBoxEmptyTile"))
    }

    func testBackgroundActionsUseNativeContextualDialog() throws {
        let actions = try source(
            at: "ArcNote/CardEditor/CardEditorBackgroundActions.swift"
        )
        let project = try source(at: "ArcNote.xcodeproj/project.pbxproj")

        XCTAssertTrue(actions.contains("enum CardEditorBackgroundActionContext"))
        XCTAssertTrue(actions.contains("case visible(canRestoreOriginal: Bool)"))
        XCTAssertTrue(actions.contains("case removed(canRestoreBackground: Bool)"))
        XCTAssertTrue(actions.contains("case choosePhoto"))
        XCTAssertTrue(actions.contains("case remove"))
        XCTAssertTrue(actions.contains("case restore"))
        XCTAssertTrue(actions.contains(".confirmationDialog("))
        XCTAssertTrue(actions.contains("cardEditorReplaceBackgroundButton"))
        XCTAssertTrue(actions.contains("cardEditorRemoveBackgroundButton"))
        XCTAssertTrue(actions.contains("cardEditorRestoreBackgroundButton"))
        XCTAssertTrue(actions.contains("if canRestoreBackground"))
        XCTAssertTrue(
            project.contains("/* CardEditorBackgroundActions.swift in Sources */")
        )
    }

    func testAppTargetOwnsFocusedCardEditorFiles() throws {
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

        let presentationURL = Self.repositoryRoot.appendingPathComponent(
            "ArcNote/CardEditor/CardMetadataPresentation.swift"
        )
        guard FileManager.default.fileExists(atPath: presentationURL.path) else {
            return
        }
        let presentation = try source(
            at: "ArcNote/CardEditor/CardMetadataPresentation.swift"
        )
        XCTAssertTrue(presentation.contains("struct CardMetadataTagCapsule: View"))
        XCTAssertTrue(presentation.contains("let showsRemoveIndicator: Bool"))
        XCTAssertTrue(presentation.contains("let leadingSystemImage: String?"))
        XCTAssertTrue(presentation.contains("if let leadingSystemImage"))
        XCTAssertTrue(presentation.contains(".font(.caption.weight(.medium))"))
        XCTAssertFalse(
            presentation.contains(".font(.system(size: 12, weight: .medium))")
        )
        XCTAssertTrue(presentation.contains(".foregroundStyle(ChoraiTheme.ink)"))
        XCTAssertTrue(presentation.contains(".padding(.horizontal, 12)"))
        XCTAssertTrue(presentation.contains(".padding(.vertical, 6)"))
        XCTAssertTrue(
            presentation.contains(
                "cardMetadataMaximumReadableTagWidth: CGFloat = 280"
            )
        )
        XCTAssertTrue(presentation.contains(".truncationMode(.tail)"))
        XCTAssertTrue(
            presentation.contains(".frame(maxWidth: maximumWidth)")
        )
        XCTAssertTrue(
            presentation.contains(
                "ChoraiTheme.raisedSurface"
            )
        )
        XCTAssertFalse(presentation.contains(#"#\(tag)"#))
        XCTAssertFalse(presentation.contains(".stroke("))

        XCTAssertTrue(presentation.contains("struct CardMetadataRelatedRow: View"))
        XCTAssertTrue(presentation.contains("let avatarURL: String?"))
        XCTAssertTrue(presentation.contains("let previewHTML: String?"))
        XCTAssertTrue(presentation.contains(".frame(width: 40, height: 40)"))
        XCTAssertTrue(presentation.contains(".font(.callout.weight(.semibold))"))
        XCTAssertTrue(presentation.contains("font: .footnote"))
        XCTAssertTrue(
            presentation.contains(
                "foregroundColor: ChoraiTheme.secondaryInk"
            )
        )

        let htmlRenderer = try source(at: "ArcNote/HomeView.swift")
        XCTAssertTrue(htmlRenderer.contains("let font: Font"))
        XCTAssertTrue(htmlRenderer.contains("let foregroundColor: Color"))
        XCTAssertTrue(
            htmlRenderer.contains(
                "font: Font = .system(size: 17, weight: .regular)"
            )
        )
        XCTAssertTrue(
            htmlRenderer.contains(
                "foregroundColor: Color = ChoraiTheme.ink"
            )
        )
        XCTAssertTrue(htmlRenderer.contains(".font(font)"))
        XCTAssertTrue(
            htmlRenderer.contains(".foregroundColor(foregroundColor)")
        )

        let metadataRows = try source(
            at: "ArcNote/CardEditor/CardEditorMetadataRows.swift"
        )
        XCTAssertTrue(metadataRows.contains(".font(.caption.weight(.medium))"))
        XCTAssertFalse(
            metadataRows.contains(".font(.system(size: 12, weight: .medium))")
        )
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
        XCTAssertTrue(shell.contains("cardEditorLeadingAction"))
        XCTAssertTrue(shell.contains("cardEditorPrivacyButton"))
        XCTAssertTrue(shell.contains("cardEditorMoreButton"))
        XCTAssertTrue(
            shell.contains("onOpenCardActions: (() -> Void)? = nil")
        )
        XCTAssertFalse(shell.contains("cardEditorCardActionsButton"))
    }

    func testShellUsesOneSemanticLeadingControlWithoutInlineSave() throws {
        let shell = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")

        for state in [
            "case back",
            "case save",
            "case saving",
            "case retry",
            "case readOnly",
            "case bridgeFailed",
        ] {
            XCTAssertTrue(shell.contains(state), "Missing leading state: \(state)")
        }
        XCTAssertTrue(
            shell.contains(
                "let leadingControlState: CardEditorLeadingControlState"
            )
        )
        XCTAssertTrue(shell.contains("let onLeadingControl: () -> Void"))
        XCTAssertTrue(shell.contains("? \"checkmark\""))
        XCTAssertTrue(shell.contains("ProgressView()"))
        XCTAssertTrue(shell.contains("\"Close note\""))
        XCTAssertTrue(shell.contains("\"Save note\""))
        XCTAssertTrue(shell.contains("\"Retry saving note\""))
        XCTAssertTrue(
            shell.contains(
                ".accessibilityIdentifier(\"cardEditorLeadingAction\")"
            )
        )
        XCTAssertFalse(shell.contains("inlineSaveAction"))
        XCTAssertFalse(
            shell.contains(
                ".accessibilityIdentifier(\"cardEditorSave\")"
            )
        )
        XCTAssertFalse(shell.contains("cardEditorFloatingBack"))
        XCTAssertFalse(shell.contains("saveActionTitle"))
        XCTAssertFalse(shell.contains("let onSave:"))
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

    func testCardLinkBridgeEventUsesDedicatedNativeCallback() throws {
        let adapter = try source(
            at: "ArcNote/CardEditor/BlockNoteCardEditor.swift"
        )

        XCTAssertTrue(adapter.contains("private let onRequestCardLink: () -> Void"))
        XCTAssertTrue(
            adapter.contains("onRequestCardLink: @escaping () -> Void = {}")
        )
        XCTAssertTrue(adapter.contains("self.onRequestCardLink = onRequestCardLink"))

        let branchStart = try XCTUnwrap(
            adapter.range(of: "case .requestCardLink:")
        )
        let nextBranch = try XCTUnwrap(
            adapter[branchStart.upperBound...].range(of: "case ")
        )
        let branch = adapter[branchStart.lowerBound..<nextBranch.lowerBound]
        XCTAssertTrue(branch.contains("onRequestCardLink()"))
        XCTAssertFalse(
            branch.contains("onRequestInlineLink()"),
            "Card relations must not reuse the inline URL callback"
        )
    }

    func testPrematureCardLinkRequestDoesNotFailAppEditorSession() throws {
        let adapter = try source(
            at: "ArcNote/CardEditor/BlockNoteCardEditor.swift"
        )

        XCTAssertTrue(
            adapter.contains(
                #"case "read_only", "unexpected_card_link_request":"#
            )
        )
    }

    func testCompatibilityBlockKeepsFallbackAndFocusTracksWebBody() throws {
        let adapter = try source(
            at: "ArcNote/CardEditor/BlockNoteCardEditor.swift"
        )

        XCTAssertTrue(adapter.contains("Text(model.fallbackMarkdown)"))
        XCTAssertTrue(adapter.contains("cardEditorReadOnlyFallback"))
        XCTAssertTrue(adapter.contains("case let .bodyFocusChanged(isFocused)"))
        XCTAssertFalse(adapter.contains("keyboardWillShowNotification"))
        XCTAssertFalse(adapter.contains("keyboardWillHideNotification"),
                       "Software keyboard visibility must not override the focused WebKit body, including hardware keyboard transitions")
        XCTAssertFalse(adapter.contains("func keyboardDidHide()"))
        XCTAssertTrue(adapter.contains("isBodyFocused = canMutate && isFocused"),
                      "Observed focus belongs to the active editable bridge instance")

        let focusBody = try XCTUnwrap(adapter.range(of: "func focusBody()"))
        let dismissKeyboard = try XCTUnwrap(
            adapter.range(of: "func dismissKeyboard()")
        )
        let canPerform = try XCTUnwrap(adapter.range(of: "func canPerform("))
        let focusImplementation = adapter[
            focusBody.lowerBound..<dismissKeyboard.lowerBound
        ]
        let dismissImplementation = adapter[
            dismissKeyboard.lowerBound..<canPerform.lowerBound
        ]
        XCTAssertFalse(
            focusImplementation.contains("isBodyFocused = true"),
            "A tap request alone must not claim keyboard focus"
        )
        XCTAssertTrue(dismissImplementation.contains("isBodyFocused = false"))
        XCTAssertTrue(dismissImplementation.contains("controller.blur()"),
                      "Explicit menu and drag dismissal must still end the real editor focus")
    }

    func testMetadataRowsShareStylingAndKeepUnlinkInlineAndDirectional() throws {
        let metadata = try source(
            at: "ArcNote/CardEditor/CardEditorMetadataRows.swift"
        )
        let shell = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")

        XCTAssertTrue(metadata.contains("ScrollView(.horizontal, showsIndicators: false)"))
        let tagCapsule = try XCTUnwrap(
            metadata.range(of: "CardMetadataTagCapsule(")
        )
        let addTag = try XCTUnwrap(metadata.range(of: "cardEditorAddTag"))
        XCTAssertLessThan(tagCapsule.lowerBound, addTag.lowerBound)
        XCTAssertTrue(metadata.contains("showsRemoveIndicator: true"))
        let addTagBranch = try XCTUnwrap(metadata.range(of: "} else {"))
        let addTagImplementation = metadata[addTagBranch.lowerBound...]
        XCTAssertTrue(
            addTagImplementation.contains("leadingSystemImage: \"plus\"")
        )
        XCTAssertFalse(
            metadata.contains("ZenVisualTokens.accent.opacity(0.16)")
        )
        XCTAssertFalse(metadata.contains("Text(\"#"))
        XCTAssertGreaterThanOrEqual(
            metadata.components(separatedBy: ".frame(minWidth: 44, minHeight: 44)").count - 1,
            2,
            "Tag actions need compact visuals inside 44-point hit targets"
        )

        XCTAssertTrue(metadata.contains("if !links.isEmpty"))
        XCTAssertTrue(
            metadata.contains(
                "@Environment(\\.accessibilityReduceMotion) private var reduceMotion"
            )
        )
        XCTAssertTrue(
            metadata.contains(
                "withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3))"
            )
        )
        XCTAssertTrue(metadata.contains("CardMetadataRelatedRow("))
        XCTAssertTrue(
            metadata.contains(".accessibilityElement(children: .combine)")
        )
        XCTAssertTrue(
            metadata.contains(
                "\"cardEditorLink.\\(accessibilityComponent(link.id))\""
            )
        )
        XCTAssertTrue(metadata.contains("cardEditorLinksDisclosure"))
        XCTAssertTrue(
            metadata.contains(
                ".accessibilityValue(isExpanded ? \"Expanded\" : \"Collapsed\")"
            )
        )
        XCTAssertTrue(metadata.contains(".frame(width: 44, height: 44)"))
        XCTAssertTrue(metadata.contains("ChoraiTheme.ink.opacity(0.1)"))
        XCTAssertTrue(metadata.contains("if link.canRemove"))
        XCTAssertTrue(metadata.contains("onRemove(link)"))
        XCTAssertTrue(metadata.contains("cardEditorRemoveLink."))
        XCTAssertTrue(metadata.contains(".disabled(!isRemovalEnabled)"))
        for staleContract in [
            "cardEditorAddLink",
            "cardEditorLinkOverflow",
            "CardEditorLinkManagementSheet",
            "Button(action: onOpen)",
        ] {
            XCTAssertFalse(
                metadata.contains(staleContract),
                "Editor link metadata must stay inline: \(staleContract)"
            )
        }
        for staleShellContract in [
            "onAddLink",
            "isManagingLinks",
            "CardEditorLinkManagementSheet",
        ] {
            XCTAssertFalse(
                shell.contains(staleShellContract),
                "The shell must not own link management: \(staleShellContract)"
            )
        }
        XCTAssertTrue(shell.contains("let onRemoveLink: (CardEditorLinkItem) -> Void"))
        XCTAssertTrue(shell.contains("onRemove: onRemoveLink"))

        let nonEmptyLinks = try XCTUnwrap(shell.range(of: "if !links.isEmpty"))
        let linkRow = try XCTUnwrap(shell.range(of: "CardEditorLinkRow("))
        let directionalLinks = try XCTUnwrap(shell.range(of: "links: links"))
        let linkAccessibility = try XCTUnwrap(
            shell.range(of: "cardEditorLinksRow")
        )
        XCTAssertLessThan(nonEmptyLinks.lowerBound, linkRow.lowerBound)
        XCTAssertLessThan(linkRow.lowerBound, directionalLinks.lowerBound)
        XCTAssertLessThan(linkRow.lowerBound, linkAccessibility.lowerBound)
    }

    func testTagRowReplacesAddCapsuleWithFocusedInlineField() throws {
        let metadata = try source(
            at: "ArcNote/CardEditor/CardEditorMetadataRows.swift"
        )
        let shell = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")
        let formatting = try source(
            at: "ArcNote/CardEditor/CardEditorFormattingBar.swift"
        )

        XCTAssertTrue(metadata.contains("let isAddingTag: Bool"))
        XCTAssertTrue(metadata.contains("let prefersKeyboardTagAction: Bool"))
        XCTAssertTrue(metadata.contains("@Binding var tagInput: String"))
        XCTAssertTrue(metadata.contains("private struct CardEditorTagInput: View"))
        XCTAssertTrue(metadata.contains("CardEditorTagInput("))
        XCTAssertTrue(
            shell.contains("@FocusState private var isTagInputFocused")
        )
        XCTAssertTrue(
            metadata.contains(
                "let isTagInputFocused: FocusState<Bool>.Binding"
            )
        )
        XCTAssertTrue(metadata.contains("@State private var didAcquireFocus = false"))
        XCTAssertTrue(metadata.contains("if isAddingTag"))
        XCTAssertTrue(metadata.contains("TextField(\"Tag\", text: $tagInput)"))
        XCTAssertTrue(metadata.contains(".submitLabel(.done)"))
        XCTAssertTrue(metadata.contains(".onSubmit(onComplete)"))
        XCTAssertTrue(metadata.contains("if isFocused {"))
        XCTAssertTrue(metadata.contains("didAcquireFocus = true"))
        XCTAssertTrue(metadata.contains("guard didAcquireFocus else { return }"))
        XCTAssertTrue(metadata.contains(".task {"))
        XCTAssertTrue(metadata.contains("await Task.yield()"))
        XCTAssertTrue(
            metadata.contains("isTagInputFocused.wrappedValue = true")
        )
        XCTAssertTrue(
            shell.contains("isTagInputFocused: $isTagInputFocused")
        )
        XCTAssertTrue(metadata.contains(".accessibilityIdentifier(\"cardEditorTagInput\")"))
        XCTAssertTrue(metadata.contains(".accessibilityIdentifier(\"cardEditorAddTag\")"))
        XCTAssertTrue(metadata.contains(".accessibilityHidden(prefersKeyboardTagAction)"))
        XCTAssertTrue(metadata.contains(".allowsHitTesting(!prefersKeyboardTagAction)"))
        XCTAssertTrue(metadata.contains(".frame(minWidth: 44, minHeight: 44)"))
        XCTAssertTrue(metadata.contains("cardMetadataTagCapsuleStyle"))
        XCTAssertTrue(
            shell.contains(
                "prefersKeyboardTagAction: bodyModel.isBodyFocused"
            )
        )
        XCTAssertTrue(formatting.contains("let onBeginTag: () -> Void"))
        XCTAssertTrue(formatting.contains("Button(action: onBeginTag)"))
        XCTAssertGreaterThanOrEqual(
            formatting.components(
                separatedBy: ".frame(minWidth: 45, minHeight: 44)"
            ).count - 1,
            2
        )
        XCTAssertTrue(formatting.contains(".disabled(!isTagEntryEnabled)"))
        XCTAssertTrue(shell.contains("isTagEntryEnabled: isMetadataEditable"))
        XCTAssertTrue(
            shell.contains("tags.count < CardEditingTag.maximumCount")
        )
        XCTAssertTrue(shell.contains(".asymmetric("))
        XCTAssertTrue(shell.contains("removal: .identity"))
        XCTAssertTrue(
            shell.contains("reduceMotion || !bodyModel.isBodyFocused")
        )
        XCTAssertTrue(
            formatting.contains(
                ".accessibilityIdentifier(\"cardEditorAddTag\")"
            )
        )
        XCTAssertTrue(shell.contains("TapGesture().onEnded"))
        XCTAssertTrue(shell.contains("guard isAddingTag else { return }"))
        XCTAssertTrue(shell.contains("onCompleteTag()"))
        XCTAssertFalse(shell.contains("CardEditorNativeTagInputFixture"))
        XCTAssertFalse(shell.contains("cardEditorNativeTagInput"))
    }

    func testEditorSurfacesUseAccessibilityAwareLiquidGlassFamily() throws {
        let glass = try source(
            at: "ArcNote/CardEditor/CardEditorGlassSurface.swift"
        )
        let background = try source(
            at: "ArcNote/CardEditor/CardEditorBackground.swift"
        )
        let formatting = try source(
            at: "ArcNote/CardEditor/CardEditorFormattingBar.swift"
        )
        let shell = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")
        let coordinator = try source(
            at: "Packages/BlockNoteEditor/Sources/BlockNoteEditor/BlockNoteEditorCoordinator.swift"
        )

        XCTAssertTrue(glass.contains("enum CardEditorGlassStyle: Equatable"))
        XCTAssertTrue(glass.contains("case writingPlane"))
        XCTAssertTrue(glass.contains("case chrome"))

        let edgeStart = try XCTUnwrap(
            glass.range(of: "private var edge: some View")
        )
        let materialStart = try XCTUnwrap(
            glass.range(
                of: "private var material: some View",
                range: edgeStart.upperBound..<glass.endIndex
            )
        )
        let edge = String(
            glass[edgeStart.lowerBound..<materialStart.lowerBound]
        )
        let writingPlaneEdgeStart = try XCTUnwrap(
            edge.range(of: "case .writingPlane:")
        )
        let chromeEdgeStart = try XCTUnwrap(
            edge.range(
                of: "case .chrome:",
                range: writingPlaneEdgeStart.upperBound..<edge.endIndex
            )
        )
        let writingPlaneEdge = String(
            edge[
                writingPlaneEdgeStart.lowerBound..<chromeEdgeStart.lowerBound
            ]
        )

        let material = String(glass[materialStart.lowerBound..<glass.endIndex])
        let writingPlaneMaterialStart = try XCTUnwrap(
            material.range(of: "case .writingPlane:")
        )
        let chromeMaterialStart = try XCTUnwrap(
            material.range(
                of: "case .chrome:",
                range: writingPlaneMaterialStart.upperBound..<material.endIndex
            )
        )
        let writingPlaneMaterial = String(
            material[
                writingPlaneMaterialStart.lowerBound..<chromeMaterialStart.lowerBound
            ]
        )
        let chromeMaterial = String(
            material[chromeMaterialStart.lowerBound..<material.endIndex]
        )

        XCTAssertTrue(glass.contains("if #available(iOS 26.0, *)"))
        // The approved reading/writing surface is calm paper. Native glass
        // remains on interactive chrome, not underneath editable body text.
        XCTAssertTrue(writingPlaneMaterial.contains(".fill(ChoraiTheme.surface.opacity(0.94))"))
        XCTAssertFalse(writingPlaneMaterial.contains(".glassEffect(.clear.interactive(), in: shape)"))
        XCTAssertEqual(
            writingPlaneMaterial.components(separatedBy: ".glassEffect(").count - 1,
            0
        )
        XCTAssertFalse(
            writingPlaneMaterial.contains(
                ".glassEffect(.regular.interactive(), in: shape)"
            )
        )
        XCTAssertEqual(
            writingPlaneMaterial.components(separatedBy: ".mask {").count - 1,
            1
        )
        let preservedInterior = try XCTUnwrap(
            writingPlaneMaterial.range(of: "shape.fill(Color.white)")
        )
        let directionalPerimeter = try XCTUnwrap(
            writingPlaneMaterial.range(of: "lineWidth: 2.8")
        )
        XCTAssertLessThan(
            preservedInterior.lowerBound,
            directionalPerimeter.lowerBound
        )
        XCTAssertTrue(writingPlaneMaterial.contains(".padding(1.4)"))
        XCTAssertEqual(
            writingPlaneMaterial.components(separatedBy: ".init(").count - 1,
            4
        )
        XCTAssertTrue(
            writingPlaneMaterial.contains(
                "color: Color.white.opacity(1.0)"
            )
        )
        XCTAssertTrue(writingPlaneMaterial.contains("location: 0.0"))
        XCTAssertTrue(
            writingPlaneMaterial.contains(
                "color: Color.white.opacity(0.72)"
            )
        )
        XCTAssertTrue(writingPlaneMaterial.contains("location: 0.46"))
        XCTAssertTrue(
            writingPlaneMaterial.contains(
                "contrast == .increased ? 0.28 : 0.08"
            )
        )
        XCTAssertTrue(writingPlaneMaterial.contains("location: 0.86"))
        XCTAssertTrue(
            writingPlaneMaterial.contains(
                "contrast == .increased ? 0.18 : 0.02"
            )
        )
        XCTAssertTrue(writingPlaneMaterial.contains("location: 1.0"))
        XCTAssertTrue(writingPlaneMaterial.contains("startPoint: .top,"))
        XCTAssertTrue(writingPlaneMaterial.contains("endPoint: .bottom"))
        XCTAssertTrue(
            chromeMaterial.contains(
                ".glassEffect(.regular.interactive(), in: shape)"
            )
        )
        XCTAssertEqual(
            chromeMaterial.components(separatedBy: ".glassEffect(").count - 1,
            1
        )
        XCTAssertFalse(
            chromeMaterial.contains(
                ".glassEffect(.clear.interactive(), in: shape)"
            )
        )
        XCTAssertFalse(chromeMaterial.contains(".mask {"))
        XCTAssertFalse(chromeMaterial.contains(".padding(1.4)"))
        XCTAssertFalse(chromeMaterial.contains("lineWidth: 2.8"))
        XCTAssertTrue(glass.contains("shape.fill(.ultraThinMaterial)"))
        XCTAssertTrue(writingPlaneEdge.contains("LinearGradient("))
        XCTAssertTrue(writingPlaneEdge.contains(".mask("))
        XCTAssertTrue(writingPlaneEdge.contains("startPoint: .top,"))
        XCTAssertTrue(writingPlaneEdge.contains("endPoint: .bottom"))
        XCTAssertTrue(
            writingPlaneEdge.contains(
                "contrast == .increased ? 0.14 : 0.02"
            )
        )
        XCTAssertFalse(writingPlaneEdge.contains("startPoint: .topLeading"))
        XCTAssertFalse(writingPlaneEdge.contains("endPoint: .bottomTrailing"))
        XCTAssertTrue(
            glass.contains("@Environment(\\.accessibilityReduceTransparency)")
        )
        XCTAssertTrue(
            glass.contains("@Environment(\\.colorSchemeContrast)")
        )
        XCTAssertTrue(glass.contains("if reduceTransparency"))
        XCTAssertFalse(glass.contains("isInteractive"))

        XCTAssertTrue(background.contains("style: .writingPlane"))
        XCTAssertTrue(background.contains("return 0.58"))
        XCTAssertTrue(background.contains("return 0.34"))
        XCTAssertTrue(background.contains("return 0.22"))
        XCTAssertFalse(background.contains("0.42"))
        XCTAssertTrue(formatting.contains("style: .chrome"))
        XCTAssertFalse(
            formatting.contains(".background(ZenVisualTokens.background.opacity(0.97))")
        )
        XCTAssertTrue(shell.contains("style: .chrome"))

        XCTAssertTrue(coordinator.contains("webView.isOpaque = false"))
        XCTAssertTrue(coordinator.contains("webView.backgroundColor = .clear"))
        XCTAssertTrue(
            coordinator.contains("webView.scrollView.backgroundColor = .clear")
        )
    }

    func testDetailViewConsumesSharedMetadataPresentation() throws {
        let detail = try source(at: "ArcNote/DetailView.swift")

        XCTAssertTrue(detail.contains("CardMetadataTagCapsule("))
        XCTAssertTrue(detail.contains("CardMetadataRelatedRow("))
        XCTAssertTrue(detail.contains("if !relatedNotes.isEmpty"))
        XCTAssertTrue(
            detail.contains(
                "@Environment(\\.accessibilityReduceMotion) private var reduceMotion"
            )
        )
        XCTAssertTrue(
            detail.contains(
                "withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3))"
            )
        )
        XCTAssertTrue(detail.contains(".frame(width: 44, height: 44)"))
        XCTAssertTrue(detail.contains("detailRelatedLinksDisclosure"))
        XCTAssertTrue(
            detail.contains(
                ".accessibilityValue(isRelatedNotesExpanded ? \"Expanded\" : \"Collapsed\")"
            )
        )
    }

    func testLinkPresentationMetadataSurvivesEveryEditorMapping() throws {
        let models = try source(
            at: "Packages/CoreFlow/Sources/CoreFlow/CardEditingModels.swift"
        )
        for field in [
            "public let previewHTML: String?",
            "public let authorName: String?",
            "public let authorAvatarURL: String?",
            "previewHTML: String? = nil",
            "authorName: String? = nil",
            "authorAvatarURL: String? = nil",
        ] {
            XCTAssertTrue(models.contains(field), "Missing CardEditingLink field: \(field)")
        }

        let networkService = try source(
            at: "ArcNote/CoreFlow/NetworkCoreCardEditingService.swift"
        )
        for mapping in [
            "previewHTML: item.content",
            "authorName: item.author?.userName",
            "authorAvatarURL: item.author?.avatar",
        ] {
            XCTAssertTrue(
                networkService.contains(mapping),
                "Canonical link fetch must retain \(mapping)"
            )
        }

        let newNote = try source(at: "ArcNote/NewNoteView.swift")
        XCTAssertTrue(newNote.contains("await editingStore.loadRelatedLinks()"))
        let localService = try source(at: "ArcNote/CoreFlow/LocalNotesController.swift")
        for mapping in [
            "noteLinkID: link.noteLinkID",
            "previewHTML: link.previewHTML",
            "authorName: link.authorName",
            "authorAvatarURL: link.authorAvatarURL",
        ] {
            XCTAssertTrue(localService.contains(mapping), "Local identity mapping must retain \(mapping)")
        }
        for mapping in [
            "previewHTML: item.description",
            "authorName: item.username",
            "authorAvatarURL: item.avatar",
            "previewHTML: link.previewHTML",
            "title: link.authorName ?? link.title",
            "avatarURL: link.authorAvatarURL",
        ] {
            XCTAssertTrue(
                newNote.contains(mapping),
                "Editor link mapping must retain \(mapping)"
            )
        }
    }

    func testPhotoAndTagAreFixedBeforeTypedCommandsScrollHorizontally() throws {
        let formatting = try source(
            at: "ArcNote/CardEditor/CardEditorFormattingBar.swift"
        )

        let photo = try XCTUnwrap(
            formatting.range(of: "commandButton(.inlineImage)")
        )
        let tag = try XCTUnwrap(
            formatting.range(of: "cardEditorAddTag")
        )
        let commandScroll = try XCTUnwrap(
            formatting.range(of: "ScrollView(.horizontal")
        )
        XCTAssertLessThan(photo.lowerBound, tag.lowerBound)
        XCTAssertLessThan(tag.lowerBound, commandScroll.lowerBound)
        XCTAssertFalse(formatting.contains("cardEditorKeyboardDismiss"))
        XCTAssertFalse(formatting.contains("keyboard.chevron.compact.down"))
        XCTAssertTrue(formatting.contains("scrollableCommands"))
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
    }

    func testInlineImageProgressAndRecoverableMessagesDoNotRequireRetryAction() throws {
        let shell = try source(
            at: "ArcNote/CardEditor/CardEditorShell.swift"
        )
        XCTAssertTrue(shell.contains("let isInlineImageProcessing: Bool"))
        XCTAssertTrue(
            shell.contains("isInlineImageProcessing: Bool = false")
        )
        XCTAssertTrue(
            shell.contains(
                "if isInlineImageProcessing || saveMessage != nil"
            )
        )
        XCTAssertTrue(
            shell.contains(
                ".accessibilityIdentifier(\"cardEditorInlineImageProgress\")"
            )
        )
        XCTAssertTrue(
            shell.contains(
                ".accessibilityIdentifier(\"cardEditorSaveMessage\")"
            )
        )

        let newNote = try source(at: "ArcNote/NewNoteView.swift")
        XCTAssertTrue(
            newNote.contains(
                "isInlineImageProcessing: isProcessingInlineImage"
            )
        )
    }

    func testFatalBridgeFailureUnmountsTheEditorAndRetriesWithANewSession() throws {
        let adapter = try source(
            at: "ArcNote/CardEditor/BlockNoteCardEditor.swift"
        )

        XCTAssertTrue(adapter.contains("bridgeFailureNotice"))
        XCTAssertTrue(adapter.contains("if let bridgeFailureNotice"))
        XCTAssertTrue(adapter.contains("cardEditorBridgeFailureNotice"))
        XCTAssertTrue(adapter.contains("cardEditorBridgeRetry"))
        XCTAssertTrue(adapter.contains("func retryAfterBridgeFailure()"))
        XCTAssertTrue(adapter.contains("editorInstanceID = UUID()"))
        XCTAssertTrue(adapter.contains("controller = BlockNoteEditorController()"))
        XCTAssertTrue(adapter.contains(".id(model.editorInstanceID)"))
        XCTAssertTrue(adapter.contains("from editorInstanceID: UUID"))
        XCTAssertTrue(adapter.contains("guard editorInstanceID == self.editorInstanceID"))
    }

    func testUnsupportedSelectionsDisableSelectionCommands() throws {
        let adapter = try source(
            at: "ArcNote/CardEditor/BlockNoteCardEditor.swift"
        )
        let formatting = try source(
            at: "ArcNote/CardEditor/CardEditorFormattingBar.swift"
        )

        XCTAssertTrue(adapter.contains("func canPerform("))
        XCTAssertTrue(adapter.contains("selectionState?.blockType == .unsupported"))
        XCTAssertTrue(adapter.contains("guard canPerform(command) else"))
        XCTAssertTrue(formatting.contains(".disabled(!model.canPerform(command))"))
    }

    func testFloatingControlSymbolsStayInsideFixedHitTargetsAtLargeType() throws {
        let shell = try source(
            at: "ArcNote/CardEditor/CardEditorShell.swift"
        )
        let controlsStart = try XCTUnwrap(
            shell.range(of: "private struct CardEditorFloatingControls")
        )
        let controlsEnd = try XCTUnwrap(
            shell.range(of: "#if DEBUG", range: controlsStart.upperBound..<shell.endIndex)
        )
        let controls = shell[controlsStart.lowerBound..<controlsEnd.lowerBound]

        XCTAssertGreaterThanOrEqual(
            controls.components(separatedBy: ".font(.system(size: 17, weight: .semibold))").count - 1,
            3
        )
        XCTAssertGreaterThanOrEqual(
            controls.components(separatedBy: ".clipShape(Circle())").count - 1,
            1
        )
        XCTAssertGreaterThanOrEqual(
            controls.components(separatedBy: ".frame(width: 44, height: 44)").count - 1,
            3
        )
        XCTAssertTrue(controls.contains("HStack(spacing: 4)"))
        XCTAssertTrue(controls.contains(".choraiGlassSurface(cornerRadius: 24)"))
        XCTAssertTrue(controls.contains("Text(\"Note\")"))
        XCTAssertTrue(
            controls.contains("Image(systemName: isPublic ? \"globe\" : \"lock\")")
        )
        XCTAssertTrue(
            controls.contains(
                ".accessibilityLabel(isPublic ? \"Make Private\" : \"Make Public\")"
            )
        )
        XCTAssertTrue(
            controls.contains(
                ".accessibilityValue(isPublic ? \"Public\" : \"Private\")"
            )
        )
        XCTAssertTrue(controls.contains("onOpenCardActions?()"))
        XCTAssertTrue(controls.contains("CardEditorNativeMenuButton("))
        XCTAssertTrue(controls.contains("actions: menuActions"))
        for removedBackgroundSurface in [
            "hasBackground",
            "onChooseBackground",
            "onRemoveBackground",
            "cardEditorBackgroundButton",
        ] {
            XCTAssertFalse(
                controls.contains(removedBackgroundSurface),
                "Background belongs in Card Actions: \(removedBackgroundSurface)"
            )
        }
        XCTAssertFalse(controls.contains(".font(.body"))
    }

    func testNativeMoreMenuPreparesEditingStateOnPresentation() throws {
        let shell = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")
        let start = try XCTUnwrap(shell.range(of: "if let menuActions {"))
        let end = try XCTUnwrap(shell.range(of: "} else {", range: start.upperBound..<shell.endIndex))
        let menu = String(shell[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(menu.contains("CardEditorNativeMenuButton("))
        XCTAssertTrue(menu.contains("onPrepare: onInteraction"))
        XCTAssertTrue(menu.contains("isEnabled: isMetadataEditable"))
        XCTAssertTrue(menu.contains(".frame(width: 44, height: 44)"))
        XCTAssertFalse(menu.contains(".simultaneousGesture("))
        let actions = try source(at: "ArcNote/CardEditor/CardEditorActionBox.swift")
        XCTAssertTrue(actions.contains("struct CardEditorNativeMenuButton: UIViewRepresentable"))
        XCTAssertTrue(actions.contains("button.showsMenuAsPrimaryAction = true"))
        XCTAssertTrue(actions.contains("for: .menuActionTriggered"))
        XCTAssertTrue(actions.contains("button.window?.endEditing(true)"))
        XCTAssertTrue(actions.contains("UIDeferredMenuElement.uncached"),
                      "Every opening must read current Pin and formatting capability state")
        XCTAssertTrue(actions.contains("action.accessibilityIdentifier = identifier"))
        XCTAssertTrue(actions.contains("actions.prepare()\n            perform()"),
                      "The selected action must still perform its original preparation and save guards")
        let callback = try XCTUnwrap(actions.range(of: "func menuWillPresent(_ button: UIButton)"))
        let prepare = try XCTUnwrap(actions.range(of: "prepare?()", range: callback.upperBound..<actions.endIndex))
        let nativeResign = try XCTUnwrap(actions.range(of: "button.window?.endEditing(true)", range: callback.upperBound..<actions.endIndex))
        XCTAssertLessThan(prepare.lowerBound, nativeResign.lowerBound)
    }

    func testWritingBodyKeepsStatusCloseAndLongDocumentsCanGrow() throws {
        let shell = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")
        let editor = try source(at: "ArcNote/CardEditor/BlockNoteCardEditor.swift")
        XCTAssertTrue(shell.contains("VStack(alignment: .leading, spacing: 6) {\n                            writingStatus"))
        XCTAssertFalse(shell.contains("viewport.size.height - 150"),
                       "Measure the actual footer instead of reserving a fixed blank spacer")
        XCTAssertTrue(editor.contains("max(minimumHeight, model.renderedHeight)"),
                      "Long documents must grow beyond the page minimum and keep their footer after the body")
    }

    func testEveryEditorAssignsRemainingPageHeightToTheRealWritingSurface() throws {
        let shell = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")
        let editorView = try source(at: "ArcNote/CardEditor/BlockNoteCardEditor.swift")
        XCTAssertFalse(shell.contains("usesFullPageWritingExtent"),
                       "Existing short notes must receive the same full writing page as new drafts")
        XCTAssertFalse(shell.contains(".hasMeaningfulContent"),
                       "Document emptiness must not determine the editor's page size")
        XCTAssertFalse(shell.contains("return 248 }"),
                       "Do not restore a compact nonempty-document layout")
        let editor = try XCTUnwrap(shell.range(of: "BlockNoteCardEditor("))
        let minimumHeight = try XCTUnwrap(shell.range(
            of: "minimumHeight: minimumWritingHeight(in: viewport.size.height)",
            range: editor.upperBound..<shell.endIndex
        ))
        let accessibility = try XCTUnwrap(shell.range(of: ".accessibilityIdentifier(\"cardEditorContent\")"))
        XCTAssertLessThan(minimumHeight.lowerBound, accessibility.lowerBound,
                          "The blank lower area must belong to the real editor, not a decorative spacer")
        XCTAssertTrue(shell.contains("CardEditorPageHeightKey.self"))
        XCTAssertTrue(shell.contains("value: [.status: geometry.size.height]"))
        XCTAssertTrue(shell.contains("value: [.footer: geometry.size.height]"))
        XCTAssertTrue(shell.contains("- writingStatusHeight - footerHeight"),
                      "Dynamic Type and visible metadata must be measured rather than clipped")
        XCTAssertTrue(shell.contains("fillsWritingPage: true"))
        XCTAssertTrue(editorView.contains("fillsWritingPage: Bool = false"),
                      "Compact embedded editors must not opt into the full writing page")
        XCTAssertTrue(editorView.contains("minimumWritingHeight: fillsWritingPage ? Double(minimumHeight) : 0"),
                      "The DOM writing floor must use the independent page minimum, not its measured content height")
        XCTAssertFalse(editorView.contains("TapGesture().onEnded(model.focusBody)"),
                       "Natural DOM taps must own the caret position without a competing native focus command")
    }

    func testTrailingToolsMenuReachesExistingTagAndFormattingWorkflows() throws {
        let shell = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")
        let metadata = try source(at: "ArcNote/CardEditor/CardEditorMetadataRows.swift")
        let actions = try source(at: "ArcNote/CardEditor/CardEditorActionBox.swift")
        let tagRow = try XCTUnwrap(shell.range(of: "CardEditorTagRow("))
        let tools = try XCTUnwrap(shell.range(of: "CardEditorToolsMenuButton("))
        XCTAssertLessThan(tagRow.lowerBound, tools.lowerBound)
        let toolsSurface = try XCTUnwrap(shell.range(
            of: ".choraiGlassSurface(cornerRadius: 22)",
            range: tools.upperBound..<shell.endIndex
        ))
        let toolsControl = shell[tools.lowerBound..<toolsSurface.lowerBound]
        XCTAssertTrue(toolsControl.contains(".disabled("),
                      "SwiftUI must convey read-only state to the represented native control as well as its menu actions")
        XCTAssertTrue(toolsControl.contains("(isMetadataEditable && tags.count < CardEditingTag.maximumCount)\n                        || bodyModel.canMutate"),
                      "Tools stays available when either tag entry or formatting is independently allowed")
        XCTAssertTrue(shell.contains("onPrepare: prepareToolsMenu"))
        XCTAssertTrue(shell.contains("onFormat: focusFormattingTools"))
        XCTAssertTrue(shell.contains("private func focusFormattingTools() {\n        completeTagEntry()\n        bodyModel.focusBody()"))
        XCTAssertTrue(shell.contains("private func prepareToolsMenu() {\n        completeTagEntry()\n        bodyModel.dismissKeyboard()"))
        XCTAssertTrue(metadata.contains("else if semantics != .cardEditor || tags.isEmpty"))
        XCTAssertTrue(metadata.contains("Text(\"Add tags\")"))
        let addTag = try XCTUnwrap(metadata.range(of: "private var addTagButton: some View"))
        let tagInput = try XCTUnwrap(metadata.range(of: "private struct CardEditorTagInput"))
        XCTAssertFalse(metadata[addTag.lowerBound..<tagInput.lowerBound].contains("Image(systemName: \"plus\")"),
                       "The quiet writer footer must not restore the competing circular plus button")
        XCTAssertTrue(actions.contains("struct CardEditorToolsMenuButton: UIViewRepresentable"))
        XCTAssertTrue(actions.contains("UIImage(systemName: \"slider.horizontal.3\""))
        for identifier in ["cardEditorTools", "cardEditorToolsAddTag", "cardEditorToolsFormat"] {
            XCTAssertTrue(actions.contains("\"\(identifier)\""))
        }
        let toolsMenu = try XCTUnwrap(actions.range(of: "struct CardEditorToolsMenuButton: UIViewRepresentable"))
        let legacyActions = try XCTUnwrap(actions.range(of: "struct CardEditorActionBox: View"))
        let implementation = actions[toolsMenu.lowerBound..<legacyActions.lowerBound]
        XCTAssertTrue(implementation.contains("for: .menuActionTriggered"))
        XCTAssertTrue(implementation.contains("UIDeferredMenuElement.uncached"))
        XCTAssertTrue(implementation.contains("isTagEntryEnabled ? [] : .disabled"))
        XCTAssertTrue(implementation.contains("isFormattingEnabled ? [] : .disabled"))
        XCTAssertTrue(implementation.contains("onBeginTag()"))
        XCTAssertTrue(implementation.contains("onFormat()"))
    }

    func testBackgroundSupportsLocalAndRemoteImagesInsideBodySurface() throws {
        let background = try source(
            at: "ArcNote/CardEditor/CardEditorBackground.swift"
        )

        XCTAssertTrue(background.contains("case local(Data)"))
        XCTAssertTrue(background.contains("case remote(URL)"))
        XCTAssertTrue(background.contains("backgroundImage"))
        XCTAssertTrue(background.contains("Color.black"))
        XCTAssertFalse(background.contains("cardEditorBodyBackground"))
        XCTAssertFalse(background.contains("cardEditorBodyBackgroundVeil"))
        XCTAssertFalse(background.contains("cardEditorPendingBackgroundImage"))
        XCTAssertFalse(background.contains("cardEditorBackgroundImage"))
        XCTAssertTrue(
            background.contains(".background {"),
            "The image must decorate the body instead of determining its ideal size"
        )
        XCTAssertTrue(background.contains(".clipped()"))
    }

    func testBackgroundDecorationsNeverEnterTheAccessibilityTree() throws {
        let background = try source(
            at: "ArcNote/CardEditor/CardEditorBackground.swift"
        )

        XCTAssertTrue(background.contains(".accessibilityHidden(true)"))
        XCTAssertFalse(background.contains("#if DEBUG"))
        XCTAssertFalse(background.contains(".accessibilityElement("))
        XCTAssertFalse(background.contains(".accessibilityLabel("))
    }

    func testInlineImageSourceUIIsNativeAndCameraSafe() throws {
        let relativePath = "ArcNote/CardEditor/CardEditorInlineImageSource.swift"
        let fileURL = Self.repositoryRoot.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            XCTFail("Missing CardEditorInlineImageSource.swift")
            return
        }

        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let project = try self.source(at: "ArcNote.xcodeproj/project.pbxproj")
        XCTAssertTrue(source.contains("enum CardEditorInlineImageSource"))
        XCTAssertTrue(source.contains("case photoLibrary"))
        XCTAssertTrue(source.contains("case camera"))
        XCTAssertTrue(source.contains("confirmationDialog("))
        XCTAssertTrue(
            source.contains("Take Photo — Unavailable on this device")
        )
        XCTAssertFalse(
            source.contains(".disabled(!isCameraAvailable)"),
            "iOS 26 removes disabled confirmation actions instead of showing them"
        )
        XCTAssertTrue(
            source.contains(
                ".accessibilityValue(isCameraAvailable ? \"Available\" : \"Unavailable\")"
            )
        )
        XCTAssertTrue(
            source.contains("UIImagePickerController.SourceType.camera")
        )
        XCTAssertTrue(source.contains("imagePickerControllerDidCancel"))
        XCTAssertTrue(
            project.contains(
                "/* CardEditorInlineImageSource.swift in Sources */"
            )
        )
    }

    func testEditorRespectsMotionTransparencyAndContrastPreferences() throws {
        let shell = try source(
            at: "ArcNote/CardEditor/CardEditorShell.swift"
        )
        let background = try source(
            at: "ArcNote/CardEditor/CardEditorBackground.swift"
        )
        let ambient = try source(
            at: "ArcNote/CardEditor/CardEditorAmbientBackdrop.swift"
        )

        XCTAssertTrue(
            shell.contains(
                "@Environment(\\.accessibilityReduceMotion) private var reduceMotion"
            )
        )
        XCTAssertTrue(
            shell.contains(
                "reduceMotion || !bodyModel.isBodyFocused"
            ),
            "The formatting bar must remove immediately and respect Reduce Motion"
        )
        XCTAssertTrue(shell.contains(": .easeOut(duration: 0.18)"))
        XCTAssertTrue(
            background.contains(
                "@Environment(\\.accessibilityReduceTransparency) private var reduceTransparency"
            )
        )
        XCTAssertTrue(
            background.contains(
                "@Environment(\\.colorSchemeContrast) private var contrast"
            )
        )
        XCTAssertTrue(background.contains("if reduceTransparency"))
        XCTAssertTrue(background.contains("if contrast == .increased"))
        XCTAssertTrue(
            ambient.contains("@Environment(\\.accessibilityReduceTransparency)")
        )
        XCTAssertTrue(ambient.contains("if !reduceTransparency"))
    }

    func testPlainWritingPagePreservesImageVeilAndContentClipping() throws {
        let ambientPath = "ArcNote/CardEditor/CardEditorAmbientBackdrop.swift"
        let ambientURL = Self.repositoryRoot.appendingPathComponent(ambientPath)
        guard FileManager.default.fileExists(atPath: ambientURL.path) else {
            XCTFail("Missing CardEditorAmbientBackdrop.swift")
            return
        }

        let ambient = try source(at: ambientPath)
        let background = try source(
            at: "ArcNote/CardEditor/CardEditorBackground.swift"
        )
        let shell = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")
        let project = try source(at: "ArcNote.xcodeproj/project.pbxproj")

        XCTAssertTrue(shell.contains("ChoraiBackground()"))
        XCTAssertFalse(shell.contains("CardEditorAmbientBackdrop()"))
        XCTAssertTrue(background.contains("if background == .none"))
        XCTAssertEqual(
            ambient.components(separatedBy: "RadialGradient(").count - 1,
            2
        )
        XCTAssertTrue(ambient.contains("center: upperLightCenter"))
        XCTAssertTrue(ambient.contains("center: lowerLightCenter"))
        XCTAssertTrue(ambient.contains("if !reduceTransparency"))
        XCTAssertTrue(ambient.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(ambient.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(
            project.contains("/* CardEditorAmbientBackdrop.swift in Sources */")
        )

        XCTAssertTrue(background.contains("return 0.22"))
        XCTAssertTrue(background.contains("return 0.34"))
        XCTAssertTrue(background.contains("return 0.58"))
        XCTAssertFalse(background.contains("0.42"))

        let bodyStart = try XCTUnwrap(
            background.range(of: "var body: some View")
        )

        let layerStart = try XCTUnwrap(
            background.range(of: "private var backgroundLayer: some View")
        )
        let body = background[bodyStart.lowerBound..<layerStart.lowerBound]
        let contentClip = try XCTUnwrap(body.range(of: ".clipShape(paneShape)"))
        let backgroundModifier = try XCTUnwrap(body.range(of: ".background {"))
        XCTAssertLessThan(contentClip.lowerBound, backgroundModifier.lowerBound)
        XCTAssertFalse(body.contains(".shadow("))

        let layerEnd = try XCTUnwrap(
            background.range(
                of: "private var backgroundImage: some View",
                range: layerStart.upperBound..<background.endIndex
            )
        )
        let layer = background[layerStart.lowerBound..<layerEnd.lowerBound]
        let image = try XCTUnwrap(layer.range(of: "backgroundImage"))
        let veil = try XCTUnwrap(layer.range(of: "Color.black"))
        let glass = try XCTUnwrap(layer.range(of: "CardEditorGlassSurface("))
        XCTAssertLessThan(image.lowerBound, veil.lowerBound)
        XCTAssertLessThan(veil.lowerBound, glass.lowerBound)
        XCTAssertTrue(layer.contains("style: .writingPlane"))
    }

    func testAmbientLightUsesViewportRelativeCentersInsideTheScene() throws {
        let ambient = try source(
            at: "ArcNote/CardEditor/CardEditorAmbientBackdrop.swift"
        )

        XCTAssertTrue(ambient.contains("GeometryReader { proxy in"))
        XCTAssertTrue(
            ambient.contains("UnitPoint(x: 0.82, y: 0.18)"),
            "The upper light should originate inside the upper-trailing scene"
        )
        XCTAssertTrue(
            ambient.contains("UnitPoint(x: 0.16, y: 0.70)"),
            "The lower light should cross the writing plane on compact screens"
        )
        XCTAssertTrue(
            ambient.contains("max(proxy.size.width, proxy.size.height)"),
            "Ambient light radius should scale with the viewport"
        )
        XCTAssertTrue(ambient.contains("endRadius: sceneExtent * 0.58"))
        XCTAssertTrue(ambient.contains("endRadius: sceneExtent * 0.54"))
        XCTAssertFalse(ambient.contains("center: .bottomLeading"))
        XCTAssertFalse(
            ambient.contains(".offset("),
            "Ambient light centers should remain inside the adaptive scene"
        )
    }

    func testDebugAppRouteExposesDeterministicCardEditorFixture() throws {
        let app = try source(at: "ArcNote/ArcNoteApp.swift")
        let fixture = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")

        XCTAssertTrue(app.contains("--ui-test-card-editor-shell"))
        XCTAssertTrue(app.contains("CardEditorShellFixtureScreen"))
        XCTAssertTrue(fixture.contains("CHORAI_CARD_EDITOR_FIXTURE_MODE"))
        XCTAssertTrue(
            fixture.contains("CHORAI_CARD_EDITOR_FIXTURE_VIEWPORT_HEIGHT")
        )
        XCTAssertTrue(
            fixture.contains(
                "CHORAI_CARD_EDITOR_FIXTURE_ACTION_BOX_LAYOUT"
            )
        )
        XCTAssertTrue(
            fixture.contains(".frame(height: fixtureViewportHeight, alignment: .top)")
        )
        XCTAssertTrue(
            fixture.contains("@State private var showCardActions = false")
        )
        XCTAssertTrue(fixture.contains("@State private var isPinned = false"))
        XCTAssertTrue(fixture.contains("if showCardActions {"))
        XCTAssertTrue(fixture.contains("CardEditorActionBox("))
        XCTAssertTrue(fixture.contains("PopupMenuOverlay("))
        XCTAssertTrue(fixture.contains("layout: .grid2x2"))
        XCTAssertTrue(fixture.contains("isPresented: $showCardActions"))
        XCTAssertTrue(fixture.contains("isEnabled: bodyModel.canMutate"))
        XCTAssertTrue(fixture.contains("isPinned: isPinned"))
        XCTAssertFalse(fixture.contains(".accessibilityHidden(showCardActions)"))
        XCTAssertTrue(
            fixture.contains(
                "background = .local(Self.fixtureBackgroundData)"
            )
        )
        XCTAssertTrue(fixture.contains("actionRouter.markDirty()"))
        for callback in [
            "onSpark: {}",
            "onMerge: {}",
            "onShare: {}",
            "onLink: {}",
            "onRoot: {}",
            "onRemove: {}",
            "onTogglePin: { isPinned.toggle() }",
        ] {
            XCTAssertTrue(
                fixture.contains(callback),
                "The deterministic fixture must inject \(callback)"
            )
        }
        XCTAssertFalse(fixture.contains("cardEditorCardActionsRequested"))
        XCTAssertTrue(
            fixture.contains(
                "onOpenCardActions: fixtureCardActionsHandler"
            )
        )
        XCTAssertTrue(
            fixture.contains(
                "private var fixtureCardActionsHandler: (() -> Void)?"
            )
        )
        XCTAssertTrue(
            fixture.contains("guard mode != .blocked else { return nil }")
        )
        let actionHandlerStart = try XCTUnwrap(
            fixture.range(
                of: "private var fixtureCardActionsHandler: (() -> Void)?"
            )
        )
        let actionHandlerEnd = try XCTUnwrap(
            fixture.range(
                of: "private static func document(",
                range: actionHandlerStart.upperBound..<fixture.endIndex
            )
        )
        let actionHandler = fixture[
            actionHandlerStart.lowerBound..<actionHandlerEnd.lowerBound
        ]
        XCTAssertTrue(actionHandler.contains("bodyModel.dismissKeyboard()"))
        XCTAssertTrue(actionHandler.contains("showCardActions = true"))
        XCTAssertTrue(fixture.contains("isMetadataEditable: bodyModel.canMutate"))
        XCTAssertTrue(
            fixture.contains("CardEditorShellFixtureActionRouter")
        )
        XCTAssertTrue(
            fixture.contains(
                "onRequestInlineImage: actionRouter.requestInlineImage"
            )
        )
        XCTAssertTrue(
            fixture.contains(".cardEditorInlineImageSourceDialog(")
        )
        XCTAssertTrue(fixture.contains("isCameraAvailable: false"))
        XCTAssertTrue(
            fixture.contains("showInlineImageSourceDialog = true")
        )
        XCTAssertTrue(fixture.contains("case longTag = \"long-tag\""))
        XCTAssertTrue(fixture.contains("case legacyHTML = \"legacy-html\""))
        XCTAssertTrue(fixture.contains("case bridgeFailure = \"bridge-failure\""))
        XCTAssertTrue(fixture.contains("case inlineImage = \"inline-image\""))
        XCTAssertTrue(
            fixture.contains(
                "CHORAI_CARD_EDITOR_FIXTURE_INLINE_IMAGE_URL"
            )
        )
        XCTAssertTrue(fixture.contains(#""type":"image""#))
        XCTAssertTrue(fixture.contains(#""showPreview":true"#))
        XCTAssertTrue(fixture.contains("fixtureBackgroundData.base64EncodedString()"))
        XCTAssertTrue(fixture.contains("contentJSON: nil"))
        XCTAssertTrue(
            fixture.contains("<p>Legacy <strong>rich</strong> text</p>")
        )
        XCTAssertTrue(fixture.contains("fixtureModel.receive("))
        XCTAssertTrue(
            fixture.contains(
                ".availabilityChanged(.failed(code: \"fixture_bridge_failure\"))"
            )
        )
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
