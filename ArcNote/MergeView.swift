import SwiftUI
import Combine

struct MergeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) var presentationMode
    @State private var searchText = ""
    @State private var selectedCards: Set<Int> = []
    @State private var showLoading = false
    @State private var showNewInsight = false
    @State private var animationPhase = 0
    @State private var animationTimer: Timer?
    @StateObject private var searchManager = SearchManager.shared
    @StateObject private var cardDetailManager = CardDetailManager.shared
    @StateObject private var mergeCardsManager = MergeCardsManager.shared
    @StateObject private var networkManager = NetworkManager.shared
    
    let cardId: Int
    
    // 可选择的卡片数据
    @State private var selectableCards: [MergeCard] = []
    @State private var allCards: [MergeCard] = [] // 所有卡片数据
    @State private var isLoadingCards = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var previewData: MergePreviewResponse? = nil
    
    // MARK: 搜索框高光效果
    private var searchBarTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 25)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 25)
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
    
    private var searchBarBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 25)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 25)
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
    
    private var searchBarTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 25)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var searchBarBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 25)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 25)
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
        ZStack {
            // 背景图片
//            Image("home_bg")
//                .resizable()
//                .aspectRatio(contentMode: .fill)
//                .frame(maxWidth: .infinity, maxHeight: .infinity)
//                .clipped()
//                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶部导航栏
                HStack {
                    Spacer()
                    
                    // Merge 标题
                    HStack(spacing: 8) {
                            Image("menu_merge")
                                .resizable().frame(width: 28, height: 28)
                        
                        Text("Merge")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
//                .padding(.top, 60)
                
                                // 主要内容
                VStack(spacing: 0) {
                    // 固定的第一张卡片
                    if let cardDetail = cardDetailManager.cardDetail {
                        FixedMergeCardView(card: convertCardDetailToMergeCard(cardDetail))
                            .padding(.top, 20)
                    } else if cardDetailManager.isLoading {
                        // 加载状态
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                            
                            Text("Loading card...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                    } else {
                        // 错误状态
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.5))
                            
                            Text("Failed to load card")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                    }
                    
                    // 分割线
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.white.opacity(0.2))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                    
                    // 搜索栏
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.7))
                        
                        TextField("", text: $searchText)
                            .foregroundColor(.white)
                            .textFieldStyle(PlainTextFieldStyle())
                            .placeholder(when: searchText.isEmpty) {
                                Text("Please enter your search...")
                                    .foregroundColor(.white).font(.system(size: 13))
                            }
                        
                        Button(action: {
                            // 搜索按钮
                        }) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(Color(red: 0.2, green: 0.1, blue: 0.3))
                            .overlay(searchBarTopLeftHighlight)
                            .overlay(searchBarBottomRightHighlight)
                            .overlay(searchBarTopEdgeHighlight)
                            .overlay(searchBarBottomEdgeHighlight)
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                    
                    // 可选择的卡片列表
                    ScrollView {
                        VStack(spacing: 20) {
                            if searchManager.isLoading && searchManager.searchResults.isEmpty {
                                // 加载状态
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(1.2)
                                    
                                    Text("Searching...")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.top, 100)
                            } else if selectableCards.isEmpty && !isLoadingCards {
                                // 无卡片数据
                                VStack(spacing: 16) {
//                                    Image(systemName: "doc.text")
//                                        .font(.system(size: 48))
//                                        .foregroundColor(.white.opacity(0.5))
                                    
                                    Text("No linked cards found")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.top, 100)
                            } else if isLoadingCards {
                                // 加载状态
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(1.2)
                                    
                                    Text("Loading linked cards...")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.top, 100)
                            } else {
                                // 显示卡片列表（支持本地搜索筛选）
                                ForEach(selectableCards) { card in
                                    MergeCardView(
                                        card: card,
                                        isSelected: selectedCards.contains(card.id),
                                        onToggleSelection: {
                                            if selectedCards.contains(card.id) {
                                                selectedCards.remove(card.id)
                                            } else {
                                                selectedCards.insert(card.id)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.bottom, 100) // 为悬浮按钮留出空间
                    }
                }
            }.background(
                Image("home_bg")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            )
            
            // 底部悬浮的合并按钮
            VStack {
                Spacer()
                Button(action: {
                    performMerge()
                }) {
                    Text(selectedCards.isEmpty ? "Merge Selected Cards (1)" : "Merge Selected Cards (\(selectedCards.count + 1))")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(selectedCards.isEmpty ? .white.opacity(0.5) : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(selectedCards.isEmpty ? Color.gray.opacity(0.3) : Color.gray.opacity(0.3))
                        )
                }
                .disabled(selectedCards.isEmpty)
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            
            // 加载效果
            if mergeCardsManager.isMerging {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                    
                    HStack(spacing: 30) {
                        // 四个白点动画
                        HStack(spacing: 12) {
                            ForEach(0..<4, id: \.self) { index in
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 20, height: 20)
                                    .scaleEffect(animationPhase == index ? 1.5 : 1.0)
                                    .animation(.easeInOut(duration: 0.3), value: animationPhase)
                            }
                        }
                        .frame(height: 20) // 固定白点容器高度
                        
                        // Logo
                        Image("loading_logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .transition(.opacity)
            }
            
            // 新洞察弹窗
            if showNewInsight {
                NewInsightView(
                    isPresented: $showNewInsight, 
                    mergeResult: mergeCardsManager.mergeResult, 
                    previewData: previewData,
                    selectedCards: getSelectedCardsForPreview()
                )
                .transition(.opacity.combined(with: .scale))
            }
            
            // 返回按钮 放在最上层
            VStack {
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
//                    .padding(.top, 60)
                    
                    Spacer()
                }
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .gesture(
            DragGesture()
                .onEnded { value in
                    // 侧滑返回手势
                    if value.translation.width > 100 && abs(value.translation.height) < 50 {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
        )
        .animation(.easeInOut(duration: 0.3), value: mergeCardsManager.isMerging)
        .animation(.easeInOut(duration: 0.3), value: showNewInsight)
        .onAppear {
            loadCardDetail()
            loadUserAllCards() // 改为加载用户所有卡片
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exitMergePage)) { _ in
            // 发布成功后退出Merge页面
            presentationMode.wrappedValue.dismiss()
        }
        .onChange(of: searchText) { newValue in
            // 调用搜索接口
            performSearch()
        }
    }
    
    // MARK: 加载卡片详细信息
    private func loadCardDetail() {
        cardDetailManager.fetchCardDetail(cardId: cardId) { result in
            switch result {
            case .success:
                print("卡片详细信息加载成功")
            case .failure(let error):
                print("详细信息加载失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: 加载用户所有卡片
    private func loadUserAllCards() {
        guard let userId = AuthManager.shared.currentUser?.id else {
            return
        }
        
        isLoadingCards = true
        print("开始加载用户所有卡片: userId=\(userId)")
        
        networkManager.getUserAllCards(userId: userId, searchType: "own+favorited", cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoadingCards = false
                    switch completion {
                    case .finished:
                        print("用户所有卡片加载完成")
                    case .failure(let error):
                        print("用户所有卡片加载失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { response in
                    print("用户所有卡片加载成功")
                    
                    // 合并所有卡片数据
                    var allUserCards: [MergeCard] = []
                    
                    allUserCards.append(contentsOf: response.data.ownCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: false)
                    })
                    
                    allUserCards.append(contentsOf: response.data.favoritedCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: true)
                    })
                    
                    allUserCards.append(contentsOf: response.data.likedCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: false)
                    })
                    
                    allUserCards.append(contentsOf: response.data.linkedCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: false)
                    })
                    
                    self.allCards = allUserCards
                    self.filterCards() // 初始显示所有卡片
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 本地搜索筛选
    private func filterCards() {
        if searchText.isEmpty {
            selectableCards = allCards
        } else {
            let searchLowercased = searchText.lowercased()
            selectableCards = allCards.filter { card in
                card.content.lowercased().contains(searchLowercased) ||
                card.tags.contains { $0.lowercased().contains(searchLowercased) }
            }
        }
    }
    
    // MARK: 转换CardDetail为MergeCard
    private func convertCardDetailToMergeCard(_ cardDetail: CardDetail) -> MergeCard {
        // 格式化日期
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        let displayDate: String
        if let date = dateFormatter.date(from: cardDetail.createdAt) {
            let now = Date()
            let timeInterval = now.timeIntervalSince(date)
            
            if timeInterval < 86400 { // 24小时内
                displayDate = "Today"
            } else if timeInterval < 172800 { // 48小时内
                displayDate = "Yesterday"
            } else {
                let days = Int(timeInterval / 86400)
                displayDate = "\(days) days ago"
            }
        } else {
            displayDate = "Unknown"
        }
        
        return MergeCard(
            id: cardDetail.id,
            date: displayDate,
            content: cardDetail.content,
            tags: cardDetail.tags,
            isUserCard: true,
            userName: cardDetail.author?.userName ?? "Unknown",
            avatarUrl: cardDetail.author?.avatarUrl,
            favoriteCount: cardDetail.favoriteCount ?? 0,
            rate: cardDetail.rate
        )
    }
    
    // MARK: 执行合并
    private func performMerge() {
        guard !selectedCards.isEmpty else {
            print("没有选择要合并的卡片")
            return
        }
        
        // 获取头部固定卡片的内容
        guard let cardDetail = cardDetailManager.cardDetail else {
            print("头部卡片数据未加载")
            return
        }
        
        // 构建选择的卡片列表，包含头部卡片
        var selectedCardsList: [SelectedCard] = []
        
        // 添加头部卡片（当前卡片）
        selectedCardsList.append(SelectedCard(id: cardDetail.id, content: cardDetail.content))
        
        // 添加选中的链接卡片
        for cardId in selectedCards {
            if let linkedCard = allCards.first(where: { $0.id == cardId }) {
                selectedCardsList.append(SelectedCard(id: linkedCard.id, content: linkedCard.content))
            }
        }
        
        print("开始合并 \(selectedCardsList.count) 张卡片")
        print("包含当前卡片: \(cardDetail.id)")
        print("选中卡片: \(selectedCards)")
        
        mergeCardsManager.mergeCards(selectedCards: selectedCardsList) { result in
            switch result {
            case .success(let previewResponse):
                print("合并预览成功: \(previewResponse.message)")
                DispatchQueue.main.async {
                    self.previewData = previewResponse
                    self.showNewInsight = true
                }
            case .failure(let error):
                print("卡片合并失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: 执行搜索
    private func performSearch() {
        guard let userId = AuthManager.shared.currentUser?.id else {
            print("用户未登录，无法执行搜索")
            return
        }
        
        // 如果搜索框为空，显示所有卡片
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectableCards = allCards
            return
        }
        
        print("搜索: \(searchText)")
        
        isLoadingCards = true
        
        networkManager.getUserAllCards(userId: userId, searchType: "own+favorited", search: searchText, limit: 50, cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoadingCards = false
                    switch completion {
                    case .finished:
                        print("搜索完成")
                    case .failure(let error):
                        print("搜索失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { response in
                    
                    var searchResults: [MergeCard] = []
                    
                    searchResults.append(contentsOf: response.data.ownCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: true)
                    })
                    
                    searchResults.append(contentsOf: response.data.favoritedCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: false)
                    })
                    
                    // 添加点赞的卡片
                    searchResults.append(contentsOf: response.data.likedCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: false)
                    })
                    
                    // 添加链接的卡片
                    searchResults.append(contentsOf: response.data.linkedCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: false)
                    })
                    
                    // 更新可选择的卡片列表
                    self.selectableCards = searchResults
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 获取预览用的选中卡片
    private func getSelectedCardsForPreview() -> [SelectedCard] {
        guard let cardDetail = cardDetailManager.cardDetail else {
            return []
        }
        
        var selectedCardsList: [SelectedCard] = []
        
        selectedCardsList.append(SelectedCard(id: cardDetail.id, content: cardDetail.content))
        
        // 添加选中的链接卡片
        for cardId in selectedCards {
            if let linkedCard = allCards.first(where: { $0.id == cardId }) {
                selectedCardsList.append(SelectedCard(id: linkedCard.id, content: linkedCard.content))
            }
        }
        
        return selectedCardsList
    }
    
    // MARK: 动画控制
    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                animationPhase = (animationPhase + 1) % 4
            }
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    // MARK: 转换Link为MergeCard
    private func convertLinkToMergeCard(_ link: CardLink) -> MergeCard {
        // 格式化日期
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        let displayDate: String
        if let date = dateFormatter.date(from: link.createdAt) {
            let now = Date()
            let timeInterval = now.timeIntervalSince(date)
            
            if timeInterval < 86400 { // 24小时内
                displayDate = "Today"
            } else if timeInterval < 172800 { // 48小时内
                displayDate = "Yesterday"
            } else {
                let days = Int(timeInterval / 86400)
                displayDate = "\(days) days ago"
            }
        } else {
            displayDate = "Unknown"
        }
        
        return MergeCard(
            id: link.linkedCardId,
            date: displayDate,
            content: link.content,
            tags: [],
            isUserCard: false,
            userName: nil,
            avatarUrl: nil,
            favoriteCount: 0,
            rate: 0
        )
    }
    
    // MARK: - 转换SearchCard为MergeCard
    private func convertSearchCardToMergeCard(_ searchCard: SearchCard) -> MergeCard {
        // 格式化日期
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        let displayDate: String
        if let date = dateFormatter.date(from: searchCard.createdAt) {
            let now = Date()
            let timeInterval = now.timeIntervalSince(date)
            
            if timeInterval < 86400 { // 24小时内
                displayDate = "Today"
            } else if timeInterval < 172800 { // 48小时内
                displayDate = "Yesterday"
            } else {
                let days = Int(timeInterval / 86400)
                displayDate = "\(days) days ago"
            }
        } else {
            displayDate = "Unknown"
        }
        
        return MergeCard(
            id: searchCard.id,
            date: displayDate,
            content: searchCard.content,
            tags: searchCard.tags,
            isUserCard: true,
            userName: searchCard.author.username,
            avatarUrl: searchCard.author.avatarUrl,
            favoriteCount: searchCard.favoriteCount,
            rate: searchCard.rate
        )
    }
    
    // MARK: 转换UserAllCard为MergeCard
    private func convertUserAllCardToMergeCard(_ userAllCard: UserAllCard, isOwnCard: Bool) -> MergeCard {
        // 格式化日期
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        let displayDate: String
        if let date = dateFormatter.date(from: userAllCard.createdAt) {
            let now = Date()
            let timeInterval = now.timeIntervalSince(date)
            
            if timeInterval < 86400 { // 24小时内
                displayDate = "Today"
            } else if timeInterval < 172800 { // 48小时内
                displayDate = "Yesterday"
            } else {
                let days = Int(timeInterval / 86400)
                displayDate = "\(days) days ago"
            }
        } else {
            displayDate = "Unknown"
        }
        
        // 解析标签
        let tags = userAllCard.labels.isEmpty ? [] : userAllCard.labels.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        
        return MergeCard(
            id: userAllCard.id,
            date: displayDate,
            content: userAllCard.content,
            tags: tags,
            isUserCard: isOwnCard,
            userName: isOwnCard ? userAllCard.author?.username : nil,
            avatarUrl: isOwnCard ? userAllCard.author?.avatar : nil,
            favoriteCount: userAllCard.favoriteCount,
            rate: userAllCard.rate // 使用真实的 rate 值
        )
    }
}

// MARK: - Merge Card Data Model
struct MergeCard: Identifiable {
    let id: Int
    let date: String
    let content: String
    let tags: [String]
    let isUserCard: Bool
    let userName: String?
    let avatarUrl: String?
    let favoriteCount: Int
    let rate: Int
    
    init(id: Int, date: String, content: String, tags: [String], isUserCard: Bool, userName: String? = nil, avatarUrl: String? = nil, favoriteCount: Int = 0, rate: Int = 0) {
        self.id = id
        self.date = date
        self.content = content
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 头部信息
            HStack {
                if card.isUserCard {
                    // 用户卡片头像
                    AsyncImage(url: URL(string: card.avatarUrl ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image("avatar")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.userName ?? "")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(card.date)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else {
                    // 普通卡片日期
                    Text(card.date)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
            }
            
            // 内容文本
            HTMLTextRenderer(htmlContent: card.content, maxLines: 3)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.9))
            
            // 底部标签和交互
            VStack(spacing: 12) {
                // 标签 - 横向滚动
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(card.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white.opacity(0.2))
                                    .overlay(mergeCardTagTopLeftHighlight)
                                    .overlay(mergeCardTagBottomRightHighlight)
                                    .overlay(mergeCardTagTopEdgeHighlight)
                                    .overlay(mergeCardTagBottomEdgeHighlight)
                            )
                    }
                    }
                    .padding(.horizontal, 1) // 添加一点内边距确保滚动效果
                }
                
                // 交互统计（如果需要）
                if card.isUserCard {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image("favorite")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                            Text("\(card.favoriteCount)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            ZStack {
                // 根据 rate 值显示不同的背景
                backgroundImageForRate(card.rate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .allowsHitTesting(false)
                
            RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color(red: 198/255, green: 89/255, blue: 231/255) : Color.clear, lineWidth: 2)
                )
        )
        .contentShape(Rectangle())
        .padding(.horizontal, 20)
        .onTapGesture {
            onToggleSelection()
        }
    }
    
    // MARK: 根据 rate 值返回背景图片
    private func backgroundImageForRate(_ rate: Int) -> some View {
        Group {
            if rate < 3{
                // 默认样式（毛玻璃效果）
                RoundedRectangle(cornerRadius: 16)
                    .background(.ultraThinMaterial.opacity(0.55))
                    .cornerRadius(16)
                    .overlay(topLeftHighlight)
                    .overlay(bottomRightHighlight)
                    .overlay(topEdgeHighlight)
                    .overlay(bottomEdgeHighlight)
            } else if rate >= 3 && rate <= 8 {
                // note_bg_green
                Image("note_bg_green")
                    .resizable()
            } else if rate >= 9 && rate <= 26 {
                // note_bg_blue
                Image("note_bg_blue")
                    .resizable()
            } else if rate >= 27 && rate <= 80 {
                // note_bg_purple
                Image("note_bg_purple")
                    .resizable()
            } else if rate >= 81 && rate <= 242 {
                // note_bg_yellow
                Image("note_bg_yellow")
                    .resizable()
            } else if rate > 242 {
                // note_bg_red
                Image("note_bg_red")
                    .resizable()
            } else {
                // 默认样式
                RoundedRectangle(cornerRadius: 16)
                    .background(.ultraThinMaterial.opacity(0.55))
                    .cornerRadius(16)
                    .overlay(topLeftHighlight)
                    .overlay(bottomRightHighlight)
                    .overlay(topEdgeHighlight)
                    .overlay(bottomEdgeHighlight)
            }
        }
    }
    
    // MARK: 标签高光效果
    private var mergeCardTagTopLeftHighlight: some View {
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
    
    private var mergeCardTagBottomRightHighlight: some View {
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
    
    private var mergeCardTagTopEdgeHighlight: some View {
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
    
    private var mergeCardTagBottomEdgeHighlight: some View {
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
    
    // MARK: 高光效果
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

// MARK: 固定卡片视图
struct FixedMergeCardView: View {
    let card: MergeCard
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 头部信息
            HStack {
                Text(card.date)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
            }
            
            // 内容文本
            HTMLTextRenderer(htmlContent: card.content, maxLines: 3)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.9))
            
            // 底部标签 横向滚动
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(card.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.2))
                                .overlay(fixedCardTagTopLeftHighlight)
                                .overlay(fixedCardTagBottomRightHighlight)
                                .overlay(fixedCardTagTopEdgeHighlight)
                                .overlay(fixedCardTagBottomEdgeHighlight)
                        )
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .allowsHitTesting(false)
                
                // 毛玻璃效果覆盖层
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial.opacity(0.3))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .padding(.horizontal, 20)
        .onTapGesture {
            // 固定卡片
        }
    }
    
    // MARK: 固定卡片标签高光效果
    private var fixedCardTagTopLeftHighlight: some View {
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
    
    private var fixedCardTagBottomRightHighlight: some View {
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
    
    private var fixedCardTagTopEdgeHighlight: some View {
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
    
    private var fixedCardTagBottomEdgeHighlight: some View {
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
    
    // MARK: - 根据 rate 值返回背景图片
    private func backgroundImageForRate(_ rate: Int) -> some View {
        Group {
            
            if rate < 3{
                // 默认样式（毛玻璃效果）
                RoundedRectangle(cornerRadius: 16)
                    .background(.ultraThinMaterial.opacity(0.55))
                    .cornerRadius(16)
                    .overlay(topLeftHighlight)
                    .overlay(bottomRightHighlight)
                    .overlay(topEdgeHighlight)
                    .overlay(bottomEdgeHighlight)
            } else if rate >= 3 && rate <= 8 {
                // note_bg_green
                Image("note_bg_green")
                    .resizable()
            } else if rate >= 9 && rate <= 26 {
                // note_bg_blue
                Image("note_bg_blue")
                    .resizable()
            } else if rate >= 27 && rate <= 80 {
                // note_bg_purple
                Image("note_bg_purple")
                    .resizable()
            } else if rate >= 81 && rate <= 242 {
                // note_bg_yellow
                Image("note_bg_yellow")
                    .resizable()
            } else if rate > 242 {
                // note_bg_red
                Image("note_bg_red")
                    .resizable()
            } else {
                // 默认样式
                RoundedRectangle(cornerRadius: 16)
                    .background(.ultraThinMaterial.opacity(0.55))
                    .cornerRadius(16)
                    .overlay(topLeftHighlight)
                    .overlay(bottomRightHighlight)
                    .overlay(topEdgeHighlight)
                    .overlay(bottomEdgeHighlight)
            }
        }
    }
    
    // MARK: - 固定卡片高光效果
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
                            startRadius: 5,
                            endRadius: 15
                        )
                    )
            )
    }
    
    private var bottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
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
    
    private var topEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: UnitPoint(x: 0, y: 0),
                            endPoint: UnitPoint(x: 1, y: 0.05)
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
                            startPoint: UnitPoint(x: 0, y: 0.95),
                            endPoint: UnitPoint(x: 1, y: 1)
                        )
                    )
            )
    }
}


#Preview {
    MergeView(cardId: 133)
} 
