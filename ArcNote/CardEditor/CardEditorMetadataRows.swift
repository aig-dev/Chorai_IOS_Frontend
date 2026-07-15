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
    let onAdd: () -> Void
    let onRemove: (String) -> Void

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

                Button(action: onAdd) {
                    Label("Tag", systemImage: "plus")
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(
                            Capsule(style: .continuous)
                                .fill(ZenVisualTokens.accent.opacity(0.16))
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(
                                    ZenVisualTokens.accent.opacity(0.42),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(!isEditable)
                .accessibilityLabel("Add Tag")
                .accessibilityIdentifier("cardEditorAddTag")
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
