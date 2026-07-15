import BlockNoteEditor
import Combine
import SwiftUI
import UIKit

enum CardEditorBodyError: Error, Equatable {
    case compatibilityBlocked
    case unavailable
}

@MainActor
final class BlockNoteCardEditorModel: ObservableObject {
    static let compatibilityExplanation =
        "This note uses content this version of Chorai cannot safely edit. "
        + "It is read-only so nothing is lost."
    static let bridgeFailureExplanation =
        "Editing stopped because the editor could not continue safely. "
        + "Your most recent recovered draft is shown here."

    @Published private(set) var availability: BlockNoteEditorAvailability
    @Published private(set) var revision: Int
    @Published private(set) var contentJSON: String?
    @Published private(set) var fallbackMarkdown: String
    @Published private(set) var selectionState: BlockNoteSelectionState?
    @Published private(set) var contentHeight: CGFloat
    @Published private(set) var compatibilityNotice: String?
    @Published private(set) var bridgeFailureNotice: String?
    @Published private(set) var isBodyFocused: Bool

    private(set) var controller: BlockNoteEditorController
    private(set) var initialDocument: BlockNoteInitialDocument
    private(set) var editorInstanceID: UUID
    let isInitiallyEditable: Bool

    private let requestedInitialFocus: Bool
    private var didRequestInitialFocus = false
    private var sessionRevisionBase: Int
    private var latestSessionRevision = 0
    private let onDocumentChanged: (BlockNoteDocumentRevision) -> Void
    private let onCompatibilityBlocked: (String) -> Void
    private let onRequestCardLink: () -> Void
    private let onRequestInlineLink: () -> Void
    private let onRequestInlineImage: () -> Void

    init(
        document: BlockNoteInitialDocument,
        editable: Bool = true,
        initialRevision: Int = 0,
        initialContentHeight: CGFloat = 248,
        initialSelection: BlockNoteSelectionState? = nil,
        initiallyFocused: Bool = false,
        initialCompatibilityBlock: String? = nil,
        onDocumentChanged: @escaping (BlockNoteDocumentRevision) -> Void = { _ in },
        onCompatibilityBlocked: @escaping (String) -> Void = { _ in },
        onRequestCardLink: @escaping () -> Void = {},
        onRequestInlineLink: @escaping () -> Void = {},
        onRequestInlineImage: @escaping () -> Void = {}
    ) {
        controller = BlockNoteEditorController()
        initialDocument = document
        editorInstanceID = UUID()
        revision = max(0, initialRevision)
        sessionRevisionBase = max(0, initialRevision)
        contentJSON = document.contentJSON
        fallbackMarkdown = document.fallbackMarkdown
        selectionState = initialSelection
        contentHeight = max(248, initialContentHeight)
        requestedInitialFocus = initiallyFocused
        isBodyFocused = false
        compatibilityNotice = initialCompatibilityBlock.map { _ in
            Self.compatibilityExplanation
        }
        bridgeFailureNotice = nil
        isInitiallyEditable = editable && initialCompatibilityBlock == nil
        availability = initialCompatibilityBlock == nil
            ? .loading
            : .readOnly(reason: initialCompatibilityBlock ?? "compatibility_blocked")
        self.onDocumentChanged = onDocumentChanged
        self.onCompatibilityBlocked = onCompatibilityBlocked
        self.onRequestCardLink = onRequestCardLink
        self.onRequestInlineLink = onRequestInlineLink
        self.onRequestInlineImage = onRequestInlineImage
    }

    var renderedHeight: CGFloat {
        max(248, contentHeight)
    }

    var canMutate: Bool {
        guard compatibilityNotice == nil,
              bridgeFailureNotice == nil,
              isInitiallyEditable else { return false }
        return availability == .ready
    }

    var canSave: Bool {
        guard compatibilityNotice == nil,
              bridgeFailureNotice == nil,
              isInitiallyEditable else { return false }
        return availability == .ready
    }

    func receive(_ event: BlockNoteEditorEvent) {
        receive(event, from: editorInstanceID)
    }

    func receive(
        _ event: BlockNoteEditorEvent,
        from editorInstanceID: UUID
    ) {
        guard editorInstanceID == self.editorInstanceID else { return }

        switch event {
        case let .availabilityChanged(nextAvailability):
            if case let .failed(code) = nextAvailability {
                transitionToBridgeFailure(code: code)
                return
            }
            availability = nextAvailability
            if nextAvailability == .ready,
               requestedInitialFocus,
               !didRequestInitialFocus {
                didRequestInitialFocus = true
                focusBody()
            } else if nextAvailability != .ready {
                isBodyFocused = false
            }

        case let .documentChanged(document):
            guard document.revision >= latestSessionRevision else { return }
            latestSessionRevision = document.revision
            let rebasedDocument = BlockNoteDocumentRevision(
                revision: sessionRevisionBase + document.revision,
                contentJSON: document.contentJSON,
                fallbackMarkdown: document.fallbackMarkdown
            )
            guard rebasedDocument.revision >= revision else { return }
            revision = rebasedDocument.revision
            contentJSON = rebasedDocument.contentJSON
            fallbackMarkdown = rebasedDocument.fallbackMarkdown
            onDocumentChanged(rebasedDocument)

        case let .selectionChanged(selection):
            selectionState = selection

        case let .bodyFocusChanged(isFocused):
            isBodyFocused = canMutate && isFocused

        case let .heightChanged(height):
            guard height.isFinite else { return }
            contentHeight = max(248, CGFloat(height))

        case .requestCardLink:
            onRequestCardLink()

        case let .compatibilityBlocked(code, _):
            compatibilityNotice = Self.compatibilityExplanation
            availability = .readOnly(reason: code)
            isBodyFocused = false
            controller.blur()
            onCompatibilityBlocked(code)

        case let .bridgeError(code):
            switch code {
            case "read_only", "unexpected_card_link_request":
                isBodyFocused = false
            default:
                transitionToBridgeFailure(code: code)
            }
        }
    }

    func retryAfterBridgeFailure() {
        guard bridgeFailureNotice != nil,
              compatibilityNotice == nil,
              isInitiallyEditable else { return }

        availability = .loading
        selectionState = nil
        isBodyFocused = false
        didRequestInitialFocus = false
        sessionRevisionBase = revision
        latestSessionRevision = 0
        initialDocument = BlockNoteInitialDocument(
            contentJSON: contentJSON,
            fallbackMarkdown: fallbackMarkdown
        )
        controller = BlockNoteEditorController()
        editorInstanceID = UUID()
        bridgeFailureNotice = nil
    }

    func focusBody() {
        guard canMutate else { return }
        controller.focus()
    }

    func keyboardDidHide() {
        guard isBodyFocused else { return }
        isBodyFocused = false
        controller.blur()
    }

    func dismissKeyboard() {
        isBodyFocused = false
        controller.blur()
    }

    func canPerform(_ command: CardEditorFormattingCommand) -> Bool {
        guard canMutate else { return false }
        guard selectionState?.blockType == .unsupported else { return true }
        switch command {
        case .undo, .redo:
            return true
        default:
            return false
        }
    }

    func perform(_ command: CardEditorFormattingCommand) {
        guard canPerform(command) else { return }
        switch command {
        case .paragraph:
            controller.setBlockType(.paragraph)
        case .heading2:
            controller.setBlockType(.heading2)
        case .heading3:
            controller.setBlockType(.heading3)
        case .bold:
            controller.applyFormat(.bold)
        case .italic:
            controller.applyFormat(.italic)
        case .underline:
            controller.applyFormat(.underline)
        case .strike:
            controller.applyFormat(.strike)
        case .bulletList:
            controller.toggleList(.bullet)
        case .numberedList:
            controller.toggleList(.numbered)
        case .checklist:
            controller.toggleList(.checklist)
        case .inlineLink:
            onRequestInlineLink()
        case .inlineImage:
            onRequestInlineImage()
        case .undo:
            controller.undo()
        case .redo:
            controller.redo()
        }
    }

    func insertLink(url: String, text: String) {
        guard canPerform(.inlineLink) else { return }
        controller.insertLink(url: url, text: text)
    }

    func insertImage(url: String, alt: String) {
        guard canPerform(.inlineImage) else { return }
        controller.insertImage(url: url, alt: alt)
    }

    func requestSnapshot() async throws -> BlockNoteSnapshot {
        guard canSave else {
            if compatibilityNotice != nil {
                throw CardEditorBodyError.compatibilityBlocked
            }
            throw CardEditorBodyError.unavailable
        }
        let snapshot = try await controller.requestSnapshot()
        return BlockNoteSnapshot(
            requestID: snapshot.requestID,
            revision: sessionRevisionBase + snapshot.revision,
            contentJSON: snapshot.contentJSON,
            fallbackMarkdown: snapshot.fallbackMarkdown
        )
    }

    private func transitionToBridgeFailure(code: String) {
        guard compatibilityNotice == nil else { return }
        availability = .failed(code: code)
        bridgeFailureNotice = Self.bridgeFailureExplanation
        selectionState = nil
        isBodyFocused = false
        controller.blur()
    }
}

struct BlockNoteCardEditor: View {
    @ObservedObject var model: BlockNoteCardEditorModel

    var body: some View {
        Group {
            if let compatibilityNotice = model.compatibilityNotice {
                readOnlyFallback(compatibilityNotice)
            } else if let bridgeFailureNotice = model.bridgeFailureNotice {
                bridgeFailureFallback(bridgeFailureNotice)
            } else {
                editableBody
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification
            )
        ) { _ in
            model.keyboardDidHide()
        }
        .frame(minHeight: 248, alignment: .topLeading)
    }

    private var editableBody: some View {
        BlockNoteEditorView(
            document: model.initialDocument,
            editable: model.isInitiallyEditable,
            controller: model.controller,
            onEvent: { [editorInstanceID = model.editorInstanceID] event in
                model.receive(event, from: editorInstanceID)
            }
        )
        .id(model.editorInstanceID)
        .frame(height: model.renderedHeight)
        .simultaneousGesture(
            TapGesture().onEnded(model.focusBody)
        )
        .accessibilityIdentifier("cardEditorBodyWebView")
    }

    private func readOnlyFallback(_ compatibilityNotice: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.fallbackMarkdown)
                .font(.body)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
                .accessibilityIdentifier("cardEditorReadOnlyFallback")

            Spacer(minLength: 16)

            Label(compatibilityNotice, systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.76))
                .clipShape(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("cardEditorCompatibilityNotice")
        }
        .padding(10)
        .frame(minHeight: 248, alignment: .topLeading)
    }

    private func bridgeFailureFallback(
        _ bridgeFailureNotice: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.fallbackMarkdown)
                .font(.body)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
                .accessibilityIdentifier("cardEditorBridgeFailureFallback")

            Spacer(minLength: 16)

            VStack(alignment: .leading, spacing: 12) {
                Label(bridgeFailureNotice, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("cardEditorBridgeFailureNotice")

                Button(action: model.retryAfterBridgeFailure) {
                    Text("Retry editor")
                        .font(.body.weight(.semibold))
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 44,
                            alignment: .leading
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cardEditorBridgeRetry")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.76))
            .clipShape(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .padding(10)
        .frame(minHeight: 248, alignment: .topLeading)
    }
}
