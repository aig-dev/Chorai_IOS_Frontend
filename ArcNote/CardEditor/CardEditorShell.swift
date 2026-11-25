import BlockNoteEditor
import CoreFlow
import SwiftUI

enum CardEditorLeadingControlState: Equatable {
    case back
    case save
    case saving
    case retry
    case readOnly
    case bridgeFailed

    var accessibilityLabel: String {
        switch self {
        case .back, .readOnly, .bridgeFailed:
            return "Close note"
        case .save:
            return "Save note"
        case .saving:
            return "Saving note"
        case .retry:
            return "Retry saving note"
        }
    }
}

struct CardEditorShell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTagInputFocused: Bool
    @ObservedObject var bodyModel: BlockNoteCardEditorModel
    @State private var writingStatusHeight: CGFloat = 20
    @State private var footerHeight: CGFloat = 67

    let tags: [String]
    let links: [CardEditorLinkItem]
    let unlinkingLinkID: String?
    let isLinkRemovalEnabled: Bool
    let background: CardEditorBackgroundSource
    let isPublic: Bool?
    let audienceName: String?
    let isMetadataEditable: Bool
    let isInlineImageProcessing: Bool
    let saveMessage: String?
    let isAddingTag: Bool
    @Binding var tagInput: String
    let leadingControlState: CardEditorLeadingControlState
    let onLeadingControl: () -> Void
    let onBeginTag: () -> Void
    let onCompleteTag: () -> Void
    let onRemoveTag: (String) -> Void
    let onRemoveLink: (CardEditorLinkItem) -> Void
    let onTogglePrivacy: () -> Void
    let onOpenCardActions: (() -> Void)?
    let menuActions: CardEditorMenuActions?
    let isPrivacyEditable: Bool
    let saveStatus: String?
    let onReviewVersions: (() -> Void)?

    init(
        bodyModel: BlockNoteCardEditorModel,
        tags: [String],
        links: [CardEditorLinkItem],
        unlinkingLinkID: String? = nil,
        isLinkRemovalEnabled: Bool = false,
        background: CardEditorBackgroundSource,
        isPublic: Bool?,
        audienceName: String? = nil,
        isMetadataEditable: Bool,
        isInlineImageProcessing: Bool = false,
        saveMessage: String? = nil,
        isAddingTag: Bool,
        tagInput: Binding<String>,
        leadingControlState: CardEditorLeadingControlState,
        onLeadingControl: @escaping () -> Void,
        onBeginTag: @escaping () -> Void,
        onCompleteTag: @escaping () -> Void,
        onRemoveTag: @escaping (String) -> Void,
        onRemoveLink: @escaping (CardEditorLinkItem) -> Void,
        onTogglePrivacy: @escaping () -> Void,
        onOpenCardActions: (() -> Void)? = nil,
        menuActions: CardEditorMenuActions? = nil,
        isPrivacyEditable: Bool = true,
        saveStatus: String? = nil,
        onReviewVersions: (() -> Void)? = nil
    ) {
        self.bodyModel = bodyModel
        self.tags = tags
        self.links = links
        self.unlinkingLinkID = unlinkingLinkID
        self.isLinkRemovalEnabled = isLinkRemovalEnabled
        self.background = background
        self.isPublic = isPublic
        self.audienceName = audienceName
        self.isMetadataEditable = isMetadataEditable
        self.isInlineImageProcessing = isInlineImageProcessing
        self.saveMessage = saveMessage
        self.isAddingTag = isAddingTag
        _tagInput = tagInput
        self.leadingControlState = leadingControlState
        self.onLeadingControl = onLeadingControl
        self.onBeginTag = onBeginTag
        self.onCompleteTag = onCompleteTag
        self.onRemoveTag = onRemoveTag
        self.onRemoveLink = onRemoveLink
        self.onTogglePrivacy = onTogglePrivacy
        self.onOpenCardActions = onOpenCardActions
        self.menuActions = menuActions
        self.isPrivacyEditable = isPrivacyEditable
        self.saveStatus = saveStatus
        self.onReviewVersions = onReviewVersions
    }

    var body: some View {
        VStack(spacing: 0) {
            CardEditorFloatingControls(
                bodyModel: bodyModel,
                isPublic: isPublic,
                audienceName: audienceName,
                isMetadataEditable: isMetadataEditable,
                isPrivacyEditable: isPrivacyEditable,
                leadingControlState: leadingControlState,
                onInteraction: completeTagEntry,
                onLeadingControl: onLeadingControl,
                onTogglePrivacy: onTogglePrivacy,
                onOpenCardActions: onOpenCardActions,
                menuActions: menuActions
            )
            .padding(.bottom, 14)

            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            writingStatus
                                .background {
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: CardEditorPageHeightKey.self,
                                            value: [.status: geometry.size.height]
                                        )
                                    }
                                }
                            CardEditorBackground(background: background) {
                                BlockNoteCardEditor(
                                    model: bodyModel,
                                    minimumHeight: minimumWritingHeight(in: viewport.size.height),
                                    fillsWritingPage: true
                                )
                            }
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    completeTagEntry()
                                }
                            )
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("cardEditorContent")
                        }

                        editorFooter
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: CardEditorPageHeightKey.self,
                                        value: [.footer: geometry.size.height]
                                    )
                                }
                            }
                    }
                    .padding(.horizontal, 27)
                    .padding(.top, 6)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: viewport.size.height, alignment: .top)
                    .background {
                        CardEditorBlankTapSurface(action: completeTagEntry)
                            .allowsHitTesting(isAddingTag)
                    }
                }
                .clipped()
                .onPreferenceChange(CardEditorPageHeightKey.self) { heights in
                    if let height = heights[.status] { writingStatusHeight = height }
                    if let height = heights[.footer] { footerHeight = height }
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            let horizontal = abs(value.translation.width)
                            let vertical = abs(value.translation.height)
                            guard bodyModel.isBodyFocused,
                                  vertical >= 24,
                                  vertical > horizontal else { return }
                            bodyModel.dismissKeyboard()
                        }
                )
            }

        }
        .background { ChoraiBackground() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if bodyModel.isBodyFocused {
                CardEditorFormattingBar(
                    model: bodyModel,
                    isTagEntryEnabled: isMetadataEditable
                        && tags.count < CardEditingTag.maximumCount,
                    onBeginTag: onBeginTag
                )
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom)
                                .combined(with: .opacity),
                            removal: .identity
                        )
                    )
            }
        }
        .animation(
            reduceMotion || !bodyModel.isBodyFocused
                ? nil
                : .easeOut(duration: 0.18),
            value: bodyModel.isBodyFocused
        )
    }

    private func minimumWritingHeight(in viewportHeight: CGFloat) -> CGFloat {
        // Every note opens as a full writing page, including existing short notes.
        // The real editor grows beyond this minimum when its document is longer.
        // Status/body gap (6), body/footer gap (14), and page insets (6 + 20).
        // Footer measurements include its divider, tags, links, and save status.
        return max(248, viewportHeight - writingStatusHeight - footerHeight - 6 - 14 - 26)
    }

    private var editorFooter: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
                .padding(.top, 8)

            HStack(spacing: 12) {
                CardEditorTagRow(
                    tags: tags,
                    isEditable: isMetadataEditable,
                    isAddingTag: isAddingTag,
                    prefersKeyboardTagAction: bodyModel.isBodyFocused,
                    tagInput: $tagInput,
                    isTagInputFocused: $isTagInputFocused,
                    onBeginTag: onBeginTag,
                    onCompleteTag: completeTagEntry,
                    onInteraction: completeTagEntry,
                    onRemove: onRemoveTag
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("cardEditorTagsRow")

                CardEditorToolsMenuButton(
                    isTagEntryEnabled: isMetadataEditable
                        && tags.count < CardEditingTag.maximumCount,
                    isFormattingEnabled: bodyModel.canMutate,
                    onPrepare: prepareToolsMenu,
                    onBeginTag: onBeginTag,
                    onFormat: focusFormattingTools
                )
                .frame(width: 44, height: 44)
                .disabled(
                    !((isMetadataEditable && tags.count < CardEditingTag.maximumCount)
                        || bodyModel.canMutate)
                )
                .choraiGlassSurface(cornerRadius: 22)
            }

            if !links.isEmpty {
                CardEditorLinkRow(
                    links: links,
                    unlinkingLinkID: unlinkingLinkID,
                    isRemovalEnabled: isMetadataEditable && isLinkRemovalEnabled,
                    onInteraction: completeTagEntry,
                    onRemove: onRemoveLink
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("cardEditorLinksRow")
            }

            if isInlineImageProcessing || saveMessage != nil {
                editorStatus
            }
        }
    }

    private func prepareToolsMenu() {
        completeTagEntry()
        bodyModel.dismissKeyboard()
    }

    private func focusFormattingTools() {
        completeTagEntry()
        bodyModel.focusBody()
    }

    private var writingStatus: some View {
        HStack(spacing: 8) {
            Circle().fill(ChoraiTheme.ink.opacity(0.55))
                .frame(width: 5, height: 5)
            if let onReviewVersions {
                Button(action: onReviewVersions) {
                    HStack(spacing: 4) {
                        Text(writingStatusLabel)
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Review version options")
                .accessibilityIdentifier("cardEditorVersionOptions")
            } else {
                Text(writingStatusLabel)
            }
            Spacer()
            Text("\(bodyModel.fallbackMarkdown.split { $0.isWhitespace || $0.isNewline }.count) words")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 4)
    }

    private var writingStatusLabel: String {
        if let saveStatus { return saveStatus }
        switch leadingControlState {
        case .save: return "Unsaved changes"
        case .saving: return "Saving…"
        case .retry: return "Save needs retry"
        case .readOnly, .bridgeFailed: return "Read only"
        case .back: return isPublic.map { $0 ? "Public note" : "Private note" } ?? "Note audience unknown"
        }
    }

    private var editorStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isInlineImageProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(ChoraiTheme.accent)
                    Text("Adding image…")
                        .font(.footnote.weight(.medium))
                }
                .foregroundStyle(ChoraiTheme.secondaryInk)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("cardEditorInlineImageProgress")
            }

            if let saveMessage {
                Text(saveMessage)
                    .font(.footnote)
                    .foregroundStyle(ChoraiTheme.secondaryInk)
                    .accessibilityIdentifier("cardEditorSaveMessage")
            }
        }
    }

    private func completeTagEntry() {
        guard isAddingTag else { return }
        isTagInputFocused = false
        onCompleteTag()
    }
}

private enum CardEditorPageRegion: Hashable {
    case status
    case footer
}

private struct CardEditorPageHeightKey: PreferenceKey {
    static var defaultValue: [CardEditorPageRegion: CGFloat] { [:] }

    static func reduce(
        value: inout [CardEditorPageRegion: CGFloat],
        nextValue: () -> [CardEditorPageRegion: CGFloat]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct CardEditorBlankTapSurface: View {
    let action: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityHidden(true)
    }
}

private struct CardEditorFloatingControls: View {
    @ObservedObject var bodyModel: BlockNoteCardEditorModel
    let isPublic: Bool?
    let audienceName: String?
    let isMetadataEditable: Bool
    let isPrivacyEditable: Bool
    let leadingControlState: CardEditorLeadingControlState
    let onInteraction: () -> Void
    let onLeadingControl: () -> Void
    let onTogglePrivacy: () -> Void
    let onOpenCardActions: (() -> Void)?
    let menuActions: CardEditorMenuActions?

    var body: some View {
        ZStack {
            Text("Note")
                .font(.headline)
                .foregroundStyle(.primary)
            Button {
                onInteraction()
                onLeadingControl()
            } label: {
                Group {
                    if leadingControlState == .saving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(ChoraiTheme.accent)
                    } else {
                        Image(
                            systemName: leadingControlState == .save
                                || leadingControlState == .retry
                                ? "checkmark"
                                : "chevron.left"
                        )
                        .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(width: 44, height: 44)
                .background(controlBackground)
                .clipShape(Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(ChoraiTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(leadingControlState == .saving)
            .accessibilityLabel(leadingControlState.accessibilityLabel)
            .accessibilityIdentifier("cardEditorLeadingAction")
            .accessibilitySortPriority(3)

            HStack(spacing: 4) {
                Button {
                    onInteraction()
                    onTogglePrivacy()
                } label: {
                    Image(systemName: isPublic.map { $0 ? "globe" : "lock" } ?? "questionmark.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(ChoraiTheme.ink)
                .disabled(!isMetadataEditable || !isPrivacyEditable)
                .accessibilityLabel(isPublic.map { $0 ? "Make Private" : "Make Public" } ?? "Check note audience")
                .accessibilityValue(audienceName ?? isPublic.map { $0 ? "Public" : "Private" } ?? "Unknown")
                .accessibilityIdentifier("cardEditorPrivacyButton")
                .accessibilitySortPriority(2)

                Group {
                    if let menuActions {
                        CardEditorNativeMenuButton(
                            actions: menuActions,
                            bodyModel: bodyModel,
                            isEnabled: isMetadataEditable,
                            onPrepare: onInteraction
                        )
                        .frame(width: 44, height: 44)
                    } else {
                        Button {
                            onInteraction()
                            onOpenCardActions?()
                        } label: { moreLabel }
                        .disabled(onOpenCardActions == nil)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(ChoraiTheme.ink)
                .accessibilityLabel("More note actions")
                .accessibilityIdentifier("cardEditorMoreButton")
                .accessibilitySortPriority(1)
            }
            .padding(.horizontal, 6)
            .choraiGlassSurface(cornerRadius: 24)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .adaptiveContentGutter()
        .padding(.top, 6)
    }

    private var controlBackground: some View {
        CardEditorGlassSurface(shape: Circle(), style: .chrome)
    }

    private var moreLabel: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}

#if DEBUG
import UIKit

@MainActor
private final class CardEditorShellFixtureActionRouter: ObservableObject {
    @Published var hasPendingChanges = false
    private(set) var hasBodyInteraction = false
    var onRequestInlineImage: () -> Void = {}

    func requestInlineImage() {
        onRequestInlineImage()
    }

    func beginBodyInteraction() {
        hasBodyInteraction = true
    }

    func markDirty() {
        hasPendingChanges = true
    }

    func markSaved() {
        hasPendingChanges = false
    }
}

private enum CardEditorShellFixtureMode: String {
    case empty
    case populated
    case background
    case blocked
    case keyboard
    case longTag = "long-tag"
    case legacyHTML = "legacy-html"
    case bridgeFailure = "bridge-failure"
    case inlineImage = "inline-image"
}

@MainActor
struct CardEditorShellFixtureScreen: View {
    private let mode: CardEditorShellFixtureMode
    @StateObject private var bodyModel: BlockNoteCardEditorModel
    @StateObject private var actionRouter: CardEditorShellFixtureActionRouter
    @State private var tags: [String]
    @State private var links: [CardEditorLinkItem]
    @State private var background: CardEditorBackgroundSource
    @State private var isPublic = false
    @State private var isAddingTag = false
    @State private var tagInput = ""
    @State private var showCardActions = false
    @State private var showBackgroundActions = false
    @State private var isFixtureBackgroundRemoved = false
    @State private var showInlineImageSourceDialog = false
    @State private var isPinned = false
    @State private var isDismissed = false

    init() {
        let mode = CardEditorShellFixtureMode(
            rawValue: ProcessInfo.processInfo.environment[
                "CHORAI_CARD_EDITOR_FIXTURE_MODE"
            ] ?? "empty"
        ) ?? .empty
        self.mode = mode

        let blockedCode = mode == .blocked ? "unknown_block" : nil
        let initialSelection = mode == .keyboard
            ? BlockNoteSelectionState(
                blockType: .heading2,
                formats: .init(
                    bold: true,
                    italic: false,
                    underline: false,
                    strike: false
                )
            )
            : nil
        let actionRouter = CardEditorShellFixtureActionRouter()
        _actionRouter = StateObject(wrappedValue: actionRouter)
        let fixtureModel = BlockNoteCardEditorModel(
            document: Self.document(for: mode),
            initialContentHeight: mode == .keyboard ? 640 : 248,
            initialSelection: initialSelection,
            initiallyFocused: false,
            initialCompatibilityBlock: blockedCode,
            onDocumentChanged: { _ in
                guard actionRouter.hasBodyInteraction else { return }
                actionRouter.markDirty()
            },
            onRequestInlineImage: actionRouter.requestInlineImage
        )
        if mode == .bridgeFailure {
            fixtureModel.receive(
                .availabilityChanged(.failed(code: "fixture_bridge_failure"))
            )
        }
        _bodyModel = StateObject(wrappedValue: fixtureModel)
        _tags = State(initialValue: mode.fixtureTags)
        _links = State(initialValue: mode.fixtureLinks)
        _background = State(
            initialValue: mode == .background
                ? .local(Self.fixtureBackgroundData)
                : .none
        )
    }

    var body: some View {
        Group {
            if isDismissed {
                Color.clear
            } else {
                fixtureContent
            }
        }
    }

    private var fixtureContent: some View {
        ZStack(alignment: .topLeading) {
            CardEditorShell(
                bodyModel: bodyModel,
                tags: tags,
                links: links,
                isLinkRemovalEnabled: bodyModel.canMutate,
                background: background,
                isPublic: isPublic,
                isMetadataEditable: bodyModel.canMutate,
                saveMessage: mode == .blocked
                    ? "Read-only compatibility mode"
                    : nil,
                isAddingTag: isAddingTag,
                tagInput: $tagInput,
                leadingControlState: fixtureLeadingControlState,
                onLeadingControl: handleFixtureLeadingControl,
                onBeginTag: beginTagEntry,
                onCompleteTag: completeTagEntry,
                onRemoveTag: { tag in
                    tags.removeAll { $0 == tag }
                    actionRouter.markDirty()
                },
                onRemoveLink: { link in
                    links.removeAll { $0.id == link.id }
                },
                onTogglePrivacy: {
                    isPublic.toggle()
                    actionRouter.markDirty()
                },
                onOpenCardActions: fixtureCardActionsHandler,
                menuActions: usesTwoRowActionBoxFixture ? nil : fixtureMenuActions
            )

            ChoraiTheme.ink
                .opacity(0.001)
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Card editor shell")
                .accessibilityIdentifier("screen.card-editor-shell")
                .allowsHitTesting(false)

            if showCardActions {
                if usesTwoRowActionBoxFixture {
                    PopupMenuOverlay(
                        isPresented: $showCardActions,
                        layout: .grid2x2,
                        cardData: nil,
                        isOwnCard: true
                    )
                } else {
                    CardEditorActionBox(
                        isPresented: $showCardActions,
                        isEnabled: bodyModel.canMutate,
                        isPinned: isPinned,
                        onBackground: presentFixtureBackgroundActions,
                        onSpark: {},
                        onMerge: {},
                        onShare: {},
                        onLink: {},
                        onRoot: {},
                        onRemove: {},
                        onTogglePin: { isPinned.toggle() }
                    )
                }
            }
        }
        .frame(height: fixtureViewportHeight, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .cardEditorInlineImageSourceDialog(
            isPresented: $showInlineImageSourceDialog,
            isCameraAvailable: false,
            onSelect: { _ in }
        )
        .cardEditorBackgroundActionDialog(
            isPresented: $showBackgroundActions,
            context: fixtureBackgroundActionContext,
            onSelect: handleFixtureBackgroundAction
        )
        .onAppear {
            actionRouter.onRequestInlineImage = {
                bodyModel.dismissKeyboard()
                showInlineImageSourceDialog = true
            }
        }
        .onChange(of: bodyModel.isBodyFocused) { isFocused in
            if isFocused {
                actionRouter.beginBodyInteraction()
            }
        }
    }

    private var fixtureViewportHeight: CGFloat? {
        ProcessInfo.processInfo.environment[
            "CHORAI_CARD_EDITOR_FIXTURE_VIEWPORT_HEIGHT"
        ].flatMap(Double.init).map { CGFloat($0) }
    }

    private var usesTwoRowActionBoxFixture: Bool {
        ProcessInfo.processInfo.environment[
            "CHORAI_CARD_EDITOR_FIXTURE_ACTION_BOX_LAYOUT"
        ] == "grid2x2"
    }

    private var fixtureCardActionsHandler: (() -> Void)? {
        guard mode != .blocked else { return nil }
        return {
            bodyModel.dismissKeyboard()
            showCardActions = true
        }
    }

    private var fixtureMenuActions: CardEditorMenuActions {
        CardEditorMenuActions(
            isPinned: isPinned,
            prepare: {
                completeTagEntry()
                bodyModel.dismissKeyboard()
            },
            background: presentFixtureBackgroundActions,
            spark: {}, merge: {}, share: {}, link: {}, root: {}, remove: {},
            togglePin: { isPinned.toggle() }
        )
    }

    private var fixtureBackgroundActionContext:
        CardEditorBackgroundActionContext {
        isFixtureBackgroundRemoved
            ? .removed(canRestoreBackground: true)
            : .visible(canRestoreOriginal: false)
    }

    private func presentFixtureBackgroundActions() {
        completeTagEntry()
        bodyModel.dismissKeyboard()
        if background == .none, mode != .background {
            background = .local(Self.fixtureBackgroundData)
            actionRouter.markDirty()
        } else {
            showBackgroundActions = true
        }
    }

    private func handleFixtureBackgroundAction(
        _ action: CardEditorBackgroundAction
    ) {
        switch action {
        case .choosePhoto:
            background = .local(Self.fixtureBackgroundData)
            isFixtureBackgroundRemoved = false
            actionRouter.markDirty()
        case .remove:
            background = .none
            isFixtureBackgroundRemoved = true
            actionRouter.markDirty()
        case .close:
            isDismissed = true
        case .restore:
            background = .local(Self.fixtureBackgroundData)
            isFixtureBackgroundRemoved = false
            actionRouter.markSaved()
        }
    }

    private var fixtureLeadingControlState: CardEditorLeadingControlState {
        if mode == .blocked {
            return .readOnly
        }
        if mode == .bridgeFailure,
           bodyModel.bridgeFailureNotice != nil {
            return .bridgeFailed
        }
        return actionRouter.hasPendingChanges ? .save : .back
    }

    private func handleFixtureLeadingControl() {
        switch fixtureLeadingControlState {
        case .save, .retry:
            actionRouter.markSaved()
        case .back:
            isDismissed = true
        case .saving, .readOnly, .bridgeFailed:
            break
        }
    }

    private func beginTagEntry() {
        guard bodyModel.canMutate else { return }
        bodyModel.dismissKeyboard()
        tagInput = ""
        isAddingTag = true
    }

    private func completeTagEntry() {
        guard isAddingTag else { return }
        let candidate = tagInput
        isAddingTag = false
        tagInput = ""
        guard let updatedTags = CardEditingTag.appending(
            candidate,
            to: tags
        ) else {
            return
        }
        tags = updatedTags
        actionRouter.markDirty()
    }

    private static func document(
        for mode: CardEditorShellFixtureMode
    ) -> BlockNoteInitialDocument {
        if mode == .blocked {
            return BlockNoteInitialDocument(
                contentJSON: #"[{"type":"futureWebBlock","props":{"payload":"preserve"},"content":[],"children":[]}]"#,
                fallbackMarkdown: "A note from a newer editor"
            )
        }

        if mode == .legacyHTML {
            return BlockNoteInitialDocument(
                contentJSON: nil,
                fallbackMarkdown:
                    "<p>Legacy <strong>rich</strong> text</p>"
            )
        }

        if mode == .inlineImage {
            let configuredURL = ProcessInfo.processInfo.environment[
                "CHORAI_CARD_EDITOR_FIXTURE_INLINE_IMAGE_URL"
            ]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let imageURL = configuredURL.flatMap { $0.isEmpty ? nil : $0 }
                ?? "data:image/jpeg;base64,\(fixtureBackgroundData.base64EncodedString())"
            let encodedURL = (try? JSONEncoder().encode(imageURL))
                .flatMap { String(data: $0, encoding: .utf8) }
                ?? "\"\""
            return BlockNoteInitialDocument(
                contentJSON: #"[{"id":"inline-image-fixture","type":"image","props":{"backgroundColor":"default","textAlignment":"center","name":"Inline image fixture","url":\#(encodedURL),"caption":"","showPreview":true},"children":[]}]"#,
                fallbackMarkdown: ""
            )
        }

        if mode == .keyboard {
            let heading = #"{"id":"heading-fixture","type":"heading","props":{"backgroundColor":"default","textColor":"default","textAlignment":"left","level":2,"isToggleable":false},"content":[{"type":"text","text":"A selected heading","styles":{"bold":true}}],"children":[]}"#
            let paragraphs = (0..<14).map { index in
                #"{"id":"paragraph-fixture-\#(index)","type":"paragraph","props":{"backgroundColor":"default","textColor":"default","textAlignment":"left"},"content":[{"type":"text","text":"Scroll fixture paragraph \#(index)","styles":{}}],"children":[]}"#
            }
            return BlockNoteInitialDocument(
                contentJSON: "[\(([heading] + paragraphs).joined(separator: ","))]",
                fallbackMarkdown: "A selected heading"
            )
        }

        let text = mode == .empty
            ? ""
            : "A lightweight note begins with its body, without a title row."
        let inlineContentJSON = text.isEmpty
            ? "[]"
            : #"[{"type":"text","text":"\#(text)","styles":{}}]"#
        return BlockNoteInitialDocument(
            contentJSON: #"[{"id":"paragraph-fixture","type":"paragraph","props":{"backgroundColor":"default","textColor":"default","textAlignment":"left"},"content":\#(inlineContentJSON),"children":[]}]"#,
            fallbackMarkdown: text
        )
    }

    private static let fixtureBackgroundData: Data = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 520))
        return renderer.image { context in
            UIColor(red: 0.24, green: 0.10, blue: 0.46, alpha: 1).setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 720, height: 520))
            UIColor(red: 0.48, green: 0.30, blue: 0.76, alpha: 1).setFill()
            context.cgContext.fill(CGRect(x: 330, y: 0, width: 390, height: 520))
            UIColor(red: 0.96, green: 0.56, blue: 0.46, alpha: 0.72).setFill()
            context.cgContext.fillEllipse(
                in: CGRect(x: 70, y: 80, width: 280, height: 280)
            )
        }.jpegData(compressionQuality: 0.88) ?? Data()
    }()
}

private extension CardEditorShellFixtureMode {
    var fixtureTags: [String] {
        switch self {
        case .populated, .background, .keyboard:
            return ["idea", "research"]
        case .blocked:
            return ["archive"]
        case .longTag:
            return ["this-is-an-intentionally-long-tag-that-must-compress"]
        case .empty, .legacyHTML, .bridgeFailure, .inlineImage:
            return []
        }
    }

    var fixtureLinks: [CardEditorLinkItem] {
        if self == .blocked {
            return [
                .init(
                    sourceCardID: "ast_blocked",
                    targetCardID: "ast_blocked_target",
                    title: "Preserved relation",
                    previewHTML: "Read-only linked note"
                ),
            ]
        }
        guard self == .populated || self == .background || self == .keyboard else {
            return []
        }
        return [
            .init(
                sourceCardID: "ast_fixture_source",
                targetCardID: "ast_fixture_a",
                title: "Ada",
                previewHTML: "A compact related-note preview.",
                canRemove: true
            ),
            .init(
                sourceCardID: "ast_fixture_source",
                targetCardID: "ast_fixture_b",
                title: "Bea",
                canRemove: true
            ),
            .init(
                sourceCardID: "ast_fixture_c",
                targetCardID: "ast_fixture_source",
                title: "Chen",
                canRemove: true
            ),
            .init(
                sourceCardID: "ast_fixture_source",
                targetCardID: "ast_fixture_d",
                title: "Dev",
                canRemove: true
            ),
            .init(
                sourceCardID: "ast_fixture_source",
                targetCardID: "ast_fixture_e",
                title: "Eli",
                canRemove: true
            ),
        ]
    }
}
#endif

#if DEBUG
/// Isolated real-editor fixture. Only transport and app storage are substituted.
@MainActor
struct BackgroundRecoveryFixture: View {
    @StateObject private var owner = BackgroundRecoveryFixtureOwner()
    @State private var showing = false
    @State private var openingNew = true
    @State private var proof = ""
    @State private var dismissedProof = ""
    let held: Bool
    var ownerChoice = false

    var body: some View {
        VStack {
            Text(dismissedProof).accessibilityIdentifier("fixture.background.proof")
            Button("Open note") { dismissedProof = ""; showing = true }.accessibilityIdentifier("fixture.background.open")
        }
        .accessibilityHidden(showing)
        .task {
            do {
                try await owner.prepare(held: held, ownerChoice: ownerChoice)
                openingNew = !held && !ownerChoice
                showing = true
            } catch { proof = String(describing: error) }
        }
        .sheet(isPresented: $showing, onDismiss: {
            openingNew = false
            Task {
                do { dismissedProof = try await owner.readback() }
                catch { dismissedProof = String(describing: error) }
            }
        }) {
            NewNoteView(cardId: openingNew ? "" : owner.identifier,
                        creationID: owner.id, suppliedService: owner.editor(new: openingNew), localNotes: owner.notes)
                .safeAreaInset(edge: .bottom) {
                    VStack {
                        if held && !openingNew {
                            Button("Release upload") { owner.release() }.accessibilityIdentifier("fixture.background.release")
                        }
                        Button("Inspect local note") {
                            Task {
                                do { proof = try await owner.readback() }
                                catch { proof = String(describing: error) }
                            }
                        }.accessibilityIdentifier("fixture.background.inspect")
                        Text(proof).accessibilityIdentifier("fixture.background.live-proof")
                    }
                }
        }
    }
}

@MainActor
final class BackgroundRecoveryFixtureOwner: ObservableObject, NoteBackgroundTransport {
    let id = UUID().uuidString
    let scope = NoteStoreScope(actorID: UUID().uuidString, environmentID: "offline-real-background-editor")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private lazy var source = BackgroundRecoveryFixtureSync(scope: scope)
    lazy var library = NoteLibraryStore(rootURL: root, service: { [source] _ in source })
    lazy var notes = LocalNotesController(library: library, access: { [scope] in (scope, true) })
    var identifier: String { "local-note:" + id }
    private let generation = NoteBackgroundGeneration()
    private var uploads = 0
    private var writes = 0
    private var waiting: CheckedContinuation<Void, Never>?
    private var holdUpload = false
    private var observation = NoteBackgroundObservation(revision: 0, displayRef: nil)
    private var refreshOnAction = false
    private var observationCount = 0

    func editor(new: Bool) -> LocalCoreCardEditingService {
        LocalCoreCardEditingService(identifier: new ? nil : identifier, creationID: id, scope: scope, library: library,
                                    backgroundTransport: self, backgroundGeneration: generation, backgroundAccess: { [scope] in (scope, 0, true) })
    }
    func prepare(held: Bool, ownerChoice: Bool = false) async throws {
        holdUpload = held
        await library.configure(scope: scope, cloudEnabled: true)
        if held || ownerChoice {
            _ = try await library.save(identifier: nil, createID: id, body: .init(content: "Initial body", contentJSON: #"[{"id":"held-initial","type":"paragraph","props":{},"content":[{"type":"text","text":"Initial body","styles":{}}],"children":[]}]"#), scope: scope)
            await library.synchronize(forceRetry: true)
        }
        if ownerChoice {
            _ = try await library.recordMetadata(identifier: identifier, backgroundMediaRef: .some("/fixture/A"), scope: scope)
            let refresh = ProcessInfo.processInfo.environment["CHORAI_CARD_EDITOR_BACKGROUND_REFRESH"]
            refreshOnAction = refresh != nil
            observation = .init(revision: 2, displayRef: refresh == "remove" ? nil : "/fixture/B")
            return
        }
        let service = editor(new: !held)
        _ = try await service.readBackground()
        try await service.observeBackgroundChoice()
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        _ = try await service.stageBackground(.init(data: data, filename: "photo.png", mimeType: "image/png"))
    }
    func readback() async throws -> String {
        await library.synchronize(forceRetry: true)
        let target = try await library.backgroundTarget(identifier: identifier, createID: id, scope: scope)
        let record = try await target.store.background(localID: id)
        return "\(await counts()) revision=\(target.note?.bodyRevision ?? 0) ack=\(target.note?.acknowledgedBodyRevision ?? 0) phase=\(record?.phase.rawValue ?? "none") public=\(target.note?.isPublic ?? false) body=\(target.note?.body.content ?? "")"
    }
    func counts() async -> String {
        "creates=\(await source.creates) uploads=\(uploads) writes=\(writes)"
    }
    func release() { holdUpload = false; waiting?.resume(); waiting = nil }
    func backgroundObservation(scope: NoteStoreScope, asset: String) async throws -> NoteBackgroundObservation {
        observationCount += 1
        if refreshOnAction && observationCount == 1 {
            return .init(revision: 1, displayRef: "/fixture/A")
        }
        return observation
    }
    func uploadBackground(_ command: NoteBackgroundCommand, bytes: Data) async throws -> String {
        uploads += 1
        if holdUpload { await withCheckedContinuation { waiting = $0 } }
        return "med_1234567890abcdef"
    }
    func writeBackground(_ command: NoteBackgroundCommand) async throws -> NoteBackgroundObservation {
        writes += 1
        observation = .init(revision: command.baseline + 1, displayRef: command.logicalRef == nil ? nil : "/fixture/background")
        return observation
    }
}

private actor BackgroundRecoveryFixtureSync: NoteSyncServing {
    let scope: NoteStoreScope
    private(set) var creates = 0
    private var current: NoteRemoteSnapshot?
    init(scope: NoteStoreScope) { self.scope = scope }
    func manifest() async throws -> NoteSyncManifest {
        .init(protocolVersion: 3, complete: true, notes: current.map { [.init(assetID: $0.assetID, syncToken: $0.syncToken, lifecycle: $0.lifecycle)] } ?? [])
    }
    func detail(assetID: String) async throws -> NoteRemoteSnapshot {
        guard let current, current.assetID == assetID else { throw NoteSyncFailure.notFound }
        return current
    }
    func send(_ op: NotePendingOperation) async throws -> NoteSyncReceipt {
        if op.kind == .create { creates += 1 }
        let data = try JSONSerialization.jsonObject(with: op.requestBody) as? [String: Any]
        let token = UUID().uuidString
        let asset = op.serverAssetID ?? "fixture-asset"
        current = .init(assetID: asset, syncToken: token,
                        body: .init(content: data?["content"] as? String ?? "", contentJSON: data?["content_json"] as? String),
                        lifecycle: op.lifecycle, isPublic: data?["is_public"] as? Bool ?? false)
        return .init(operationID: op.operationID, assetID: asset, syncToken: token, noteDocumentVersionID: token, lifecycle: op.lifecycle)
    }
    func upload(_ attachment: NoteLocalAttachment, data: Data) async throws -> NoteSyncUploadReceipt { throw NoteSyncFailure.notReady }
    func downloadAttachment(assetID: String, mediaRef: String) async throws -> NoteSyncDownloadedAttachment { throw NoteSyncFailure.notReady }
}
#endif
