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
    @ObservedObject var bodyModel: BlockNoteCardEditorModel

    let tags: [String]
    let links: [CardEditorLinkItem]
    let background: CardEditorBackgroundSource
    let isPublic: Bool
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
    let onTogglePrivacy: () -> Void
    let onOpenCardActions: (() -> Void)?

    init(
        bodyModel: BlockNoteCardEditorModel,
        tags: [String],
        links: [CardEditorLinkItem],
        background: CardEditorBackgroundSource,
        isPublic: Bool,
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
        onTogglePrivacy: @escaping () -> Void,
        onOpenCardActions: (() -> Void)? = nil
    ) {
        self.bodyModel = bodyModel
        self.tags = tags
        self.links = links
        self.background = background
        self.isPublic = isPublic
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
        self.onTogglePrivacy = onTogglePrivacy
        self.onOpenCardActions = onOpenCardActions
    }

    var body: some View {
        ZStack(alignment: .top) {
            CardEditorAmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CardEditorBackground(background: background) {
                        BlockNoteCardEditor(model: bodyModel)
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            guard isAddingTag else { return }
                            onCompleteTag()
                        }
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("cardEditorContent")

                    CardEditorTagRow(
                        tags: tags,
                        isEditable: isMetadataEditable,
                        isAddingTag: isAddingTag,
                        prefersKeyboardTagAction: bodyModel.isBodyFocused,
                        tagInput: $tagInput,
                        onBeginTag: onBeginTag,
                        onCompleteTag: onCompleteTag,
                        onRemove: onRemoveTag
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("cardEditorTagsRow")

                    if !links.isEmpty {
                        CardEditorLinkRow(links: links)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("cardEditorLinksRow")
                    }

                    if isInlineImageProcessing || saveMessage != nil {
                        editorStatus
                    }

                }
                .adaptiveContentGutter()
                .padding(.top, 56)
                .padding(.bottom, 96)
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

            CardEditorFloatingControls(
                isPublic: isPublic,
                isMetadataEditable: isMetadataEditable,
                leadingControlState: leadingControlState,
                onLeadingControl: onLeadingControl,
                onTogglePrivacy: onTogglePrivacy,
                onOpenCardActions: onOpenCardActions
            )
        }
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

    private var editorStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isInlineImageProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Adding image…")
                        .font(.footnote.weight(.medium))
                }
                .foregroundStyle(.white.opacity(0.76))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("cardEditorInlineImageProgress")
            }

            if let saveMessage {
                Text(saveMessage)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.68))
                    .accessibilityIdentifier("cardEditorSaveMessage")
            }
        }
    }
}

private struct CardEditorFloatingControls: View {
    let isPublic: Bool
    let isMetadataEditable: Bool
    let leadingControlState: CardEditorLeadingControlState
    let onLeadingControl: () -> Void
    let onTogglePrivacy: () -> Void
    let onOpenCardActions: (() -> Void)?

    var body: some View {
        ZStack {
            Button(action: onLeadingControl) {
                Group {
                    if leadingControlState == .saving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
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
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(leadingControlState == .saving)
            .accessibilityLabel(leadingControlState.accessibilityLabel)
            .accessibilityIdentifier("cardEditorLeadingAction")
            .accessibilitySortPriority(3)

            HStack(spacing: 8) {
                Button(action: onTogglePrivacy) {
                    Image(systemName: isPublic ? "globe" : "lock")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(controlBackground)
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(!isMetadataEditable)
                .accessibilityLabel(isPublic ? "Make Private" : "Make Public")
                .accessibilityValue(isPublic ? "Public" : "Private")
                .accessibilityIdentifier("cardEditorPrivacyButton")
                .accessibilitySortPriority(2)

                Button {
                    onOpenCardActions?()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(controlBackground)
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(onOpenCardActions == nil)
                .accessibilityLabel("More note actions")
                .accessibilityIdentifier("cardEditorMoreButton")
                .accessibilitySortPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .adaptiveContentGutter()
        .padding(.top, 6)
    }

    private var controlBackground: some View {
        CardEditorGlassSurface(shape: Circle(), style: .chrome)
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
                onTogglePrivacy: {
                    isPublic.toggle()
                    actionRouter.markDirty()
                },
                onOpenCardActions: fixtureCardActionsHandler
            )

            Color.white
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
        case .empty, .legacyHTML, .bridgeFailure:
            return []
        }
    }

    var fixtureLinks: [CardEditorLinkItem] {
        if self == .blocked {
            return [
                .init(
                    id: "ast_blocked",
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
                id: "ast_fixture_a",
                title: "Ada",
                previewHTML: "A compact related-note preview."
            ),
            .init(id: "ast_fixture_b", title: "Bea"),
            .init(id: "ast_fixture_c", title: "Chen"),
            .init(id: "ast_fixture_d", title: "Dev"),
            .init(id: "ast_fixture_e", title: "Eli"),
        ]
    }
}
#endif
