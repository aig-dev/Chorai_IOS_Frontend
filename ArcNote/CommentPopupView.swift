import Combine
import CoreFlow
import SwiftUI

// MARK: 禁用键盘调整的扩展
extension View {
    func disableKeyboardAdjustment(in view: UIView) {
        if let scrollView = view as? UIScrollView {
            scrollView.keyboardDismissMode = .none
            scrollView.contentInsetAdjustmentBehavior = .never
        }
        
        for subview in view.subviews {
            disableKeyboardAdjustment(in: subview)
        }
    }
}


// MARK: 评论弹窗管理器
class CommentPopupManager: ObservableObject {
    @Published var isShowing = false
    @Published var comments: [CommentModel] = []
    @Published var isLoading = false
    @Published var showErrorAlert = false
    @Published var errorMessage = ""
    
    // Callback for when a comment is created
    var onCommentCreated: ((String) -> Void)?
    
    static let shared = CommentPopupManager()
    private var commentManager = CommentManager()
    private var currentCardId: String?
    
    private init() {
        // 监听评论管理器的数据变化
        commentManager.$comments
            .assign(to: \.comments, on: self)
            .store(in: &cancellables)
        
        commentManager.$isLoading
            .assign(to: \.isLoading, on: self)
            .store(in: &cancellables)
        
        // 设置评论数量变化回调
        commentManager.onCommentCountChanged = { cardId, newCount in
            print("评论数量变化回调: cardId=\(cardId), newCount=\(newCount)")
            // 通知所有相关的卡片管理器更新评论数量
            NotificationCenter.default.post(
                name: NSNotification.Name("CommentCountChanged"),
                object: nil,
                userInfo: ["cardId": cardId, "newCount": newCount]
            )
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
//    func show() {
//        isShowing = true
//    }
    
    func hide() {
        isShowing = false
    }
    
    func show(for cardId: String) {
        currentCardId = cardId
        isShowing = true
        commentManager.loadComments(for: cardId, refresh: true)
    }
    
    func addComment(_ content: String) {
        guard let cardId = currentCardId else { return }
        
        commentManager.createComment(
            for: cardId,
            content: content
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let comment):
                    print("评论发布成功: id=\(comment.id)")
                case .failure(let error):
                    print("评论发布失败: \(error.localizedDescription)")
                    
                    // 检查是否是未授权错误
                    if case .unauthorized = error {
                        self.hide()
                        // 发送通知返回首页
                        NotificationCenter.default.post(
                            name: NSNotification.Name("UnauthorizedError"),
                            object: nil
                        )
                    } else {
                        self.errorMessage = "Failed comment: \(error.localizedDescription)"
                        self.showErrorAlert = true
                    }
                }
            }
        }
    }
    
    func loadMoreComments() {
        guard currentCardId != nil else { return }
        commentManager.loadMoreComments()
    }
    
    func refreshComments() {
        guard currentCardId != nil else { return }
        commentManager.refreshComments()
    }
    
    // MARK: - 移除评论（用于拉黑后移除）
    func removeComment(commentId: String) {
        DispatchQueue.main.async {
            // 从主评论列表中移除
            if let index = self.comments.firstIndex(where: { $0.id == commentId }) {
                self.comments.remove(at: index)

                // 更新评论数量
                if let cardId = self.currentCardId {
                    let newCount = self.comments.count
                    NotificationCenter.default.post(
                        name: NSNotification.Name("CommentCountChanged"),
                        object: nil,
                        userInfo: ["cardId": cardId, "newCount": newCount]
                    )
                }
            } else {
                // 从子评论中移除
                for i in 0..<self.comments.count {
                    if let replyIndex = self.comments[i].replies.firstIndex(where: { $0.id == commentId }) {
                        self.comments[i].replies.remove(at: replyIndex)
                        print("已移除回复: replyId=\(commentId)")
                        
                        // 更新回复数量
                        var updatedComment = self.comments[i]
                        updatedComment = CommentModel(
                            id: updatedComment.id,
                            commentAssetId: updatedComment.commentAssetId,
                            cardId: updatedComment.cardId,
                            parentCommentId: updatedComment.parentCommentId,
                            content: updatedComment.content,
                            createdAt: updatedComment.createdAt,
                            updatedAt: updatedComment.updatedAt,
                            user: updatedComment.user,
                            replies: updatedComment.replies
                        )
                        self.comments[i] = updatedComment
                        break
                    }
                }
            }
        }
    }
}

// MARK: - 评论弹窗视图
struct CommentPopupView: View {
    @ObservedObject private var manager = CommentPopupManager.shared
    @State private var commentText = ""
    @State private var keyboardHeight: CGFloat = 0
    @State private var slideOffset: CGFloat = 0
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
//        if manager.isShowing {
            ZStack {
                // 背景遮罩
                if manager.isShowing {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            isTextFieldFocused = false
                            manager.hide()
                        }
                }
                
                // 弹窗内容
                GeometryReader { geometry in
                    let sheetHeight = geometry.size.height * 0.6
                    let hiddenOffset = sheetHeight + geometry.safeAreaInsets.bottom

                    VStack(spacing: 0) {
                        #if DEBUG
                        Text("Comment popup")
                            .font(.system(size: 1))
                            .foregroundColor(.white.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("comment.popup")
                        #endif

                        // 弹窗头部
                        HStack {
                            Text("Comment")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button(action: {
                                isTextFieldFocused = false
                                manager.hide()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                        .adaptiveContentGutter()
                        .padding(.top, 20)
                        .padding(.bottom, 16)
                        .frame(height: 60) // 固定头部高度
                        
                        // 评论列表
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: true) {
                                LazyVStack(spacing: 16) {
                                    // 加载状态
                                    if manager.isLoading && manager.comments.isEmpty {
                                        VStack {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(1.2)
                                            Text("Loading comments...")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.white.opacity(0.7))
                                                .padding(.top, 10)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 40)
                                    } else {
                                        ForEach(manager.comments) { comment in
                                            CommentRowView(comment: comment)
                                                .id(comment.id)
                                                .accessibilityIdentifier("comment.row.\(comment.id)")
                                        }
                                        
                                        // 加载更多指示器
                                        if manager.isLoading && !manager.comments.isEmpty {
                                            HStack {
                                                Spacer()
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                    .scaleEffect(0.8)
                                                Text("Loading more...")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(.white.opacity(0.7))
                                                    .padding(.leading, 8)
                                                Spacer()
                                            }
                                            .padding(.vertical, 20)
                                        }
                                    }
                                }
                                .adaptiveContentGutter()
                                .padding(.top, 10)
                                .padding(.bottom, 20)
                            }
                            .frame(maxHeight: .infinity)
                            .clipped()
                            .refreshable {
                                manager.refreshComments()
                            }
                            .onChange(of: keyboardHeight) { _ in
                                // 当键盘高度变化时，滚动到顶部避免系统自动滚动
                                if let firstComment = manager.comments.first {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(firstComment.id, anchor: .top)
                                    }
                                }
                            }
                        }
                        
                        // 评论输入框
                        HStack(spacing: 12) {
                            HStack(spacing: 12){
                                TextField("Add Comment", text: $commentText)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .foregroundColor(.white)
                                    .padding(.vertical, 12)
                                    .placeholder(when: commentText.isEmpty) {
                                        Text("Add Comment")
                                            .foregroundColor(Color(red: 0.627, green: 0.627, blue: 0.627)) // A0A0A0
                                    }
                                    .focused($isTextFieldFocused)
                                    .onTapGesture {
                                        // 防止系统自动滚动
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            isTextFieldFocused = true
                                        }
                                    }
                                    .accessibilityIdentifier("comment.input")
                                
                                Button(action: {
                                    if !commentText.isEmpty {
                                        manager.addComment(commentText)
                                        
                                        // 重置状态
                                        commentText = ""
                                        isTextFieldFocused = false
                                    }
                                }) {
                                    Image("send")
                                        .resizable()
                                        .frame(width: 40,height: 40)
                                }
                                .accessibilityIdentifier("comment.send")
                                .disabled(commentText.isEmpty)
                            }
                            .padding(.leading, 16)
                            .padding(.trailing, 2)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 15)
                                    .background(.ultraThinMaterial)
                                    .roundedButtonHighlightEffect(cornerRadius: 30)
                            )
                            .cornerRadius(30)
                        }
                        .padding(.top, 10)
                        .adaptiveContentGutter()
                        .padding(.bottom, 40)
                        .frame(height: 80) // 固定输入框区域高度
//                        .background(Color.white.opacity(0.1))
                    }
                    .frame(maxWidth: geometry.size.width, maxHeight: sheetHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .background(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .cardHighlightEffect()
                            .cornerRadius(16)
                    )
                    .clipShape(
                        RoundedCorner(radius: 20, corners: [.topLeft, .topRight])
                    )
                    .accessibilityIdentifier("adaptive-layout.comment-surface")
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height - sheetHeight / 2 - keyboardHeight
                            + geometry.safeAreaInsets.bottom
                    )
                    .offset(y: slideOffset)
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                            keyboardHeight = keyboardFrame.height - 20
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                        keyboardHeight = 0
                    }
                    .animation(.easeInOut(duration: 0.4), value: slideOffset)
                    .animation(.easeInOut(duration: 0.3), value: keyboardHeight)
                    .onChange(of: manager.isShowing) { isShowing in
                        if isShowing {
                            slideOffset = hiddenOffset
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                guard manager.isShowing else { return }
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    slideOffset = 0
                                }
                            }
                        } else {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                slideOffset = hiddenOffset
                            }
                        }
                    }
                    .onChange(of: geometry.size) { _ in
                        if !manager.isShowing {
                            slideOffset = hiddenOffset
                        }
                    }
                    .onAppear {
                        slideOffset = manager.isShowing ? 0 : hiddenOffset
                    }
                }

                .onChange(of: manager.isShowing) { isShowing in
                    if !isShowing {
                        isTextFieldFocused = false
                    }
                }
                .alert("Error", isPresented: $manager.showErrorAlert) {
                    Button("OK") {
                        manager.showErrorAlert = false
                    }
                } message: {
                    Text(manager.errorMessage)
                }
//                .ignoresSafeArea(.container, edges: .bottom)
                .ignoresSafeArea(.keyboard, edges: .bottom)
//                .onAppear {
//                    // 禁用系统键盘处理
//                    UIApplication.shared.windows.first?.endEditing(true)
//                    
//                    // 禁用所有ScrollView的自动键盘处理
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                        if let window = UIApplication.shared.windows.first {
//                            disableKeyboardAdjustment(in: window)
//                        }
//                    }
//                }
            }
//        }
    }
    
}

// MARK: 评论行视图
struct CommentRowView: View {
    let comment: CommentModel
    let isSubComment: Bool
    
    @State private var showActionSheet = false
    @State private var navigateToReport = false
    @State private var cancellables = Set<AnyCancellable>()
    
    init(comment: CommentModel, isSubComment: Bool = false) {
        self.comment = comment
        self.isSubComment = isSubComment
    }
    
    // 检查是否是当前用户的评论
    private var isCurrentUserComment: Bool {
        guard let currentUserId = AuthManager.shared.currentUser?.id else {
            return false
        }
        return comment.user.id == currentUserId
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: isSubComment ? 4 : 12) {
            // 评论内容
            HStack(alignment: .top, spacing: 12) {
                // 头像
                AsyncImage(url: URL(string: comment.user.avatarUrl ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 8) {
                    // 用户名和时间
                    HStack {
                        Text(comment.user.username ?? comment.user.id)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        if !isCurrentUserComment {
                            Button(action: {
                                showActionSheet = true
                            }) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    
                    // 评论内容
                    Text(comment.content)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                        .accessibilityIdentifier("comment.content.\(comment.id)")
                    
                    Text(formatDate(comment.createdAt))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            // 子评论（只有主评论才显示）
            if !isSubComment && !comment.replies.isEmpty {
                VStack(spacing: 8) {
                    ForEach(comment.replies) { subComment in
                        CommentRowView(comment: subComment, isSubComment: true)
                    }
                }
                .padding(.leading, 52) // 缩进对齐
            }
        }
        .confirmationDialog("", isPresented: $showActionSheet, titleVisibility: .hidden) {
            Button("Report this user", role: .destructive) {
                navigateToReport = true
            }
            Button("Block this user", role: .destructive) {
                blockUser()
            }
            Button("Cancel", role: .cancel) {}
        }
        .navigationDestination(isPresented: $navigateToReport) {
            WebViewPage(
                url: ChoraiWebDestination.report,
                title: "Help & Report"
            )
        }
    }
    
    // MARK: - 拉黑用户
    private func blockUser() {
        guard let currentUserId = AuthManager.shared.currentUser?.id else {
            return
        }
        
        
        NetworkManager.shared.blockUser(blockedActorId: comment.user.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("拉黑用户失败: \(error.localizedDescription)")
                    } else {
                        print("拉黑用户成功")
                    }
                },
                receiveValue: { _ in
                    print("拉黑用户请求完成")
                    // 拉黑后移除该评论
                    CommentPopupManager.shared.removeComment(commentId: comment.id)
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 日期格式化方法
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        if let date = formatter.date(from: dateString) {
            let now = Date()
            let timeInterval = now.timeIntervalSince(date)
            
            if timeInterval < 60 {
                return "刚刚"
            } else if timeInterval < 3600 {
                let minutes = Int(timeInterval / 60)
                return "\(minutes)分钟前"
            } else if timeInterval < 86400 {
                let hours = Int(timeInterval / 3600)
                return "\(hours)小时前"
            } else if timeInterval < 604800 {
                let days = Int(timeInterval / 86400)
                return "\(days)天前"
            } else {
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "MM-dd"
                return displayFormatter.string(from: date)
            }
        }
        
        return dateString
    }
}



// MARK: 评论按钮组件
struct CommentButton: View {
    @ObservedObject private var manager = CommentPopupManager.shared
    @ObservedObject private var relatedCardsManager = RelatedCardsManager.shared
    let cardId: String
    let cardsManager: RecommendedCardsManager?
    let useRelatedCardsManager: Bool
    let iconSize: CGFloat
    @State private var staticCommentCount: Int = 0
    
    init(cardId: String, cardsManager: RecommendedCardsManager) {
        self.cardId = cardId
        self.cardsManager = cardsManager
        self.useRelatedCardsManager = false
        self.iconSize = 20
        self.staticCommentCount = 0
    }
    
    init(cardId: String, relatedCardsManager: RelatedCardsManager) {
        self.cardId = cardId
        self.cardsManager = nil
        self.useRelatedCardsManager = true
        self.iconSize = 20
        self.staticCommentCount = 0
    }
    
    init(cardId: String, commentCount: Int = 0, iconSize: CGFloat = 20) {
        self.cardId = cardId
        self.cardsManager = nil
        self.useRelatedCardsManager = false
        self.iconSize = iconSize
        self.staticCommentCount = commentCount
    }
    
    var body: some View {
        Button(action: {
            manager.show(for: cardId)
        }) {
            HStack(spacing: 4) {
                Image("comment")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                Text("\(displayCommentCount)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CommentCountChanged"))) { notification in
            if let userInfo = notification.userInfo,
               let updatedCardId = userInfo["cardId"] as? String,
               let newCount = userInfo["newCount"] as? Int,
               updatedCardId == cardId && cardsManager == nil && !useRelatedCardsManager {
                print("数量变化通知: cardId=\(cardId), newCount=\(newCount)")
                staticCommentCount = newCount
            }
        }
    }
    
    private var displayCommentCount: Int {
        if let cardsManager = cardsManager {
            return cardsManager.getCommentCount(for: cardId)
        } else if useRelatedCardsManager {
            return relatedCardsManager.getCommentCount(for: cardId)
        } else {
            return staticCommentCount
        }
    }
}

#Preview {
    CommentPopupView()
} 
