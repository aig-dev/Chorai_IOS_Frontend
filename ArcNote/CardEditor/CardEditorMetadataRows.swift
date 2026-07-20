import CoreFlow
import SwiftUI

struct CardEditorLinkItem: Identifiable, Equatable {
    let id: String
    let sourceCardID: String
    let targetCardID: String
    let title: String
    let previewHTML: String?
    let avatarURL: String?
    let canRemove: Bool

    init(
        sourceCardID: String,
        targetCardID: String,
        title: String,
        previewHTML: String? = nil,
        avatarURL: String? = nil,
        canRemove: Bool = false
    ) {
        self.id = "\(sourceCardID)->\(targetCardID)"
        self.sourceCardID = sourceCardID
        self.targetCardID = targetCardID
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.previewHTML = previewHTML
        self.avatarURL = avatarURL
        self.canRemove = canRemove
    }
}

struct CardEditorTagRow: View {
    let tags: [String]
    let isEditable: Bool
    let isAddingTag: Bool
    let prefersKeyboardTagAction: Bool
    @Binding var tagInput: String
    let isTagInputFocused: FocusState<Bool>.Binding
    let onBeginTag: () -> Void
    let onCompleteTag: () -> Void
    let onInteraction: () -> Void
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        onInteraction()
                        onRemove(tag)
                    } label: {
                        CardMetadataTagCapsule(
                            tag: tag,
                            showsRemoveIndicator: true
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .disabled(!isEditable)
                    .accessibilityLabel(
                        isEditable ? "Remove tag \(tag)" : "Tag \(tag)"
                    )
                    .accessibilityIdentifier(
                        "cardEditorTag.\(accessibilityComponent(tag))"
                    )
                }

                if isAddingTag {
                    CardEditorTagInput(
                        tagInput: $tagInput,
                        isTagInputFocused: isTagInputFocused,
                        onComplete: onCompleteTag
                    )
                } else {
                    Button(action: onBeginTag) {
                        CardMetadataTagCapsule(
                            tag: "Tag",
                            showsRemoveIndicator: false,
                            leadingSystemImage: "plus"
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .disabled(
                        !isEditable || tags.count >= CardEditingTag.maximumCount
                    )
                    .accessibilityLabel("Add Tag")
                    .accessibilityHint("Adds a tag to this note")
                    .accessibilityIdentifier("cardEditorAddTag")
                    .accessibilityHidden(prefersKeyboardTagAction)
                    .allowsHitTesting(!prefersKeyboardTagAction)
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

private struct CardEditorTagInput: View {
    @Binding var tagInput: String
    let isTagInputFocused: FocusState<Bool>.Binding
    let onComplete: () -> Void

    @State private var didAcquireFocus = false

    var body: some View {
        TextField("Tag", text: $tagInput)
            .font(.caption.weight(.medium))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused(isTagInputFocused)
            .onSubmit(onComplete)
            .onChange(of: isTagInputFocused.wrappedValue) { isFocused in
                if isFocused {
                    didAcquireFocus = true
                    return
                }
                guard didAcquireFocus else { return }
                didAcquireFocus = false
                onComplete()
            }
            .frame(width: 96)
            .cardMetadataTagCapsuleStyle(maximumWidth: 120)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Tag")
            .accessibilityIdentifier("cardEditorTagInput")
            .accessibilityAction(named: Text("Finish Editing")) {
                onComplete()
            }
            .task {
                await Task.yield()
                isTagInputFocused.wrappedValue = true
            }
    }
}

struct CardEditorLinkRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let links: [CardEditorLinkItem]
    let unlinkingLinkID: String?
    let isRemovalEnabled: Bool
    let onInteraction: () -> Void
    let onRemove: (CardEditorLinkItem) -> Void

    @State private var isExpanded = false

    var body: some View {
        if !links.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        onInteraction()
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(
                            systemName: isExpanded
                                ? "chevron.up"
                                : "chevron.down"
                        )
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Related notes")
                    .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                    .accessibilityIdentifier("cardEditorLinksDisclosure")
                }

                if isExpanded {
                    VStack(spacing: 0) {
                        ForEach(Array(links.enumerated()), id: \.element.id) {
                            index, link in
                            HStack(spacing: 4) {
                                CardMetadataRelatedRow(
                                    avatarURL: link.avatarURL,
                                    title: link.title,
                                    previewHTML: link.previewHTML
                                )
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier(
                                    "cardEditorLink.\(accessibilityComponent(link.id))"
                                )

                                if link.canRemove {
                                    if unlinkingLinkID == link.id {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(.white.opacity(0.7))
                                            .frame(width: 44, height: 44)
                                            .accessibilityLabel(
                                                "Unlinking \(link.title)"
                                            )
                                            .accessibilityIdentifier(
                                                "cardEditorRemoveLink.\(accessibilityComponent(link.id))"
                                            )
                                    } else {
                                        Button {
                                            onInteraction()
                                            onRemove(link)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(
                                                    .system(
                                                        size: 13,
                                                        weight: .semibold
                                                    )
                                                )
                                                .foregroundStyle(
                                                    .white.opacity(0.7)
                                                )
                                                .frame(width: 44, height: 44)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(!isRemovalEnabled)
                                        .accessibilityLabel("Unlink \(link.title)")
                                        .accessibilityHint("Removes this link without deleting either note")
                                        .accessibilityIdentifier(
                                            "cardEditorRemoveLink.\(accessibilityComponent(link.id))"
                                        )
                                    }
                                }
                            }

                            if index < links.count - 1 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 1)
                            }
                        }
                    }
                    .transition(
                        .opacity.combined(with: .move(edge: .top))
                    )
                }
            }
        }
    }
}

private func accessibilityComponent(_ source: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "-_")
    )
    let scalars = source.unicodeScalars.map { scalar -> Character in
        allowed.contains(scalar) ? Character(String(scalar)) : "-"
    }
    return String(scalars)
}
