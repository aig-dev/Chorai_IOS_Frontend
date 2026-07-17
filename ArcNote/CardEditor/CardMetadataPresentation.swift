import SwiftUI

private let maximumReadableTagWidth: CGFloat = 280

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
                    .font(.system(size: 10, weight: .semibold))
            }

            Text(tag)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)

            if showsRemoveIndicator {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: maximumReadableTagWidth)
        .background(
            Capsule(style: .continuous)
                .fill(Color(red: 0.2, green: 0.1, blue: 0.3))
        )
    }
}

struct CardMetadataRelatedRow: View {
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HTMLTextRenderer(
                    htmlContent: previewHTML ?? "",
                    maxLines: 2,
                    font: .system(size: 14, weight: .regular),
                    foregroundColor: .white.opacity(0.7)
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
