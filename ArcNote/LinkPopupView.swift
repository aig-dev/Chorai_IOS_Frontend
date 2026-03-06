import SwiftUI
import Combine
import UIKit

// MARK: - Link数据模型
struct LinkItem: Identifiable {
    let id: Int
    let avatar: String
    let title: String
    let description: String
    let username: String
    let authorId: Int?
    let labels: [String]
    
    init(id: Int, avatar: String, title: String, description: String, username: String, authorId: Int? = nil, labels: [String] = []) {
        self.id = id
        self.avatar = avatar
        self.title = title
        self.description = description
        self.username = username
        self.authorId = authorId
        self.labels = labels
    }
}

// MARK: - Link弹窗管理器
class LinkPopupManager: ObservableObject {
    @Published var isShowing = false
    @Published var searchText = ""
    @Published var linkItems: [LinkItem] = []
    @Published var isLoading = false
    @Published var isLinking = false
    @Published var showErrorAlert = false
    @Published var errorMessage = ""
    
    // 选择回调
    var onCardSelected: ((LinkItem) -> Void)?
    
    private var cancellables = Set<AnyCancellable>()
    private var currentCardId: Int? = nil
    private var searchType: String = "own+favorite" // 默认搜索类型
    private var isInitiatingCardOwned = true
    
    static let shared = LinkPopupManager()
    
    private init() {
        // 监听搜索文本变化
        $searchText
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] searchText in
                self?.searchCards(keyword: searchText)
            }
            .store(in: &cancellables)
    }
    
    func show(cardId: Int? = nil, isInitiatingCardOwned: Bool = true) {
        isShowing = true
        currentCardId = cardId
        self.isInitiatingCardOwned = isInitiatingCardOwned
        self.searchType = isInitiatingCardOwned ? "own+favorite" : "own"
        // 打开时获取初始数据（不带关键词）
        searchCards(keyword: "")
    }
    
    func hide() {
        isShowing = false
        searchText = ""
        linkItems = []
        currentCardId = nil
        isInitiatingCardOwned = true
    }
    
    // MARK: - Link 卡片
    func linkCard(linkItem: LinkItem) {
        if let cardId = currentCardId {
            // 如果有cardId，调用API关联卡片
            guard let userId = AuthManager.shared.currentUser?.id else {
                return
            }
            
            isLinking = true
            
            // card_id 必须属于发起用户的卡片
            let actualCardId: Int
            let actualLinkedCardId: Int
            
            if isInitiatingCardOwned {
                // 发起卡片属于当前用户
                actualCardId = cardId
                actualLinkedCardId = linkItem.id
                print("开始关联卡片: cardId=\(actualCardId), linkedCardId=\(actualLinkedCardId)")
            } else {
                // 发起卡片不属于当前用户，改用搜索结果中的自有卡片作为 card_id
                actualCardId = linkItem.id
                actualLinkedCardId = cardId
                print("开始关联卡片own: cardId=\(actualCardId), linkedCardId=\(actualLinkedCardId)")
            }
            
            let linkRequest = LinkRequest(userId: userId, linkedCardId: actualLinkedCardId)
            
            NetworkManager.shared.createCardLink(cardId: actualCardId, reques: linkRequest)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { [weak self] completion in
                        self?.isLinking = false
                        if case .failure(let error) = completion {
                            print("关联卡片失败: \(error.localizedDescription)")
                            // 检查是否是400错误（卡片链接已存在）
                            switch error {
                            case .serverError(let code, _):
                                if code == 400 {
                                    self?.errorMessage = "卡片链接已存在"
                                } else {
                                    self?.errorMessage = "链接失败"
                                }
                                self?.showErrorAlert = true
                            default:
                                self?.errorMessage = "链接失败"
                                self?.showErrorAlert = true
                            }
                        }
                    },
                    receiveValue: { [weak self] response in
                        self?.isLinking = false
                        if response.success {
                            guard let self = self else { return }
                            self.hide()
                            
                            // 判断被链接的卡片是否属于当前用户
                            let targetCardId: Int
//                            if self.searchType == "own" {
//                                // own模式：被链接的卡片是 actualCardId（即 linkItem.id）
                                targetCardId = actualCardId
//                            } else {
//                                // 正常模式：被链接的卡片是 actualLinkedCardId（即 linkItem.id）
//                                targetCardId = actualLinkedCardId
//                            }
                            
                            // 判断是否为自己的卡片
                            let isOwnCard = linkItem.authorId == userId
                            
                            if isOwnCard {
                                // 如果是自己的卡片，跳转到编辑页
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("NavigateToEdit"),
                                    object: nil,
                                    userInfo: ["cardId": targetCardId]
                                )
                            } else {
                                // 如果不是自己的卡片，跳转到详情页
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("NavigateToDetail"),
                                    object: nil,
                                    userInfo: ["cardId": targetCardId]
                                )
                            }
                            
                            // 调用回调
                            self.onCardSelected?(linkItem)
                        } else {
                            print("失败: \(response.message)")
                        }
                    }
                )
                .store(in: &cancellables)
        } else {
            print("选择卡片: \(linkItem.title)")
            hide()
            onCardSelected?(linkItem)
        }
    }
    
    // 搜索卡片
    private func searchCards(keyword: String) {
        guard let userId = AuthManager.shared.currentUser?.id else {
            print("用户未登录")
            return
        }
        
        isLoading = true
        
        // 根据关键词决定搜索类型
        let searchValue = keyword.isEmpty ? "" : keyword
        
        NetworkManager.shared.getUserAllCards(
            userId: userId,
            searchType: searchType,
            search: searchValue,
            limit: 50,
            cardId: currentCardId
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    print("搜索卡片失败: \(error.localizedDescription)")
                }
            },
            receiveValue: { [weak self] response in
                self?.isLoading = false
                if response.success {
                    // 合并所有类型的卡片
                    var allCards: [UserAllCard] = []
                    allCards.append(contentsOf: response.data.ownCards)
                    allCards.append(contentsOf: response.data.favoritedCards)
                    allCards.append(contentsOf: response.data.likedCards)
                    allCards.append(contentsOf: response.data.linkedCards)
                    
                    self?.linkItems = allCards.map { card in
                        LinkItem(
                            id: card.id,
                            avatar: card.author?.avatar ?? "", // 使用author的avatar字段
                            title: card.title ?? "",
                            description: card.content,
                            username: card.author?.username ?? "Unknown", // 使用author的username字段
                            authorId: card.author?.id, // 传入作者ID
                            labels: self?.parseLabels(card.labels) ?? [] // 解析labels字符串为数组
                        )
                    }
                } else {
                    print("搜索失败: 服务器返回失败")
                }
            }
        )
        .store(in: &cancellables)
    }
    
    // 过滤后的Link项目
    var filteredItems: [LinkItem] {
        return linkItems
    }
    
    // MARK: 解析labels字符串为数组
    private func parseLabels(_ labelsString: String) -> [String] {
        // 如果labels为空或只包含空白字符，返回空数组
        let trimmed = labelsString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return []
        }
        
        // 尝试解析JSON数组格式
        if let data = trimmed.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return jsonArray
        }
        
        // 如果不是JSON格式，尝试按逗号分割
        return trimmed.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Link弹窗视图
struct LinkPopupView: View {
    @ObservedObject private var manager = LinkPopupManager.shared
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        if manager.isShowing {
            ZStack {
                Color.black.opacity(0.5)
                    .ignoresSafeArea(.all)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture {
                        isTextFieldFocused = false
                        manager.hide()
                    }
                
                // 弹窗内容
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        // 弹窗头部
//                        HStack {
//                            Text("Link")
//                                .font(.system(size: 18, weight: .semibold))
//                                .foregroundColor(.white)
//                            
//                            Spacer()
//                            
//                            Button(action: {
//                                isTextFieldFocused = false
//                                manager.hide()
//                            }) {
//                                Image(systemName: "xmark")
//                                    .font(.system(size: 16, weight: .medium))
//                                    .foregroundColor(.white)
//                            }
//                        }
//                        .padding(.horizontal, 20)
//                        .padding(.top, 20)
//                        .padding(.bottom, 16)
//                        
                        // 搜索栏
                        HStack {
                            TextField("Design", text: $manager.searchText)
                                .textFieldStyle(PlainTextFieldStyle())
                                .foregroundColor(.white)
                                .focused($isTextFieldFocused)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 30)
                                        .fill(.ultraThinMaterial.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 30)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                            
                            Button("Cancel") {
                                isTextFieldFocused = false
                                manager.hide()
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.leading, 12)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        
                        // Link列表
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                if manager.isLoading {
                                    // 加载状态
                                    VStack(spacing: 12) {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        Text("Loading...")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .frame(height: 100)
                                } else if manager.filteredItems.isEmpty {
                                    // 空状态
                                    VStack(spacing: 12) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 32))
                                            .foregroundColor(.white.opacity(0.5))
                                        Text("No cards found")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .frame(height: 100)
                                } else {
                                    // 数据列表
                                    ForEach(Array(manager.filteredItems.enumerated()), id: \.element.id) { index, item in
                                        VStack(spacing: 0) {
                                            LinkItemView(item: item)
                                                .onTapGesture {
                                                    // 调用 link 方法
                                                    manager.linkCard(linkItem: item)
                                                }
                                            
                                            // 分割线（除了最后一个）
                                            if index < manager.filteredItems.count - 1 {
                                                Rectangle()
                                                    .fill(Color.white.opacity(0.2))
                                                    .frame(height: 1)
                                                    .padding(.horizontal, 20)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, 20)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(maxWidth: geometry.size.width * 0.9, maxHeight: UIScreen.main.bounds.height * 0.55)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .background(.ultraThinMaterial.opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .cardHighlightEffect()
                            .cornerRadius(20)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2.8)
                    .transition(.scale.combined(with: .opacity))
                }
                
                .animation(.easeInOut(duration: 0.3), value: manager.isShowing)
                .ignoresSafeArea(.all)
                .onAppear {
                    isTextFieldFocused = true
                    // 强制禁用键盘自动调整
                    if let window = keyWindow() {
                        window.endEditing(true)
                    }
                    disableKeyboardAdjustment()
                }
                .alert("Notice", isPresented: $manager.showErrorAlert) {
                    Button("OK") {
                        manager.showErrorAlert = false
                    }
                } message: {
                    Text(manager.errorMessage)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
        }
    }
}

// MARK: - Link项目视图
struct LinkItemView: View {
    let item: LinkItem
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 头像
            if !item.avatar.isEmpty {
                AsyncImage(url: URL(string: item.avatar)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .overlay(
                            Text(String(item.username.prefix(1)).uppercased())
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                // 默认头像
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(item.username.prefix(1)).uppercased())
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            
            // 内容区域
            VStack(alignment: .leading, spacing: 8) {
                // 第一行：用户名
                Text(item.username)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                // 第二行：内容
                HTMLTextRenderer(htmlContent: item.description, maxLines: 4)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                
                // 标签
                if !item.labels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(item.labels, id: \.self) { label in
                                Text(label)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(linkItemTagBackground)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 1) // 添加一点内边距，避免标签贴边
                    }
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: 标签背景样式
    private var linkItemTagBackground: some View {
        RoundedRectangle(cornerRadius: 15)
            .fill(Color.white.opacity(0.2))
            .overlay(linkItemTagTopLeftHighlight)
            .overlay(linkItemTagBottomRightHighlight)
            .overlay(linkItemTagTopEdgeHighlight)
            .overlay(linkItemTagBottomEdgeHighlight)
    }
    
    // MARK: 标签高光
    private var linkItemTagTopLeftHighlight: some View {
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
    
    private var linkItemTagBottomRightHighlight: some View {
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
    
    private var linkItemTagTopEdgeHighlight: some View {
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
    
    private var linkItemTagBottomEdgeHighlight: some View {
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
}

// MARK: - Link弹窗Modifier
struct LinkPopupModifier: ViewModifier {
    @ObservedObject private var manager = LinkPopupManager.shared
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if manager.isShowing {
                        LinkPopupView()
                            .transition(.opacity.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: manager.isShowing)
                .ignoresSafeArea(.all)
            )
    }
}

// MARK: - View Extension
extension View {
    func linkPopup() -> some View {
        self.modifier(LinkPopupModifier())
    }
}

// MARK: - Window Helper
private func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }
}

// MARK: - 禁用键盘调整扩展
extension View {
    func disableKeyboardAdjustment() {
        // 递归查找并禁用所有UITextField的自动调整
        if let window = keyWindow() {
            disableKeyboardAdjustmentRecursive(in: window)
        }
    }
    
    private func disableKeyboardAdjustmentRecursive(in view: UIView) {
        // 如果是UITextField，禁用自动调整
        if let textField = view as? UITextField {
            textField.autocorrectionType = .no
            textField.autocapitalizationType = .none
            textField.smartDashesType = .no
            textField.smartQuotesType = .no
            textField.smartInsertDeleteType = .no
        }
        
        // 递归处理子视图
        for subview in view.subviews {
            disableKeyboardAdjustmentRecursive(in: subview)
        }
    }
}

#Preview {
    ZStack {
        Color.black
            .ignoresSafeArea()
        
        VStack {
            Text("Test Content")
                .foregroundColor(.white)
            
            Button("Show Link Popup") {
                LinkPopupManager.shared.show()
            }
        }
    }
    .linkPopup()
} 
