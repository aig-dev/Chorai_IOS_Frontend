import CoreFlow
import Combine
import SwiftUI
import UIKit

struct SparkContinuationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    @StateObject private var store: SparkSessionStore
    @StateObject private var likeStore: CardLikeStore
    @State private var showPopupMenu = false
    @State private var currentMenuCard: UserCard?
    @State private var menuCardIsOwned = false
    @State private var selectedDetailCardID: String?
    @State private var selectedAuthorID: String?
    @State private var showDetail = false
    @State private var showAuthor = false
    @State private var presentationRevision = 0
    @State private var showsOfflineFixtureNotice = false
#if DEBUG
    private var usesOfflineFixture = false
#endif

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
        _likeStore = StateObject(wrappedValue: CardLikeStore(
            state: CardLikeState(cardID: "", isLiked: false, likeCount: 0),
            service: NetworkCoreCardLikeService(),
            onCommit: { CardEngagementCenter.shared.publish($0) }
        ))
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

#if DEBUG
    /// Uses the production view and state machine with process-local fixture services.
    static func fidelityFixture() -> SparkContinuationView {
        SparkContinuationView(fidelityService: SparkFidelityService())
    }

    private init(fidelityService service: SparkFidelityService) {
        actorID = SparkFidelityService.actorID
        rootCardID = SparkFidelityService.sourceID
        onboardingStore = nil
        contextualTipStore = nil
        usesOfflineFixture = true
        let session = SparkSessionStore(
            actorID: SparkFidelityService.actorID,
            rootSourceAssetID: SparkFidelityService.sourceID,
            service: service,
            persistence: SparkFidelityMemoryPersistence()
        )
        _store = StateObject(wrappedValue: session)
        _likeStore = StateObject(wrappedValue: CardLikeStore(
            state: CardLikeState(cardID: "", isLiked: false, likeCount: 0),
            service: SparkFidelityLikeService(),
            onCommit: { state in
                service.applyLikeState(state)
                session.applyLikeState(state)
            }
        ))
    }
#endif

    private var allowsNetworkNavigation: Bool {
#if DEBUG
        !usesOfflineFixture
#else
        true
#endif
    }

    private var allowsNativeMenuPresentation: Bool {
        if allowsNetworkNavigation { return true }
#if DEBUG
        return usesOfflineFixture
            && LocalDevelopmentPreview.isEnabled
            && ProcessInfo.processInfo.arguments.contains("--ui-test-spark-native-menus")
#else
        return false
#endif
    }

    var body: some View {
        ZStack {
            sparkAtmosphere

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        SparkChainRail(
                            nodes: store.chain,
                            activeActivityID: store.activeActivityID,
                            showsPendingNode: store.phase == .triggering || store.phase == .reconciling,
                            isInteractionLocked: store.isInteractionLocked,
                            onOpenRoot: {
                                dismissSparkFavoriteTipIfVisible()
                                openDetail(rootCardID)
                            },
                            onSelect: { nodeID in
                                dismissSparkFavoriteTipIfVisible()
                                store.selectNode(activityID: nodeID)
                            }
                        )
                        if let onboardingStore {
                            OnboardingGuideLine(
                                store: onboardingStore,
                                allowedStates: ["product_spark_intro", "product_spark_results", "product_save_material"]
                            )
                        }
                        sourceStrip
#if DEBUG
                        if usesOfflineFixture {
                            Label("Sample results · no AI request", systemImage: "sparkles")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ChoraiTheme.secondaryInk)
                                .accessibilityIdentifier("spark.fixture.offline")
                        }
#endif
                        if store.currentResult != nil {
                            HStack(alignment: .firstTextBaseline) {
                                Text((activeNode?.chainDepth ?? 0) == 0 ? "Related ideas" : "A little further")
                                    .font(.title3.weight(.semibold))
                                Spacer()
                            }
                        }
                        phaseContent.id(screenStateIdentifier)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .id(presentationRevision)
            .foregroundStyle(ChoraiTheme.ink)

            automationAnchors
                .id(automationStateIdentity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let result = store.currentResult {
                Button {
                    dismissSparkFavoriteTipIfVisible()
                    store.sparkCurrentDeeper()
                } label: {
                    HStack(spacing: 12) {
                        Label("Continue Spark", systemImage: "sparkles")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .foregroundStyle(ChoraiTheme.onAccent)
                    .background(ChoraiTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.phase != .loaded || store.isInteractionLocked)
                .accessibilityIdentifier("spark.continue.\(result.id)")
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)

        .alert("Offline Spark preview", isPresented: $showsOfflineFixtureNotice) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This fixture uses sample notes. Favorites and likes stay in memory; profiles, full-note routes, comments and sharing require the live app.")
        }
        .popupMenu(
            isPresented: $showPopupMenu,
            layout: menuCardIsOwned ? .grid3x3 : .grid3x2,
            cardData: currentMenuCard,
            isOwnCard: menuCardIsOwned,
            isSparkEnabled: store.phase == .loaded,
            onSpark: store.sparkCurrentDeeper,
            onRouteDismissed: { dismissal in
                if case .editor(let cardID) = dismissal.route {
                    store.refreshOwnedCardAfterEditing(cardID: cardID)
                }
            },
            ownedCardActionRefresh: store.ownedCardActionRefresh,
            ownedCardActionRefreshInFlight: store.isRefreshingOwnedCard,
            onOwnedCardActionCommitted: applyOwnedCardAction
        )
        .alert("Couldn’t refresh this note", isPresented: Binding(
            get: { store.ownedCardRefreshFailure != nil },
            set: { if !$0 { store.dismissOwnedCardRefreshFailure() } }
        ), presenting: store.ownedCardRefreshFailure) { cardID in
            Button("Retry") { store.refreshOwnedCardAfterEditing(cardID: cardID) }
            Button("Cancel", role: .cancel) { store.dismissOwnedCardRefreshFailure() }
        } message: { _ in
            Text("The last confirmed status is still shown. Try again to load your changes.")
        }
        .onChange(of: store.ownedCardActionRefresh?.id) { _ in
            guard let cardID = currentMenuCard?.id else { return }
            currentMenuCard = store.results.first(where: { $0.id == cardID })?.card.asUserCard
                ?? (store.sourceCard?.id == cardID ? store.sourceCard?.asUserCard : nil)
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .choraiFavoriteChanged)) { notification in
            guard let cardID = notification.userInfo?["cardID"] as? String,
                  let isFavorited = notification.userInfo?["isFavorited"] as? Bool else { return }
            store.applyFavoriteState(CardFavoriteState(
                cardID: cardID,
                isFavorited: isFavorited,
                favoriteCount: notification.userInfo?["count"] as? Int
            ))
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
        ChoraiBackground()
    }

    private var header: some View {
        ZStack {
            Text("Spark").font(.headline).foregroundStyle(.primary)
            HStack {
                Button {
                    dismissSparkFavoriteTipIfVisible()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .choraiGlassSurface(cornerRadius: 22)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("spark.back")
                Spacer()
                if let result = store.currentResult {
                    headerMenu(for: result.card)
                    .buttonStyle(.plain)
                    .choraiGlassSurface(cornerRadius: 22)
                    .accessibilityLabel("Note actions")
                    .accessibilityIdentifier("spark.header.menu")
                }
            }
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private func headerMenu(for card: FlowCard) -> some View {
        if allowsNativeMenuPresentation {
            NativeCardActionsMenu(
                cardData: card.asUserCard,
                layout: (card.isOwner || card.author?.id == actorID) ? .grid3x3 : .grid3x2,
                isOwnCard: card.isOwner || card.author?.id == actorID,
                isSparkEnabled: store.phase == .loaded,
                onPrepare: { openMenu(card) },
                onSpark: store.sparkCurrentDeeper
            ) {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
            }
        } else {
            Button { openMenu(card) } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
            }
        }
    }

    @ViewBuilder
    private var sourceStrip: some View {
        if let card = store.sourceCard {
            Button {
                dismissSparkFavoriteTipIfVisible()
                openDetail(card.id)
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ChoraiTheme.gold)
                        .frame(width: 3, height: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(card.isOwner ? "FROM YOUR NOTE" : "FROM \((card.author?.username ?? "CHORAI").uppercased())")
                            .font(.caption2.weight(.semibold))
                            .tracking(1)
                            .foregroundStyle(ChoraiTheme.secondaryInk)
                        CardPlainTextPreview(card: card)
                            .font(.subheadline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ChoraiTheme.gold)
                }
                .padding(15)
                .frame(maxWidth: .infinity, minHeight: 74)
                .background(ChoraiTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(ChoraiTheme.separator, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Read source note")
        } else {
            RoundedRectangle(cornerRadius: 18)
                .fill(ChoraiTheme.raisedSurface)
                .frame(height: 74)
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

                    SparkResultCard(
                        result: result,
                        isInteractionLocked: store.isInteractionLocked,
                        isLikeMutationInFlight: likeStore.isMutating,
                        likeErrorMessage: likeErrorMessage(for: result.card.id),
                        allowsSparkDeeper: store.phase == .loaded,
                        allowsNetworkNavigation: allowsNetworkNavigation,
                        allowsNativeMenuPresentation: allowsNativeMenuPresentation,
                        isMenuCardOwned: result.card.isOwner || result.card.author?.id == actorID,
                        forcesAccessibleAppearance: usesAccessibilityEvidenceMode,
                        onNext: {
                            dismissSparkFavoriteTipIfVisible()
                            store.advance()
                        },
                        onToggleFavorite: {
                            contextualTipStore?.complete(
                                .sparkFavorite,
                                onboardingState: onboardingStore?.contextualTipState,
                                targetIsVisible: !result.card.isOwner
                            )
                            store.toggleFavoriteCurrent(onFavoriteMutationSucceeded: { cardID, isFavorited, count in
                                guard allowsNetworkNavigation else { return }
                                NotificationCenter.default.post(
                                    name: .choraiFavoriteChanged,
                                    object: nil,
                                    userInfo: ["cardID": cardID, "isFavorited": isFavorited, "count": count]
                                )
                            }) { assetID in
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
                            if let author = result.card.author {
                                dismissSparkFavoriteTipIfVisible()
                                openAuthor(author.id)
                            }
                        },
                        onOpenMenu: {
                            dismissSparkFavoriteTipIfVisible()
                            openMenu(result.card)
                        },
                        onboardingState: onboardingStore?.contextualTipState,
                        contextualTipStore: contextualTipStore
                    )
                    .id(result.id)
                }

                HStack {
                    Button {
                        dismissSparkFavoriteTipIfVisible()
                        store.previous()
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                            .frame(minHeight: 44)
                    }
                    .disabled(store.visibleIndex == 0 || store.isInteractionLocked)
                    .accessibilityIdentifier("spark.previous")
                    Spacer()
                    Button {
                        dismissSparkFavoriteTipIfVisible()
                        store.advance()
                    } label: {
                        Label("Next idea", systemImage: "chevron.right")
                            .frame(minHeight: 44)
                    }
                    .disabled(store.nextResult == nil || store.isInteractionLocked)
                    .accessibilityIdentifier("spark.next")
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.plain)
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
            onboardingState: onboardingStore?.contextualTipState,
            targetIsVisible: targetIsVisible
        ) == true else {
            return
        }
        contextualTipStore?.dismiss(
            .sparkFavorite,
            onboardingState: onboardingStore?.contextualTipState,
            targetIsVisible: targetIsVisible
        )
    }

    @ViewBuilder
    private var noticeView: some View {
        switch store.notice {
        case .saveFailed:
            Text("Favorite failed. Try again.")
                .font(.footnote)
                .foregroundStyle(ChoraiTheme.secondaryInk)
                .frame(minHeight: 44)
                .accessibilityIdentifier("spark.save.failed")
        case .moreFailed:
            Text("More results paused.")
                .font(.footnote)
                .foregroundStyle(ChoraiTheme.secondaryInk)
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
            .foregroundStyle(ChoraiTheme.ink.opacity(0.01))
            .frame(width: 1, height: 1)
            .id("\(identifier)::\(value)")
            .accessibilityIdentifier(identifier)
    }

    private func openDetail(_ cardID: String) {
        guard allowsNetworkNavigation else {
            showsOfflineFixtureNotice = true
            return
        }
        selectedDetailCardID = cardID
        showDetail = true
    }

    private func openAuthor(_ authorID: String) {
        guard allowsNetworkNavigation else {
            showsOfflineFixtureNotice = true
            return
        }
        selectedAuthorID = authorID
        showAuthor = true
    }

    private func applyOwnedCardAction(_ commit: OwnedCardActionCommit) {
        let removedSource: Bool
        if case .removed(let cardID) = commit {
            removedSource = cardID == rootCardID || cardID == store.sourceCard?.id
        } else {
            removedSource = false
        }
        store.applyOwnedCardAction(commit)
        if currentMenuCard?.id == commit.cardID {
            currentMenuCard = store.results.first(where: { $0.id == commit.cardID })?.card.asUserCard
                ?? (store.sourceCard?.id == commit.cardID ? store.sourceCard?.asUserCard : nil)
        }
        if removedSource { dismiss() }
    }

    private func openMenu(_ card: FlowCard) {
        guard allowsNativeMenuPresentation else {
            showsOfflineFixtureNotice = true
            return
        }
        dismissSparkFavoriteTipIfVisible()
        currentMenuCard = card.asUserCard
        menuCardIsOwned = card.isOwner || card.author?.id == actorID
    }
}

private struct SparkChainRail: View {
    let nodes: [SparkChainNode]
    let activeActivityID: String?
    let showsPendingNode: Bool
    let isInteractionLocked: Bool
    let onOpenRoot: () -> Void
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                Button(action: onOpenRoot) {
                    Image(systemName: "doc.text").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .choraiGlassSurface(cornerRadius: 22)
                .accessibilityLabel("Read original source")
                ForEach(displayedNodes) { node in
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                        .accessibilityHidden(true)
                    Button { onSelect(node.activityID) } label: {
                        HStack(spacing: 6) {
                            Text("\(node.chainDepth + 1)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                            Text(node.chainDepth == 0 ? "First Spark" : "Deeper")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 13)
                        .frame(minHeight: 44)
                        .foregroundStyle(node.activityID == activeActivityID ? ChoraiTheme.onAccent : ChoraiTheme.ink)
                        .background(node.activityID == activeActivityID ? ChoraiTheme.accent : ChoraiTheme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isInteractionLocked)
                    .accessibilityLabel("\(node.sourcePreview), depth \(node.chainDepth)")
                    .accessibilityValue(node.activityID == activeActivityID ? "Current" : "Ancestor")
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
                            .foregroundStyle(ChoraiTheme.secondaryInk)
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
    let allowsNetworkNavigation: Bool
    let allowsNativeMenuPresentation: Bool
    let isMenuCardOwned: Bool
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

    @ViewBuilder
    private var resultMenu: some View {
        if allowsNativeMenuPresentation {
            NativeCardActionsMenu(
                cardData: result.card.asUserCard,
                layout: isMenuCardOwned ? .grid3x3 : .grid3x2,
                isOwnCard: isMenuCardOwned,
                isSparkEnabled: allowsSparkDeeper,
                onPrepare: onOpenMenu,
                onSpark: onSparkDeeper
            ) {
                menuLabel
            }
        } else {
            Button(action: onOpenMenu) { menuLabel }
        }
    }

    private var menuLabel: some View {
        Image(systemName: "ellipsis")
            .font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

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

    @State private var previewSnapshotID = UUID()

    var body: some View {
        CardPreviewValue(input: LibraryCardPreviewInput(
            cardID: result.card.id, contentHash: result.card.contentHash, snapshotID: previewSnapshotID,
            content: result.card.content, contentJSON: result.card.contentJSON
        )) { presentation in
            cardBody(presentation: presentation)
        }
    }

    private func cardBody(presentation: LibraryCardPresentation?) -> some View {
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

                if let bucketLabel {
                    Text(bucketLabel.capitalized)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ChoraiTheme.gold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(ChoraiTheme.gold.opacity(0.09), in: Capsule())
                }

                resultMenu
                    .buttonStyle(.plain)
                    .accessibilityLabel("More actions")
                    .accessibilityIdentifier("spark.menu.\(result.id)")
            }

            ChoraiLevelBadge(rate: result.card.rate, compact: true)

            tappableContent(presentation: presentation)
            Button(action: onOpenCard) {
                Label("Read full note", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            Divider()
            engagementFooter

            if let likeErrorMessage {
                Text(likeErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(ChoraiTheme.secondaryInk)
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
        .choraiCardLevel(rate: result.card.rate)
        .offset(x: dragOffset.width)
        .rotationEffect(
            reduceMotion ? .zero : .degrees(Double(dragOffset.width / 42))
        )
        .disabled(isInteractionLocked || isResolvingGesture)
    }

    private func tappableContent(presentation: LibraryCardPresentation?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(presentation?.preview.text ?? "")
                .font(.system(.title3, design: .serif))
                .lineSpacing(5)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 7 : 9)
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
                                Capsule().fill(ChoraiTheme.ink.opacity(0.08))
                            )
                    }
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenCard)
        .gesture(cardGesture)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityCardLabel(presentation: presentation))
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
                        .frame(width: 220, alignment: .leading)
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
            #if DEBUG
            .disabled(!allowsNetworkNavigation && !CommentPresentationFixture.isEnabled)
            #else
            .disabled(!allowsNetworkNavigation)
            #endif
            .simultaneousGesture(
                TapGesture().onEnded { _ in
                    dismissSparkFavoriteTipIfVisible()
                }
            )
        }
        .foregroundStyle(ChoraiTheme.secondaryInk)
    }

    private var cardBackground: some View {
        RoundedRectangle(
            cornerRadius: ZenVisualTokens.cardRadius,
            style: .continuous
        )
        .fill(
            reduceTransparency
                ? ChoraiTheme.surface
                : ZenVisualTokens.cardFill
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: ZenVisualTokens.cardRadius,
                style: .continuous
            )
            .stroke(
                contrast == .increased
                    ? ChoraiTheme.ink.opacity(0.44)
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

    private func accessibilityCardLabel(presentation: LibraryCardPresentation?) -> String {
        let content = presentation?.plainText ?? ""
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
            .fill(ChoraiTheme.ink.opacity(0.09))
            .overlay(
                Text(author?.username.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined() ?? "C")
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(ChoraiTheme.secondaryInk)
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

    private var symbol: String {
        switch image {
        case "favorite_active": "bookmark.fill"
        case "favorite": "bookmark"
        case "like_active": "heart.fill"
        case "like": "heart"
        default: "bubble.right"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: iconSize - 3, weight: .regular))
                .frame(width: iconSize, height: iconSize)
            Text("\(count)")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .foregroundStyle(ChoraiTheme.secondaryInk)
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
                    Circle().fill(ChoraiTheme.ink.opacity(0.08)).frame(width: 28, height: 28)
                    Capsule().fill(ChoraiTheme.ink.opacity(0.08)).frame(width: 94, height: 10)
                    Spacer()
                }
                Capsule().fill(ChoraiTheme.ink.opacity(0.08)).frame(width: 72, height: 9)
                RoundedRectangle(cornerRadius: 6)
                    .fill(ChoraiTheme.ink.opacity(0.08))
                    .frame(height: 16)
                RoundedRectangle(cornerRadius: 6)
                    .fill(ChoraiTheme.ink.opacity(0.065))
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
            Image(systemName: "sparkles")
                .font(.body.weight(.medium))
                .frame(width: 26, height: 26)
            if isChecking {
                Text("Checking Spark")
                    .font(.caption.weight(.medium))
            }
        }
        .foregroundStyle(ChoraiTheme.secondaryInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChoraiTheme.surface.opacity(0.82))
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
            Image(systemName: "sparkles")
                .font(.body.weight(.medium))
                .frame(width: 38, height: 38)
                .opacity(0.72)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(ChoraiTheme.ink.opacity(0.52))
                    .multilineTextAlignment(.center)
            }
            if let action {
                Button(action: action) {
                    Image(systemName: "sparkles")
                .font(.body.weight(.medium))
                        .frame(width: 22, height: 22)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(ChoraiTheme.ink.opacity(0.08)))
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
                    Image(systemName: "sparkles")
                .font(.body.weight(.medium))
                        .frame(width: 18, height: 18)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry Spark")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, canRetry ? 4 : 14)
        .background(Capsule().fill(ChoraiTheme.raisedSurface))
    }
}

#if DEBUG
// Offline fidelity data: the approved V8 Model's first source and its Nia/Leo
// Spark results. These services cannot access the transport or durable storage.
private final class SparkFidelityService: CoreSparkServing {
    static let actorID = "fixture-spark-actor"
    static let sourceID = "fixture-spark-source"
    private static let resultIDs = ["fixture-spark-nia", "fixture-spark-leo"]
    private var cards: [String: FlowCard]
    private var activities: [String: SparkActivityPage] = [:]

    init() {
        let source = Self.makeCard(
            id: Self.sourceID, content: "Some ideas need a little room.\n\nI used to think a good note was a finished thought. Now I think it is a place to return to. A sentence, a question, something noticed on the way home.\n\nWhat if we leave the edges open? Give an idea enough space to meet another one. Let the connection arrive before the conclusion.\n\nToday, I’m keeping the unfinished things.",
            authorID: Self.actorID, author: "You", tags: ["Writing", "Ideas"], owned: true
        )
        let nia = Self.makeCard(
            id: "fixture-spark-nia", content: "Leave a little unfinished.\n\nA line from my notebook after a long conversation. Sharing an idea before it is polished can give someone else a place to begin.",
            authorID: "fixture-spark-author-nia", author: "Nia Bell", tags: ["Writing", "Ideas"]
        )
        let leo = Self.makeCard(
            id: "fixture-spark-leo", content: "A garden is never quite finished.\n\nPerhaps knowledge works the same way. We keep what is growing, make room for what is next, and learn to see a path where there wasn’t one before.\n\nThinking together is a way of tending it.\n\nLast winter I stopped sorting every note into a perfect folder. I began leaving small paths instead: a question beside an observation, a passage beside a drawing. The connections were uneven, but they were mine.\n\nA useful garden has more than one pace. There are places to pause and places to pass through. Some ideas need a season before they become useful; others give something back the day you put them in the ground.\n\nWhen a friend adds a different view, the whole arrangement changes. What looked like a dead end becomes a place to sit. A familiar sentence opens onto another person’s experience.\n\nI still make lists. I still pull weeds. But I no longer mistake a tidy system for a living one. The point is to keep something growing.",
            authorID: "fixture-spark-author-leo", author: "Leo Park", tags: ["Design", "Connections"]
        )
        cards = Dictionary(uniqueKeysWithValues: [source, nia, leo].map { ($0.id, $0) })
    }

    func card(assetID: String) -> AnyPublisher<FlowCard, CoreSparkError> {
        guard let card = cards[assetID] else { return failure(.notFound) }
        return value(card)
    }

    func trigger(sourceAssetID: String, parentActivityID: String?) -> AnyPublisher<SparkActivityPage, CoreSparkError> {
        guard cards[sourceAssetID] != nil else { return failure(.notFound) }
        if let parentActivityID, activities[parentActivityID] == nil { return failure(.notFound) }
        let parent = parentActivityID.flatMap { activities[$0] }
        let activityID = "fixture-spark-activity-\(activities.count + 1)"
        // Reusing sample notes is intentional; no generated content or AI request is implied.
        let results = (Self.resultIDs + [Self.sourceID])
            .filter { $0 != sourceAssetID }
            .compactMap { cards[$0] }
            .map { SparkResult(card: $0, bucket: .related, score: 1, resultID: "\(activityID)-\($0.id)") }
        let page = SparkActivityPage(
            activityID: activityID,
            parentActivityID: parentActivityID,
            rootActivityID: parent?.rootActivityID ?? activityID,
            chainDepth: (parent?.chainDepth).map { $0 + 1 } ?? 0,
            sourceAssetID: sourceAssetID,
            groups: [.related: results],
            createdAt: Date(timeIntervalSince1970: 1_792_534_400)
        )
        activities[activityID] = page
        return value(page)
    }

    func activityResults(activityID: String) -> AnyPublisher<SparkActivityPage, CoreSparkError> {
        guard let page = activities[activityID] else { return failure(.notFound) }
        return value(SparkActivityPage(
            activityID: page.activityID, parentActivityID: page.parentActivityID,
            rootActivityID: page.rootActivityID, chainDepth: page.chainDepth,
            sourceAssetID: page.sourceAssetID,
            groups: page.groups.mapValues { results in
                results.map { SparkResult(card: cards[$0.id] ?? $0.card, bucket: $0.bucket, score: $0.score, resultID: $0.resultID) }
            },
            createdAt: page.createdAt
        ))
    }

    func history(sourceAssetID: String, limit: Int) -> AnyPublisher<[SparkHistoryEntry], CoreSparkError> {
        let history = activities.values.filter { $0.sourceAssetID == sourceAssetID }
            .sorted { $0.activityID < $1.activityID }
            .prefix(max(0, limit))
            .map { SparkHistoryEntry(
                activityID: $0.activityID, parentActivityID: $0.parentActivityID,
                sourceAssetID: $0.sourceAssetID, rootActivityID: $0.rootActivityID,
                chainDepth: $0.chainDepth, createdAt: $0.createdAt ?? .distantPast
            ) }
        return value(history)
    }

    func more(sourceAssetID: String, cursor: String?, limit: Int) -> AnyPublisher<SparkMorePage, CoreSparkError> {
        value(SparkMorePage(results: [], nextCursor: nil, round: 1, sourceAssetID: sourceAssetID))
    }

    func favorite(assetID: String, sparkActivityID: String) -> AnyPublisher<Void, CoreSparkError> {
        guard activities[sparkActivityID] != nil else { return failure(.notFound) }
        return setFavorite(assetID: assetID, favorited: true)
    }

    func unfavorite(assetID: String) -> AnyPublisher<Void, CoreSparkError> {
        setFavorite(assetID: assetID, favorited: false)
    }

    func applyLikeState(_ state: CardLikeState) {
        guard let card = cards[state.cardID] else { return }
        cards[state.cardID] = card.replacingLike(with: state)
    }

    private func setFavorite(assetID: String, favorited: Bool) -> AnyPublisher<Void, CoreSparkError> {
        guard let card = cards[assetID], !card.isOwner else { return failure(.forbidden) }
        let delta = card.isFavorited == favorited ? 0 : (favorited ? 1 : -1)
        cards[assetID] = card.replacingFavorite(
            isFavorited: favorited,
            favoriteCount: max(0, card.favoriteCount + delta)
        )
        return value(())
    }

    private func value<T>(_ value: T) -> AnyPublisher<T, CoreSparkError> {
        Just(value).setFailureType(to: CoreSparkError.self).eraseToAnyPublisher()
    }

    private func failure<T>(_ error: CoreSparkError) -> AnyPublisher<T, CoreSparkError> {
        Fail(error: error).eraseToAnyPublisher()
    }

    private static func makeCard(
        id: String, content: String, authorID: String, author: String,
        tags: [String], owned: Bool = false
    ) -> FlowCard {
        FlowCard(
            id: id, title: nil, content: content, contentHash: nil,
            tags: tags, isPublic: !owned,
            createdAt: "2026-10-21T09:00:00Z", updatedAt: "2026-10-21T09:00:00Z",
            favoriteCount: 0, likeCount: 0, commentCount: 0, rate: 0,
            isFavorited: false, isLiked: false, isPinned: false, pinnedAt: nil,
            author: FlowAuthor(id: authorID, username: author, avatarURL: nil),
            isOwner: owned
        )
    }
}

private actor SparkFidelityLikeService: CoreCardLikeServing {
    private var likes: [String: Bool] = [:]

    func setLiked(cardID: String, liked: Bool) async throws {
        likes[cardID] = liked
    }
}

private final class SparkFidelityMemoryPersistence: SparkSessionPersisting {
    private var saved: SparkSessionSnapshot?

    func snapshot(actorID: String, rootSourceAssetID: String) -> SparkSessionSnapshot? {
        guard saved?.actorID == actorID, saved?.rootSourceAssetID == rootSourceAssetID else { return nil }
        return saved
    }

    func save(_ snapshot: SparkSessionSnapshot) { saved = snapshot }

    func remove(actorID: String, rootSourceAssetID: String) {
        guard saved?.actorID == actorID, saved?.rootSourceAssetID == rootSourceAssetID else { return }
        saved = nil
    }
}
#endif
