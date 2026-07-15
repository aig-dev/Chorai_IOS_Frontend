import BlockNoteEditor
import SwiftUI

struct CardEditorShell: View {
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
    let onAddLink: () -> Void
    let onRemoveLink: (CardEditorLinkItem) -> Void
    let onTogglePrivacy: () -> Void
    let onChooseBackground: () -> Void
    let onRemoveBackground: () -> Void
    let onOpenCardActions: (() -> Void)?
    let onSave: (() -> Void)?

    @State private var isManagingLinks = false

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
        onAddLink: @escaping () -> Void,
        onRemoveLink: @escaping (CardEditorLinkItem) -> Void,
        onTogglePrivacy: @escaping () -> Void,
        onChooseBackground: @escaping () -> Void,
        onRemoveBackground: @escaping () -> Void,
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
        self.onAddLink = onAddLink
        self.onRemoveLink = onRemoveLink
        self.onTogglePrivacy = onTogglePrivacy
        self.onChooseBackground = onChooseBackground
        self.onRemoveBackground = onRemoveBackground
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

                    CardEditorLinkRow(
                        links: links,
                        isEditable: isMetadataEditable,
                        onOpen: { isManagingLinks = true },
                        onAdd: onAddLink
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("cardEditorLinksRow")

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
                hasBackground: background != .none,
                isMetadataEditable: isMetadataEditable,
                onBack: onBack,
                onTogglePrivacy: onTogglePrivacy,
                onChooseBackground: onChooseBackground,
                onRemoveBackground: onRemoveBackground,
                onOpenCardActions: onOpenCardActions
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if bodyModel.isBodyFocused {
                CardEditorFormattingBar(model: bodyModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $isManagingLinks) {
            CardEditorLinkManagementSheet(
                links: links,
                isEditable: isMetadataEditable,
                onRemove: onRemoveLink
            )
        }
        .animation(
            .easeOut(duration: 0.18),
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
    let hasBackground: Bool
    let isMetadataEditable: Bool
    let onBack: () -> Void
    let onTogglePrivacy: () -> Void
    let onChooseBackground: () -> Void
    let onRemoveBackground: () -> Void
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

            Menu {
                if let onOpenCardActions {
                    Button(action: onOpenCardActions) {
                        Label("Card Actions", systemImage: "square.grid.2x2")
                    }
                    .accessibilityIdentifier("cardEditorCardActionsButton")

                    Divider()
                }

                Button(action: onTogglePrivacy) {
                    Label(
                        isPublic ? "Make Private" : "Make Public",
                        systemImage: isPublic ? "lock" : "globe"
                    )
                }
                .disabled(!isMetadataEditable)
                .accessibilityIdentifier("cardEditorPrivacyButton")

                Button(action: onChooseBackground) {
                    Label(
                        hasBackground ? "Replace Background" : "Add Background",
                        systemImage: "photo"
                    )
                }
                .disabled(!isMetadataEditable)
                .accessibilityIdentifier("cardEditorBackgroundButton")

                if hasBackground {
                    Button(role: .destructive, action: onRemoveBackground) {
                        Label("Remove Background", systemImage: "photo.badge.minus")
                    }
                    .disabled(!isMetadataEditable)
                }
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
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("More note actions")
            .accessibilityIdentifier("cardEditorMoreButton")
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
    case bridgeFailure = "bridge-failure"
}

private enum CardEditorNativeInputKind: String, Identifiable {
    case tag
    case link

    var id: String { rawValue }
}

@MainActor
struct CardEditorShellFixtureScreen: View {
    private let mode: CardEditorShellFixtureMode
    @StateObject private var bodyModel: BlockNoteCardEditorModel
    @State private var tags: [String]
    @State private var links: [CardEditorLinkItem]
    @State private var background: CardEditorBackgroundSource
    @State private var isPublic = false
    @State private var nativeInputKind: CardEditorNativeInputKind?
    @State private var didRequestCardActions = false

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
                    nativeInputKind = .tag
                },
                onRemoveTag: { tag in
                    tags.removeAll { $0 == tag }
                },
                onAddLink: { nativeInputKind = .link },
                onRemoveLink: { link in
                    links.removeAll { $0.id == link.id }
                },
                onTogglePrivacy: { isPublic.toggle() },
                onChooseBackground: {
                    background = .local(Self.fixtureBackgroundData)
                },
                onRemoveBackground: { background = .none },
                onOpenCardActions: { didRequestCardActions = true },
                onSave: {}
            )

            Color.white
                .opacity(0.001)
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Card editor shell")
                .accessibilityIdentifier("screen.card-editor-shell")
                .allowsHitTesting(false)

            if didRequestCardActions {
                Color.white
                    .opacity(0.001)
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Card actions requested")
                    .accessibilityIdentifier("cardEditorCardActionsRequested")
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $nativeInputKind) { kind in
            CardEditorNativeInputFixture(kind: kind) {
                nativeInputKind = nil
            }
        }
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

private struct CardEditorNativeInputFixture: View {
    let kind: CardEditorNativeInputKind
    let onDone: () -> Void

    @State private var value = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField(
                    kind == .tag ? "Tag" : "Search linked notes",
                    text: $value
                )
                .focused($isFocused)
                .accessibilityIdentifier(
                    kind == .tag
                        ? "cardEditorNativeTagInput"
                        : "cardEditorNativeLinkInput"
                )
            }
            .navigationTitle(kind == .tag ? "Add Tag" : "Add Link")
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
        case .empty, .bridgeFailure:
            return []
        }
    }

    var fixtureLinks: [CardEditorLinkItem] {
        if self == .blocked {
            return [.init(id: "ast_blocked", title: "Preserved relation")]
        }
        guard self == .populated || self == .background || self == .keyboard else {
            return []
        }
        return [
            .init(id: "ast_fixture_a", title: "A"),
            .init(id: "ast_fixture_b", title: "B"),
            .init(id: "ast_fixture_c", title: "C", canRemove: false),
            .init(id: "ast_fixture_d", title: "D"),
            .init(id: "ast_fixture_e", title: "E"),
        ]
    }
}
#endif
