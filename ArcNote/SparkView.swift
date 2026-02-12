import SwiftUI
import Combine
import UIKit

struct SparkView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentInspiredIndex = 0
    @State private var cardOffset: CGFloat = 0
    @State private var cardRotation: Double = 0
    @State private var cardScale: CGFloat = 1.0
    
    
    // Popup menu 状态
    @State private var showPopupMenu = false
    @State private var popupMenuLayout: PopupMenuLayout = .grid2x2
    @State private var currentMenuCardData: UserCard? = nil
    
    // 导航状态
    @State private var selectedCardId: Int? = nil
    @State private var showDetailView = false
    
    let cardId: Int
    @StateObject private var cardDetailManager = CardDetailManager.shared
    @StateObject private var relatedCardsManager = RelatedCardsManager.shared
    @State private var cancellables = Set<AnyCancellable>()
    
    // 监听返回首页通知
    @State private var shouldDismiss = false
    
    init(cardId: Int) {
        self.cardId = cardId
    }
    
    var body: some View {
        ZStack {
            // 背景图片
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶部导航栏
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // Spark 标题
                    HStack(spacing: 8) {
                        Image("menu_spark")
                            .resizable().frame(width: 28, height: 28)
                        
                        Text("Spark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // 右上角 Home 按钮
                    Button(action: {
                        // 递归 dismiss 所有父视图，确保回到首页
                        dismissAllViews()
                    }) {
                            Image("home_btn")
                                .resizable().frame(width: 25, height: 25)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                // 主要内容
                ScrollView {
                    VStack(spacing: 30) {
                        // Source Notes 部分
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Source Notes")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            
                            SourceNoteCard(cardDetail: cardDetailManager.cardDetail)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // Inspired Notes 部分
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Inspired Notes")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            
                            // 扇形滑动切换的卡片
                            ZStack {
                                // 第三张卡片（最底层）- 只显示背景
                                RoundedRectangle(cornerRadius: 16)
                                    .background(.ultraThinMaterial.opacity(0.55))
                                    .cornerRadius(16)
                                    .frame(height: 300)
                                    .offset(x: 40, y: 20)
                                    .opacity(0.3)
                                    .scaleEffect(0.95)
                                
                                // 第二张卡片（中间层）- 只显示背景
                                RoundedRectangle(cornerRadius: 16)
                                    .background(.ultraThinMaterial.opacity(0.55))
                                    .cornerRadius(16)
                                    .frame(height: 300)
                                    .offset(x: 20, y: 10)
                                    .opacity(0.6)
                                    .scaleEffect(0.97)
                                
                                // 第一张卡片（最顶层）- 显示完整内容
                                InspiredNoteCardWrapper(
                                    relatedCardsManager: relatedCardsManager,
                                    currentInspiredIndex: currentInspiredIndex,
                                    cardOffset: cardOffset,
                                    cardRotation: cardRotation,
                                    cardScale: cardScale,
                                    onMenuTap: { card in
                                        currentMenuCardData = card
                                        showPopupMenu = true
                                    },
                                    onCardTap: {
                                        // 获取当前卡片的ID并导航到详情页
                                        if !relatedCardsManager.relatedCards.isEmpty {
                                            let cardId = relatedCardsManager.relatedCards[currentInspiredIndex].id
                                            selectedCardId = cardId
                                            DispatchQueue.main.async {
                                                showDetailView = true
                                                print("导航状态: selectedCardId=\(selectedCardId), showDetailView=\(showDetailView)")
                                            }
                                        }
                                    }
                                )
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            // 只有在有相关卡片数据时才允许滑动
                                            guard !relatedCardsManager.relatedCards.isEmpty else { return }
                                            
                                            cardOffset = value.translation.width
                                            cardRotation = Double(value.translation.width / 10)
                                            cardScale = 1.0 - abs(value.translation.width) / 1000
                                        }
                                        .onEnded { value in
                                            // 只有在有相关卡片数据时才处理滑动
                                            guard !relatedCardsManager.relatedCards.isEmpty else { return }
                                            
                                            let threshold: CGFloat = 100
                                            if abs(value.translation.width) > threshold {
                                                // 滑动距离足够，先让当前卡片划走
                                                withAnimation(.easeInOut(duration: 0.3)) {
                                                    cardOffset = value.translation.width > 0 ? 500 : -500
                                                    cardRotation = value.translation.width > 0 ? 30 : -30
                                                    cardScale = 0.8
                                                }
                                                
                                                // 等待卡片划走后，立即切换新卡片
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                    // 向右滑动（正值）显示上一张，向左滑动（负值）显示下一张
                                                    if value.translation.width > 0 {
                                                        // 向右滑动：显示上一张卡片
                                                        currentInspiredIndex = (currentInspiredIndex - 1 + relatedCardsManager.relatedCards.count) % relatedCardsManager.relatedCards.count
                                                    } else {
                                                        // 向左滑动：显示下一张卡片
                                                        currentInspiredIndex = (currentInspiredIndex + 1) % relatedCardsManager.relatedCards.count
                                                    }
                                                    
                                                    // 立即重置卡片状态，新卡片直接出现
                                                    cardOffset = 0
                                                    cardRotation = 0
                                                    cardScale = 1.0
                                                    
                                                    print("切换到卡片索引: \(currentInspiredIndex)")
                                                }
                                            } else {
                                                // 滑动距离不够，回到原位
                                                withAnimation(.easeInOut(duration: 0.3)) {
                                                    cardOffset = 0
                                                    cardRotation = 0
                                                    cardScale = 1.0
                                                }
                                            }
                                        }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                    }
                }
            }
            
            
            EmptyView()
                .onAppear {
                    print("selectedCardId: \(selectedCardId), showDetailView: \(showDetailView)")
                }
                .onChange(of: selectedCardId) { newValue in
                    print("selectedCardId 变化: \(newValue)")
                }
                .onChange(of: showDetailView) { newValue in
                    print("showDetailView 变化: \(newValue)")
                }
            }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .overlay(
            Group {
                if let cardId = selectedCardId {
                    NavigationLink(
                        destination: DetailView(cardId: cardId)
                            .onAppear {
                                print("onAppear, cardId: \(cardId)")
                            },
                        isActive: $showDetailView
                    ) {
                        EmptyView()
                    }
                }
            }
        )
        .gesture(
            DragGesture()
                .onEnded { value in
                    // 侧滑返回手势
                    if value.translation.width > 100 && abs(value.translation.height) < 50 {
                        dismiss()
                    }
                }
        )
        .overlay(
            CommentPopupView()
        )
        .popupMenu(isPresented: $showPopupMenu, layout: popupMenuLayout, cardData: currentMenuCardData)
        .onAppear {
            if cardId > 0 {
                // 清除所有缓存数据
                cardDetailManager.clearCardDetail()
                relatedCardsManager.clearCache()
                
                loadCardDetail()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToHome"))) { _ in
            // 收到返回首页通知时，关闭当前视图
            shouldDismiss = true
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DismissAllSparkViews"))) { _ in
            // 收到关闭所有 SparkView 通知时，立即关闭
            dismiss()
        }
        .onChange(of: shouldDismiss) { newValue in
            if newValue {
                // 延迟一点时间，确保通知能够传播到所有 SparkView 实例
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - 加载卡片详情
    private func loadCardDetail() {
        print("开始加载卡片详情: cardId=\(cardId)")
        
        // 清除之前的卡片详情缓存
        cardDetailManager.clearCardDetail()
        
        cardDetailManager.fetchCardDetail(cardId: cardId) { result in
            switch result {
            case .success(let cardDetail):
                print("卡片详情加载成功: \(cardDetail.title)")
                
                loadMergeHistory()
            case .failure(let error):
                print("卡片详情加载失败: \(error)")
            }
        }
    }
    
    // MARK: - 生成相关卡片
    private func loadMergeHistory() {
        print("开始生成相关卡片: cardId=\(cardId)")
        
        // 清除之前的缓存数据
        relatedCardsManager.clearCache()
        
        // 获取用户ID
        guard let userId = AuthManager.shared.currentUser?.id else {
            print("用户未登录")
            return
        }
        
        // 调用生成相关卡片API
        relatedCardsManager.generateRelatedCards(userId: userId, cardId: cardId, count: 5)
        
        // 监听相关卡片数据变化，重置到第一张卡片
        relatedCardsManager.$relatedCards
            .receive(on: DispatchQueue.main)
            .sink { cards in
                if !cards.isEmpty {
                    currentInspiredIndex = 0
                    print("相关卡片生成完成")
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 递归关闭所有视图
    private func dismissAllViews() {
        // 发送通知让 TabBarView 切换到首页并清空导航栈
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToHome"),
            object: nil
        )
        
        // 发送通知让所有 SparkView 实例都关闭
        NotificationCenter.default.post(
            name: NSNotification.Name("DismissAllSparkViews"),
            object: nil
        )
        
        // 使用 UIKit 方法找到所有导航控制器并 pop 到根视图
        DispatchQueue.main.async {
            self.popAllNavigationStacks()
        }
        
        // 递归关闭所有层级
        dismissAllLevels(level: 0)
    }
    
    // MARK: - 递归关闭所有导航层级
    private func dismissAllLevels(level: Int) {
        guard level < 10 else { return }
        
        // 关闭当前视图
        dismiss()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                self.findAndPopAllNavigationControllers(in: rootViewController)
            }
        }
    }
    
    // MARK: 查找并 pop 所有导航控制
    private func findAndPopAllNavigationControllers(in viewController: UIViewController) {
        // 如果是导航控制器，pop 到根视图
        if let navController = viewController as? UINavigationController {
            // 如果导航栈中有多个视图，pop 到根
            if navController.viewControllers.count > 1 {
                navController.popToRootViewController(animated: false)
            }
        }
        
        for child in viewController.children {
            findAndPopAllNavigationControllers(in: child)
        }
        
        if let tabBarController = viewController as? UITabBarController {
            for child in tabBarController.viewControllers ?? [] {
                findAndPopAllNavigationControllers(in: child)
            }
        }
    }
    
    // MARK: - Pop 所有导航栈到根视图
    private func popAllNavigationStacks() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return
        }
        
        findAndPopNavigationControllers(in: rootViewController)
    }
    private func findAndPopNavigationControllers(in viewController: UIViewController) {
        
        if let navController = viewController as? UINavigationController {
            if navController.viewControllers.count > 1 {
                navController.popToRootViewController(animated: true)
            }
        }
        
        if let presented = viewController.presentedViewController {
            viewController.dismiss(animated: true) {
                self.findAndPopNavigationControllers(in: viewController)
            }
            return
        }
        
        if let tabBarController = viewController as? UITabBarController {
            for child in tabBarController.viewControllers ?? [] {
                findAndPopNavigationControllers(in: child)
            }
        }
        
        for child in viewController.children {
            findAndPopNavigationControllers(in: child)
        }
    }
    
    // MARK: - 关闭最顶层的视图控制器
    private func dismissTopmostViewController(from viewController: UIViewController) {
        // 找到最顶层的 presented 视图控制器
        var topViewController = viewController
        while let presented = topViewController.presentedViewController {
            topViewController = presented
        }
        
        // 如果最顶层不是根视图控制器，尝试 dismiss
        if topViewController != viewController {
            topViewController.presentingViewController?.dismiss(animated: true, completion: nil)
        }
    }
    
    // MARK: - 格式化日期
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
            } else {
                let days = Int(timeInterval / 86400)
                return "\(days) days ago"
            }
        }
        
        return dateString
    }
}

// MARK: - Inspired Note Card Wrapper
struct InspiredNoteCardWrapper: View {
    @ObservedObject var relatedCardsManager: RelatedCardsManager
    let currentInspiredIndex: Int
    let cardOffset: CGFloat
    let cardRotation: Double
    let cardScale: CGFloat
    let onMenuTap: (UserCard) -> Void
    let onCardTap: (() -> Void)?
    
    var body: some View {
        if !relatedCardsManager.relatedCards.isEmpty {
            InspiredNoteCard(
                card: relatedCardsManager.relatedCards[currentInspiredIndex],
                showMenu: true,
                relatedCardsManager: relatedCardsManager,
                onMenuTap: onMenuTap,
                onCardTap: onCardTap
            )
            .opacity(1.0)
            .scaleEffect(1.0)
            .offset(x: cardOffset, y: 0)
            .rotationEffect(.degrees(cardRotation))
            .scaleEffect(cardScale)
        } else if relatedCardsManager.isLoading {
            // 加载状态
            VStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                Text("Generating related content...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 16)
            }
            .frame(height: 300)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .background(.ultraThinMaterial.opacity(0.55))
                    .cornerRadius(16)
            )
            .opacity(1.0)
            .scaleEffect(1.0)
            .offset(x: cardOffset, y: 0)
            .rotationEffect(.degrees(cardRotation))
            .scaleEffect(cardScale)
        } else {
            // 空状态
            VStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.5))
                Text("No related content available")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 16)
            }
            .frame(height: 300)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .background(.ultraThinMaterial.opacity(0.55))
                    .cornerRadius(16)
            )
            .opacity(1.0)
            .scaleEffect(1.0)
            .offset(x: cardOffset, y: 0)
            .rotationEffect(.degrees(cardRotation))
            .scaleEffect(cardScale)
        }
    }
}

// MARK: - Source Note Card
struct SourceNoteCard: View {
    let cardDetail: CardDetail?
    
    // MARK: 格式化日期
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
            } else {
                let days = Int(timeInterval / 86400)
                return "\(days) days ago"
            }
        }
        
        return dateString
    }
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .background(.ultraThinMaterial.opacity(0.55))
            .cornerRadius(16)
            .overlay(sourceTopLeftHighlight)
            .overlay(sourceBottomRightHighlight)
            .overlay(sourceTopEdgeHighlight)
            .overlay(sourceBottomEdgeHighlight)
    }
    
    private var sourceTopLeftHighlight: some View {
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
    
    private var sourceBottomRightHighlight: some View {
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
    
    private var sourceTopEdgeHighlight: some View {
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
    
    private var sourceBottomEdgeHighlight: some View {
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
        VStack(alignment: .leading, spacing: 16) {
            // 头部信息
            HStack {
                // 头像
                Image("avatar")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(cardDetail?.author?.userName ?? "Unknown User")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(formatDate(cardDetail?.createdAt ?? ""))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
            }
            
            // 内容文本
            if let cardDetail = cardDetail {
                HTMLTextRenderer(htmlContent: cardDetail.content, maxLines: 5)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.9))
            } else {
                Text("Loading content...")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // 底部标签 横向滚动视图
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(cardDetail?.tags ?? [], id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(Color.white.opacity(0.2))
                            )
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 1) // 添加一点内边距，避免标签贴边
            }
        }
        .padding(20)
        .background(cardBackground)
    }
}

// MARK: - Inspired Note Card
struct InspiredNoteCard: View {
    let card: RelatedCard
    let showMenu: Bool
    @ObservedObject var relatedCardsManager: RelatedCardsManager
    let onMenuTap: (UserCard) -> Void
    let onCardTap: (() -> Void)?
    
    // MARK: - 格式化日期
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
            } else {
                let days = Int(timeInterval / 86400)
                return "\(days) days ago"
            }
        }
        
        return dateString
    }
    
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
            // 用户信息 固定在顶部
            HStack {
                // 头像
                NavigationLink(destination: UserProfileView(userId: card.author?.userId ?? AuthManager.shared.currentUser?.id ?? 1)) {
                    AsyncImage(url: URL(string: card.author?.avatarUrl ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image("avatar")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .frame(width: 50, height: 50)
                            .clipShape(Circle())
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.author?.username ?? AuthManager.shared.currentUser?.username ?? "AI Generated")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(formatDate(card.createdAt))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                if showMenu {
                    Button(action: {
                        // 创建UserCard对象用于菜单
                        let userCard = UserCard(
                            id: card.id,
                            title: card.title,
                            content: card.content,
                            contentHash: "",
                            isPublic: true,
                            tags: card.tags,
                            createdAt: "",
                            updatedAt: "",
                            likeCount: card.likeCount ?? 0,
                            commentCount: card.commentCount,
                            isLiked: card.isLiked ?? false,
                            isPinned: false,
                            pinnedAt: nil,
                            isFavorited: card.isFavorited,
                            favoriteCount: card.favoriteCount,
                            rate: 0 // RelatedCard 模型没有 rate 字段，默认为 0
                        )
                        onMenuTap(userCard)
                    }) {
                        Image(systemName: "ellipsis")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.bottom, 16)
            
            // 帖子内容 - 填充剩余空间
            VStack(alignment: .leading, spacing: 12) {
                HTMLTextRenderer(htmlContent: card.content, maxLines: 10)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onCardTap?()
            }
            
            // 底部内容 - 固定在底部
            VStack(spacing: 16) {
                // 标签 横向滚动视图
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(card.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(Color.white.opacity(0.1))
                                )
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 1) // 添加一点内边距，避免标签贴边
                }
                
                // 交互统计
                HStack {
                    // 左边一个 收藏按钮
                    Button(action: {
                        relatedCardsManager.toggleFavorite(for: card.id)
                    }) {
                        HStack(spacing: 4) {
                            Image(relatedCardsManager.getFavoriteState(for: card.id) ? "favorite" : "favorite")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                            Text("\(relatedCardsManager.getFavoriteCount(for: card.id))")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    
                    Spacer()
                    
                    // 右边两个
                    HStack(spacing: 20) {
                        Button(action: {
                            relatedCardsManager.toggleLike(for: card.id)
                        }) {
                            HStack(spacing: 4) {
                                Image(relatedCardsManager.getLikeState(for: card.id) ? "like_active" : "like")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 18, height: 18)
                                Text("\(relatedCardsManager.getLikeCount(for: card.id))")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        
                        CommentButton(cardId: card.id, relatedCardsManager: relatedCardsManager)
                    }
                }
            }
        }
        .padding(20)
        .frame(height: 300)
        .background(cardBackground)
    }
}

// 标签组件
//struct TagView: View {
//    let text: String
//    
//    var body: some View {
//        Text(text)
//            .font(.system(size: 12, weight: .medium))
//            .foregroundColor(.white)
//            .padding(.horizontal, 12)
//            .padding(.vertical, 6)
//            .background(
//                RoundedRectangle(cornerRadius: 15)
//                    .fill(Color.white.opacity(0.1))
//            )
//    }
//}

#Preview {
    SparkView(cardId: 133)
} 
