import SwiftUI

let cardMetadataMaximumReadableTagWidth: CGFloat = 280

struct CardMetadataTagCapsuleStyle: ViewModifier {
    let maximumWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .foregroundStyle(ChoraiTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: maximumWidth)
            .background(
                Capsule(style: .continuous)
                    .fill(ChoraiTheme.raisedSurface)
            )
    }
}

extension View {
    func cardMetadataTagCapsuleStyle(
        maximumWidth: CGFloat = cardMetadataMaximumReadableTagWidth
    ) -> some View {
        modifier(CardMetadataTagCapsuleStyle(maximumWidth: maximumWidth))
    }
}

struct CardMetadataTagCapsule: View {
    let tag: String
    let showsRemoveIndicator: Bool
    let leadingSystemImage: String?

    init(
        tag: String,
        showsRemoveIndicator: Bool,
        leadingSystemImage: String? = nil
    ) {
        self.tag = tag
        self.showsRemoveIndicator = showsRemoveIndicator
        self.leadingSystemImage = leadingSystemImage
    }

    var body: some View {
        HStack(spacing: 5) {
            if let leadingSystemImage {
                Image(systemName: leadingSystemImage)
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }

            Text(tag)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)

            if showsRemoveIndicator {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .cardMetadataTagCapsuleStyle()
    }
}

struct CardMetadataRelatedRow: View {
    let cardID: String
    let avatarURL: String?
    let title: String
    let previewHTML: String?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let resolvedAvatarURL {
                    AsyncImage(url: resolvedAvatarURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        fallbackAvatar
                    }
                } else {
                    fallbackAvatar
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title.isEmpty ? "Related note" : title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ChoraiTheme.ink)
                    .lineLimit(1)

                HTMLTextRenderer(
                    cardID: cardID,
                    htmlContent: previewHTML ?? "",
                    maxLines: 2,
                    font: .footnote,
                    foregroundColor: ChoraiTheme.secondaryInk
                )
            }

            Spacer()
        }
        .padding(.vertical, 16)
    }

    private var resolvedAvatarURL: URL? {
        guard let avatarURL,
              !avatarURL.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty else {
            return nil
        }
        return URL(
            string: APIConfiguration.resourceURLString(avatarURL)
        )
    }

    private var fallbackAvatar: some View {
        Image("avatar")
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
}
