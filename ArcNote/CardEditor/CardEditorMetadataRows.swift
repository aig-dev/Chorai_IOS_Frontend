import CoreFlow
import SwiftUI

struct CardEditorLinkItem: Identifiable, Equatable {
    let id: String
    let title: String
    let previewHTML: String?
    let avatarURL: String?

    init(
        id: String,
        title: String,
        previewHTML: String? = nil,
        avatarURL: String? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.previewHTML = previewHTML
        self.avatarURL = avatarURL
    }
}

struct CardEditorTagRow: View {
    let tags: [String]
    let isEditable: Bool
    let isAddingTag: Bool
    @Binding var tagInput: String
    let onBeginTag: () -> Void
    let onCompleteTag: () -> Void
    let onRemove: (String) -> Void

    @FocusState private var isTagInputFocused: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Button {
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
                    TextField("Tag", text: $tagInput)
                        .font(.system(size: 12, weight: .medium))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isTagInputFocused)
                        .onSubmit(onCompleteTag)
                        .onChange(of: isTagInputFocused) { isFocused in
                            guard !isFocused, isAddingTag else { return }
                            onCompleteTag()
                        }
                        .frame(width: 96)
                        .cardMetadataTagCapsuleStyle(maximumWidth: 120)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Tag")
                        .accessibilityIdentifier("cardEditorTagInput")
                        .onAppear {
                            DispatchQueue.main.async {
                                isTagInputFocused = true
                            }
                        }
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
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

struct CardEditorLinkRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let links: [CardEditorLinkItem]

    @State private var isExpanded = false

    var body: some View {
        if !links.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
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
                            CardMetadataRelatedRow(
                                avatarURL: link.avatarURL,
                                title: link.title,
                                previewHTML: link.previewHTML
                            )
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier(
                                "cardEditorLink.\(accessibilityComponent(link.id))"
                            )

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
