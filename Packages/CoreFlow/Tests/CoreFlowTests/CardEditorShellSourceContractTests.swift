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
        XCTAssertTrue(actionBox.contains(".fill(.ultraThinMaterial.opacity(1))"))
        XCTAssertTrue(actionBox.contains(".spring(response: 0.3, dampingFraction: 0.8)"))
        XCTAssertTrue(actionBox.contains("let rowCount: Int"))
        XCTAssertTrue(
            actionBox.contains("static let standardTileSize: CGFloat = 90")
        )
        XCTAssertTrue(
            actionBox.contains("static let headerHeight: CGFloat = 60")
        )
        XCTAssertTrue(
            actionBox.contains(
                "let reservedHeaderHeight = rowCount >= 3 ? headerHeight : 0"
            )
        )
        XCTAssertTrue(
            actionBox.contains("let reservesCloseHeader = rowCount >= 3")
        )
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
            2,
            "Action and empty tiles must share the adaptive standard size"
        )
        XCTAssertTrue(actionBox.contains(".frame(width: 38, height: 33)"))
        XCTAssertTrue(actionBox.contains(".font(.system(size: min(scaledLabelSize, 18), weight: .medium))"))
        XCTAssertTrue(actionBox.contains(".minimumScaleFactor(0.65)"))
        XCTAssertTrue(actionBox.contains(".allowsTightening(true)"))
        XCTAssertTrue(actionBox.contains("RoundedRectangle(cornerRadius: 12)"))
        XCTAssertTrue(actionBox.contains("@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertTrue(actionBox.contains(".accessibilityAddTraits(.isModal)"))
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

    func testAppTargetOwnsTheSixFocusedCardEditorFiles() throws {
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
        XCTAssertTrue(presentation.contains(".font(.system(size: 12, weight: .medium))"))
        XCTAssertTrue(presentation.contains(".foregroundStyle(.white)"))
        XCTAssertTrue(presentation.contains(".padding(.horizontal, 12)"))
        XCTAssertTrue(presentation.contains(".padding(.vertical, 6)"))
        XCTAssertTrue(
            presentation.contains(
                "Color(red: 0.2, green: 0.1, blue: 0.3)"
            )
        )
        XCTAssertFalse(presentation.contains(#"#\(tag)"#))
        XCTAssertFalse(presentation.contains(".stroke("))

        XCTAssertTrue(presentation.contains("struct CardMetadataRelatedRow: View"))
        XCTAssertTrue(presentation.contains("let avatarURL: String?"))
        XCTAssertTrue(presentation.contains("let previewHTML: String?"))
        XCTAssertTrue(presentation.contains(".frame(width: 40, height: 40)"))
        XCTAssertTrue(presentation.contains(".font(.system(size: 16, weight: .semibold))"))
        XCTAssertTrue(presentation.contains("font: .system(size: 14, weight: .regular)"))
        XCTAssertTrue(
            presentation.contains(
                "foregroundColor: .white.opacity(0.7)"
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
                "foregroundColor: Color = .white.opacity(0.9)"
            )
        )
        XCTAssertTrue(htmlRenderer.contains(".font(font)"))
        XCTAssertTrue(
            htmlRenderer.contains(".foregroundColor(foregroundColor)")
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
        XCTAssertTrue(shell.contains("cardEditorFloatingBack"))
        XCTAssertTrue(shell.contains("cardEditorPrivacyButton"))
        XCTAssertTrue(shell.contains("cardEditorMoreButton"))
        XCTAssertTrue(
            shell.contains("onOpenCardActions: (() -> Void)? = nil")
        )
        XCTAssertFalse(shell.contains("cardEditorCardActionsButton"))
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

    func testMetadataRowsShareViewStylingAndKeepLinksStatic() throws {
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
        XCTAssertTrue(metadata.contains("Color.white.opacity(0.1)"))
        for staleContract in [
            "cardEditorAddLink",
            "cardEditorLinkOverflow",
            "CardEditorLinkManagementSheet",
            "cardEditorRemoveLink.",
            "Button(action: onOpen)",
        ] {
            XCTAssertFalse(
                metadata.contains(staleContract),
                "Editor link metadata must be static: \(staleContract)"
            )
        }
        for staleShellContract in [
            "onAddLink",
            "onRemoveLink",
            "isManagingLinks",
            "CardEditorLinkManagementSheet",
        ] {
            XCTAssertFalse(
                shell.contains(staleShellContract),
                "The shell must not own link management: \(staleShellContract)"
            )
        }

        let nonEmptyLinks = try XCTUnwrap(shell.range(of: "if !links.isEmpty"))
        let linkRow = try XCTUnwrap(shell.range(of: "CardEditorLinkRow(links: links)"))
        let linkAccessibility = try XCTUnwrap(
            shell.range(of: "cardEditorLinksRow")
        )
        XCTAssertLessThan(nonEmptyLinks.lowerBound, linkRow.lowerBound)
        XCTAssertLessThan(linkRow.lowerBound, linkAccessibility.lowerBound)
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
        for mapping in [
            "previewHTML: item.content",
            "authorName: item.author?.userName",
            "authorAvatarURL: item.author?.avatar",
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
            3
        )
        XCTAssertGreaterThanOrEqual(
            controls.components(separatedBy: ".frame(width: 44, height: 44)").count - 1,
            3
        )
        XCTAssertTrue(controls.contains("HStack(spacing: 8)"))
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
        XCTAssertFalse(controls.contains("Menu {"))
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

    func testEditorRespectsMotionTransparencyAndContrastPreferences() throws {
        let shell = try source(
            at: "ArcNote/CardEditor/CardEditorShell.swift"
        )
        let background = try source(
            at: "ArcNote/CardEditor/CardEditorBackground.swift"
        )

        XCTAssertTrue(
            shell.contains(
                "@Environment(\\.accessibilityReduceMotion) private var reduceMotion"
            )
        )
        XCTAssertTrue(
            shell.contains(
                "reduceMotion ? nil : .easeOut(duration: 0.18)"
            ),
            "The formatting bar must not animate when Reduce Motion is enabled"
        )
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
        XCTAssertTrue(
            background.contains(
                "reduceTransparency || contrast == .increased"
            )
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
                "onBackground: { background = .local(Self.fixtureBackgroundData) }"
            )
        )
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
        XCTAssertTrue(fixture.contains("case longTag = \"long-tag\""))
        XCTAssertTrue(fixture.contains("case legacyHTML = \"legacy-html\""))
        XCTAssertTrue(fixture.contains("case bridgeFailure = \"bridge-failure\""))
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
