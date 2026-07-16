import BlockNoteEditor
import SwiftUI

struct CardEditorShell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var bodyModel: BlockNoteCardEditorModel

    let tags: [String]
    let links: [CardEditorLinkItem]
    let background: CardEditorBackgroundSource
    let isPublic: Bool
    let isMetadataEditable: Bool
    let isSaving: Bool
    let saveActionTitle: String
    let saveMessage: String?
    let onBack: () -> Void
    let onAddTag: () -> Void
    let onRemoveTag: (String) -> Void
    let onTogglePrivacy: () -> Void
    let onOpenCardActions: (() -> Void)?
    let onSave: (() -> Void)?

    init(
        bodyModel: BlockNoteCardEditorModel,
        tags: [String],
        links: [CardEditorLinkItem],
        background: CardEditorBackgroundSource,
        isPublic: Bool,
        isMetadataEditable: Bool,
        isSaving: Bool = false,
        saveActionTitle: String = "Save",
        saveMessage: String? = nil,
        onBack: @escaping () -> Void,
        onAddTag: @escaping () -> Void,
        onRemoveTag: @escaping (String) -> Void,
        onTogglePrivacy: @escaping () -> Void,
        onOpenCardActions: (() -> Void)? = nil,
        onSave: (() -> Void)? = nil
    ) {
        self.bodyModel = bodyModel
        self.tags = tags
        self.links = links
        self.background = background
        self.isPublic = isPublic
        self.isMetadataEditable = isMetadataEditable
        self.isSaving = isSaving
        self.saveActionTitle = saveActionTitle
        self.saveMessage = saveMessage
        self.onBack = onBack
        self.onAddTag = onAddTag
        self.onRemoveTag = onRemoveTag
        self.onTogglePrivacy = onTogglePrivacy
        self.onOpenCardActions = onOpenCardActions
        self.onSave = onSave
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZenVisualTokens.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CardEditorBackground(background: background) {
                        BlockNoteCardEditor(model: bodyModel)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("cardEditorContent")

                    CardEditorTagRow(
                        tags: tags,
                        isEditable: isMetadataEditable,
                        onAdd: onAddTag,
                        onRemove: onRemoveTag
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("cardEditorTagsRow")

                    if !links.isEmpty {
                        CardEditorLinkRow(links: links)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("cardEditorLinksRow")
                    }

                    if let onSave {
                        inlineSaveAction(onSave)
                    }
                }
                .padding(.horizontal, 20)
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
                onBack: onBack,
                onTogglePrivacy: onTogglePrivacy,
                onOpenCardActions: onOpenCardActions
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if bodyModel.isBodyFocused {
                CardEditorFormattingBar(model: bodyModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: bodyModel.isBodyFocused
        )
    }

    private func inlineSaveAction(_ action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let saveMessage {
                Text(saveMessage)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.68))
                    .accessibilityIdentifier("cardEditorSaveMessage")
            }

            Button(action: action) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isSaving ? "Saving" : saveActionTitle)
                        .font(.body.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .frame(minWidth: 88, minHeight: 44)
                .background(
                    Capsule(style: .continuous)
                        .fill(ZenVisualTokens.accent.opacity(0.28))
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(!bodyModel.canSave || isSaving)
            .accessibilityIdentifier("cardEditorSave")
        }
    }
}

private struct CardEditorFloatingControls: View {
    let isPublic: Bool
    let isMetadataEditable: Bool
    let onBack: () -> Void
    let onTogglePrivacy: () -> Void
    let onOpenCardActions: (() -> Void)?

    var body: some View {
        ZStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(controlBackground)
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Close note")
            .accessibilityIdentifier("cardEditorFloatingBack")
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
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var controlBackground: some View {
        Circle()
            .fill(ZenVisualTokens.background.opacity(0.82))
            .overlay {
                Circle()
                    .stroke(ZenVisualTokens.cardBorder, lineWidth: 1)
            }
    }
}

#if DEBUG
import UIKit

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
    @State private var tags: [String]
    @State private var links: [CardEditorLinkItem]
    @State private var background: CardEditorBackgroundSource
    @State private var isPublic = false
    @State private var isAddingTag = false
    @State private var showCardActions = false
    @State private var isPinned = false

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
        let fixtureModel = BlockNoteCardEditorModel(
            document: Self.document(for: mode),
            initialContentHeight: mode == .keyboard ? 640 : 248,
            initialSelection: initialSelection,
            initiallyFocused: false,
            initialCompatibilityBlock: blockedCode
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
                onBack: {},
                onAddTag: {
                    isAddingTag = true
                },
                onRemoveTag: { tag in
                    tags.removeAll { $0 == tag }
                },
                onTogglePrivacy: { isPublic.toggle() },
                onOpenCardActions: fixtureCardActionsHandler,
                onSave: {}
            )

            Color.white
                .opacity(0.001)
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Card editor shell")
                .accessibilityIdentifier("screen.card-editor-shell")
                .allowsHitTesting(false)

            if showCardActions {
                CardEditorActionBox(
                    isPresented: $showCardActions,
                    isEnabled: bodyModel.canMutate,
                    isPinned: isPinned,
                    onBackground: { background = .local(Self.fixtureBackgroundData) },
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
        .sheet(isPresented: $isAddingTag) {
            CardEditorNativeTagInputFixture {
                isAddingTag = false
            }
        }
    }

    private var fixtureCardActionsHandler: (() -> Void)? {
        guard mode != .blocked else { return nil }
        return { showCardActions = true }
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

private struct CardEditorNativeTagInputFixture: View {
    let onDone: () -> Void

    @State private var value = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField(
                    "Tag",
                    text: $value
                )
                .focused($isFocused)
                .accessibilityIdentifier("cardEditorNativeTagInput")
            }
            .navigationTitle("Add Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
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
