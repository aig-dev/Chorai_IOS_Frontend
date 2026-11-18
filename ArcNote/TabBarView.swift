import SwiftUI
import Combine
import CoreFlow
import UIKit

struct TabBarView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var mergeTaskCoordinator: MergeTaskCoordinator
    @EnvironmentObject private var onboardingStore: OnboardingGuideStore
    @EnvironmentObject private var contextualTipStore: ContextualGuideTipStore
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var coordinator = CoreFlowCoordinator()
    @StateObject private var keyboardLayout = KeyboardLayoutObserver()
    @State private var showPopupMenu = false
    @State private var showSideMenu = false
    @State private var currentMenuCardData: UserCard? = nil
    @State private var navigationPaths: [CoreTab: NavigationPath] = [:]
    @State private var hasRoutedInitialOnboardingState = false
    @State private var libraryCardRouteCoverageDepth = 0
    @State private var isLibrarySurfaceVisible = false
    @State private var shareRoute: ShareRoute?
    @State private var reportRoute: ReportRoute?
    @State private var lastSelectedTab: CoreTab = .flow

    #if DEBUG
    @State private var lastCreatedNoteID: String?
    @State private var exploreSearchSmokeInvoked = false
    @State private var exploreSearchSmokeInFlight = false
    @State private var exploreSearchSmokeCompleted = false
    @State private var exploreDetailSmokeInvoked = false
    @State private var exploreDetailSmokeInFlight = false
    @State private var selectedDetailSmokeCardId: String? = nil
    @State private var navigateToDetailSmoke = false
    @State private var detailSmokeCancellable: AnyCancellable?
    @State private var exploreDetailSmokeAutoStarted = false
    @State private var visibleExploreCardId: String? = nil
    #endif

    private enum TabRoute: Hashable {
        case spark(String)
        case detail(String)
    }

    private struct ShareRoute: Identifiable {
        let cardID: String
        var id: String { cardID }
    }

    private struct ReportRoute: Identifiable {
        let cardID: String
        var id: String { cardID }
    }

    private var onboardingSparkResumePersistence:
        UserDefaultsOnboardingSparkResumeStore
    {
        let scope = ProcessInfo.processInfo.environment[
            "CHORAI_UI_TEST_SPARK_SESSION_SCOPE"
        ]
        let keyPrefix = scope.map {
            "chorai.onboarding.spark.resume.\($0)"
        } ?? "chorai.onboarding.spark.resume"
        return UserDefaultsOnboardingSparkResumeStore(keyPrefix: keyPrefix)
    }

    private var sparkResumeRootSourceAssetID: String? {
        guard onboardingStore.phase == .active,
              let actorID = authManager.currentUser?.id,
              let session = onboardingStore.session,
              session.flowVersion
                == OnboardingGuideStore.canonicalFlowVersion else {
            return nil
        }
        return onboardingSparkResumePersistence.metadata(
            actorID: actorID,
            sessionID: session.sessionID
        )?.rootSourceAssetID
    }

    private func syncContextualTipsWithOnboardingSession() {
        guard authManager.sessionPhase == .verified,
              let actorID = authManager.currentUser?.id,
              onboardingStore.phase == .active,
              let session = onboardingStore.session,
              session.flowVersion
                == OnboardingGuideStore.canonicalFlowVersion else {
            contextualTipStore.reset()
            return
        }
        guard contextualTipStore.actorID != actorID
                || contextualTipStore.sessionID != session.sessionID else {
            return
        }
        contextualTipStore.load(
            actorID: actorID,
            sessionID: session.sessionID
        )
    }

    private func dismissContextualTipWhenLeaving(_ tab: CoreTab) {
        let onboardingState = onboardingStore.contextualTipState
        switch (tab, onboardingState) {
        case (.library, "elicit_signal"):
            contextualTipStore.dismiss(
                .libraryCreate,
                onboardingState: onboardingState,
                targetIsVisible: true
            )
        case (.flow, "product_curator_intro"),
             (.flow, "product_explore_card"):
            contextualTipStore.dismiss(
                .flowCard,
                onboardingState: onboardingState,
                targetIsVisible: true
            )
        case (.flow, "product_spark_intro"):
            contextualTipStore.dismiss(
                .flowSpark,
                onboardingState: onboardingState,
                targetIsVisible: true
            )
        case (.flow, "product_spark_results"),
             (.flow, "product_save_material"):
            contextualTipStore.dismiss(
                .sparkResume,
                onboardingState: onboardingState,
                targetIsVisible:
                    OnboardingSparkContinuationPolicy.shouldShowResumeTip(
                        onboardingState: onboardingState,
                        resumeRootSourceAssetID: sparkResumeRootSourceAssetID
                    )
            )
        case (.library, "product_merge_intro"):
            contextualTipStore.dismiss(
                .libraryMergeEntry,
                onboardingState: onboardingState,
                targetIsVisible: true
            )
        case (.library, "product_merge_preview"):
            contextualTipStore.dismiss(
                .mergeResume,
                onboardingState: onboardingState,
                targetIsVisible: !mergeTaskCoordinator.summaries.isEmpty
            )
        default:
            break
        }
    }

    #if DEBUG
    private var onboardingPhaseLabel: String {
        switch onboardingStore.phase {
        case .idle: return "idle"
        case .loading: return "loading"
        case .active: return "active"
        case .completed: return "completed"
        case .skipped: return "skipped"
        case .deferred(let flowVersion): return "deferred:\(flowVersion)"
        case .unavailable: return "unavailable"
        }
    }
    #endif

    private func routeInitialOnboardingState(_ state: String?) {
        guard !hasRoutedInitialOnboardingState,
              let state,
              OnboardingGuideNavigationDirective.forState(state) != nil else {
            return
        }
        hasRoutedInitialOnboardingState = true
        applyOnboardingNavigation(for: state)
    }

    private func applyOnboardingNavigation(for state: String?) {
        guard onboardingStore.phase == .active,
              let state,
              let directive = OnboardingGuideNavigationDirective.forState(
                state
              ) else {
            return
        }
        DispatchQueue.main.async {
            if directive.clearsNavigationPath {
                clearTabNavigationPaths()
            }

            switch directive.destination {
            case .library:
                coordinator.selectedTab = .library
            case .flow:
                coordinator.selectedTab = .flow
            }
        }
    }

    #if DEBUG
    private var activeScreenAutomationAnchor: some View {
        let identifier: String
        let label: String

        switch coordinator.selectedTab {
        case .library:
            identifier = "screen.home.content"
            label = "Library screen"
        case .chat:
            identifier = "screen.chat.content"
            label = "Chat screen"
        case .flow:
            identifier = "screen.flow.content"
            label = "Flow screen"
        }

        return Text(label)
            .font(.system(size: 1))
            .foregroundColor(ChoraiTheme.ink.opacity(0.01))
            .frame(width: 1, height: 1)
            .accessibilityIdentifier(identifier)
    }

    private func submitExploreSearchSmoke() {
        print("Explore search smoke invoked")
        exploreSearchSmokeInvoked = true
        exploreSearchSmokeCompleted = false
        exploreSearchSmokeInFlight = true

        ExploreSearchManager.shared.searchCards(query: "go api ui smoke unlikely result") { _ in
            DispatchQueue.main.async {
                print("Explore search smoke completed")
                exploreSearchSmokeInFlight = false
                exploreSearchSmokeCompleted = true
            }
        }
    }

    private func openExploreRecommendedDetailSmoke() {
        print("Explore detail smoke invoked")
        exploreDetailSmokeInvoked = true
        exploreDetailSmokeInFlight = true
        selectedDetailSmokeCardId = nil
        navigateToDetailSmoke = false

        if let requestedCardId = ProcessInfo.processInfo.environment["CHORAI_UI_TEST_DETAIL_CARD_ID"],
           !requestedCardId.isEmpty {
            exploreDetailSmokeInFlight = false
            selectedDetailSmokeCardId = requestedCardId
            navigateToDetailSmoke = true
            return
        }

        detailSmokeCancellable = NetworkManager.shared
            .getRecommendedCards(limit: 1)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    exploreDetailSmokeInFlight = false
                    if case .failure(let error) = completion {
                        print("Explore detail smoke failed: \(error.localizedDescription)")
                    }
                },
                receiveValue: { response in
                    guard let card = response.data.first else {
                        print("Explore detail smoke has no recommended card")
                        return
                    }

                    selectedDetailSmokeCardId = card.id
                    navigateToDetailSmoke = true
                }
            )
    }

    private func startExploreDetailSmokeIfRequested() {
        guard !exploreDetailSmokeAutoStarted,
              ProcessInfo.processInfo.arguments.contains("--ui-test-open-recommended-detail") else {
            return
        }

        exploreDetailSmokeAutoStarted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            coordinator.selectedTab = .flow
            openExploreRecommendedDetailSmoke()
        }
    }
    #endif

    // MARK: - My Notes 点击处理
    private func onMyNotesTapped() {
        coordinator.openLibrary(scope: .notes)
        closeAllPopups()
    }
    
    // MARK: - Favorites 点击处理
    private func onFavoritesTapped() {
        coordinator.openLibrary(scope: .collect)
        closeAllPopups()
    }
    
    // MARK: - 关闭所有 Popup
    private func closeAllPopups() {
        // 关闭 popup 菜单
        showPopupMenu = false
        
        // 关闭侧边菜单
        showSideMenu = false
        
        // 发送通知关闭所有 popup
        NotificationCenter.default.post(
            name: NSNotification.Name("CloseAllPopups"),
            object: nil
        )
        
        print("已关闭所有 popup")
    }

    private func handleNoteCreated(cardID: String, content: String) {
        #if DEBUG
        lastCreatedNoteID = cardID
        #endif
        coordinator.noteCreated()
        onboardingStore.receive(
            .noteCreated(cardID: cardID, content: content)
        )
    }

    private func handleSparkRequested(proposedCardID: String) {
        let onboardingState = onboardingStore.contextualTipState
        let existingResumeRoot = sparkResumeRootSourceAssetID
        guard let rootSourceAssetID = OnboardingSparkContinuationPolicy
            .requestedRootSourceAssetID(
                onboardingState: onboardingState,
                proposedCardID: proposedCardID,
                resumeRootSourceAssetID: existingResumeRoot
            ) else {
            return
        }

        if onboardingState == "product_spark_intro",
           existingResumeRoot == nil,
           let actorID = authManager.currentUser?.id,
           let session = onboardingStore.session {
            onboardingSparkResumePersistence.save(
                OnboardingSparkResumeMetadata(
                    actorID: actorID,
                    sessionID: session.sessionID,
                    rootSourceAssetID: rootSourceAssetID
                )
            )
        }

        navigationPaths[coordinator.selectedTab, default: NavigationPath()]
            .append(TabRoute.spark(rootSourceAssetID))
    }

    private func pruneSparkResumeMetadataIfNeeded(for state: String?) {
        guard let state,
              ![
                "product_spark_intro",
                "product_spark_results",
                "product_save_material",
              ].contains(state),
              let actorID = authManager.currentUser?.id,
              let session = onboardingStore.session,
              session.flowVersion
                == OnboardingGuideStore.canonicalFlowVersion else {
            return
        }
        onboardingSparkResumePersistence.remove(
            actorID: actorID,
            sessionID: session.sessionID
        )
    }

    private func handleLibraryCardRouteDismissed(
        _: CardNavigationDismissal
    ) {}

    private func handleLibraryCardRoutePresentationChanged(
        _ isPresented: Bool
    ) {
        isLibrarySurfaceVisible = false
        if isPresented {
            libraryCardRouteCoverageDepth += 1
        } else {
            libraryCardRouteCoverageDepth = max(
                0,
                libraryCardRouteCoverageDepth - 1
            )
        }
    }

    private func handleLibrarySurfaceVisibilityChanged(_ isVisible: Bool) {
        isLibrarySurfaceVisible = isVisible
        if isVisible {
            recordLibraryViewedIfVisible()
        }
    }

    private var isLibraryCovered: Bool {
        isTabBarCovered || showSideMenu
    }

    private var isTabBarCovered: Bool {
        mergeTaskCoordinator.presentation != nil
            || libraryCardRouteCoverageDepth > 0
            || shareRoute != nil
            || reportRoute != nil
    }

    private var isOnboardingLibrarySurfaceActive: Bool {
        onboardingStore.contextualTipState == "product_library_intro"
            && coordinator.selectedTab == .library
            && !isLibraryCovered
    }

    private func recordLibraryViewedIfVisible() {
        guard OnboardingGuideLibraryVisibilityPolicy
            .shouldRecordLibraryViewed(
                onboardingState: onboardingStore.contextualTipState,
                isLibrarySelected: coordinator.selectedTab == .library,
                isLibrarySurfaceVisible: isLibrarySurfaceVisible,
                isLibraryCovered: isLibraryCovered
            ) else {
            return
        }
        onboardingStore.receive(.libraryViewed)
    }

    private func navigationPath(for tab: CoreTab) -> Binding<NavigationPath> {
        Binding(
            get: { navigationPaths[tab] ?? NavigationPath() },
            set: { navigationPaths[tab] = $0 }
        )
    }

    private func clearTabNavigationPaths() {
        navigationPaths.removeAll()
    }

    private func tabNavigationRoot<Content: View>(
        _ tab: CoreTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack(path: navigationPath(for: tab)) {
            ZStack {
                content()
                // Keep the sidebar's existing destinations in the presenting tab.
                // Inactive tabs must not also load a hidden copy of the drawer.
                if coordinator.selectedTab == tab {
                    SideMenuView(
                        isPresented: $showSideMenu,
                        onMyNotesTapped: onMyNotesTapped,
                        onFavoritesTapped: onFavoritesTapped
                    )
                }
            }
            .popupMenu(
                isPresented: Binding(
                    get: { coordinator.selectedTab == tab && showPopupMenu },
                    set: { showPopupMenu = $0 }
                ),
                layout: .grid2x2,
                cardData: currentMenuCardData
            )
            // Let pushed destinations own their tab visibility. Forcing visible
            // here also kept the reader's tab bar visible despite its hidden rule.
            .toolbar(isTabBarCovered || keyboardLayout.isVisible ? .hidden : .automatic, for: .tabBar)
            #if DEBUG
            .navigationDestination(isPresented: Binding(
                    get: { coordinator.selectedTab == tab && navigateToDetailSmoke },
                    set: { navigateToDetailSmoke = $0 }
                )) {
                if let cardId = selectedDetailSmokeCardId {
                    DetailView(cardId: cardId)
                        .toolbar(.hidden, for: .tabBar)
                        .environmentObject(mergeTaskCoordinator)
                        .environment(
                            \.cardNavigationMergeCoordinator,
                            mergeTaskCoordinator
                        )
                } else {
                    EmptyView()
                }
            }
            #endif
            .navigationDestination(for: TabRoute.self) { route in
                switch route {
                case .spark(let cardId):
                    if let actorID = AuthManager.shared.currentUser?.id {
                        SparkContinuationView(
                            cardID: cardId,
                            actorID: actorID,
                            onboardingStore: onboardingStore,
                            contextualTipStore: contextualTipStore
                        )
                        .toolbar(.hidden, for: .tabBar)
                    } else {
                        EmptyView()
                    }
                case .detail(let cardId):
                    DetailView(cardId: cardId)
                        .toolbar(.hidden, for: .tabBar)
                        .environmentObject(mergeTaskCoordinator)
                        .environment(
                            \.cardNavigationMergeCoordinator,
                            mergeTaskCoordinator
                        )
                }
            }
        }
    }

    private var allowsCommunityTabs: Bool {
        #if DEBUG
        if LocalDevelopmentPreview.isEnabled { return true }
        #endif
        return authManager.canEnterProduct
    }

    var body: some View {
        ZStack {
            
            // 主要内容区域 - 全屏显示
            TabView(selection: Binding(get: { coordinator.selectedTab }, set: { tab in
                if tab == .library || allowsCommunityTabs { coordinator.selectedTab = tab }
            })) {
                // Explore 页面
                tabNavigationRoot(.flow) {
                ExploreView(
                    showSideMenu: $showSideMenu,
                    onSpark: { cardId in
                        handleSparkRequested(proposedCardID: cardId)
                    },
                    onFlowCardVisible: { assetID in
                        onboardingStore.receive(.flowViewed)
                    },
                    onFlowCardSaved: { assetID in
                        onboardingStore.receive(.flowCardSaved(assetID: assetID))
                    },
                    onFlowCardDismissed: { assetID in
                        onboardingStore.receive(.flowCardDismissed(assetID: assetID))
                    },
                    onboardingStore: onboardingStore,
                    contextualTipStore: contextualTipStore,
                    sparkResumeRootSourceAssetID: sparkResumeRootSourceAssetID
                )
                }
                .tabItem { Label("Explore", systemImage: "safari").accessibilityIdentifier("tab.flow") }
                .tag(CoreTab.flow)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                .background(ChoraiTheme.background)
                
                // Home 页面
                tabNavigationRoot(.library) {
                HomeView(
                    showSideMenu: $showSideMenu,
                    refreshID: coordinator.libraryRefreshID,
                    committedCardID: coordinator.lastMergedCardID,
                    librarySelectionRequest: coordinator.librarySelectionRequest,
                    onboardingStore: onboardingStore,
                    contextualTipStore: contextualTipStore,
                    isOnboardingLibrarySurfaceActive:
                        isOnboardingLibrarySurfaceActive,
                    onNoteCreated: handleNoteCreated,
                    onCardRouteDismissed: handleLibraryCardRouteDismissed,
                    onCardRoutePresentationChanged:
                        handleLibraryCardRoutePresentationChanged,
                    onLibrarySurfaceVisibilityChanged:
                        handleLibrarySurfaceVisibilityChanged
                )
                }
                    .tabItem { Label("Home", systemImage: "square.stack").accessibilityIdentifier("tab.library") }
                .tag(CoreTab.library)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                .background(ChoraiTheme.background)
                
                // Chat 页面
                tabNavigationRoot(.chat) {
                ChatView(
                    showSideMenu: $showSideMenu,
                    onExplore: { coordinator.selectedTab = .flow }
                )
                }
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right").accessibilityIdentifier("tab.chat") }
                .tag(CoreTab.chat)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                .background(ChoraiTheme.background)
            }

            .frame(maxWidth: .infinity, maxHeight: .infinity)

                .background(ChoraiTheme.background)
            .onAppear {
                #if DEBUG
                startExploreDetailSmokeIfRequested()
                #endif
            }
            .onChange(of: coordinator.selectedTab) { selectedTab in
                if selectedTab != lastSelectedTab {
                    dismissContextualTipWhenLeaving(lastSelectedTab)
                    lastSelectedTab = selectedTab
                }
                isLibrarySurfaceVisible = false
                // 切换 tab 时关闭所有 popup
                closeAllPopups()
            }

            #if DEBUG
            activeScreenAutomationAnchor
            VStack(alignment: .leading, spacing: 1) {
                Text(onboardingPhaseLabel)
                    .accessibilityIdentifier("onboarding.phase")
                Text(onboardingStore.session?.state ?? "none")
                    .accessibilityIdentifier("onboarding.state")
                Text(onboardingStore.session?.sessionID ?? "none")
                    .accessibilityIdentifier("onboarding.session.id")
                Text(String(onboardingStore.session?.flowVersion ?? 0))
                    .accessibilityIdentifier("onboarding.flow.version")
            }
            .font(.system(size: 1))
            .foregroundColor(ChoraiTheme.ink.opacity(0.01))
            .frame(width: 1, height: 1)
            if coordinator.selectedTab == .flow {
                VStack(alignment: .leading, spacing: 4) {
                    if let proposedCardID = ProcessInfo.processInfo.environment[
                        "CHORAI_UI_TEST_ONBOARDING_SPARK_RESUME_PROPOSED_CARD_ID"
                    ], !proposedCardID.isEmpty {
                        Button(action: {
                            handleSparkRequested(
                                proposedCardID: proposedCardID
                            )
                        }) {
                            Color.white.opacity(0.01)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Resume onboarding Spark")
                        .accessibilityIdentifier(
                            "onboarding.spark.resume.test-hook"
                        )
                    }

                    Button(action: {
                        submitExploreSearchSmoke()
                    }) {
                        Color.white.opacity(0.01)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Explore search smoke")
                    .accessibilityIdentifier("explore.search")

                    Button(action: {
                        openExploreRecommendedDetailSmoke()
                    }) {
                        Color.white.opacity(0.01)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Explore detail smoke")
                    .accessibilityIdentifier("explore.card-detail")

                    if exploreSearchSmokeInvoked {
                        Text("Explore search invoked")
                            .font(.system(size: 1))
                            .foregroundColor(ChoraiTheme.ink.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.search.invoked")
                    }

                    if exploreSearchSmokeInFlight {
                        Text("Explore search loading")
                            .font(.system(size: 1))
                            .foregroundColor(ChoraiTheme.ink.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.search.loading")
                    }

                    if exploreSearchSmokeCompleted {
                        Text("Explore search completed")
                            .font(.system(size: 1))
                            .foregroundColor(ChoraiTheme.ink.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.search.completed")
                    }

                    if exploreDetailSmokeInvoked {
                        Text("Explore detail invoked")
                            .font(.system(size: 1))
                            .foregroundColor(ChoraiTheme.ink.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.card-detail.invoked")
                    }

                    if exploreDetailSmokeInFlight {
                        Text("Explore detail loading")
                            .font(.system(size: 1))
                            .foregroundColor(ChoraiTheme.ink.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.card-detail.loading")
                    }

                    if let visibleExploreCardId {
                        Text(visibleExploreCardId)
                            .font(.system(size: 1))
                            .foregroundColor(ChoraiTheme.ink.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.visible-card.id")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 90)
                .padding(.leading, 8)
            }
            #endif

            // 全局弹窗 - 最顶层
            // 使用 modifier 方式，不需要额外的 if 语句
            
        }
        .tint(ChoraiTheme.accent)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                #if DEBUG
                if let cardID = lastCreatedNoteID {
                    Text(cardID)
                        .font(.system(size: 1))
                        .foregroundStyle(ChoraiTheme.ink.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("note.created-card-id")
                }

                if let cardID = coordinator.lastMergedCardID {
                    Text(cardID)
                        .font(.system(size: 1))
                        .foregroundStyle(ChoraiTheme.ink.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("merge.committed-card-id")
                }
                #endif

            }
            .padding(.top, 112)
        }
        .environment(\.cardNavigationOnboardingStore, onboardingStore)
        .environment(\.cardNavigationContextualTipStore, contextualTipStore)
        .environment(
            \.cardNavigationRoutePresentationChanged,
            handleLibraryCardRoutePresentationChanged
        )
        .sheet(item: $shareRoute) { route in
            ShareCardView(cardID: route.cardID)
        }
        .sheet(item: $reportRoute) { route in
            ContentReportView(targetType: .asset, targetID: route.cardID)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name("ShowCardShare")
            )
        ) { notification in
            guard let cardID = notification.userInfo?["cardId"] as? String,
                  !cardID.isEmpty else { return }
            shareRoute = ShareRoute(cardID: cardID)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name("ShowContentReport")
            )
        ) { notification in
            guard let cardID = notification.userInfo?["cardId"] as? String,
                  !cardID.isEmpty else { return }
            reportRoute = ReportRoute(cardID: cardID)
        }
        .onChange(of: authManager.currentUser?.id) { _ in
            hasRoutedInitialOnboardingState = false
            libraryCardRouteCoverageDepth = 0
            isLibrarySurfaceVisible = false
        }
        .onChange(of: allowsCommunityTabs) { allowed in
            if !allowed { coordinator.selectedTab = .library }
        }
        .onChange(of: onboardingStore.phase) { phase in
            syncContextualTipsWithOnboardingSession()
            if phase == .active {
                routeInitialOnboardingState(onboardingStore.session?.state)
            }
        }
        .onChange(of: onboardingStore.session?.state) { state in
            isLibrarySurfaceVisible = false
            pruneSparkResumeMetadataIfNeeded(for: state)
            applyOnboardingNavigation(for: state)
        }
        .onChange(of: onboardingStore.session?.sessionID) { _ in
            isLibrarySurfaceVisible = false
            syncContextualTipsWithOnboardingSession()
        }
        .onChange(of: mergeTaskCoordinator.presentation) { _ in
            isLibrarySurfaceVisible = false
        }
        .onChange(of: mergeTaskCoordinator.completionEventJobID) { jobID in
            guard jobID != nil, scenePhase == .active else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .onChange(of: mergeTaskCoordinator.committedCardIntent) { intent in
            guard let intent else { return }
            mergeTaskCoordinator.minimize()
            onboardingStore.receive(.mergeCommitted(assetID: intent.assetID))
            coordinator.mergeCompleted(cardID: intent.assetID)
            clearTabNavigationPaths()
            onMyNotesTapped()
            mergeTaskCoordinator.acknowledgeCommittedCardIntent(
                jobID: intent.jobID
            )
        }
        .onChange(of: showSideMenu) { isPresented in
            isLibrarySurfaceVisible = false
            if isPresented {
                dismissContextualTipWhenLeaving(coordinator.selectedTab)
            }
        }
        .onChange(of: shareRoute?.id) { _ in
            isLibrarySurfaceVisible = false
        }
        .onChange(of: reportRoute?.id) { _ in
            isLibrarySurfaceVisible = false
        }
        .onAppear {
            if !allowsCommunityTabs { coordinator.selectedTab = .library }
            lastSelectedTab = coordinator.selectedTab
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ExploreVisibleRecommendedCardChanged"))) { notification in
            visibleExploreCardId = notification.userInfo?["cardId"] as? String
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowCardMenu"))) { notification in
            if let userInfo = notification.userInfo,
               let cardData = userInfo["cardData"] as? UserCard {
                currentMenuCardData = cardData
                // 显示菜单
                showPopupMenu = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToHome"))) { _ in
            clearTabNavigationPaths()
            coordinator.selectedTab = .library
            // 关闭所有 popup
            closeAllPopups()
        }
        .environmentObject(mergeTaskCoordinator)
        .environment(
            \.cardNavigationMergeCoordinator,
            mergeTaskCoordinator
        )
    }
}



// 帖子卡片组件
@MainActor
private struct TabBarMergePortalPreview: View {
    @StateObject private var anchorStore = MergeTaskRailAnchorStore()

    var body: some View {
        TabBarView()
            .globalMergeTaskPortal(anchorStore: anchorStore)
    }
}

#Preview {
    TabBarMergePortalPreview()
}
