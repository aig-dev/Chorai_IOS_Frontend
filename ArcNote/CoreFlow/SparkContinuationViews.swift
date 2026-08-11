import CoreFlow
import SwiftUI
import UIKit

struct SparkContinuationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    @StateObject private var store: SparkSessionStore
    @StateObject private var likeStore = CardLikeStore(
        state: CardLikeState(cardID: "", isLiked: false, likeCount: 0),
        service: NetworkCoreCardLikeService(),
        onCommit: CardEngagementCenter.shared.publish
    )
    @State private var showPopupMenu = false
    @State private var currentMenuCard: UserCard?
    @State private var menuCardIsOwned = false
    @State private var selectedDetailCardID: String?
    @State private var selectedAuthorID: String?
    @State private var showDetail = false
    @State private var showAuthor = false
    @State private var presentationRevision = 0

    private let actorID: String
    private let rootCardID: String
    private let onboardingStore: OnboardingGuideStore?
    private let contextualTipStore: ContextualGuideTipStore?

    init(
        cardID: String,
        actorID: String,
        onboardingStore: OnboardingGuideStore? = nil,
        contextualTipStore: ContextualGuideTipStore? = nil
    ) {
        self.actorID = actorID
        self.rootCardID = cardID
        self.onboardingStore = onboardingStore
        self.contextualTipStore = contextualTipStore
        let scope = ProcessInfo.processInfo.environment[
            "CHORAI_UI_TEST_SPARK_SESSION_SCOPE"
        ]
        let keyPrefix = scope.map { "chorai.spark.session.\($0)" }
            ?? "chorai.spark.session"
        _store = StateObject(
            wrappedValue: SparkSessionStore(
                actorID: actorID,
                rootSourceAssetID: cardID,
                service: NetworkCoreSparkService(),
                persistence: UserDefaultsSparkSessionStore(
                    keyPrefix: keyPrefix
                )
            )
        )
    }

    var body: some View {
        ZStack {
            sparkAtmosphere

            VStack(spacing: 14) {
                header
                if let onboardingStore {
                    OnboardingGuideLine(
                        store: onboardingStore,
                        allowedStates: [
                            "product_spark_intro",
                            "product_spark_results",
                            "product_save_material"
                        ]
                    )
                }
                sourceStrip
                phaseContent
                    .id(screenStateIdentifier)
            }
            .id(presentationRevision)
            .adaptiveContentGutter()
            .padding(.top, 8)
            .padding(.bottom, 18)
            .foregroundStyle(.white)

            automationAnchors
                .id(automationStateIdentity)
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(.dark)
        .overlay {
            CommentPopupView()
                .environment(\.colorScheme, .light)
        }
        .popupMenu(
            isPresented: $showPopupMenu,
            layout: menuCardIsOwned ? .grid3x3 : .grid3x2,
            cardData: currentMenuCard,
            isOwnCard: menuCardIsOwned,
            isSparkEnabled: store.phase == .loaded,
            onSpark: store.sparkCurrentDeeper
        )
        .navigationDestination(isPresented: $showDetail) {
            if let cardID = selectedDetailCardID {
                DetailView(cardId: cardID)
            }
        }
        .navigationDestination(isPresented: $showAuthor) {
            if let actorID = selectedAuthorID {
                UserProfileView(actorId: actorID)
            }
        }
        .task {
            store.start()
            guard presentationRevision == 0 else { return }
            // iOS 26 can retain the pushed destination snapshot when a fast
            // replay completes while the source popup is still dismissing.
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, presentationRevision == 0 else { return }
            presentationRevision = 1
        }
        .onChange(of: store.currentResult?.id) { _ in
            guard let card = store.currentResult?.card else { return }
            likeStore.hydrate(
                CardLikeState(
                    cardID: card.id,
                    isLiked: card.isLiked,
                    likeCount: card.likeCount
                )
            )
        }
        .onReceive(CardEngagementCenter.shared.likes) { state in
            store.applyLikeState(state)
            likeStore.applyCommitted(state)
        }
        .onChange(of: store.activeActivityID) { activityID in
            guard activityID != nil else { return }
            onboardingStore?.receive(.sparkStarted(assetID: rootCardID))
        }
        .onChange(of: store.phase) { phase in
            guard phase == .loaded,
                  let activityID = store.activeActivityID else {
                return
            }
            onboardingStore?.receive(
                .sparkResultsViewed(activityID: activityID)
            )
        }
        .environment(
            \.dynamicTypeSize,
            usesAccessibilityEvidenceMode
                ? .accessibility3
                : systemDynamicTypeSize
        )
    }

    private var sparkAtmosphere: some View {
        ZStack {
            ZenVisualTokens.background
            RadialGradient(
                colors: [
                    ZenVisualTokens.accent.opacity(0.16),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                dismissSparkFavoriteTipIfVisible()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("spark.back")

            Image("menu_spark")
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
                .accessibilityHidden(true)

            SparkChainRail(
                nodes: store.chain,
                activeActivityID: store.activeActivityID,
                showsPendingNode: store.phase == .triggering
                    || store.phase == .reconciling,
                isInteractionLocked: store.isInteractionLocked,
                onSelect: { nodeID in
                    dismissSparkFavoriteTipIfVisible()
                    store.selectNode(activityID: nodeID)
                }
            )
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var sourceStrip: some View {
        if let card = store.sourceCard {
            HStack(spacing: 8) {
                if let author = card.author {
                    Button {
                        dismissSparkFavoriteTipIfVisible()
                        openAuthor(author.id)
                    } label: {
                        HStack(spacing: 6) {
                            SparkAvatar(author: author, size: 24)
                            Text(author.username)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open source author")
                } else {
                    SparkAvatar(author: nil, size: 24)
                        .accessibilityHidden(true)
                }

                Text(FlowTextPreview.make(card.content))
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.56))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.055))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .accessibilityElement(children: .contain)
        } else {
            Capsule()
                .fill(Color.white.opacity(0.055))
                .frame(height: 44)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 190, height: 10)
                        .padding(.leading, 14)
                }
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch store.phase {
        case .idle, .loadingSource:
            SparkDeckSkeleton()
        case .triggering, .replaying, .reconciling:
            if store.currentResult != nil {
                ZStack {
                    loadedDeck
                    SparkLoadingVeil(
                        isChecking: store.phase == .reconciling
                    )
                }
            } else {
                SparkDeckSkeleton()
            }
        case .loaded:
            loadedDeck
        case .empty:
            SparkCompactState(
                title: "No new thread",
                message: nil,
                action: nil
            )
        case .failed(let message):
            if store.currentResult != nil {
                ZStack(alignment: .bottom) {
                    loadedDeck
                    SparkFailureNotice(
                        message: message,
                        canRetry: message != "This Spark has reached its limit.",
                        retry: store.retryTrigger
                    )
                    .padding(.bottom, 14)
                }
            } else {
                SparkCompactState(
                    title: message,
                    message: nil,
                    action: retryAction(for: message)
                )
            }
        }
    }

    private func retryAction(for message: String) -> (() -> Void)? {
        guard message != "This Spark can no longer be restored." else {
            return nil
        }
        return store.retryTrigger
    }

    @ViewBuilder
    private var loadedDeck: some View {
        if let result = store.currentResult {
            VStack(spacing: 8) {
                ZStack {
                    if store.nextResult != nil {
                        RoundedRectangle(
                            cornerRadius: ZenVisualTokens.cardRadius,
                            style: .continuous
                        )
                        .fill(ZenVisualTokens.cardFill.opacity(0.72))
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: ZenVisualTokens.cardRadius,
                                style: .continuous
                            )
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .offset(y: 11)
                        .scaleEffect(0.968)
                        .accessibilityHidden(true)
                    }

                    SparkResultCard(
                        result: result,
                        isInteractionLocked: store.isInteractionLocked,
                        isLikeMutationInFlight: likeStore.isMutating,
                        likeErrorMessage: likeErrorMessage(for: result.card.id),
                        allowsSparkDeeper: store.phase == .loaded,
                        forcesAccessibleAppearance: usesAccessibilityEvidenceMode,
                        onNext: {
                            dismissSparkFavoriteTipIfVisible()
                            store.advance()
                        },
                        onToggleFavorite: {
                            contextualTipStore?.complete(
                                .sparkFavorite,
                                onboardingState: onboardingStore?.session?.state,
                                targetIsVisible: !result.card.isOwner
                            )
                            store.toggleFavoriteCurrent { assetID in
                                onboardingStore?.receive(
                                    .sparkResultSaved(assetID: assetID)
                                )
                            }
                        },
                        onToggleLike: {
                            dismissSparkFavoriteTipIfVisible()
                            likeStore.toggle()
                        },
                        onSparkDeeper: {
                            dismissSparkFavoriteTipIfVisible()
                            store.sparkCurrentDeeper()
                        },
                        onOpenCard: {
                            dismissSparkFavoriteTipIfVisible()
                            openDetail(result.card.id)
                        },
                        onOpenAuthor: {
                            dismissSparkFavoriteTipIfVisible()
                            if let authorID = result.card.author?.id {
                                openAuthor(authorID)
                            }
                        },
                        onOpenMenu: {
                            dismissSparkFavoriteTipIfVisible()
                            openMenu(result.card)
                        },
                        onboardingState: onboardingStore?.session?.state,
                        contextualTipStore: contextualTipStore
                    )
                    .id(result.id)
                }

                noticeView
            }
        }
    }

    private func likeErrorMessage(for cardID: String) -> String? {
        guard likeStore.state.cardID == cardID,
              case .failed = likeStore.phase else {
            return nil
        }
        return "Like failed. Try again."
    }

    private func dismissSparkFavoriteTipIfVisible() {
        let targetIsVisible = store.currentResult.map {
            !$0.card.isOwner
        } ?? false
        guard contextualTipStore?.isVisible(
            .sparkFavorite,
            onboardingState: onboardingStore?.session?.state,
            targetIsVisible: targetIsVisible
        ) == true else {
            return
        }
        contextualTipStore?.dismiss(
            .sparkFavorite,
            onboardingState: onboardingStore?.session?.state,
            targetIsVisible: targetIsVisible
        )
    }

    @ViewBuilder
    private var noticeView: some View {
        switch store.notice {
        case .saveFailed:
            Text("Favorite failed. Try again.")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(minHeight: 44)
                .accessibilityIdentifier("spark.save.failed")
        case .moreFailed:
            Text("More results paused.")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(minHeight: 44)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var automationAnchors: some View {
        VStack(spacing: 1) {
            automationText("Spark", identifier: screenStateIdentifier)
            if let sourceID = store.sourceCard?.id {
                automationText(sourceID, identifier: "spark.source.card-id")
            }
            if let activityID = store.activeActivityID {
                automationText(activityID, identifier: "spark.activity.id")
            }
            if let node = activeNode {
                automationText(node.rootActivityID, identifier: "spark.root.id")
                automationText(
                    node.parentActivityID ?? "",
                    identifier: "spark.parent.id"
                )
                automationText(String(node.chainDepth), identifier: "spark.depth")
            }
            if let result = store.currentResult {
                automationText(result.id, identifier: "spark.visible-card.id")
                automationText(
                    result.bucket.rawValue,
                    identifier: "spark.visible-card.bucket"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private var activeNode: SparkChainNode? {
        guard let activityID = store.activeActivityID else { return nil }
        return store.chain.first { $0.activityID == activityID }
    }

    private var screenStateIdentifier: String {
        switch store.phase {
        case .idle, .loadingSource, .triggering, .replaying, .reconciling:
            return "screen.spark.loading"
        case .loaded:
            return "screen.spark.loaded"
        case .empty:
            return "screen.spark.empty"
        case .failed:
            return "screen.spark.error"
        }
    }

    private var automationStateIdentity: String {
        [
            screenStateIdentifier,
            store.activeActivityID ?? "",
            store.currentResult?.id ?? "",
            String(store.visibleIndex)
        ].joined(separator: "::")
    }

    private var usesAccessibilityEvidenceMode: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment[
            "CHORAI_UI_TEST_SPARK_ACCESSIBILITY_MODE"
        ] == "1"
#else
        false
#endif
    }

    private func automationText(
        _ value: String,
        identifier: String
    ) -> some View {
        Text(value)
            .font(.system(size: 1))
            .foregroundStyle(Color.white.opacity(0.01))
            .frame(width: 1, height: 1)
            .id("\(identifier)::\(value)")
            .accessibilityIdentifier(identifier)
    }

    private func openDetail(_ cardID: String) {
        selectedDetailCardID = cardID
        showDetail = true
    }

    private func openAuthor(_ authorID: String) {
        selectedAuthorID = authorID
        showAuthor = true
    }

    private func openMenu(_ card: FlowCard) {
        currentMenuCard = card.asUserCard
        menuCardIsOwned = card.author?.id == actorID
        showPopupMenu = true
    }
}

private struct SparkChainRail: View {
    let nodes: [SparkChainNode]
    let activeActivityID: String?
    let showsPendingNode: Bool
    let isInteractionLocked: Bool
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(displayedNodes) { node in
                    Button {
                        onSelect(node.activityID)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    node.activityID == activeActivityID
                                        ? ZenVisualTokens.accent.opacity(0.3)
                                        : Color.white.opacity(0.065)
                                )
                            Circle()
                                .stroke(
                                    node.activityID == activeActivityID
                                        ? ZenVisualTokens.accent
                                        : Color.white.opacity(0.16),
                                    lineWidth: 1
                                )
                            Text("\(node.chainDepth + 1)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(
                                    Color.white.opacity(
                                        node.activityID == activeActivityID ? 1 : 0.5
                                    )
                                )
                        }
                        .frame(width: 32, height: 32)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isInteractionLocked)
                    .accessibilityLabel(
                        "\(node.sourcePreview), depth \(node.chainDepth)"
                    )
                    .accessibilityValue(
                        node.activityID == activeActivityID ? "Current" : "Ancestor"
                    )
                    .accessibilityIdentifier("spark.chain.\(node.activityID)")
                }

                if showsPendingNode {
                    ZStack {
                        Circle()
                            .fill(ZenVisualTokens.accent.opacity(0.16))
                        Circle()
                            .stroke(
                                ZenVisualTokens.accent.opacity(0.52),
                                style: StrokeStyle(
                                    lineWidth: 1,
                                    dash: [3, 3]
                                )
                            )
                        Text("\(pendingDepth + 1)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                        .frame(width: 32, height: 32)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel(
                            "Spark depth \(pendingDepth), loading"
                        )
                        .accessibilityIdentifier("spark.chain.pending")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayedNodes: [SparkChainNode] {
        guard
            showsPendingNode,
            let activeActivityID,
            let activeIndex = nodes.firstIndex(where: {
                $0.activityID == activeActivityID
            })
        else {
            return nodes
        }

        return Array(nodes.prefix(through: activeIndex))
    }

    private var pendingDepth: Int {
        if let activeActivityID,
           let activeNode = nodes.first(where: {
               $0.activityID == activeActivityID
           }) {
            return activeNode.chainDepth + 1
        }

        return displayedNodes.last.map { $0.chainDepth + 1 } ?? 0
    }
}

private struct SparkResultCard: View {
    let result: SparkResult
    let isInteractionLocked: Bool
    let isLikeMutationInFlight: Bool
    let likeErrorMessage: String?
    let allowsSparkDeeper: Bool
    let forcesAccessibleAppearance: Bool
    let onNext: () -> Void
    let onToggleFavorite: () -> Void
    let onToggleLike: () -> Void
    let onSparkDeeper: () -> Void
    let onOpenCard: () -> Void
    let onOpenAuthor: () -> Void
    let onOpenMenu: () -> Void
    let onboardingState: String?
    let contextualTipStore: ContextualGuideTipStore?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var dragOffset: CGSize = .zero
    @State private var isResolvingGesture = false
    @State private var isHorizontalSwipeCommitted = false

    private var isSparkFavoriteTipVisible: Bool {
        contextualTipStore?.isVisible(
            .sparkFavorite,
            onboardingState: onboardingState,
            targetIsVisible: !result.card.isOwner
        ) ?? false
    }

    private func dismissSparkFavoriteTipIfVisible() {
        guard isSparkFavoriteTipVisible else { return }
        contextualTipStore?.dismiss(
            .sparkFavorite,
            onboardingState: onboardingState,
            targetIsVisible: !result.card.isOwner
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button(action: onOpenAuthor) {
                    HStack(spacing: 8) {
                        SparkAvatar(author: result.card.author, size: 28)
                        Text(result.card.author?.username ?? "Chorai")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(result.card.author == nil)
                .accessibilityLabel("Open author")

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
                    .accessibilityIdentifier("spark.menu.\(result.id)")

                    Button(action: onSparkDeeper) {
                        Image("menu_spark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!allowsSparkDeeper)
                    .accessibilityLabel("Continue Spark")
                    .accessibilityIdentifier("spark.continue.\(result.id)")
                }
            }

            if let bucketLabel {
                Text(bucketLabel)
                    .font(.caption2.weight(.semibold))
                    .tracking(0.7)
                    .foregroundStyle(ZenVisualTokens.accent.opacity(0.82))
            }

            tappableContent
            engagementFooter

            if let likeErrorMessage {
                Text(likeErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .accessibilityIdentifier("spark.like.error.\(result.id)")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: ZenVisualTokens.cardRadius,
                style: .continuous
            )
        )
        .offset(x: dragOffset.width)
        .rotationEffect(
            reduceMotion ? .zero : .degrees(Double(dragOffset.width / 42))
        )
        .disabled(isInteractionLocked || isResolvingGesture)
    }

    private var tappableContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(FlowTextPreview.make(result.card.content))
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .lineSpacing(5)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 5 : 7)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !result.card.tags.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(result.card.tags.prefix(3)), id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 28)
                            .background(
                                Capsule().fill(Color.white.opacity(0.08))
                            )
                    }
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenCard)
        .gesture(cardGesture)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityCardLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Next result"), onNext)
        .accessibilityAction(named: Text("Open card"), onOpenCard)
        .accessibilityIdentifier("spark.card.\(result.id)")
    }

    private var engagementFooter: some View {
        HStack(spacing: 10) {
            if !result.card.isOwner {
                Button(action: onToggleFavorite) {
                    SparkCount(
                        image: result.card.isFavorited
                            ? "favorite_active"
                            : "favorite",
                        count: result.card.favoriteCount,
                        label: "favorites",
                        iconSize: 24
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    result.card.isFavorited ? "Unfavorite" : "Favorite"
                )
                .accessibilityValue(result.card.isFavorited ? "true" : "false")
                .accessibilityIdentifier("spark.favorite.\(result.id)")
                .overlay {
                    ContextualGuideTargetHalo(
                        isVisible: isSparkFavoriteTipVisible
                    )
                }
                .overlay(alignment: .topLeading) {
                    if let contextualTipStore {
                        ContextualGuideCallout(
                            store: contextualTipStore,
                            tip: .sparkFavorite,
                            onboardingState: onboardingState,
                            targetIsVisible: !result.card.isOwner
                        )
                        .offset(y: -58)
                    }
                }
            }

            Spacer(minLength: 16)

            Button(action: onToggleLike) {
                SparkCount(
                    image: result.card.isLiked ? "like_active" : "like",
                    count: result.card.likeCount,
                    label: "likes"
                )
            }
            .buttonStyle(.plain)
            .disabled(isLikeMutationInFlight)
            .accessibilityLabel(result.card.isLiked ? "Unlike" : "Like")
            .accessibilityValue(result.card.isLiked ? "true" : "false")
            .accessibilityIdentifier("spark.like.\(result.id)")

            CommentButton(
                cardId: result.card.id,
                commentCount: result.card.commentCount,
                iconSize: 22
            )
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Comments")
            .accessibilityValue("\(result.card.commentCount)")
            .accessibilityIdentifier("spark.comment.\(result.id)")
            .simultaneousGesture(
                TapGesture().onEnded { _ in
                    dismissSparkFavoriteTipIfVisible()
                }
            )
        }
        .padding(.bottom, -18)
        .foregroundStyle(Color.white.opacity(0.58))
    }

    private var cardBackground: some View {
        RoundedRectangle(
            cornerRadius: ZenVisualTokens.cardRadius,
            style: .continuous
        )
        .fill(
            reduceTransparency
                ? Color(red: 0.09, green: 0.075, blue: 0.15)
                : ZenVisualTokens.cardFill
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: ZenVisualTokens.cardRadius,
                style: .continuous
            )
            .stroke(
                contrast == .increased
                    ? Color.white.opacity(0.44)
                    : ZenVisualTokens.cardBorder,
                lineWidth: 1
            )
        )
    }

    private var reduceMotion: Bool {
        forcesAccessibleAppearance || systemReduceMotion
    }

    private var reduceTransparency: Bool {
        forcesAccessibleAppearance || systemReduceTransparency
    }

    private var contrast: ColorSchemeContrast {
        forcesAccessibleAppearance ? .increased : systemContrast
    }

    private var cardGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard !isInteractionLocked, !isResolvingGesture else { return }
                dragOffset = CGSize(width: value.translation.width, height: 0)
                let decision = SparkGestureResolver.resolve(
                    translationX: Double(value.translation.width),
                    translationY: Double(value.translation.height),
                    predictedEndX: Double(value.predictedEndTranslation.width),
                    predictedEndY: Double(value.predictedEndTranslation.height)
                )
                if !isHorizontalSwipeCommitted, decision == .next {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                isHorizontalSwipeCommitted = decision == .next
            }
            .onEnded { value in
                let decision = SparkGestureResolver.resolve(
                    translationX: Double(value.translation.width),
                    translationY: Double(value.translation.height),
                    predictedEndX: Double(value.predictedEndTranslation.width),
                    predictedEndY: Double(value.predictedEndTranslation.height)
                )
                let exitDirection: CGFloat = value.predictedEndTranslation.width >= 0
                    ? 1
                    : -1
                resolve(decision, exitDirection: exitDirection)
            }
    }

    private func resolve(
        _ decision: SparkGestureDecision,
        exitDirection: CGFloat
    ) {
        guard decision != .cancel else {
            isHorizontalSwipeCommitted = false
            withAnimation(
                .spring(
                    response: ZenVisualTokens.transitionDuration,
                    dampingFraction: 0.86
                )
            ) {
                dragOffset = .zero
            }
            return
        }
        guard !isResolvingGesture else { return }

        isResolvingGesture = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        guard !reduceMotion else {
            resetGesture()
            onNext()
            return
        }

        withAnimation(
            .spring(
                response: ZenVisualTokens.transitionDuration,
                dampingFraction: 0.86
            )
        ) {
            dragOffset = CGSize(width: 640 * exitDirection, height: 0)
        }

        DispatchQueue.main.asyncAfter(
            deadline: .now() + ZenVisualTokens.transitionDuration
        ) {
            resetGesture()
            onNext()
        }
    }

    private func resetGesture() {
        dragOffset = .zero
        isHorizontalSwipeCommitted = false
        isResolvingGesture = false
    }

    private var accessibilityCardLabel: String {
        let content = FlowTextPreview.make(result.card.content)
        guard let bucketLabel else { return content }
        return "\(bucketLabel). \(content)"
    }

    private var bucketLabel: String? {
        switch result.bucket {
        case .related:
            return "RELATED"
        case .angles:
            return "ANGLE"
        case .keywords:
            return nil
        }
    }
}

private struct SparkAvatar: View {
    let author: FlowAuthor?
    let size: CGFloat

    var body: some View {
        Group {
            if let rawURL = author?.avatarURL,
               let url = URL(string: APIConfiguration.resourceURLString(rawURL)) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.white.opacity(0.09))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(Color.white.opacity(0.6))
            )
    }
}

private struct SparkCount: View {
    let image: String
    let count: Int
    let label: String
    let iconSize: CGFloat

    init(
        image: String,
        count: Int,
        label: String,
        iconSize: CGFloat = 22
    ) {
        self.image = image
        self.count = count
        self.label = label
        self.iconSize = iconSize
    }

    var body: some View {
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
        .foregroundStyle(Color.white.opacity(0.56))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(label)")
    }
}

private struct SparkDeckSkeleton: View {
    var body: some View {
        RoundedRectangle(
            cornerRadius: ZenVisualTokens.cardRadius,
            style: .continuous
        )
        .fill(ZenVisualTokens.cardFill)
        .overlay(
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Circle().fill(Color.white.opacity(0.08)).frame(width: 28, height: 28)
                    Capsule().fill(Color.white.opacity(0.08)).frame(width: 94, height: 10)
                    Spacer()
                }
                Capsule().fill(Color.white.opacity(0.08)).frame(width: 72, height: 9)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 16)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.065))
                    .frame(maxWidth: 250)
                    .frame(height: 16)
                Spacer()
            }
            .padding(22)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: ZenVisualTokens.cardRadius,
                style: .continuous
            )
            .stroke(ZenVisualTokens.cardBorder, lineWidth: 1)
        )
        .accessibilityLabel("Loading Spark")
    }
}

private struct SparkLoadingVeil: View {
    let isChecking: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image("menu_spark")
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
            if isChecking {
                Text("Checking Spark")
                    .font(.caption.weight(.medium))
            }
        }
        .foregroundStyle(Color.white.opacity(0.76))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.34))
        .clipShape(
            RoundedRectangle(
                cornerRadius: ZenVisualTokens.cardRadius,
                style: .continuous
            )
        )
        .accessibilityLabel(isChecking ? "Checking Spark" : "Loading Spark")
    }
}

private struct SparkCompactState: View {
    let title: String
    let message: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image("menu_spark")
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .opacity(0.72)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.52))
                    .multilineTextAlignment(.center)
            }
            if let action {
                Button(action: action) {
                    Image("menu_spark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry Spark")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SparkFailureNotice: View {
    let message: String
    let canRetry: Bool
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(message)
                .font(.caption.weight(.medium))
                .lineLimit(2)
            if canRetry {
                Button(action: retry) {
                    Image("menu_spark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry Spark")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, canRetry ? 4 : 14)
        .background(Capsule().fill(Color.black.opacity(0.72)))
    }
}
