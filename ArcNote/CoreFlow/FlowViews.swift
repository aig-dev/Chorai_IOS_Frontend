import CoreFlow
import SwiftUI
import UIKit

enum ZenVisualTokens {
    static let pageInset: CGFloat = 20
    static let cardRadius: CGFloat = 28
    static let tabHeight: CGFloat = 72
    static let transitionDuration = 0.28
    static let background = ChoraiTheme.background
    static let accent = ChoraiTheme.accent
    static let cardFill = ChoraiTheme.surface
    static let cardBorder = ChoraiTheme.separator
    static let opaqueCardFill = ChoraiTheme.surface
    static let glassTint = ChoraiTheme.raisedSurface
}

private enum FlowGlassLayer {
    case foreground
    case rear(depth: Int)

    var tintOpacity: Double {
        switch self {
        case .foreground:
            return 0.64
        case .rear(let depth):
            return depth == 1 ? 0.72 : 0.78
        }
    }

    var edgeOpacity: Double {
        switch self {
        case .foreground:
            return 0.46
        case .rear(let depth):
            return depth == 1 ? 0.28 : 0.2
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .foreground:
            return 0.3
        case .rear(let depth):
            return depth == 1 ? 0.2 : 0.14
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .foreground:
            return 18
        case .rear(let depth):
            return depth == 1 ? 14 : 10
        }
    }

    var shadowY: CGFloat {
        switch self {
        case .foreground:
            return 10
        case .rear(let depth):
            return depth == 1 ? 8 : 6
        }
    }
}

private struct FlowGlassSurface: View {
    let layer: FlowGlassLayer

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    private var shadowOpacity: Double {
        guard !reduceTransparency, case .foreground = layer else { return 0 }
        return scheme == .dark ? 0.1 : 0.025
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: ZenVisualTokens.cardRadius,
            style: .continuous
        )
    }

    var body: some View {
        shape.fill(ZenVisualTokens.opaqueCardFill)
            .overlay(shape.strokeBorder(ChoraiTheme.separator, lineWidth: contrast == .increased ? 1.5 : 0.7))
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 16, y: 6)
    }

}

private struct FlowDeckBackplate: View {
    let depth: Int

    var body: some View {
        FlowGlassSurface(layer: .rear(depth: depth))
            .padding(.horizontal, depth == 1 ? 6 : 12)
            .offset(y: depth == 1 ? 6 : 12)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
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

private struct FlowSparkButtonStyle: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass).tint(ChoraiTheme.gold)
        } else {
            content.buttonStyle(.bordered).tint(ChoraiTheme.gold)
        }
    }
}

struct FlowCardView: View {
    let card: FlowCard
    let isLikeMutationInFlight: Bool
    let isFavoritePending: Bool
    let hasFavoriteError: Bool
    let likeErrorMessage: String?
    let onOpenDetail: () -> Void
    let onOpenAuthor: () -> Void
    let onOpenMenu: () -> Void
    let onToggleFavorite: () -> Void
    let onSpark: () -> Void
    let onDismiss: () -> Void
    let onToggleLike: () -> Void
    var onboardingState: String?
    var contextualTipStore: ContextualGuideTipStore?
    var sparkResumeTargetIsVisible: Bool
    var cardHeight: CGFloat = 440

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var dragOffset: CGSize = .zero
    @State private var isResolvingSwipe = false
    @State private var dragCrossedThreshold = false

    private var isFlowCardTipVisible: Bool {
        contextualTipStore?.isVisible(
            .flowCard,
            onboardingState: onboardingState,
            targetIsVisible: true
        ) ?? false
    }

    private var isFlowSparkTipVisible: Bool {
        contextualTipStore?.isVisible(
            .flowSpark,
            onboardingState: onboardingState,
            targetIsVisible: true
        ) ?? false
    }

    private var isSparkResumeTipVisible: Bool {
        contextualTipStore?.isVisible(
            .sparkResume,
            onboardingState: onboardingState,
            targetIsVisible: sparkResumeTargetIsVisible
        ) ?? false
    }

    private var activeSparkTip: ContextualGuideTipID? {
        if isFlowSparkTipVisible { return .flowSpark }
        if isSparkResumeTipVisible { return .sparkResume }
        return nil
    }

    private func dismissVisibleTips() {
        for tip in [
            ContextualGuideTipID.flowCard,
            .flowSpark,
            .sparkResume,
        ] {
            let targetIsVisible = tip == .sparkResume
                ? sparkResumeTargetIsVisible
                : true
            guard contextualTipStore?.isVisible(
                tip,
                onboardingState: onboardingState,
                targetIsVisible: targetIsVisible
            ) == true else {
                continue
            }
            contextualTipStore?.dismiss(
                tip,
                onboardingState: onboardingState,
                targetIsVisible: targetIsVisible
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 12))
            headerLayout {
                Button {
                    dismissVisibleTips()
                    onOpenAuthor()
                } label: {
                    HStack(spacing: 8) {
                        authorAvatar
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.author?.username ?? "Chorai")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            if let date = cardDate {
                                Text(date).font(.caption).foregroundStyle(Color.secondary)
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Open author")
                .accessibilityValue([card.author?.username, cardDate].compactMap { $0 }.joined(separator: ", "))
                .accessibilityIdentifier("flow.author.\(card.id)")
                .disabled(card.author == nil)

                if !dynamicTypeSize.isAccessibilitySize { Spacer() }

                HStack(spacing: 2) {
                    if dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }

                    Button(action: performSparkAction) {
                        Group {
                            if dynamicTypeSize.isAccessibilitySize {
                                Image(systemName: "sparkles").font(.system(size: 20, weight: .semibold))
                            }
                            else { Label("Spark", systemImage: "sparkles") }
                        }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ChoraiTheme.gold)
                            .padding(.horizontal, 4)
                            .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? 44 : nil,
                                   minHeight: dynamicTypeSize.isAccessibilitySize ? 44 : 36)
                    }
                    .modifier(FlowSparkButtonStyle())
                    .accessibilityLabel("Spark")
                    .accessibilityIdentifier("flow.spark.\(card.id)")
                    .overlay {
                        ContextualGuideTargetHalo(
                            isVisible: activeSparkTip != nil
                        )
                    }
                    NativeCardActionsMenu(
                        cardData: card.asUserCard,
                        layout: .grid2x2,
                        isOwnCard: card.isOwner,
                        onPrepare: dismissVisibleTips,
                        onSpark: performSparkAction
                    ) {
                        Image(systemName: "ellipsis")
                            .font(dynamicTypeSize.isAccessibilitySize
                                  ? .system(size: 20, weight: .semibold)
                                  : .body.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More actions")
                    .accessibilityIdentifier("flow.menu.\(card.id)")

                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("flow.header.\(card.id)")

            if let activeSparkTip, let contextualTipStore {
                HStack {
                    Spacer(minLength: 0)
                    ContextualGuideCallout(
                        store: contextualTipStore,
                        tip: activeSparkTip,
                        onboardingState: onboardingState,
                        targetIsVisible: true
                    )
                }
            }

            if isFlowCardTipVisible, let contextualTipStore {
                ContextualGuideCallout(
                    store: contextualTipStore,
                    tip: .flowCard,
                    onboardingState: onboardingState,
                    targetIsVisible: true
                )
            }

            ChoraiLevelBadge(rate: card.rate)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .fixedSize(horizontal: false, vertical: true)

            FlowRichPreview(card: card, compact: false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissVisibleTips()
                    onOpenDetail()
                }
                .highPriorityGesture(cardDragGesture)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("flow.card.\(card.id)")
                .accessibilityAction {
                    dismissVisibleTips()
                    onOpenDetail()
                }
                .accessibilityAction(named: Text("Next note"), onDismiss)

            if !card.tags.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(card.tags.prefix(3)), id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(Color.secondary)
                            .background(Capsule().fill(ChoraiTheme.background))
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 16) {
                if !card.isOwner {
                    Button {
                        if !isFlowCardTipVisible {
                            dismissVisibleTips()
                        }
                        onToggleFavorite()
                    } label: {
                        engagementMetric(
                            image: card.isFavorited ? "favorite_active" : "favorite",
                            count: card.favoriteCount
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isFavoritePending)
                    .accessibilityLabel(card.isFavorited ? "Unfavorite" : "Favorite")
                    .accessibilityValue(card.isFavorited ? "true" : "false")
                    .accessibilityIdentifier("flow.favorite.\(card.id)")
                }

                Spacer(minLength: 16)

                Button {
                    dismissVisibleTips()
                    onToggleLike()
                } label: {
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

                CommentButton(cardId: card.id, commentCount: card.commentCount, iconSize: 14, countFont: .caption)
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Comments")
                    .accessibilityValue("\(card.commentCount)")
                    .accessibilityIdentifier("flow.comment.\(card.id)")
                    .simultaneousGesture(
                        TapGesture().onEnded { _ in
                            dismissVisibleTips()
                        }
                    )
            }
            .foregroundStyle(Color.secondary)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .fixedSize(horizontal: false, vertical: true)

            if hasFavoriteError {
                FlowFavoriteErrorView()
            }
            if let likeErrorMessage {
                Text(likeErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(ChoraiTheme.secondaryInk)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityIdentifier("flow.like.error.\(card.id)")
            }

        }
        .padding(24)
        .foregroundStyle(ChoraiTheme.ink)
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight, alignment: .topLeading)
        .background(cardBackground)
        .choraiCardLevel(rate: card.rate, showsChora: false, cornerRadius: 28)
        .overlay(alignment: .topLeading) {
            if abs(dragOffset.width) > 8 {
                Label("Next note", systemImage: dragOffset.width > 0 ? "arrow.right" : "arrow.left")
                    .font(.headline).padding(.horizontal, 16).padding(.vertical, 10)
                    .foregroundStyle(ChoraiTheme.ink)
                    .background(ChoraiTheme.raisedSurface, in: Capsule())
                    .opacity(min(1, Double(abs(dragOffset.width) / 80)))
                    .padding(22).allowsHitTesting(false).accessibilityHidden(true)
                    .accessibilityIdentifier("flow.swipe.feedback")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("flow.card.surface.\(card.id)")
        .overlay {
            ContextualGuideRoundedTargetHalo(
                isVisible: isFlowCardTipVisible,
                cornerRadius: ZenVisualTokens.cardRadius
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: ZenVisualTokens.cardRadius, style: .continuous))
        .offset(x: dragOffset.width)
        .rotationEffect(reduceMotion ? .zero : .degrees(Double(dragOffset.width / 34)))
        .disabled(isResolvingSwipe)
    }

    private func performSparkAction() {
        if let activeSparkTip {
            contextualTipStore?.complete(activeSparkTip, onboardingState: onboardingState, targetIsVisible: true)
        } else {
            dismissVisibleTips()
        }
        onSpark()
    }

    private var cardBackground: some View {
        FlowGlassSurface(layer: .foreground)
    }

    private var cardDate: String? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: card.createdAt) ?? ISO8601DateFormatter().date(from: card.createdAt)
        guard let date else { return nil }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
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
        .frame(width: 34, height: 34)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        Text((card.author?.username ?? "Chorai").split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined())
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(ChoraiTheme.ink)
            .frame(width: 34, height: 34)
            .background(ChoraiTheme.ink.opacity(0.08), in: Circle())
    }

    private func engagementMetric(
        image: String,
        count: Int,
        iconSize: CGFloat = 14
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: image == "favorite_active" ? "bookmark.fill" : image == "favorite" ? "bookmark" : image == "like_active" ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .regular))
                .frame(width: iconSize, height: iconSize)
            Text("\(count)")
                .font(.caption)
                .monospacedDigit()
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }

    private var cardDragGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard !isResolvingSwipe, abs(value.translation.width) > abs(value.translation.height) * 1.15 else { return }
                dragOffset = CGSize(width: value.translation.width, height: 0)
                let crossed = abs(value.translation.width) >= 100
                if crossed && !dragCrossedThreshold { UISelectionFeedbackGenerator().selectionChanged() }
                dragCrossedThreshold = crossed
            }
            .onEnded { value in
                dragCrossedThreshold = false
                guard abs(value.translation.width) > abs(value.translation.height) * 1.15 else { dragOffset = .zero; return }
                resolveSwipe(
                    FlowSwipeResolver.resolve(
                        translation: Double(value.translation.width),
                        predictedEndTranslation: Double(value.predictedEndTranslation.width)
                    )
                )
            }
    }

    private func resolveSwipe(_ decision: FlowSwipeDecision) {
        guard !isResolvingSwipe else { return }
        guard decision != .cancel else {
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)) { dragOffset = .zero }
            return
        }
        dismissVisibleTips()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard !reduceMotion else {
            dragOffset = .zero
            onDismiss()
            return
        }
        isResolvingSwipe = true
        withAnimation(.easeOut(duration: 0.16)) { dragOffset.width = decision == .advanceRight ? 500 : -500 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            dragOffset = .zero
            isResolvingSwipe = false
            onDismiss()
        }
    }

}

struct FlowDeckView: View {
    @ObservedObject var store: FlowDeckStore
    var isGrid = false
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
    var onboardingStore: OnboardingGuideStore?
    var contextualTipStore: ContextualGuideTipStore?
    var sparkResumeRootSourceAssetID: String?

    private var backplateDepths: [Int] {
        let count = min(2, max(0, store.remainingCount - 1))
        guard count > 0 else { return [] }
        return Array(1...count)
    }

    var body: some View {
        ZStack {
            deckContent
                .zIndex(isGrid ? 0 : 1)
                .opacity(isGrid ? 0 : 1)
                .allowsHitTesting(!isGrid)
                .accessibilityHidden(isGrid)
            gridContent
                .zIndex(isGrid ? 1 : 0)
                .opacity(isGrid ? 1 : 0)
                .allowsHitTesting(isGrid)
                .accessibilityHidden(!isGrid)
        }
        .overlay(alignment: .bottomLeading) { testStateMarkers }
        .padding(.horizontal, isGrid ? 12 : 14)
        .foregroundStyle(ChoraiTheme.ink)
        .task { store.loadInitialIfNeeded() }
        .onChange(of: store.currentCard?.id) { _ in
            if let card = store.currentCard {
                hydrateLike(for: card)
                onCardVisible(card)
            }
        }
        .onChange(of: onboardingStore?.session?.state) { state in
            guard state == "product_curator_intro",
                  let card = store.currentCard else {
                return
            }
            onCardVisible(card)
        }
        .onReceive(CardEngagementCenter.shared.likes) { state in
            store.applyLikeState(state)
            likeStore.applyCommitted(state)
        }
        .onReceive(CardEngagementCenter.shared.favorites) { store.applyFavoriteState($0) }
    }

    @ViewBuilder
    private var deckContent: some View {
        switch store.phase {
        case .idle, .loading:
            FlowSkeletonView().accessibilityIdentifier("screen.flow.loading")
        case .loaded: loadedDeck
        case .empty:
            FlowStateView(title: "You're caught up", message: "Your recent notes are still here. Go back or refresh when you're ready.", button: "Refresh", action: store.refresh)
                .accessibilityIdentifier("screen.flow.empty")
        case .failed(let message):
            FlowStateView(title: "Explore paused", message: message, button: "Retry", action: store.refresh)
                .accessibilityIdentifier("screen.flow.error")
        }
    }

    @ViewBuilder
    private var loadedDeck: some View {
        if let card = store.currentCard {
            GeometryReader { viewport in
                ZStack {
                        ForEach(backplateDepths.reversed(), id: \.self) { depth in
                            FlowDeckBackplate(depth: depth)
                        }
                        FlowCardView(
                            card: displayedCard(card),
                            isLikeMutationInFlight: likeStore.state.cardID == card.id && likeStore.isMutating,
                            isFavoritePending: store.isFavoritePending(card.id),
                            hasFavoriteError: store.failedFavoriteIDs.contains(card.id),
                            likeErrorMessage: likeErrorMessage(for: card.id),
                            onOpenDetail: { onOpenDetail(card) },
                            onOpenAuthor: { onOpenAuthor(card) },
                            onOpenMenu: { onOpenMenu(card) },
                            onToggleFavorite: { store.toggleFavoriteCurrent(onFavoriteSucceeded: recordSaved) },
                            onSpark: { onSpark(card) },
                            onDismiss: {
                                guard store.currentCard?.id == card.id else { return }
                                contextualTipStore?.complete(.flowCard, onboardingState: onboardingStore?.contextualTipState, targetIsVisible: true)
                                store.dismissCurrent()
                                onCardDismissed(card.id)
                            },
                            onToggleLike: {
                                if likeStore.state.cardID != card.id { hydrateLike(for: card) }
                                likeStore.toggle()
                            },
                            onboardingState: onboardingStore?.contextualTipState,
                            contextualTipStore: contextualTipStore,
                            sparkResumeTargetIsVisible: OnboardingSparkContinuationPolicy.shouldShowResumeTip(
                                onboardingState: onboardingStore?.contextualTipState,
                                resumeRootSourceAssetID: sparkResumeRootSourceAssetID
                            ),
                            cardHeight: max(0, viewport.size.height - 12)
                        )
                        .id(card.id)
                }
                .frame(height: max(0, viewport.size.height - 12))
            }
        }
    }

    private func hydrateLike(for card: FlowCard) {
        likeStore.hydrate(CardLikeState(cardID: card.id, isLiked: card.isLiked, likeCount: card.likeCount))
    }

    private func displayedCard(_ card: FlowCard) -> FlowCard {
        likeStore.state.cardID == card.id ? card.replacingLike(with: likeStore.state) : card
    }

    private func recordSaved(_ assetID: String) {
        contextualTipStore?.complete(.flowCard, onboardingState: onboardingStore?.contextualTipState, targetIsVisible: true)
        onCardSaved(assetID)
    }

    @ViewBuilder
    private var gridContent: some View {
        if store.browsingCards.isEmpty { deckContent }
        else {
            FlowGridView(store: store, onOpenDetail: onOpenDetail, onOpenAuthor: onOpenAuthor, onOpenMenu: onOpenMenu, onSpark: onSpark, onCardSaved: recordSaved)
        }
    }

    @ViewBuilder
    private var testStateMarkers: some View {
        if store.phase == .loaded {
            Text("Flow loaded").font(.system(size: 1)).foregroundStyle(ChoraiTheme.ink.opacity(0.01)).frame(width: 1, height: 1).accessibilityIdentifier("screen.flow.loaded")
        }
        if let card = store.currentCard {
            Group {
                Text(card.id).accessibilityIdentifier("flow.visible-card.id")
                Text("\(displayedCard(card).likeCount)").accessibilityIdentifier("flow.like.count.\(card.id)")
                Text("\(card.favoriteCount)").accessibilityIdentifier("flow.favorite.count.\(card.id)")
            }.font(.system(size: 1)).foregroundStyle(ChoraiTheme.ink.opacity(0.01)).frame(width: 1, height: 1)
        }
    }

    private func likeErrorMessage(for cardID: String) -> String? {
        guard likeStore.state.cardID == cardID,
              case .failed = likeStore.phase else {
            return nil
        }
        return "Like failed. Try again."
    }
}

private struct FlowFavoriteErrorView: View {
    var body: some View {
        Text("Couldn’t update this bookmark. Tap it to retry.")
            .font(.footnote)
            .foregroundStyle(ChoraiTheme.secondaryInk)
            .accessibilityIdentifier("flow.favorite.error")
    }
}

private struct FlowSkeletonView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: ZenVisualTokens.cardRadius, style: .continuous)
            .fill(ZenVisualTokens.cardFill)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 14) {
                    Capsule().fill(ChoraiTheme.separator).frame(width: 112, height: 14)
                    Capsule().fill(ChoraiTheme.separator).frame(height: 22)
                    Capsule().fill(ChoraiTheme.raisedSurface).frame(height: 14)
                    Capsule().fill(ChoraiTheme.raisedSurface).frame(width: 210, height: 14)
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
                .foregroundStyle(ChoraiTheme.secondaryInk)
                .multilineTextAlignment(.center)
            Button(button, action: action)
                .buttonStyle(.borderedProminent)
                .tint(ZenVisualTokens.accent)
        }
        .foregroundStyle(ChoraiTheme.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// Both presentations read the same store; each keeps its own scroll position.
private struct FlowGridView: View {
    @ObservedObject var store: FlowDeckStore
    let onOpenDetail: (FlowCard) -> Void
    let onOpenAuthor: (FlowCard) -> Void
    let onOpenMenu: (FlowCard) -> Void
    let onSpark: (FlowCard) -> Void
    let onCardSaved: (String) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                FlowMasonryLayout(columns: typeSize.isAccessibilitySize ? 1 : 2, spacing: 12) {
                    ForEach(Array(store.browsingCards.enumerated()), id: \.element.id) { index, card in
                        tile(card)
                            .accessibilitySortPriority(Double(store.browsingCards.count - index))

                    }
                }
                if store.canLoadMore, let last = store.browsingCards.last {
                    Color.clear.frame(height: 1)
                        .onAppear { store.loadMoreIfNeeded(visibleCardID: last.id) }
                        .id(last.id)
                }
                if !store.canLoadMore {
                    Text("You're all caught up").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }.padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .refreshable { store.refresh() }
        .accessibilityIdentifier("explore.grid")
    }

    private func tile(_ card: FlowCard) -> some View {
        ratedTile(card)
    }

    /// The rated Grid uses the approved V8 level card as a complete surface.
    private func ratedTile(_ card: FlowCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ChoraiLevelBadge(rate: card.rate, compact: true)
            Button { onOpenDetail(card) } label: {
                Text(ratedSummary(card)).font(.system(.subheadline, design: .serif))
                    .lineSpacing(3).lineLimit(7)
                    .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("Read note, \(FlowTextPreview.make(card.content).prefix(100))")
                .accessibilityHint("Opens the full note")
                .accessibilityIdentifier("explore.grid.card.\(card.id)")
            Button { onOpenAuthor(card) } label: {
                Text(card.author?.username ?? "Chorai")
                    .font(.caption.weight(.medium)).foregroundStyle(Color.secondary)
                    .lineLimit(1).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(card.author == nil)
                .accessibilityLabel("Open author, \(card.author?.username ?? "Chorai")")
            HStack(spacing: 0) {
                if !card.isOwner {
                    Button { store.toggleFavorite(assetID: card.id, onFavoriteSucceeded: onCardSaved) } label: {
                        Image(systemName: card.isFavorited ? "bookmark.fill" : "bookmark")
                            .font(.subheadline).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .disabled(store.isFavoritePending(card.id))
                        .accessibilityLabel(card.isFavorited ? "Remove from collection" : "Collect")
                        .accessibilityValue(card.isFavorited ? "true" : "false")
                        .accessibilityIdentifier("explore.grid.favorite.\(card.id)")
                }
                Spacer(minLength: 0)
                NativeCardActionsMenu(
                    cardData: card.asUserCard,
                    layout: .grid2x2,
                    isOwnCard: card.isOwner,
                    onSpark: { onSpark(card) }
                ) {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }.accessibilityLabel("Note actions")
                    .accessibilityIdentifier("explore.grid.menu.\(card.id)")
            }.buttonStyle(.plain)
            if store.failedFavoriteIDs.contains(card.id) {
                FlowFavoriteErrorView()
            }
        }
        .padding(14)
        .choraiCardLevel(rate: card.rate, showsChora: false, cornerRadius: 17)
        .foregroundStyle(ChoraiTheme.ink)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .contain)
    }

    private func ratedSummary(_ card: FlowCard) -> String {
        let preview = LibraryCardPreviewParser.parse(content: card.content, contentJSON: card.contentJSON)
        let blocks = FlowPreviewBlock.read(card, fallback: preview.text)
        return blocks.map(\.text).joined(separator: "\n\n")
    }

}

/// The approved Grid places the next note in the shortest column without
/// changing source order for VoiceOver or reading history.
private struct FlowMasonryLayout: Layout {
    var columns: Int
    var spacing: CGFloat

    private func placements(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], heights: [CGFloat], columnWidth: CGFloat) {
        let count = max(1, columns)
        let columnWidth = max(1, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
        var heights = Array(repeating: CGFloat.zero, count: count)
        var points: [CGPoint] = []
        for subview in subviews {
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            points.append(CGPoint(x: CGFloat(column) * (columnWidth + spacing), y: heights[column]))
            heights[column] += size.height + spacing
        }
        return (points, heights, columnWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let result = placements(width: width, subviews: subviews)
        return CGSize(width: width, height: max(0, (result.heights.max() ?? 0) - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = placements(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let point = result.points[index]
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: result.columnWidth, height: nil))
        }
    }
}

/// Preview only the note's real blocks. In particular a paragraph never becomes
/// an invented title, and the legacy title field is not displayed.
private struct FlowPreviewBlock {
    let kind: String
    let text: String
    let checked: Bool

    static func read(_ card: FlowCard, fallback: String) -> [Self] {
        var decoded: Any? = card.contentJSON
        for _ in 0..<2 {
            guard let value = decoded as? String, let data = value.data(using: .utf8) else { break }
            decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        }
        let raw = (decoded as? [[String: Any]]) ?? ((decoded as? [String: Any])?["blocks"] as? [[String: Any]])
        if let raw {
            func flatten(_ blocks: [[String: Any]]) -> [[String: Any]] {
                blocks.flatMap { [$0] + flatten($0["children"] as? [[String: Any]] ?? []) }
            }
            let result = flatten(raw).compactMap { block -> Self? in
                let kind = (block["type"] as? String ?? "paragraph").lowercased()
                guard kind != "image", let data = try? JSONSerialization.data(withJSONObject: [block]),
                      let json = String(data: data, encoding: .utf8) else { return nil }
                // Children are separate previews, not repeated in their parent.
                var ownBlock = block
                ownBlock["children"] = []
                let ownJSON = (try? JSONSerialization.data(withJSONObject: [ownBlock])).flatMap { String(data: $0, encoding: .utf8) } ?? json
                let text = LibraryCardPreviewParser.parse(content: "", contentJSON: ownJSON).text
                guard !text.isEmpty else { return nil }
                let checked = (block["props"] as? [String: Any])?["checked"] as? Bool ?? false
                return Self(kind: kind, text: text, checked: checked)
            }
            if !result.isEmpty { return result }
        }
        // Existing HTML remains a plain, paragraph-preserving preview. No title
        // is inferred from the first sentence when structured blocks are absent.
        return fallback.isEmpty ? [] : [Self(kind: "paragraph", text: fallback, checked: false)]
    }
}

struct FlowRichPreview: View {
    let card: FlowCard
    let compact: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var readingSize = 20.0
    @ScaledMetric(relativeTo: .body) private var compactSize = 13.0
    @ScaledMetric(relativeTo: .title2) private var headingSize = 24.0
    @ScaledMetric(relativeTo: .title2) private var compactHeadingSize = 20.0
    @ScaledMetric(relativeTo: .title) private var quoteSize = 33.0
    @ScaledMetric(relativeTo: .title2) private var compactQuoteSize = 23.0
    @ScaledMetric(relativeTo: .footnote) private var codeSize = 13.0
    @ScaledMetric(relativeTo: .footnote) private var compactCodeSize = 11.0

    private var preview: LibraryCardPreviewContent {
        LibraryCardPreviewParser.parse(content: card.content, contentJSON: card.contentJSON)
    }
    private var blocks: [FlowPreviewBlock] { FlowPreviewBlock.read(card, fallback: preview.text) }
    private var imageURL: URL? {
        guard let source = preview.imageSource else { return nil }
        return CardEditingMediaURLResolver.resolve(
            source.hasPrefix("chorai-assets/") ? "/\(source)" : source,
            canonicalizeRelativePath: APIConfiguration.resourceURLString
        )
    }

    var body: some View {
        Group {
            if compact {
                previewContent(blockLimit: 5, lineLimit: nil, showsImage: true)
            } else {
                GeometryReader { available in
                    ViewThatFits(in: .vertical) {
                        previewContent(blockLimit: 3, lineLimit: 4, showsImage: true).fixedSize(horizontal: false, vertical: true)
                        previewContent(blockLimit: 2, lineLimit: 3, showsImage: true).fixedSize(horizontal: false, vertical: true)
                        previewContent(blockLimit: 1, lineLimit: 2, showsImage: true).fixedSize(horizontal: false, vertical: true)
                        previewContent(blockLimit: 1, lineLimit: 3, showsImage: false).fixedSize(horizontal: false, vertical: true)
                        Text(preview.text.isEmpty ? "Open note" : preview.text)
                            .font(.body).lineLimit(1).truncationMode(.tail)
                    }
                    .frame(width: available.size.width, height: available.size.height, alignment: .topLeading)
                }
            }
        }
        .foregroundStyle(ChoraiTheme.ink)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func previewContent(blockLimit: Int, lineLimit: Int?, showsImage: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 14) {
            if showsImage, let imageURL { imageContent(imageURL) }
            if !blocks.isEmpty {
                VStack(alignment: .leading, spacing: compact ? 12 : 14) {
                    ForEach(Array(blocks.prefix(blockLimit).enumerated()), id: \.offset) { _, block in
                        blockContent(block, summaryLines: lineLimit)
                    }
                }.padding(compact ? 15 : 0)
            } else if imageURL == nil || !showsImage {
                Text("Open note").font(.body).foregroundStyle(.secondary).padding(compact ? 15 : 0)
            }
        }
    }

    @ViewBuilder private func blockContent(_ block: FlowPreviewBlock, summaryLines: Int? = nil) -> some View {
        switch block.kind {
        case "heading":
            Text(block.text).font(.system(size: compact ? compactHeadingSize : headingSize, design: .serif))
                .tracking(-0.35).lineSpacing(2).lineLimit(summaryLines ?? (typeSize.isAccessibilitySize ? nil : 4))
        case "quote", "blockquote":
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "quote.opening").font(.system(size: compact ? 22 : 30)).foregroundStyle(ChoraiTheme.gold).accessibilityHidden(true)
                Text(block.text).font(.system(size: compact ? compactQuoteSize : quoteSize, design: .serif))
                    .tracking(-0.4).lineSpacing(3).lineLimit(summaryLines ?? (typeSize.isAccessibilitySize ? nil : 8))
            }.padding(.vertical, compact ? 7 : 8)
        case "codeblock", "code":
            Text(block.text).font(.system(size: compact ? compactCodeSize : codeSize, design: .monospaced))
                .lineSpacing(3).lineLimit(summaryLines ?? (typeSize.isAccessibilitySize ? nil : 10))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(compact ? 0 : 14)
                .background(compact ? Color.clear : ChoraiTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 10))
        case "checklistitem", "bulletlistitem", "numberedlistitem":
            HStack(alignment: .firstTextBaseline, spacing: compact ? 6 : 10) {
                Image(systemName: block.kind == "checklistitem" ? (block.checked ? "checkmark.circle.fill" : "circle") : "circle.fill")
                    .font(.system(size: block.kind == "checklistitem" ? (compact ? 13 : 17) : 5))
                    .foregroundStyle(ChoraiTheme.gold).accessibilityHidden(true)
                Text(block.text).font(.system(size: compact ? compactSize : readingSize))
                    .lineSpacing(3).lineLimit(summaryLines ?? (typeSize.isAccessibilitySize ? nil : 4))
            }
        default:
            Text(block.text).font(.system(size: compact ? compactSize : readingSize, design: .serif))
                .lineSpacing(4).lineLimit(summaryLines ?? (typeSize.isAccessibilitySize ? nil : (compact ? 10 : 12)))
        }
    }

    private func imageContent(_ url: URL) -> some View {
        Color.clear.frame(height: compact ? 184 : 146)
            .overlay {
                GeometryReader { geometry in
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        case .empty:
                            ZStack { ChoraiTheme.raisedSurface; ProgressView() }
                        case .failure:
                            ZStack {
                                ChoraiTheme.raisedSurface
                                Label("Image unavailable", systemImage: "photo").font(.caption).foregroundStyle(.secondary)
                            }
                        @unknown default: ChoraiTheme.raisedSurface
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 16))
            .accessibilityLabel(preview.imageAlternativeText ?? "Note image")
    }
}
