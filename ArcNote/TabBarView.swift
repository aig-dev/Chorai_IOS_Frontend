import SwiftUI
import Combine
import CoreFlow
import UIKit
import WebKit

struct TabBarView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var mergeTaskCoordinator: MergeTaskCoordinator
    @EnvironmentObject private var onboardingStore: OnboardingGuideStore
    @EnvironmentObject private var contextualTipStore: ContextualGuideTipStore
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var coordinator = CoreFlowCoordinator()
    @StateObject private var keyboardLayout = KeyboardLayoutObserver()
    @State private var showPopupMenu = false
    @State private var selectedFilter = "All"
    @State private var showFilterTags = false
    @State private var showSideMenu = false
    @State private var currentMenuCardData: UserCard? = nil
    @State private var navigationPath = NavigationPath()
    @State private var hasRoutedInitialOnboardingState = false
    @State private var libraryCardRouteCoverageDepth = 0
    @State private var isLibrarySurfaceVisible = false
    @State private var shareRoute: ShareRoute?
    @State private var reportRoute: ReportRoute?
    @State private var lastSelectedTab: CoreTab = .flow
    @State private var synchronizedMergeActorID: String?
    @State private var hasSynchronizedMergeRuntimeInputs = false

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

    private func loadOnboardingIfVerified() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["CHORAI_UI_TEST"] == "1",
           environment["CHORAI_UI_TEST_ONBOARDING"] != "1" {
            return
        }
        #endif
        guard authManager.sessionPhase == .verified,
              let actorID = authManager.currentUser?.id else {
            contextualTipStore.reset()
            return
        }
        contextualTipStore.reset()
        onboardingStore.load(actorID: actorID)
    }

    private func synchronizeMergeRuntimeInputs() {
        mergeTaskCoordinator.setApplicationActive(scenePhase == .active)
        mergeTaskCoordinator.setNetworkAvailable(
            NetworkManager.shared.isConnected
        )
        hasSynchronizedMergeRuntimeInputs = true
    }

    private func synchronizeMergeActor() {
        guard hasSynchronizedMergeRuntimeInputs else { return }
        let actorID = authManager.sessionPhase == .verified
            ? authManager.currentUser?.id
            : nil
        guard synchronizedMergeActorID != actorID else { return }
        synchronizedMergeActorID = actorID
        if let actorID {
            mergeTaskCoordinator.activate(actorID: actorID)
        } else {
            mergeTaskCoordinator.deactivate()
        }
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
            if directive.clearsNavigationPath, !navigationPath.isEmpty {
                navigationPath.removeLast(navigationPath.count)
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
            .foregroundColor(.white.opacity(0.01))
            .frame(width: 1, height: 1)
            .accessibilityIdentifier(identifier)
    }

    private func submitExploreSearchSmoke() {
        print("Explore search smoke invoked")
        exploreSearchSmokeInvoked = true
        exploreSearchSmokeCompleted = false
        exploreSearchSmokeInFlight = true

        SearchManager.shared.searchCards(query: "go api ui smoke unlikely result") { _ in
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
        // 切换到Home页面 (tag = 1)
        coordinator.selectedTab = .library
        
        // 关闭所有 popup
        closeAllPopups()
        
        // 通知HomeView切换到NotesList
        NotificationCenter.default.post(
            name: NSNotification.Name("SwitchToNotesList"),
            object: nil
        )
    }
    
    // MARK: - Favorites 点击处理
    private func onFavoritesTapped() {
        // 切换到Home页面 (tag = 1)
        coordinator.selectedTab = .library
        
        // 关闭所有 popup
        closeAllPopups()
        
        // 通知HomeView切换到AIList
        NotificationCenter.default.post(
            name: NSNotification.Name("SwitchToAIList"),
            object: nil
        )
    }
    
    // MARK: - 关闭所有 Popup
    private func closeAllPopups() {
        // 关闭 popup 菜单
        showPopupMenu = false
        
        // 关闭筛选标签
        showFilterTags = false
        
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

        navigationPath.append(TabRoute.spark(rootSourceAssetID))
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
        mergeTaskCoordinator.presentation != nil
            || libraryCardRouteCoverageDepth > 0
            || showSideMenu
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

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
            // 背景图片
//                Image("home_bg")
//                    .resizable()
//                    .aspectRatio(contentMode: .fill)
//                    .frame(maxWidth: .infinity, maxHeight: .infinity)
//                    .clipped()
//                    .ignoresSafeArea()
            
            // 主要内容区域 - 全屏显示
            TabView(selection: $coordinator.selectedTab) {
                // Explore 页面
                ExploreView(
                    showPopupMenu: $showPopupMenu,
                    selectedFilter: $selectedFilter,
                    showFilterTags: $showFilterTags,
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
                .tag(CoreTab.flow)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)
                .background(
                    Image("home_bg")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .ignoresSafeArea(.all)
                )
                
                // Home 页面
                HomeView(
                    showSideMenu: $showSideMenu,
                    refreshID: coordinator.libraryRefreshID,
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
                    .tag(CoreTab.library)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)
                .background(
                    Image("home_bg")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .ignoresSafeArea(.all)
                )
                
                // Chat 页面
                ChatView(showSideMenu: $showSideMenu)
                    .tag(CoreTab.chat)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)
                .background(
                    Image("home_bg")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .ignoresSafeArea(.all)
                )
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
            .background(
                Image("home_bg")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea(.all)
            )
            .onAppear {
                // 禁用 TabView 的侧滑手势
                UIScrollView.appearance().isScrollEnabled = false
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
            .foregroundColor(.white.opacity(0.01))
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
                            .foregroundColor(.white.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.search.invoked")
                    }

                    if exploreSearchSmokeInFlight {
                        Text("Explore search loading")
                            .font(.system(size: 1))
                            .foregroundColor(.white.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.search.loading")
                    }

                    if exploreSearchSmokeCompleted {
                        Text("Explore search completed")
                            .font(.system(size: 1))
                            .foregroundColor(.white.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.search.completed")
                    }

                    if exploreDetailSmokeInvoked {
                        Text("Explore detail invoked")
                            .font(.system(size: 1))
                            .foregroundColor(.white.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.card-detail.invoked")
                    }

                    if exploreDetailSmokeInFlight {
                        Text("Explore detail loading")
                            .font(.system(size: 1))
                            .foregroundColor(.white.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.card-detail.loading")
                    }

                    if let visibleExploreCardId {
                        Text(visibleExploreCardId)
                            .font(.system(size: 1))
                            .foregroundColor(.white.opacity(0.01))
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
            
            // 侧边菜单
            SideMenuView(
                isPresented: $showSideMenu,
                onMyNotesTapped: {
                    onMyNotesTapped()
                },
                onFavoritesTapped: {
                    onFavoritesTapped()
                }
            )
            
            // 评论弹窗
            CommentPopupView()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardLayout.isVisible && !isLibraryCovered {
                CoreTabBar(selectedTab: $coordinator.selectedTab)
                    .adaptiveContentGutter()
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: keyboardLayout.isVisible)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                #if DEBUG
                if let cardID = lastCreatedNoteID {
                    Text(cardID)
                        .font(.system(size: 1))
                        .foregroundStyle(Color.white.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("note.created-card-id")
                }

                if let cardID = coordinator.lastMergedCardID {
                    Text(cardID)
                        .font(.system(size: 1))
                        .foregroundStyle(Color.white.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("merge.committed-card-id")
                }
                #endif

            }
            .padding(.top, 112)
        }
        .popupMenu(isPresented: $showPopupMenu, layout: .grid2x2, cardData: currentMenuCardData)
        .linkPopup()
        .environment(\.cardNavigationOnboardingStore, onboardingStore)
        .environment(\.cardNavigationContextualTipStore, contextualTipStore)
        .environment(
            \.cardNavigationRoutePresentationChanged,
            handleLibraryCardRoutePresentationChanged
        )
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        #if DEBUG
        .navigationDestination(isPresented: $navigateToDetailSmoke) {
            if let cardId = selectedDetailSmokeCardId {
                DetailView(cardId: cardId)
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
                } else {
                    EmptyView()
                }
            case .detail(let cardId):
                DetailView(cardId: cardId)
                    .environmentObject(mergeTaskCoordinator)
                    .environment(
                        \.cardNavigationMergeCoordinator,
                        mergeTaskCoordinator
                    )
            }
        }
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
            synchronizeMergeActor()
            hasRoutedInitialOnboardingState = false
            libraryCardRouteCoverageDepth = 0
            isLibrarySurfaceVisible = false
            contextualTipStore.reset()
            loadOnboardingIfVerified()
        }
        .onChange(of: authManager.sessionPhase) { phase in
            synchronizeMergeActor()
            if phase == .verified {
                loadOnboardingIfVerified()
            } else {
                contextualTipStore.reset()
            }
        }
        .onChange(of: scenePhase) { phase in
            mergeTaskCoordinator.setApplicationActive(phase == .active)
        }
        .onReceive(
            NetworkManager.shared.$isConnected.removeDuplicates()
        ) { isConnected in
            mergeTaskCoordinator.setNetworkAvailable(isConnected)
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
            navigationPath.append(TabRoute.detail(intent.assetID))
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
            lastSelectedTab = coordinator.selectedTab
            synchronizeMergeRuntimeInputs()
            synchronizeMergeActor()
            loadOnboardingIfVerified()
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
            navigationPath.removeLast(navigationPath.count)
            coordinator.selectedTab = .library
            // 关闭所有 popup
            closeAllPopups()
        }
        }
        .environmentObject(mergeTaskCoordinator)
        .environment(
            \.cardNavigationMergeCoordinator,
            mergeTaskCoordinator
        )
    }
}



// 帖子卡片组件
struct PostCard: View {
    let card: Card
    @ObservedObject var cardsManager: RecommendedCardsManager
    @State private var offset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var isLoadingAuthor = false
    @State private var isMenuButtonPressed = false
    var onShowMenu: (Card) -> Void
    var onSwipe: (CGFloat, Bool) -> Void
    var onAvatarTap: ((String) -> Void)? = nil
    var onCardTap: ((String) -> Void)? = nil
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .background(.ultraThinMaterial.opacity(0.55))
            .cornerRadius(16)
            .overlay(topLeftHighlight)
            .overlay(bottomRightHighlight)
            .overlay(topEdgeHighlight)
            .overlay(bottomEdgeHighlight)
    }
    
    private var topLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var bottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var topEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var bottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 用户信息
            HStack {
                // 头像
                Button(action: {
                    print("card.author: \(String(describing: card.author))")
                    if let author = card.author {
                        print(" author.id: \(author.id)")
                        onAvatarTap?(author.id)
                    } else {
                        loadAuthorFromCardDetail()
                    }
                }) {
                    Group {
                        if let avatarUrl = card.author?.avatar, !avatarUrl.isEmpty {
                            let fullAvatarUrl = APIConfiguration.resourceURLString(avatarUrl)
                            
                            AsyncImage(url: URL(string: fullAvatarUrl)) { image in
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
                        .frame(width: 50, height: 50)
                    .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.author?.username ?? "AI")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(formatDate(card.createdAt))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Button(action: {
                    isMenuButtonPressed = true
                    onShowMenu(card)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isMenuButtonPressed = false
                    }
                }) {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 16)
            
            // 帖子内容 填充剩余空间
            VStack(alignment: .leading, spacing: 0) {
                HTMLWebView(htmlContent: card.content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                // 整个内容区域都可以点击
                onCardTap?(card.id)
            }
            
            // 底部内容 - 固定在底部
            VStack(spacing: 16) {
                // 标签
                if !card.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(card.tags, id: \.self) { tag in
                                TagView(text: tag)
                            }
                            Spacer()
                        }
                    }
                }
                
                // 交互统计
                HStack {
                    // 左边一个 - 收藏按钮
                    if card.isOwner != true {
                        Button(action: {
                            cardsManager.toggleFavorite(for: card.id)
                        }) {
                            HStack(spacing: 4) {
                                Image(cardsManager.getFavoriteState(for: card.id) ? "favorite_active" : "favorite")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 26, height: 26)
                                Text("\(cardsManager.getFavoriteCount(for: card.id))")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Favorite")
                        .accessibilityValue(cardsManager.getFavoriteState(for: card.id) ? "true" : "false")
                        .accessibilityIdentifier("card.favorite.\(card.id)")
                    }
                    
                    Spacer()
                    
                    // 右边两个
                    HStack(spacing: 20) {
                        Button(action: {
                            cardsManager.toggleLike(for: card.id)
                        }) {
                            HStack(spacing: 4) {
                                Image(cardsManager.getLikeState(for: card.id) ? "like_active" : "like")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                Text("\(cardsManager.getLikeCount(for: card.id))")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .disabled(cardsManager.isLikeMutationInFlight(for: card.id))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(cardsManager.getLikeState(for: card.id) ? "Unlike" : "Like")
                        .accessibilityValue(cardsManager.getLikeState(for: card.id) ? "true" : "false")
                        .accessibilityIdentifier("card.like.\(card.id)")
                        
                        CommentButton(cardId: card.id, cardsManager: cardsManager)
                    }
                }

                if let error = cardsManager.likeError(for: card.id) {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                        .accessibilityIdentifier("card.like.error.\(card.id)")
                }
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity)
        .background(
            cardBackground
        )
        .offset(x: offset)
        .rotationEffect(.degrees(rotation))
        .scaleEffect(scale)
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    offset = value.translation.width
                    rotation = Double(value.translation.width / 10)
                    scale = 1.0 - abs(value.translation.width) / 1000
                    onSwipe(value.translation.width, false)
                }
                .onEnded { value in
                    let threshold: CGFloat = 100
                    if abs(value.translation.width) > threshold {
                        // 滑动距离足够，切换到下一张
                        withAnimation(.easeInOut(duration: 0.3)) {
                            offset = value.translation.width > 0 ? 500 : -500
                            rotation = value.translation.width > 0 ? 30 : -30
                            scale = 0.8
                        }
                        
                        // 通知父组件切换卡片
                        onSwipe(value.translation.width, true)
                        
                        // 重置状态
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            offset = 0
                            rotation = 0
                            scale = 1.0
                        }
                    } else {
                        // 滑动距离不够，回到原位
                        withAnimation(.easeInOut(duration: 0.3)) {
                            offset = 0
                            rotation = 0
                            scale = 1.0
                        }
                    }
                }
        )
        .onAppear {
            // 点赞状态现在由 RecommendedCardsManager 管理
            #if DEBUG
            NotificationCenter.default.post(
                name: NSNotification.Name("ExploreVisibleRecommendedCardChanged"),
                object: nil,
                userInfo: ["cardId": card.id]
            )
            #endif
        }
    }
    
    // MARK: - 获取作者信息
    private func loadAuthorFromCardDetail() {
        guard !isLoadingAuthor else { return }
        
        isLoadingAuthor = true
        print("获取卡片详情: cardId=\(card.id)")
        
        guard AuthManager.shared.currentUser != nil else {
            print("用户未登录")
            isLoadingAuthor = false
            return
        }
        
        NetworkManager.shared.getCardDetail(cardId: card.id) { result in
            DispatchQueue.main.async {
                self.isLoadingAuthor = false
                switch result {
                case .success(let response):
                    if let author = response.data.author {
                        print("成功: actorId=\(author.actorId)")
                        self.onAvatarTap?(author.actorId)
                    } else {
                    }
                case .failure(let error):
                    print("获取卡片详情失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - 辅助函数
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        if let date = formatter.date(from: dateString) {
            let now = Date()
            let timeInterval = now.timeIntervalSince(date)
            
            if timeInterval < 3600 {
                let minutes = Int(timeInterval / 60)
                return "\(minutes) minutes ago"
            } else if timeInterval < 86400 {
                let hours = Int(timeInterval / 3600)
                return "\(hours) hours ago"
            } else if timeInterval < 604800 { // 7天内
                let days = Int(timeInterval / 86400)
                return "\(days) days ago"
            } else {
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "MMM dd"
                return displayFormatter.string(from: date)
            }
        }
        
        return "Recently"
    }
    
}

// 标签组件
struct TagView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.white.opacity(0.1))
            )
    }
}

#Preview {
    TabBarView()
        .globalMergeTaskPortal()
}



// MARK: - HTMLWebView 组件
struct HTMLWebView1: UIViewRepresentable {
    let html: String
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let htmlString = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    font-size: 14px;
                    line-height: 1.4;
                    color: rgba(255, 255, 255, 0.9);
                    background: transparent;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                }
                p {
                    margin: 0 0 8px 0;
                }
                p:last-child {
                    margin-bottom: 0;
                }
                h1, h2, h3, h4, h5, h6 {
                    margin: 0 0 8px 0;
                    font-weight: 600;
                }
                ul, ol {
                    margin: 0 0 8px 0;
                    padding-left: 20px;
                }
                li {
                    margin: 0 0 4px 0;
                }
                blockquote {
                    margin: 0 0 8px 0;
                    padding-left: 16px;
                    border-left: 3px solid rgba(255, 255, 255, 0.3);
                }
                code {
                    background: rgba(255, 255, 255, 0.1);
                    padding: 2px 4px;
                    border-radius: 3px;
                    font-family: 'SF Mono', Monaco, monospace;
                    font-size: 12px;
                }
                pre {
                    background: rgba(255, 255, 255, 0.1);
                    padding: 8px;
                    border-radius: 6px;
                    overflow-x: auto;
                    margin: 0 0 8px 0;
                }
                pre code {
                    background: none;
                    padding: 0;
                }
                a {
                    color: rgba(255, 255, 255, 0.8);
                    text-decoration: underline;
                }
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 4px;
                }
            </style>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
        
        webView.loadHTMLString(htmlString, baseURL: nil)
    }
}

// PopupMenuView 和 MenuButton 已移至 PopupMenuView.swift 文件中 
