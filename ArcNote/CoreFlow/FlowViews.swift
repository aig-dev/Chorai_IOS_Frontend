import CoreFlow
import SwiftUI
import UIKit

enum ZenVisualTokens {
    static let pageInset: CGFloat = 20
    static let cardRadius: CGFloat = 28
    static let tabHeight: CGFloat = 72
    static let transitionDuration = 0.28
    static let background = Color(red: 0.045, green: 0.035, blue: 0.09)
    static let accent = Color(red: 0.69, green: 0.58, blue: 1.0)
    static let cardFill = Color.white.opacity(0.07)
    static let cardBorder = Color.white.opacity(0.14)
}

enum FlowTextPreview {
    private static let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 200
        return cache
    }()

    static func make(_ source: String) -> String {
        let key = source as NSString
        if let cached = cache.object(forKey: key) {
            return cached as String
        }

        // NSAttributedString's HTML importer enters WebKit's run loop. Calling
        // it from a SwiftUI body can recursively re-enter layout while a card
        // is being replaced, so previews deliberately use a pure transform.
        let decoded = source
            .replacingOccurrences(
                of: "(?is)<(script|style)[^>]*>.*?</\\1>",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "(?i)<br\\s*/?>|</p\\s*>|</div\\s*>|</li\\s*>",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "<[^>]+>",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")

        let preview = decoded
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cache.setObject(preview as NSString, forKey: key)
        return preview
    }
}

struct FlowCardView: View {
    let card: FlowCard
    let isInteractionLocked: Bool
    let isLikeMutationInFlight: Bool
    let likeErrorMessage: String?
    let onOpenDetail: () -> Void
    let onOpenAuthor: () -> Void
    let onOpenMenu: () -> Void
    let onToggleFavorite: () -> Void
    let onSpark: () -> Void
    let onDismiss: () -> Void
    let onToggleLike: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var dragOffset: CGSize = .zero
    @State private var isResolvingSwipe = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button(action: onOpenAuthor) {
                    HStack(spacing: 8) {
                        authorAvatar
                        Text(card.author?.username ?? "Chorai")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open author")
                .disabled(card.author == nil)

                Spacer()

                HStack(spacing: 2) {
                    Button(action: onOpenMenu) {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More actions")
                    .accessibilityIdentifier("flow.menu.\(card.id)")

                    Button(action: onSpark) {
                        Image("menu_spark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Spark")
                    .accessibilityIdentifier("flow.spark.\(card.id)")
                }
            }

            Text(FlowTextPreview.make(card.content))
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .lineSpacing(5)
                .lineLimit(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpenDetail)
                .gesture(cardDragGesture)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Open card")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("flow.card.\(card.id)")
                .accessibilityAction { onOpenDetail() }

            if !card.tags.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(card.tags.prefix(3)), id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 28)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(action: onToggleFavorite) {
                    engagementMetric(
                        image: card.isFavorited ? "favorite_active" : "favorite",
                        count: card.favoriteCount,
                        iconSize: 24
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(card.isFavorited ? "Unfavorite" : "Favorite")
                .accessibilityValue(card.isFavorited ? "true" : "false")
                .accessibilityIdentifier("flow.favorite.\(card.id)")

                Spacer(minLength: 16)

                Button(action: onToggleLike) {
                    engagementMetric(
                        image: card.isLiked ? "like_active" : "like",
                        count: card.likeCount
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLikeMutationInFlight)
                .accessibilityLabel(card.isLiked ? "Unlike" : "Like")
                .accessibilityValue(card.isLiked ? "true" : "false")
                .accessibilityIdentifier("flow.like.\(card.id)")

                CommentButton(cardId: card.id, commentCount: card.commentCount, iconSize: 22)
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Comments")
                    .accessibilityValue("\(card.commentCount)")
                    .accessibilityIdentifier("flow.comment.\(card.id)")
            }
            .padding(.bottom, -18)
            .foregroundStyle(Color.white.opacity(0.58))

            if let likeErrorMessage {
                Text(likeErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .accessibilityIdentifier("flow.like.error.\(card.id)")
            }

        }
        .padding(22)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
        .contentShape(RoundedRectangle(cornerRadius: ZenVisualTokens.cardRadius, style: .continuous))
        .offset(x: dragOffset.width)
        .rotationEffect(reduceMotion ? .zero : .degrees(Double(dragOffset.width / 34)))
        .disabled(isInteractionLocked || isResolvingSwipe)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: ZenVisualTokens.cardRadius, style: .continuous)
            .fill(
                reduceTransparency
                    ? Color(red: 0.09, green: 0.075, blue: 0.15)
                    : ZenVisualTokens.cardFill
            )
            .overlay(
                RoundedRectangle(cornerRadius: ZenVisualTokens.cardRadius, style: .continuous)
                    .stroke(
                        contrast == .increased
                            ? Color.white.opacity(0.42)
                            : ZenVisualTokens.cardBorder,
                        lineWidth: 1
                    )
            )
    }

    private var resolvedAvatarURL: URL? {
        guard let candidate = card.author?.avatarURL else { return nil }
        let rawURL = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawURL.isEmpty else { return nil }

        return URL(string: APIConfiguration.resourceURLString(rawURL))
    }

    @ViewBuilder
    private var authorAvatar: some View {
        Group {
            if let resolvedAvatarURL {
                AsyncImage(url: resolvedAvatarURL) { phase in
                    switch phase {
                    case .empty:
                        avatarPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        avatarPlaceholder
                    @unknown default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.white.opacity(0.1))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.72))
            )
    }

    private func engagementMetric(
        image: String,
        count: Int,
        iconSize: CGFloat = 22
    ) -> some View {
        HStack(spacing: 6) {
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
            Text("\(count)")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }

    private var cardDragGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard !isInteractionLocked, !isResolvingSwipe else { return }
                dragOffset = CGSize(
                    width: value.translation.width,
                    height: value.translation.height * 0.08
                )
            }
            .onEnded { value in
                resolveSwipe(
                    FlowSwipeResolver.resolve(
                        translation: Double(value.translation.width),
                        predictedEndTranslation: Double(value.predictedEndTranslation.width)
                    )
                )
            }
    }

    private func resolveSwipe(_ decision: FlowSwipeDecision) {
        guard decision != .cancel else {
            withAnimation(.spring(response: ZenVisualTokens.transitionDuration, dampingFraction: 0.86)) {
                dragOffset = .zero
            }
            return
        }
        guard !isResolvingSwipe else { return }

        isResolvingSwipe = true
        let advancesRight = decision == .advanceRight
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        guard !reduceMotion else {
            dragOffset = .zero
            isResolvingSwipe = false
            onDismiss()
            return
        }

        withAnimation(.spring(response: ZenVisualTokens.transitionDuration, dampingFraction: 0.86)) {
            dragOffset.width = advancesRight ? 620 : -620
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ZenVisualTokens.transitionDuration) {
            dragOffset = .zero
            isResolvingSwipe = false
            onDismiss()
        }
    }
}

struct FlowDeckView: View {
    @ObservedObject var store: FlowDeckStore
    @StateObject private var likeStore = CardLikeStore(
        state: CardLikeState(cardID: "", isLiked: false, likeCount: 0),
        service: NetworkCoreCardLikeService(),
        onCommit: CardEngagementCenter.shared.publish
    )
    let onOpenDetail: (FlowCard) -> Void
    let onOpenAuthor: (FlowCard) -> Void
    let onOpenMenu: (FlowCard) -> Void
    let onSpark: (FlowCard) -> Void
    let onCardVisible: (FlowCard) -> Void
    let onCardSaved: (String) -> Void
    let onCardDismissed: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Group {
                switch store.phase {
                case .idle, .loading:
                    FlowSkeletonView()
                        .accessibilityIdentifier("screen.flow.loading")
                case .loaded:
                    loadedDeck
                case .empty:
                    FlowStateView(
                        title: "You're caught up",
                        message: "Refresh when you want another thread to follow.",
                        button: "Refresh",
                        action: store.refresh
                    )
                    .accessibilityIdentifier("screen.flow.empty")
                case .failed(let message):
                    FlowStateView(
                        title: "Flow paused",
                        message: message,
                        button: "Retry",
                        action: store.refresh
                    )
                    .accessibilityIdentifier("screen.flow.error")
                }
            }

            noticeView

            if store.phase == .loaded {
                Text("Flow loaded")
                    .font(.system(size: 1))
                    .foregroundStyle(Color.white.opacity(0.01))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("screen.flow.loaded")
            }

            if let card = store.currentCard {
                Text(card.id)
                    .font(.system(size: 1))
                    .foregroundStyle(Color.white.opacity(0.01))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("flow.visible-card.id")
                Text("\(card.likeCount)")
                    .font(.system(size: 1))
                    .foregroundStyle(Color.white.opacity(0.01))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("flow.like.count.\(card.id)")
                Text("\(card.favoriteCount)")
                    .font(.system(size: 1))
                    .foregroundStyle(Color.white.opacity(0.01))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("flow.favorite.count.\(card.id)")
            }
        }
        .task { store.loadInitialIfNeeded() }
        .onChange(of: store.currentCard?.id) { _ in
            if let card = store.currentCard {
                likeStore.hydrate(
                    CardLikeState(
                        cardID: card.id,
                        isLiked: card.isLiked,
                        likeCount: card.likeCount
                    )
                )
                onCardVisible(card)
            }
        }
        .onReceive(CardEngagementCenter.shared.likes) { state in
            store.applyLikeState(state)
            likeStore.applyCommitted(state)
        }
    }

    @ViewBuilder
    private var loadedDeck: some View {
        if let card = store.currentCard {
            ZStack {
                if store.nextCard != nil {
                    RoundedRectangle(cornerRadius: ZenVisualTokens.cardRadius, style: .continuous)
                        .fill(ZenVisualTokens.cardFill.opacity(0.7))
                        .offset(y: 12)
                        .scaleEffect(0.965)
                        .accessibilityHidden(true)
                }

                FlowCardView(
                    card: card,
                    isInteractionLocked: store.isInteractionLocked,
                    isLikeMutationInFlight: likeStore.isMutating,
                    likeErrorMessage: likeErrorMessage(for: card.id),
                    onOpenDetail: { onOpenDetail(card) },
                    onOpenAuthor: { onOpenAuthor(card) },
                    onOpenMenu: { onOpenMenu(card) },
                    onToggleFavorite: {
                        store.toggleFavoriteCurrent(
                            onFavoriteSucceeded: onCardSaved
                        )
                    },
                    onSpark: { onSpark(card) },
                    onDismiss: {
                        let assetID = card.id
                        store.dismissCurrent()
                        onCardDismissed(assetID)
                    },
                    onToggleLike: likeStore.toggle
                )
                .id(card.id)
            }
        } else {
            FlowStateView(
                title: "You're caught up",
                message: "Refresh to continue.",
                button: "Refresh",
                action: store.refresh
            )
        }
    }

    private func likeErrorMessage(for cardID: String) -> String? {
        guard likeStore.state.cardID == cardID,
              case .failed = likeStore.phase else {
            return nil
        }
        return "Like failed. Try again."
    }

    @ViewBuilder
    private var noticeView: some View {
        switch store.notice {
        case .favoriteFailed:
            Text("Favorite failed. Try again.")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.72))
                .accessibilityIdentifier("flow.favorite.error")
        case nil:
            EmptyView()
        }
    }
}

private struct FlowSkeletonView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: ZenVisualTokens.cardRadius, style: .continuous)
            .fill(ZenVisualTokens.cardFill)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 14) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(width: 112, height: 14)
                    Capsule().fill(Color.white.opacity(0.1)).frame(height: 22)
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 14)
                    Capsule().fill(Color.white.opacity(0.08)).frame(width: 210, height: 14)
                }
                .padding(22)
            }
    }
}

private struct FlowStateView: View {
    let title: String
    let message: String
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .foregroundStyle(Color.white.opacity(0.62))
                .multilineTextAlignment(.center)
            Button(button, action: action)
                .buttonStyle(.borderedProminent)
                .tint(ZenVisualTokens.accent)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
