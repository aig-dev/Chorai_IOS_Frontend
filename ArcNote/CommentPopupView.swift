import SwiftUI
import Combine

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
    var onCommentCreated: ((Int) -> Void)?
    
    static let shared = CommentPopupManager()
    private var commentManager = CommentManager()
    private var currentCardId: Int?
    
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
    
    func show(for cardId: Int) {
        currentCardId = cardId
        isShowing = true
        commentManager.loadComments(for: cardId, refresh: true)
    }
    
    func addComment(_ content: String, isPrivate: Bool = false) {
        guard let cardId = currentCardId else { return }
        
        let visibility = isPrivate ? "private" : "public"
        commentManager.createComment(
            for: cardId,
            content: content,
            visibility: visibility
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let comment):
                    print("评论发布成功: \(comment.content)")
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
    
    func toggleCommentLike(commentId: Int) {
        commentManager.toggleCommentLike(commentId: commentId) { result in
            switch result {
            case .success(let data):
                print("评论点赞成功: commentId=\(commentId), action=\(data.action)")
            case .failure(let error):
                print("评论点赞失败: \(error.localizedDescription)")
            }
        }
    }
    
    func createReply(for commentId: Int, content: String, visibility: String = "public") {
        commentManager.createReply(for: commentId, content: content, visibility: visibility) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let reply):
                    print("回复创建成功: commentId=\(commentId), replyId=\(reply.id)")
                case .failure(let error):
                    print("回复创建失败: \(error.localizedDescription)")
                    
                    // 检查是否是未授权错误
                    if case .unauthorized = error {
                        self.hide()
                        // 发送通知返回首页
                        NotificationCenter.default.post(
                            name: NSNotification.Name("UnauthorizedError"),
                            object: nil
                        )
                    } else {
                        self.errorMessage = "Failed to post reply: \(error.localizedDescription)"
                        self.showErrorAlert = true
                    }
                }
            }
        }
    }
    
    func enterReplyMode(commentId: Int, username: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("EnterReplyMode"),
            object: nil,
            userInfo: ["commentId": commentId, "username": username]
        )
    }
    
    func deleteComment(commentId: Int) {
        commentManager.deleteComment(commentId: commentId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("评论删除成功: commentId=\(commentId)")
                case .failure(let error):
                    print("评论删除失败: \(error.localizedDescription)")
                    
                    if case .unauthorized = error {
                        self.hide()
                        NotificationCenter.default.post(
                            name: NSNotification.Name("UnauthorizedError"),
                            object: nil
                        )
                    } else {
                        self.errorMessage = "Failed to delete comment: \(error.localizedDescription)"
                        self.showErrorAlert = true
                    }
                }
            }
        }
    }
    
    func deleteReply(replyId: Int) {
        commentManager.deleteReply(replyId: replyId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("回复删除成功: replyId=\(replyId)")
                case .failure(let error):
                    print("回复删除失败: \(error.localizedDescription)")
                    
                    if case .unauthorized = error {
                        self.hide()
                        NotificationCenter.default.post(
                            name: NSNotification.Name("UnauthorizedError"),
                            object: nil
                        )
                    } else {
                        self.errorMessage = "Failed to delete reply: \(error.localizedDescription)"
                        self.showErrorAlert = true
                    }
                }
            }
        }
    }
    
    // MARK: - 移除评论（用于拉黑后移除）
    func removeComment(commentId: Int) {
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
                            content: updatedComment.content,
                            visibility: updatedComment.visibility,
                            likeCount: updatedComment.likeCount,
                            replyCount: updatedComment.replies.count,
                            isLiked: updatedComment.isLiked,
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
    @State private var isPrivateMode = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var slideOffset: CGFloat = UIScreen.main.bounds.height
    @FocusState private var isTextFieldFocused: Bool
    
    // 回复模式状态
    @State private var isReplyMode = false
    @State private var replyToCommentId: Int? = nil
    @State private var replyToUsername: String = ""
    
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
                    VStack(spacing: 0) {
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
                        .padding(.horizontal, 20)
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
                                .padding(.horizontal, 20)
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
                        
                        // 回复模式提示
//                        if isReplyMode {
//                            HStack {
//                                Text("回复 \(replyToUsername)")
//                                    .font(.system(size: 14, weight: .medium))
//                                    .foregroundColor(.white.opacity(0.8))
//                                
//                                Spacer()
//                                
//                                Button(action: {
//                                    exitReplyMode()
//                                }) {
//                                    Image(systemName: "xmark.circle.fill")
//                                        .font(.system(size: 16))
//                                        .foregroundColor(.white.opacity(0.6))
//                                }
//                            }
//                            .padding(.horizontal, 20)
//                            .padding(.bottom, 8)
//                        }
                        
                        // 评论输入框
                        HStack(spacing: 12) {
                            Button(action: {
                                isPrivateMode.toggle()
                            }) {
                                Image(isPrivateMode ? "secret_active" : "secret")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 30, height: 30)
                            }
                            
                            HStack(spacing: 12){
                                TextField(isReplyMode ? "Replay \(replyToUsername)..." : "Add Comment", text: $commentText)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .foregroundColor(.white)
                                    .padding(.vertical, 12)
                                    .placeholder(when: commentText.isEmpty) {
                                        Text(isReplyMode ? "Replay \(replyToUsername)..." : "Add Comment")
                                            .foregroundColor(Color(red: 0.627, green: 0.627, blue: 0.627)) // A0A0A0
                                    }
                                    .focused($isTextFieldFocused)
                                    .onTapGesture {
                                        // 防止系统自动滚动
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            isTextFieldFocused = true
                                        }
                                    }
                                
                                Button(action: {
                                    if !commentText.isEmpty {
                                        if isReplyMode {
                                            // 发送回复
                                            if let commentId = replyToCommentId {
                                                manager.createReply(for: commentId, content: commentText, visibility: isPrivateMode ? "private" : "public")
                                            }
                                        } else {
                                            // 发送评论
                                            manager.addComment(commentText, isPrivate: isPrivateMode)
                                        }
                                        
                                        // 重置状态
                                        commentText = ""
                                        isPrivateMode = false
                                        isTextFieldFocused = false
                                        exitReplyMode()
                                    }
                                }) {
                                    Image("send")
                                        .resizable()
                                        .frame(width: 40,height: 40)
                                }
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
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                        .frame(height: 80) // 固定输入框区域高度
//                        .background(Color.white.opacity(0.1))
                    }
                    .frame(maxWidth: geometry.size.width, maxHeight: UIScreen.main.bounds.height * 0.6)
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
                    .position(x: geometry.size.width / 2, y: geometry.size.height - (UIScreen.main.bounds.height * 0.6) / 2 - keyboardHeight + geometry.safeAreaInsets.bottom)
                    .offset(y: slideOffset)
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                            keyboardHeight = keyboardFrame.height - 20
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                        keyboardHeight = 0
                    }
                }
                
                .animation(.easeInOut(duration: 0.4), value: slideOffset)
                .animation(.easeInOut(duration: 0.3), value: keyboardHeight)
                .onChange(of: manager.isShowing) { isShowing in
                    if isShowing {
                        // 显示时，先设置到底部，然后动画到顶部
                        slideOffset = UIScreen.main.bounds.height
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                slideOffset = 0
                            }
                        }
                    } else {
                        // 隐藏时，动画到底部
                        withAnimation(.easeInOut(duration: 0.4)) {
                            slideOffset = UIScreen.main.bounds.height
                        }
                    }
                }
                .onAppear {
                    slideOffset = manager.isShowing ? 0 : UIScreen.main.bounds.height
                }
                .onChange(of: manager.isShowing) { isShowing in
                    if !isShowing {
                        // 关闭弹窗时退出回复模式
                        exitReplyMode()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EnterReplyMode"))) { notification in
                    if let userInfo = notification.userInfo,
                       let commentId = userInfo["commentId"] as? Int,
                       let username = userInfo["username"] as? String {
                        enterReplyMode(commentId: commentId, username: username)
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
    
    // MARK: 回复模式管理
    private func enterReplyMode(commentId: Int, username: String) {
        isReplyMode = true
        replyToCommentId = commentId
        replyToUsername = username
        isTextFieldFocused = true
    }
    
    private func exitReplyMode() {
        isReplyMode = false
        replyToCommentId = nil
        replyToUsername = ""
        isTextFieldFocused = false
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
                        Text(comment.user.username)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // 删除按钮（只对当前用户的评论显示）或三个点按钮（对非当前用户的评论显示）
                        if isCurrentUserComment {
                            Button(action: {
                                if isSubComment {
                                    // 子评论（回复）使用 deleteReply
                                    CommentPopupManager.shared.deleteReply(replyId: comment.id)
                                } else {
                                    // 主评论使用 deleteComment
                                    CommentPopupManager.shared.deleteComment(commentId: comment.id)
                                }
                            }) {
                                Image("menu_remove")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        } else {
                            // 非当前用户的评论显示三个点按钮
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
                    
                    HStack(spacing: 4) {
                        if comment.visibility == "private" {
                            Image("secret_active")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                        }
                        Text(formatDate(comment.createdAt))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    // 点赞和回复
                    HStack(spacing: 16) {
                        Button(action: {
                            CommentPopupManager.shared.toggleCommentLike(commentId: comment.id)
                        }) {
                            HStack(spacing: 4) {
                                Image(comment.isLiked ? "like_active" : "like")
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text("\(comment.likeCount)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        
                        Button(action: {
                            // 进入回复模式
                            CommentPopupManager.shared.enterReplyMode(commentId: comment.id, username: comment.user.username)
                        }) {
                            HStack(spacing: 4) {
                                Image("comment")
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text("\(comment.replyCount ?? 0)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
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
            WebViewPage(url: URL(string: "https://www.chorai.app/report")!, title: "Help & Report")
        }
    }
    
    // MARK: - 拉黑用户
    private func blockUser() {
        guard let currentUserId = AuthManager.shared.currentUser?.id else {
            return
        }
        
        
        NetworkManager.shared.blockUser(userId: currentUserId, blockedId: comment.user.id)
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
    let cardId: Int
    let cardsManager: RecommendedCardsManager?
    let useRelatedCardsManager: Bool
    @State private var staticCommentCount: Int = 0
    
    init(cardId: Int, cardsManager: RecommendedCardsManager) {
        self.cardId = cardId
        self.cardsManager = cardsManager
        self.useRelatedCardsManager = false
        self.staticCommentCount = 0
    }
    
    init(cardId: Int, relatedCardsManager: RelatedCardsManager) {
        self.cardId = cardId
        self.cardsManager = nil
        self.useRelatedCardsManager = true
        self.staticCommentCount = 0
    }
    
    init(cardId: Int, commentCount: Int = 0) {
        self.cardId = cardId
        self.cardsManager = nil
        self.useRelatedCardsManager = false
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
                    .frame(width: 20, height: 20)
                Text("\(displayCommentCount)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CommentCountChanged"))) { notification in
            if let userInfo = notification.userInfo,
               let updatedCardId = userInfo["cardId"] as? Int,
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
