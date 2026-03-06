import SwiftUI

struct HomeView: View {
    @Binding var showSideMenu: Bool
    @State private var selectedSegment = 0 // 0: Notes, 1: AI

    @State private var showPopupMenu = false
    @State private var popupMenuLayout: PopupMenuLayout = .grid2x2
    @State private var showFilterTags = false
    @State private var selectedFilter = "Latest Edited" // 默认筛选
    @StateObject private var cardsManager = HomeCardsManager()
    @State private var currentCardId: Int? = nil
    @State private var currentMenuCardData: UserCard? = nil
    @StateObject private var favoritesManager = FavoritesManager.shared
    @State private var showDeleteConfirmation = false
    @State private var cardToDelete: UserCard? = nil
    @State private var animateDeleteConfirmation = false
    @State private var navigateToDetail = false
    @State private var navigateToEdit = false
    @State private var selectedCardId: Int? = nil
    @State private var navigateToUserProfile = false
    @State private var selectedUserId: Int? = nil
    @State private var navigateToRoot = false
    @State private var rootViewType: String? = nil
    
    // MARK: - 分段控制器背景
    private func segmentBackground(for segment: Int) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(selectedSegment == segment ? Color.white.opacity(0.2) : Color.clear)
            .overlay(selectedSegment == segment ? segmentTopLeftHighlight : nil)
            .overlay(selectedSegment == segment ? segmentBottomRightHighlight : nil)
            .overlay(selectedSegment == segment ? segmentTopEdgeHighlight : nil)
            .overlay(selectedSegment == segment ? segmentBottomEdgeHighlight : nil)
    }
    
    // MARK: - 获取当前卡片数据
    private func getCurrentCard() -> UserCard? {
        guard let cardId = currentCardId else { 
            return nil 
        }
        let card = cardsManager.cards.first { $0.id == cardId }
        if let card = card {
            print("找到卡片 id=\(card.id), isPublic=\(card.isPublic), isPinned=\(card.isPinned)")
        } else {
            print("未找到卡片 id=\(cardId)")
        }
        return card
    }
    
    // MARK: 加载用户卡片列表
    private func loadUserCards(userId: Int) {
        // 使用默认排序（Latest Edited）
        cardsManager.loadUserCards(userId: userId, refresh: true, sortBy: "updated_at", sortOrder: "desc")
    }
    
    // MARK: 应用排序
    private func applySort(sortBy: String, sortOrder: String) {
        print("应用排序: sortBy=\(sortBy), sortOrder=\(sortOrder)")
        if selectedSegment == 0 {
            // NotesList 排序
            cardsManager.loadUserCards(refresh: true, sortBy: sortBy, sortOrder: sortOrder)
        } else {
            // AIList 排序
            favoritesManager.loadFavorites(refresh: true, sortBy: sortBy, sortOrder: sortOrder)
        }
    }
    
    // MARK: - 分段控制器高光效果
    private var segmentTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 5,
                            endRadius: 20
                        )
                    )
            )
    }
    
    private var segmentBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 5,
                            endRadius: 20
                        )
                    )
            )
    }
    
    private var segmentTopEdgeHighlight: some View {
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
    
    private var segmentBottomEdgeHighlight: some View {
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
        VStack(spacing: 0) {
            // 顶部导航栏
            ZStack {
                
            HStack {
                // 左侧按钮
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSideMenu = true
                    }
                }) {
                    Image("menu")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
                
                Spacer()
                
                    // 右侧按钮组
                    HStack(spacing: 16) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showFilterTags.toggle()
                            }
                        }) {
                            Image("filter")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                        }
                        
                        NavigationLink(destination: SearchView()) {
                            Image("search")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                        }
                    }
                }
                
                // 分段控制器 绝对居中
                HStack(spacing: 0) {
                    // Notes 按钮
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedSegment = 0
                        }
                    }) {
                        Image(selectedSegment == 0 ? "notes_active" : "notes")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .frame(width: 50, height: 32)
                            .background(segmentBackground(for: 0))
                    }
                    
                    // Collect 按钮
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedSegment = 1
                        }
                    }) {
                        Image(selectedSegment == 1 ? "collect_active" : "collect")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .frame(width: 50, height: 32)
                            .background(segmentBackground(for: 1))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.3))
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            
            // 筛选标签
            if showFilterTags {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        HomeFilterTag(title: "Latest Edited", isSelected: selectedFilter == "Latest Edited") {
                            selectedFilter = "Latest Edited"
                            applySort(sortBy: "updated_at", sortOrder: "desc")
                        }
                        .frame(width: 120)
                        HomeFilterTag(title: "Latest Added", isSelected: selectedFilter == "Latest Added") {
                            selectedFilter = "Latest Added"
                            applySort(sortBy: "created_at", sortOrder: "desc")
                        }
                        .frame(width: 120)
                        HomeFilterTag(title: "Rarity-High Low", isSelected: selectedFilter == "Rarity-High Low") {
                            selectedFilter = "Rarity-High Low"
                            applySort(sortBy: "rate", sortOrder: "desc")
                        }
                        .frame(width: 140)
                        HomeFilterTag(title: "Rarity-Low High", isSelected: selectedFilter == "Rarity-Low High") {
                            selectedFilter = "Rarity-Low High"
                            applySort(sortBy: "rate", sortOrder: "asc")
                        }
                        .frame(width: 140)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 10)
            }
            
            // 主要内容区域
            if selectedSegment == 0 {
                // Notes 列表
                NotesListView(
                    cardsManager: cardsManager,
                    currentCardId: $currentCardId,
                    selectedCardId: $selectedCardId,
                    navigateToDetail: $navigateToDetail,
                    navigateToEdit: $navigateToEdit,
                    onShowMenu: { cardData in
                        // 设置当前卡片数据
                        currentMenuCardData = cardData
                        popupMenuLayout = .grid3x3
                        showPopupMenu = true
                    }
                )
            } else {
                // Collect 列表
                AIListView(
                    onShowMenu: { cardId in
                    // 找到对应的收藏卡片数据
                    if let favorite = favoritesManager.favorites.first(where: { $0.id == cardId }) {
                        let tempCard = UserCard(
                            id: cardId,
                            title: favorite.title ?? "",
                            content: favorite.content,
                            contentHash: "",
                            isPublic: false, // 收藏的卡片默认设为私有
                            tags: favorite.tags ?? [],
                            createdAt: favorite.createdAt,
                            updatedAt: favorite.createdAt,
                            likeCount: 0,
                            commentCount: 0,
                            isLiked: false,
                            isPinned: favorite.isPinned,
                            pinnedAt: favorite.pinnedAt,
                            isFavorited: true,
                                favoriteCount: favorite.favoriteCount ?? 0,
                                rate: 0 // 收藏卡片默认 rate 为 0
                        )
                        // 设置当前卡片数据并显示菜单
                        currentCardId = cardId
                        currentMenuCardData = tempCard
                        popupMenuLayout = .grid3x2
                        showPopupMenu = true
                    }
                    },
                    onAvatarTap: { authorId in
                        selectedUserId = authorId
                        DispatchQueue.main.async {
                            navigateToUserProfile = true
                        }
                    }
                )
            }
        }
        .popupMenu(isPresented: $showPopupMenu, layout: popupMenuLayout, cardData: currentMenuCardData ?? getCurrentCard(), isOwnCard: selectedSegment == 0)
        .onAppear {
            // 使用默认排序（Latest Edited）
            cardsManager.loadUserCards(refresh: true, sortBy: "updated_at", sortOrder: "desc")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowCardMenu"))) { notification in
            if let userInfo = notification.userInfo,
               let cardData = userInfo["cardData"] as? UserCard,
               let layoutString = userInfo["layout"] as? String {
                // 设置当前卡片数据
                currentCardId = cardData.id
                currentMenuCardData = cardData
                
                // 设置菜单布局
                switch layoutString {
                case "grid3x2":
                    popupMenuLayout = .grid3x2
                case "grid3x3":
                    popupMenuLayout = .grid3x3
                default:
                    popupMenuLayout = .grid2x2
                }
                
                // 显示菜单
                showPopupMenu = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToNotesList"))) { _ in
            // 切换到NotesList (selectedSegment = 0)
            selectedSegment = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToAIList"))) { _ in
            // 切换到AIList (selectedSegment = 1)
            selectedSegment = 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeleteCard"))) { _ in
            guard let cardId = currentCardId else {
                print("没有找到要删除的卡片ID")
                return
            }
            
            // 找到要删除的卡片数据
            if let card = cardsManager.cards.first(where: { $0.id == cardId }) {
                cardToDelete = card
                showDeleteConfirmation = true
                print("显示删除确认弹窗: cardId=\(cardId)")
            } else {
                print("未找到要删除的卡片数据: cardId=\(cardId)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleCardVisibility"))) { notification in
            guard let userInfo = notification.userInfo,
                  let cardId = userInfo["cardId"] as? Int,
                  let _ = userInfo["isPublic"] as? Bool else {
                print("通知缺少必要参数")
                return
            }
            
            cardsManager.toggleCardVisibility(cardId: cardId) { result in
                switch result {
                case .success:
                    print("卡片可见性切换成功")
                case .failure(let error):
                    print("卡片可见性切换失败: \(error.localizedDescription)")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleCardPin"))) { notification in
            guard let userInfo = notification.userInfo,
                  let cardId = userInfo["cardId"] as? Int,
                  let _ = userInfo["isPinned"] as? Bool else {
                print("通知缺少必要参数")
                return
            }
            
            
            // 执行切换置顶状态操作
            cardsManager.toggleCardPin(cardId: cardId) { result in
                switch result {
                case .success:
                    print("卡片置顶状态切换成功")
                case .failure(let error):
                    print("卡片置顶状态切换失败: \(error.localizedDescription)")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CardTapped"))) { notification in
            guard let userInfo = notification.userInfo,
                  let cardId = userInfo["cardId"] as? Int else {
                return
            }
            
            selectedCardId = cardId
            DispatchQueue.main.async {
                navigateToDetail = false
                navigateToDetail = true
                print("navigateToDetail: \(navigateToDetail) \(cardId)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseAllPopups"))) { _ in
            showPopupMenu = false
            showFilterTags = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToDetail"))) { notification in
            if let cardId = notification.userInfo?["cardId"] as? Int {
                selectedCardId = cardId
                DispatchQueue.main.async {
                    navigateToDetail = true
                }
                
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToEdit"))) { notification in
            if let cardId = notification.userInfo?["cardId"] as? Int {
                selectedCardId = cardId
                DispatchQueue.main.async {
                    navigateToEdit = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToRoot"))) { notification in
            if let cardId = notification.userInfo?["cardId"] as? Int {
                let type = notification.userInfo?["type"] as? String
                selectedCardId = cardId
                rootViewType = type
                DispatchQueue.main.async {
                    navigateToRoot = true
                }
            }
        }
        .overlay(
            // 确认删除对话框
            Group {
                if showDeleteConfirmation {
                    ZStack {
                        // 背景遮罩 - 带渐变动画
                        Color.black
                            .opacity(animateDeleteConfirmation ? 0.5 : 0)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    animateDeleteConfirmation = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        showDeleteConfirmation = false
                                        cardToDelete = nil
                                    }
                                }
                            }
                        
                        // 对话框 - 带渐变动画
                        VStack(spacing: 20) {
                            // 关闭按钮
                            HStack {
                                Spacer()
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        animateDeleteConfirmation = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            showDeleteConfirmation = false
                                            cardToDelete = nil
                                        }
                                    }
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                }
                            }
                            
                            // 确认文本
                            Text("Confirm delete this note?")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            // 按钮
                            HStack(spacing: 16) {
                                // 取消按钮
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        animateDeleteConfirmation = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            showDeleteConfirmation = false
                                            cardToDelete = nil
                                        }
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 16, weight: .medium))
                                        Text("Cancel")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color.gray.opacity(0.3))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                                }
                                
                                // 确认删除按钮
                                Button(action: {
                                    if let card = cardToDelete {
                                        cardsManager.deleteCard(cardId: card.id) { result in
                                            switch result {
                                            case .success:
                                                print("卡片删除成功")
                                                // 清除当前卡片ID
                                                currentCardId = nil
                                            case .failure(let error):
                                                print("卡片删除失败: \(error.localizedDescription)")
                                            }
                                        }
                                    }
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        animateDeleteConfirmation = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            showDeleteConfirmation = false
                                            cardToDelete = nil
                                        }
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .medium))
                                        Text("Yes")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color.red)
                                    )
                                }
                            }
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 20)
                        .opacity(animateDeleteConfirmation ? 1 : 0)
                        .scaleEffect(animateDeleteConfirmation ? 1 : 0.8)
                    }
                    .onAppear {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            animateDeleteConfirmation = true
                        }
                    }
                }
            }
        )
        .navigationDestination(isPresented: $navigateToDetail) {
            if let cardId = selectedCardId {
                DetailView(cardId: cardId)
            } else {
                EmptyView()
            }
        }
        .navigationDestination(isPresented: $navigateToEdit) {
            if let cardId = selectedCardId {
                NewNoteView(cardId: cardId)
            } else {
                EmptyView()
            }
        }
        .navigationDestination(isPresented: $navigateToRoot) {
            if let cardId = selectedCardId {
                RootView(cardId: cardId, type: rootViewType)
            } else {
                EmptyView()
            }
        }
        .navigationDestination(isPresented: $navigateToUserProfile) {
            if let userId = selectedUserId {
                UserProfileView(userId: userId)
            } else {
                EmptyView()
            }
        }
    }
}

// MARK: - Notes 列表视图
struct NotesListView: View {
    @ObservedObject var cardsManager: HomeCardsManager
    @Binding var currentCardId: Int?
    @Binding var selectedCardId: Int?
    @Binding var navigateToDetail: Bool
    @Binding var navigateToEdit: Bool
    let onShowMenu: (UserCard) -> Void
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
            if cardsManager.isLoading && cardsManager.cards.isEmpty {
                VStack {
                            Spacer(minLength: 0)
                            RotatingLoaderView()
                                .padding(.top, 120)
                            Spacer(minLength: 0)
                }
                        .frame(maxWidth: .infinity)
            } else if cardsManager.cards.isEmpty {
                        VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.white.opacity(0.5))
                            Text("Your Chorai is empty")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                            Text("spark it to life by tapping this + in the bottom right")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 160)
            } else {
                        ForEach(Array(cardsManager.cards.enumerated()), id: \.element.id) { index, entry in
                            let card = entry
                            Group {
                                if card.rate < 3 {
                            NotesCard(
                                card: card,
                                onShowMenu: { cardData in
                                    currentCardId = cardData.id
                                    print("设置当前卡片ID: \(cardData.id)")
                                    onShowMenu(cardData)
                                },
                                cardsManager: cardsManager,
                                onCardTap: { cardId in
                                    print("收到卡片点击回调: cardId=\(cardId)")
                                    selectedCardId = cardId
                                    DispatchQueue.main.async {
                                                navigateToEdit = true
                                                print("navigateToEdit: \(navigateToEdit)")
                                            }
                                        }
                                    )
                                } else {
                                    NotesColorCard(
                                        card: card,
                                        onShowMenu: { cardData in
                                            currentCardId = cardData.id
                                            print("设置当前卡片ID: \(cardData.id)")
                                            onShowMenu(cardData)
                                        },
                                        cardsManager: cardsManager,
                                        onCardTap: { cardId in
                                            print("收到卡片点击回调: cardId=\(cardId)")
                                            selectedCardId = cardId
                                            DispatchQueue.main.async {
                                                navigateToEdit = true
                                                print("设置 navigateToEdit: \(navigateToEdit)")
                                    }
                                }
                            )
                        }
                            }
                            .onAppear {
                                if index == cardsManager.cards.count - 1,
                                   cardsManager.hasMoreData,
                                   !cardsManager.isLoading {
                                    cardsManager.loadMoreCards()
                                }
                            }
                        }
                        
                        if cardsManager.isLoading && !cardsManager.cards.isEmpty {
                            HStack {
                                Spacer()
                                RotatingLoaderView()
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 100)
                }
                .refreshable {
                    cardsManager.refreshCards()
            }
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    NavigationLink(destination: NewNoteView()) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial.opacity(0.3))
                                .frame(width: 56, height: 56)
                                .overlay(createButtonTopLeftHighlight)
                                .overlay(createButtonBottomRightHighlight)
                                .overlay(createButtonTopEdgeHighlight)
                                .overlay(createButtonBottomEdgeHighlight)
                            
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 130)
                }
            }
        }
    }
    
    // MARK: - 创建按钮高光效果
    private var createButtonTopLeftHighlight: some View {
        Circle()
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 5,
                            endRadius: 25
                        )
                    )
            )
    }
    
    private var createButtonBottomRightHighlight: some View {
        Circle()
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 5,
                            endRadius: 25
                        )
                    )
            )
    }
    
    private var createButtonTopEdgeHighlight: some View {
        Circle()
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.1)
                        )
                    )
            )
    }
    
    private var createButtonBottomEdgeHighlight: some View {
        Circle()
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.1)
                        )
                    )
            )
    }
}

// MARK: - AI 列表视图
struct AIListView: View {
    let onShowMenu: (Int) -> Void
    let onAvatarTap: ((Int) -> Void)?
    @StateObject private var favoritesManager = FavoritesManager.shared
    
    init(onShowMenu: @escaping (Int) -> Void, onAvatarTap: ((Int) -> Void)? = nil) {
        self.onShowMenu = onShowMenu
        self.onAvatarTap = onAvatarTap
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if favoritesManager.isLoading && favoritesManager.favorites.isEmpty {
                    VStack {
                        Spacer(minLength: 0)
                        RotatingLoaderView()
                            .padding(.top, 120)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                } else if favoritesManager.favorites.isEmpty {
                    VStack {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(.white.opacity(0.5))
                        Text("No favorites yet")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 160)
                } else {
                    ForEach(Array(favoritesManager.favorites.enumerated()), id: \.element.id) { index, favorite in
                        HomePostCard(
                            profileImage: favorite.author.avatar ?? "",
                            name: favorite.author.username,
                            time: formatFavoriteTime(favorite.favoritedAt),
                            content: favorite.content,
                            tags: favorite.tags ?? [],
                            showSpark: true,
                            favoriteCount: favorite.favoriteCount ?? 0,
                            cardId: favorite.id,
                            rate: favorite.rate,
                            authorId: favorite.author.id,
                            onShowMenu: { cardId in
                                onShowMenu(cardId)
                            },
                            onCardTap: { cardId in
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("CardTapped"),
                                    object: nil,
                                    userInfo: ["cardId": cardId]
                                )
                            },
                            onUnfavorite: { cardId in
                                favoritesManager.unfavoriteCard(cardId: cardId) { result in
                                    switch result {
                                    case .success:
                                        print("取消收藏成功: cardId=\(cardId)")
                                        favoritesManager.removeFavoriteFromList(cardId: cardId)
                                    case .failure(let error):
                                        print("取消收藏失败: \(error.localizedDescription)")
                                    }
                                }
                            },
                            onAvatarTap: { authorId in
                                onAvatarTap?(authorId)
                            }
                        )
                        .onAppear {
                            if index == favoritesManager.favorites.count - 1,
                               favoritesManager.hasMoreData,
                               !favoritesManager.isLoading {
                            favoritesManager.loadMoreFavorites()
                            }
                        }
                    }
                    
                    if favoritesManager.isLoading && !favoritesManager.favorites.isEmpty {
                        HStack {
                            Spacer()
                            RotatingLoaderView()
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 100)
        }
        .refreshable {
            favoritesManager.refreshFavorites()
        }
        .onAppear {
            if favoritesManager.favorites.isEmpty {
                favoritesManager.loadFavorites(refresh: true, sortBy: "updated_at", sortOrder: "desc")
            }
        }
    }
    
    // 格式化收藏时间
    private func formatFavoriteTime(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        if let date = formatter.date(from: dateString) {
            let now = Date()
            let timeInterval = now.timeIntervalSince(date)
            
            if timeInterval < 60 {
                return "Just favorited"
            } else if timeInterval < 3600 {
                let minutes = Int(timeInterval / 60)
                return "\(minutes)m ago favorited"
            } else if timeInterval < 86400 {
                let hours = Int(timeInterval / 3600)
                return "\(hours)h ago favorited"
            } else {
                let days = Int(timeInterval / 86400)
                return "\(days)d ago favorited"
            }
        }
        
        return "Unknown favorited time"
    }
}




// MARK: - Notes 卡片组件
struct NotesCard: View {
    let card: UserCard
    let onShowMenu: (UserCard) -> Void
    let onCardTap: ((Int) -> Void)?
    @ObservedObject var cardsManager: HomeCardsManager
    
    init(card: UserCard, onShowMenu: @escaping (UserCard) -> Void, cardsManager: HomeCardsManager, onCardTap: ((Int) -> Void)? = nil) {
        self.card = card
        self.onShowMenu = onShowMenu
        self.cardsManager = cardsManager
        self.onCardTap = onCardTap
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 头部信息 - 左上角：open图标 + 时间 + pin图标
            HStack {
                HStack(spacing: 6) {
                    // 只有当卡片是公开状态时才显示open图标
                    if card.isPublic {
                        Image("open")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 15, height: 15)
                    }
                    
                    Text(formatDate(card.updatedAt))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                    
                    // 只有当卡片是置顶状态时才显示pin图标
                    if card.isPinned {
                        Image("pin")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 15, height: 15)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    // 菜单按钮
                    onShowMenu(card)
                }) {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            
            // 内容文本
            VStack(alignment: .leading, spacing: 8) {
                HTMLTextRenderer(htmlContent: card.content, maxLines: 3)
                    .onTapGesture {
                        // 只有点击内容文本才跳转到详细页面
                        onCardTap?(card.id)
                    }
            }
            
            // 底部标签 - 横向滚动视图
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(card.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(notesCardTagBackground)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 1) // 添加一点内边距，避免标签贴边
            }
            
        }
        .padding(20)
        .background(notesCardBackground)
    }
    
    // MARK: Background Views
    
    private var notesCardTagBackground: some View {
        RoundedRectangle(cornerRadius: 15)
            .fill(Color.white.opacity(0.2))
            .overlay(tagTopLeftHighlight)
            .overlay(tagBottomRightHighlight)
            .overlay(tagTopEdgeHighlight)
            .overlay(tagBottomEdgeHighlight)
    }
    
    private var notesCardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .background(.ultraThinMaterial.opacity(0.55))
            .cornerRadius(16)
            .overlay(topLeftHighlight)
            .overlay(bottomRightHighlight)
            .overlay(topEdgeHighlight)
            .overlay(bottomEdgeHighlight)
    }
    
    // MARK: - 标签高光效果
    private var tagTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 15)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 5,
                            endRadius: 20
                        )
                    )
            )
    }
    
    private var tagBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 15)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 5,
                            endRadius: 20
                        )
                    )
            )
    }
    
    private var tagTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 15)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var tagBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 15)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
    
    // MARK: - 高光效果
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
    
    // MARK: - 日期格式化方法
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        if let date = formatter.date(from: dateString) {
            let now = Date()
            let timeInterval = now.timeIntervalSince(date)
            
            if timeInterval < 60 {
                return "just now"
            } else if timeInterval < 3600 {
                let minutes = Int(timeInterval / 60)
                return "\(minutes) minutes ago"
            } else if timeInterval < 86400 {
                let hours = Int(timeInterval / 3600)
                return "\(hours) hours ago"
            } else if timeInterval < 604800 {
                let days = Int(timeInterval / 86400)
                return "\(days) days ago"
            } else {
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "MM-dd"
                return displayFormatter.string(from: date)
            }
        }
        
        return dateString
    }
}

// MARK: - Home 页面卡片组件
struct HomePostCard: View {
    let profileImage: String
    let name: String
    let time: String
    let content: String
    let tags: [String]
    let showSpark: Bool
    let favoriteCount: Int
    let cardId: Int
    let rate: Int
    let authorId: Int?
    let onShowMenu: (Int) -> Void
    let onCardTap: ((Int) -> Void)?
    let onUnfavorite: ((Int) -> Void)?
    let onAvatarTap: ((Int) -> Void)?
    
    init(profileImage: String, name: String, time: String, content: String, tags: [String], showSpark: Bool, favoriteCount: Int, cardId: Int, rate: Int = 0, authorId: Int? = nil, onShowMenu: @escaping (Int) -> Void, onCardTap: ((Int) -> Void)? = nil, onUnfavorite: ((Int) -> Void)? = nil, onAvatarTap: ((Int) -> Void)? = nil) {
        self.profileImage = profileImage
        self.name = name
        self.time = time
        self.content = content
        self.tags = tags
        self.showSpark = showSpark
        self.favoriteCount = favoriteCount
        self.cardId = cardId
        self.rate = rate
        self.authorId = authorId
        self.onShowMenu = onShowMenu
        self.onCardTap = onCardTap
        self.onUnfavorite = onUnfavorite
        self.onAvatarTap = onAvatarTap
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 头部信息
            HStack {
                // 头像 - 可点击跳转到用户资料
                Button(action: {
                    if let authorId = authorId {
                        onAvatarTap?(authorId)
                    }
                }) {
                    Group {
                        if !profileImage.isEmpty && (profileImage.hasPrefix("http://") || profileImage.hasPrefix("https://")) {
                            // 完整 URL
                            AsyncImage(url: URL(string: profileImage)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Image("avatar")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                        } else if !profileImage.isEmpty {
                            // 相对路径，拼接域名
                            let fullAvatarUrl = "https://api.zhizuo.site/\(profileImage.hasPrefix("/") ? String(profileImage.dropFirst()) : profileImage)"
                 
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
                            // 空字符串，使用占位符
                            Image("avatar")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                }
                .disabled(authorId == nil)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(time)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Button(action: {
                    onShowMenu(cardId)
                }) {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            
            // 内容文本
            HTMLTextRenderer(htmlContent: content, maxLines: 3)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.9))
                .onTapGesture {
                    // 只有点击内容文本才跳转到详细页面
                    onCardTap?(cardId)
                }
            
            // 底部标签和交互
            VStack(spacing: 12) {
                // 标签 - 横向滚动视图
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(homePostCardTagBackground)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 1) // 添加一点内边距，避免标签贴边
                }
                
                // 交互统计
                if showSpark {
                    HStack {
                        Spacer()
                        Button(action: {
                            // 取消收藏
                            onUnfavorite?(cardId)
                        }) {
                        HStack(spacing: 4) {
                            Image("favorite_active")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                            Text("\(favoriteCount)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        }
                        .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
        }
        .padding(20)
        .background(
            Group {
                if rate < 3 {
                    homePostCardBackground
                } else {
                    ZStack {
                        backgroundImageForRate(rate)
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Background Views
    
    private var homePostCardTagBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.white.opacity(0.2))
            .overlay(homePostCardTagTopLeftHighlight)
            .overlay(homePostCardTagBottomRightHighlight)
            .overlay(homePostCardTagTopEdgeHighlight)
            .overlay(homePostCardTagBottomEdgeHighlight)
    }
    
    private var homePostCardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .background(.ultraThinMaterial.opacity(0.55))
            .cornerRadius(16)
            .overlay(topLeftHighlight)
            .overlay(bottomRightHighlight)
            .overlay(topEdgeHighlight)
            .overlay(bottomEdgeHighlight)
    }
    
    // MARK: - 根据 rate 值返回背景图片（与 NotesColorCard 保持一致）
    private func backgroundImageForRate(_ rate: Int) -> some View {
        Group {
            if rate >= 3 && rate <= 8 {
                Image("note_bg_green")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else if rate >= 9 && rate <= 26 {
                Image("note_bg_blue")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else if rate >= 27 && rate <= 80 {
                Image("note_bg_purple")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else if rate >= 81 && rate <= 242 {
                Image("note_bg_yellow")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else if rate > 242 {
                Image("note_bg_red")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                Color(red: 0.2, green: 0.1, blue: 0.3).opacity(0.8)
            }
        }
    }
    
    // MARK: 标签高光效果
    private var homePostCardTagTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 5,
                            endRadius: 15
                        )
                    )
            )
    }
    
    private var homePostCardTagBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 5,
                            endRadius: 15
                        )
                    )
            )
    }
    
    private var homePostCardTagTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var homePostCardTagBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
    
    // MARK: - 高光效果
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
}

#Preview {
    HomeView(showSideMenu: .constant(false))
}

// MARK: - HTML 文本渲染组件
struct HTMLTextRenderer: View {
    let htmlContent: String
    let maxLines: Int
    
    init(htmlContent: String, maxLines: Int = 3) {
        self.htmlContent = htmlContent
        self.maxLines = maxLines
    }
    
    var body: some View {
        Text(plainText)
            .font(.system(size: 17, weight: .regular))
            .foregroundColor(.white.opacity(0.9))
            .lineLimit(maxLines)
            .multilineTextAlignment(.leading)
    }
    
    private var plainText: String {
        // 移除 HTML 标签，保留纯文本
        var text = htmlContent
        
        // 处理常见的 HTML 标签
        text = text.replacingOccurrences(of: "<br>", with: "\n")
        text = text.replacingOccurrences(of: "<br/>", with: "\n")
        text = text.replacingOccurrences(of: "<br />", with: "\n")
        text = text.replacingOccurrences(of: "</p>", with: "\n")
        text = text.replacingOccurrences(of: "</div>", with: "\n")
        text = text.replacingOccurrences(of: "</li>", with: "\n")
        
        // 移除所有 HTML 标签
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        
        // 解码 HTML 实体
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        
        // 清理多余的空白字符和换行
        text = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 筛选标签组件
struct HomeFilterTag: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(tagBackground)
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    private var tagBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(isSelected ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
            .overlay(tagTopLeftHighlight)
            .overlay(tagBottomRightHighlight)
            .overlay(tagTopEdgeHighlight)
            .overlay(tagBottomEdgeHighlight)
    }
    
    private var tagTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 5,
                            endRadius: 20
                        )
                    )
            )
    }
    
    private var tagBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 5,
                            endRadius: 20
                        )
                    )
            )
    }
    
    private var tagTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var tagBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
} 

// MARK: - Notes 彩色卡片组件
struct NotesColorCard: View {
    let card: UserCard
    let onShowMenu: (UserCard) -> Void
    let onCardTap: ((Int) -> Void)?
    @ObservedObject var cardsManager: HomeCardsManager
    
    init(card: UserCard, onShowMenu: @escaping (UserCard) -> Void, cardsManager: HomeCardsManager, onCardTap: ((Int) -> Void)? = nil) {
        self.card = card
        self.onShowMenu = onShowMenu
        self.cardsManager = cardsManager
        self.onCardTap = onCardTap
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 头部信息 - 左上角：open图标 + 时间 + pin图标
            HStack {
                HStack(spacing: 6) {
                    // 只有当卡片是公开状态时才显示open图标
                    if card.isPublic {
                        Image("open")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 15, height: 15)
                    }
                    
                    Text(formatDate(card.updatedAt))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                    
                    // 只有当卡片是置顶状态时才显示pin图标
                    if card.isPinned {
                        Image("pin")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 15, height: 15)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    // 菜单按钮
                    onShowMenu(card)
                }) {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            
            // 内容文本
            VStack(alignment: .leading, spacing: 8) {
                HTMLTextRenderer(htmlContent: card.content, maxLines: 3)
                    .onTapGesture {
                        // 只有点击内容文本才跳转到详细页面
                        onCardTap?(card.id)
                    }
            }
            
            // 底部标签 - 横向滚动视图
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(card.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(notesCardTagBackground)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 1) // 添加一点内边距，避免标签贴边
            }
            
        }
        .padding(20)
        .background(
            ZStack {
                // 根据 rate 值显示不同的背景
                backgroundImageForRate(card.rate)
                
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: 根据 rate 值返回背景图片
    private func backgroundImageForRate(_ rate: Int) -> some View {
        Group {
            if rate >= 3 && rate <= 8 {
                // note_bg_green
                Image("note_bg_green")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else if rate >= 9 && rate <= 26 {
                // note_bg_blue
                Image("note_bg_blue")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else if rate >= 27 && rate <= 80 {
                // note_bg_purple
                Image("note_bg_purple")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else if rate >= 81 && rate <= 242 {
                // note_bg_yellow
                Image("note_bg_yellow")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else if rate > 242 {
                // note_bg_red
                Image("note_bg_red")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                // 默认样式（不应该到达这里，因为 rate < 9 使用 NotesCard）
                Color(red: 0.2, green: 0.1, blue: 0.3).opacity(0.8)
            }
        }
    }
    
    // MARK: - Background Views
    
    private var notesCardTagBackground: some View {
        RoundedRectangle(cornerRadius: 15)
            .fill(Color.white.opacity(0.2))
            .overlay(tagTopLeftHighlight)
            .overlay(tagBottomRightHighlight)
            .overlay(tagTopEdgeHighlight)
            .overlay(tagBottomEdgeHighlight)
    }
    
    // MARK: - 标签高光效果
    private var tagTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 15)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 5,
                            endRadius: 20
                        )
                    )
            )
    }
    
    private var tagBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 15)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 5,
                            endRadius: 20
                        )
                    )
            )
    }
    
    private var tagTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 15)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var tagBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 15)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
    
    // MARK: - 日期格式化方法
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        if let date = formatter.date(from: dateString) {
            let now = Date()
            let timeInterval = now.timeIntervalSince(date)
            
            if timeInterval < 60 {
                return "just now"
            } else if timeInterval < 3600 {
                let minutes = Int(timeInterval / 60)
                return "\(minutes) minutes ago"
            } else if timeInterval < 86400 {
                let hours = Int(timeInterval / 3600)
                return "\(hours) hours ago"
            } else if timeInterval < 604800 {
                let days = Int(timeInterval / 86400)
                return "\(days) days ago"
            } else {
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "MM-dd"
                return displayFormatter.string(from: date)
            }
        }
        
        return dateString
    }
}
