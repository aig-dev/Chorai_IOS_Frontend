import SwiftUI

struct CardEditorLinkItem: Identifiable, Equatable {
    let id: String
    let title: String
    let canRemove: Bool

    init(id: String, title: String, canRemove: Bool = true) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.canRemove = canRemove
    }
}

struct CardEditorTagRow: View {
    let tags: [String]
    let isEditable: Bool
    let onAdd: () -> Void
    let onRemove: (String) -> Void

    var body: some View {
        CardEditorFlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    onRemove(tag)
                } label: {
                    HStack(spacing: 5) {
                        Text("#\(tag)")
                            .lineLimit(1)
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(
                        Capsule(style: .continuous)
                            .fill(ZenVisualTokens.cardFill)
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(ZenVisualTokens.cardBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.9))
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
    }
}

struct CardEditorLinkRow: View {
    let links: [CardEditorLinkItem]
    let isEditable: Bool
    let onOpen: () -> Void
    let onAdd: () -> Void

    private var visibleLinks: [CardEditorLinkItem] {
        Array(links.prefix(2))
    }

    var body: some View {
        CardEditorFlowLayout(spacing: 8) {
            ForEach(visibleLinks) { link in
                Button(action: onOpen) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.caption.weight(.semibold))
                        Text(link.title.isEmpty ? "Linked note" : link.title)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(
                        Capsule(style: .continuous)
                            .fill(ZenVisualTokens.cardFill)
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(ZenVisualTokens.cardBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityLabel("Open linked note \(link.title)")
                .accessibilityIdentifier(
                    "cardEditorLink.\(accessibilityComponent(link.id))"
                )
            }

            if links.count > 2 {
                Button(action: onOpen) {
                    Text("+\(links.count - 2)")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .background(
                            Circle()
                                .fill(ZenVisualTokens.cardFill)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityLabel("+\(links.count - 2)")
                .accessibilityHint("\(links.count - 2) more linked notes")
                .accessibilityIdentifier("cardEditorLinkOverflow")
            }

            Button(action: onAdd) {
                Label("Add Link", systemImage: "plus")
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
            .accessibilityLabel("Add Link")
            .accessibilityIdentifier("cardEditorAddLink")
        }
    }
}

struct CardEditorLinkManagementSheet: View {
    @Environment(\.dismiss) private var dismiss

    let links: [CardEditorLinkItem]
    let isEditable: Bool
    let onRemove: (CardEditorLinkItem) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if links.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "link")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No linked notes")
                            .font(.headline)
                        Text("Add a link from the note editor.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                } else {
                    List(links) { link in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(ZenVisualTokens.accent)
                            Text(link.title.isEmpty ? "Linked note" : link.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if link.canRemove && isEditable {
                                Button(role: .destructive) {
                                    onRemove(link)
                                } label: {
                                    Image(systemName: "xmark")
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .accessibilityLabel("Remove link \(link.title)")
                                .accessibilityIdentifier(
                                    "cardEditorRemoveLink.\(accessibilityComponent(link.id))"
                                )
                            } else {
                                Image(systemName: "lock")
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel(isEditable
                                        ? "Link \(link.title) cannot be removed here"
                                        : "Link \(link.title) is read only"
                                    )
                                    .accessibilityIdentifier(
                                        isEditable
                                            ? "cardEditorNonRemovableLink.\(accessibilityComponent(link.id))"
                                            : "cardEditorReadOnlyLink.\(accessibilityComponent(link.id))"
                                    )
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .overlay(alignment: .topLeading) {
            Color.white
                .opacity(0.001)
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Link management")
                .accessibilityIdentifier("cardEditorLinksSheet")
                .allowsHitTesting(false)
        }
    }
}

private struct CardEditorFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width ?? .greatestFiniteMagnitude
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0
        var measuredHeight: CGFloat = 0

        for subview in subviews {
            let size = constrainedSize(
                for: subview,
                availableWidth: availableWidth
            )
            let candidateWidth = lineWidth == 0
                ? size.width
                : lineWidth + spacing + size.width
            if lineWidth > 0, candidateWidth > availableWidth {
                measuredWidth = max(measuredWidth, lineWidth)
                measuredHeight += lineHeight + spacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth = candidateWidth
                lineHeight = max(lineHeight, size.height)
            }
        }

        measuredWidth = max(measuredWidth, lineWidth)
        measuredHeight += lineHeight
        return CGSize(
            width: proposal.width ?? measuredWidth,
            height: measuredHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = constrainedSize(
                for: subview,
                availableWidth: bounds.width
            )
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    private func constrainedSize(
        for subview: LayoutSubview,
        availableWidth: CGFloat
    ) -> CGSize {
        let measured = subview.sizeThatFits(
            ProposedViewSize(width: availableWidth, height: nil)
        )
        return CGSize(
            width: min(measured.width, availableWidth),
            height: measured.height
        )
    }
}

private func accessibilityComponent(_ source: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let scalars = source.unicodeScalars.map { scalar -> Character in
        allowed.contains(scalar) ? Character(String(scalar)) : "-"
    }
    return String(scalars)
}
