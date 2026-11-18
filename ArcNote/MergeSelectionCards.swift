import SwiftUI
import CoreFlow

// MARK: - Merge Card Data Model
struct MergeCard: Identifiable {
    let id: String
    let versionID: String?
    let date: String
    let content: String
    let contentJSON: String?
    let backgroundMediaRef: String?
    let tags: [String]
    let isUserCard: Bool
    let userName: String?
    let avatarUrl: String?
    let favoriteCount: Int
    let rate: Int

    init(
        id: String,
        versionID: String? = nil,
        date: String,
        content: String,
        contentJSON: String? = nil,
        backgroundMediaRef: String? = nil,
        tags: [String],
        isUserCard: Bool,
        userName: String? = nil,
        avatarUrl: String? = nil,
        favoriteCount: Int = 0,
        rate: Int = 1
    ) {
        self.id = id
        self.versionID = versionID
        self.date = date
        self.content = content
        self.contentJSON = contentJSON
        self.backgroundMediaRef = backgroundMediaRef
        self.tags = tags
        self.isUserCard = isUserCard
        self.userName = userName
        self.avatarUrl = avatarUrl
        self.favoriteCount = favoriteCount
        self.rate = rate
    }
}

// MARK: - Merge Card View
struct MergeCardView: View {
    let card: MergeCard
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let isSelectable: Bool

    init(
        card: MergeCard,
        isSelected: Bool,
        onToggleSelection: @escaping () -> Void,
        isSelectable: Bool = true
    ) {
        self.card = card
        self.isSelected = isSelected
        self.onToggleSelection = onToggleSelection
        self.isSelectable = isSelectable
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: isSelectable ? (isSelected ? "checkmark.circle.fill" : "circle") : "lock.fill")
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(isSelected || !isSelectable ? ChoraiTheme.accent : ChoraiTheme.secondaryInk)
                .frame(width: 28, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 9) {
                LibraryCardContentPreview(
                    content: card.content,
                    contentJSON: card.contentJSON,
                    cardID: card.id,
                    textFont: .system(.body, design: .serif)
                )
                HStack(spacing: 6) {
                    Text(isSelectable ? (card.isUserCard ? (card.userName ?? "Chorai") + " · Collected" : "You · My note") : "Fixed source · " + (card.isUserCard ? (card.userName ?? "Chorai") : "You"))
                        .font(.caption)
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    ChoraiLevelBadge(rate: card.rate, compact: true)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background {
            LibraryCardBackgroundSurface(
                backgroundMediaRef: card.backgroundMediaRef,
                rate: card.rate
            ) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected || !isSelectable ? ChoraiTheme.selection : ChoraiTheme.surface)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected || !isSelectable ? ChoraiTheme.accent.opacity(0.35) : ChoraiTheme.separator, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 22)
        .onTapGesture {
            guard isSelectable else { return }
            onToggleSelection()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("merge.card.\(card.id)")
        .accessibilityValue(isSelectable ? (isSelected ? "selected" : "unselected") : "")
        .accessibilityAddTraits(isSelectable ? .isButton : [])
        .accessibilityAction {
            guard isSelectable else { return }
            onToggleSelection()
        }
    }

    private var mergeCardAvatar: some View {
        Group {
            if let avatarURL = avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image("avatar")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } else {
                Image("avatar")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private var avatarURL: URL? {
        guard let avatarURL = card.avatarUrl?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !avatarURL.isEmpty else {
            return nil
        }
        if avatarURL.hasPrefix("http://") || avatarURL.hasPrefix("https://") {
            return URL(string: avatarURL)
        }
        return URL(string: APIConfiguration.resourceURLString(avatarURL))
    }

    private var hasCustomBackground: Bool {
        guard let backgroundMediaRef = card.backgroundMediaRef else {
            return false
        }
        return !backgroundMediaRef.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    private var mergeCardTagBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                (hasCustomBackground ? ChoraiTheme.background : ChoraiTheme.raisedSurface)
                    .opacity(
                        LibraryCardReadabilityPolicy.tagSurfaceOpacity(
                            hasBackground: hasCustomBackground
                        )
                    )
            )
            .overlay(mergeCardTagTopLeftHighlight)
            .overlay(mergeCardTagBottomRightHighlight)
            .overlay(mergeCardTagTopEdgeHighlight)
            .overlay(mergeCardTagBottomEdgeHighlight)
    }

    private var mergeCardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.clear)
            .background(.ultraThinMaterial.opacity(0.55))
            .cornerRadius(16)
            .overlay(topLeftHighlight)
            .overlay(bottomRightHighlight)
            .overlay(topEdgeHighlight)
            .overlay(bottomEdgeHighlight)
    }

    // MARK: 标签高光效果
    private var mergeCardTagTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            center: .topLeading,
                            startRadius: 5,
                            endRadius: 15
                        )
                    )
            )
    }

    private var mergeCardTagBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 5,
                            endRadius: 15
                        )
                    )
            )
    }

    private var mergeCardTagTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }

    private var mergeCardTagBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }

    // MARK: 高光效果
    private var topLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }

    private var bottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }

    private var topEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }

    private var bottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(ChoraiTheme.ink, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [ChoraiTheme.ink, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
}

// MARK: 固定卡片视图
struct FixedMergeCardView: View {
    let card: MergeCard

    var body: some View {
        MergeCardView(
            card: card,
            isSelected: false,
            onToggleSelection: {},
            isSelectable: false
        )
    }
}


#Preview {
    MergeView(cardId: "ast_preview")
}
