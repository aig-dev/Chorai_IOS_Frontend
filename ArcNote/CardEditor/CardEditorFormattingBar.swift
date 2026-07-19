import BlockNoteEditor
import SwiftUI

enum CardEditorFormattingCommand: String, CaseIterable, Identifiable {
    case paragraph
    case heading2
    case heading3
    case bold
    case italic
    case underline
    case strike
    case bulletList
    case numberedList
    case checklist
    case inlineLink
    case inlineImage
    case undo
    case redo

    var id: String { rawValue }

    var accessibilityIdentifier: String {
        switch self {
        case .paragraph: return "cardEditorFormatParagraph"
        case .heading2: return "cardEditorFormatHeading2"
        case .heading3: return "cardEditorFormatHeading3"
        case .bold: return "cardEditorFormatBold"
        case .italic: return "cardEditorFormatItalic"
        case .underline: return "cardEditorFormatUnderline"
        case .strike: return "cardEditorFormatStrike"
        case .bulletList: return "cardEditorFormatBulletList"
        case .numberedList: return "cardEditorFormatNumberedList"
        case .checklist: return "cardEditorFormatChecklist"
        case .inlineLink: return "cardEditorFormatInlineLink"
        case .inlineImage: return "cardEditorFormatInlineImage"
        case .undo: return "cardEditorFormatUndo"
        case .redo: return "cardEditorFormatRedo"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .paragraph: return "Paragraph"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        case .strike: return "Strikethrough"
        case .bulletList: return "Bulleted list"
        case .numberedList: return "Numbered list"
        case .checklist: return "Checklist"
        case .inlineLink: return "Insert inline link"
        case .inlineImage: return "Insert inline image"
        case .undo: return "Undo"
        case .redo: return "Redo"
        }
    }

    var symbol: String {
        switch self {
        case .paragraph: return "textformat"
        case .heading2: return "2.square"
        case .heading3: return "3.square"
        case .bold: return "bold"
        case .italic: return "italic"
        case .underline: return "underline"
        case .strike: return "strikethrough"
        case .bulletList: return "list.bullet"
        case .numberedList: return "list.number"
        case .checklist: return "checklist"
        case .inlineLink: return "link"
        case .inlineImage: return "photo"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        }
    }
}

struct CardEditorFormattingBar: View {
    @ObservedObject var model: BlockNoteCardEditorModel
    let isTagEntryEnabled: Bool
    let onBeginTag: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: model.dismissKeyboard) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 45, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel("Dismiss keyboard")
            .accessibilityIdentifier("cardEditorKeyboardDismiss")

            Button(action: onBeginTag) {
                Image(systemName: "tag")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 45, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(!isTagEntryEnabled)
            .accessibilityLabel("Add Tag")
            .accessibilityHint("Adds a tag to this note")
            .accessibilityIdentifier("cardEditorAddTag")

            Divider()
                .overlay(Color.white.opacity(0.18))
                .frame(height: 28)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(CardEditorFormattingCommand.allCases) { command in
                        commandButton(command)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            CardEditorGlassSurface(
                shape: Rectangle(),
                style: .chrome
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cardEditorFormattingBar")
    }

    private func commandButton(
        _ command: CardEditorFormattingCommand
    ) -> some View {
        let selected = isSelected(command)
        return Button {
            model.perform(command)
        } label: {
            Image(systemName: command.symbol)
                .font(.body.weight(.semibold))
                .frame(minWidth: 45, minHeight: 44)
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            selected
                                ? ZenVisualTokens.accent.opacity(0.34)
                                : Color.clear
                        )
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .white : .white.opacity(0.74))
        .disabled(!model.canPerform(command))
        .accessibilityLabel(command.accessibilityLabel)
        .accessibilityValue(selected ? "selected" : "not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(command.accessibilityIdentifier)
    }

    private func isSelected(_ command: CardEditorFormattingCommand) -> Bool {
        guard let selection = model.selectionState else { return false }
        switch command {
        case .paragraph:
            return selection.blockType == .paragraph
        case .heading2:
            return selection.blockType == .heading2
        case .heading3:
            return selection.blockType == .heading3
        case .bold:
            return selection.formats.bold
        case .italic:
            return selection.formats.italic
        case .underline:
            return selection.formats.underline
        case .strike:
            return selection.formats.strike
        case .bulletList:
            return selection.blockType == .bullet
        case .numberedList:
            return selection.blockType == .numbered
        case .checklist:
            return selection.blockType == .checklist
        case .inlineLink, .inlineImage, .undo, .redo:
            return false
        }
    }
}
