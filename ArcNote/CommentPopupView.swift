import Combine
import CoreFlow
import SwiftUI

// MARK: 评论弹窗管理器
class CommentPopupManager: ObservableObject {
    @Published var isShowing = false
    @Published var comments: [CommentModel] = []
    @Published var isLoading = false
    @Published var loadedCommentCount = 0
    @Published var isSubmitting = false
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

        commentManager.$loadedCommentCount
            .assign(to: \.loadedCommentCount, on: self)
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
    
    func addComment(
        _ content: String,
        parentCommentId: String? = nil,
        visibility: CommentVisibility = .publicComment,
        completion: ((Bool) -> Void)? = nil
    ) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cardId = currentCardId, !trimmedContent.isEmpty, !isSubmitting else {
            completion?(false)
            return
        }
        isSubmitting = true
        
        commentManager.createComment(
            for: cardId,
            content: trimmedContent,
            parentCommentId: parentCommentId,
            visibility: visibility
        ) { result in
            DispatchQueue.main.async {
                self.isSubmitting = false
                switch result {
                case .success(let comment):
                    print("评论发布成功: id=\(comment.id)")
                    completion?(true)
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
                    completion?(false)
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
        commentManager.removeComment(commentId: commentId)
    }
}

// MARK: - 评论弹窗视图
struct CommentPopupView: View {
    @ObservedObject private var manager = CommentPopupManager.shared
    @State private var commentText = ""
    @State private var isPrivateMode = false
    @State private var replyTarget: CommentModel?
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
                    let sheetHeight = min(
                        max(geometry.size.height * 0.6, 280),
                        geometry.size.height
                    )
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
                                            CommentRowView(comment: comment) { selectedComment in
                                                enterReplyMode(for: selectedComment)
                                            }
                                                .id(comment.id)
                                                .accessibilityIdentifier("comment.row.\(comment.id)")
                                        }

                                        if !manager.comments.isEmpty {
                                            Color.clear
                                                .frame(height: 1)
                                                .id("comment-load-more-\(manager.loadedCommentCount)")
                                                .onAppear {
                                                    manager.loadMoreComments()
                                                }
                                                .accessibilityHidden(true)
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
                            .scrollDismissesKeyboard(.interactively)
                            .frame(maxHeight: .infinity)
                            .clipped()
                            .refreshable {
                                manager.refreshComments()
                            }
                        
                        // 评论输入框
                        VStack(spacing: 8) {
                            if let replyTarget {
                                HStack(spacing: 8) {
                                    Text("Replying to \(replyTarget.user.displayName)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.72))
                                        .lineLimit(1)
                                    Spacer()
                                    Button(action: exitReplyMode) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(.white.opacity(0.65))
                                    }
                                    .accessibilityLabel("Cancel reply")
                                    .accessibilityIdentifier("comment.reply.cancel")
                                }
                            }

                            HStack(spacing: 12) {
                                Button(action: {
                                    guard !isReplyPrivacyLocked else { return }
                                    isPrivateMode.toggle()
                                }) {
                                    Image(isPrivateMode ? "secret_active" : "secret")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 30, height: 30)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(isPrivateMode ? "Private comment" : "Public comment")
                                .accessibilityValue(isPrivateMode ? "Visible only to you and the card author" : "Visible to card readers")
                                .accessibilityHint(isReplyPrivacyLocked ? "Replies to a private thread stay private" : "Double tap to change comment privacy")
                                .accessibilityIdentifier("comment.visibility.toggle")

                                HStack(spacing: 12) {
                                    TextField(composerPlaceholder, text: $commentText)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .foregroundColor(.white)
                                        .padding(.vertical, 12)
                                        .placeholder(when: commentText.isEmpty) {
                                            Text(composerPlaceholder)
                                                .foregroundColor(Color(red: 0.627, green: 0.627, blue: 0.627))
                                        }
                                        .focused($isTextFieldFocused)
                                        .accessibilityIdentifier("comment.input")

                                    Button(action: submitComment) {
                                        Image("send")
                                            .resizable()
                                            .frame(width: 40, height: 40)
                                    }
                                    .accessibilityIdentifier("comment.send")
                                    .disabled(trimmedCommentText.isEmpty || manager.isSubmitting)
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
                        }
                        .padding(.top, 10)
                        .adaptiveContentGutter()
                        .padding(.bottom, 24)
                        .frame(minHeight: 80)
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
                        y: geometry.size.height - sheetHeight / 2
                    )
                    .offset(y: slideOffset)
                    .opacity(manager.isShowing ? 1 : 0)
                    .allowsHitTesting(manager.isShowing)
                    .animation(.easeInOut(duration: 0.4), value: slideOffset)
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
                        resetComposer()
                    }
                }
                .alert("Error", isPresented: $manager.showErrorAlert) {
                    Button("OK") {
                        manager.showErrorAlert = false
                    }
                } message: {
                    Text(manager.errorMessage)
                }
            }
//        }
    }

    private var trimmedCommentText: String {
        commentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var composerPlaceholder: String {
        guard let replyTarget else {
            return isPrivateMode ? "Add a private comment" : "Add Comment"
        }
        return "Reply to \(replyTarget.user.displayName)"
    }

    private var isReplyPrivacyLocked: Bool {
        replyTarget?.visibility == .privateComment
    }

    private func submitComment() {
        guard !trimmedCommentText.isEmpty else { return }
        manager.addComment(
            trimmedCommentText,
            parentCommentId: replyTarget?.id,
            visibility: isPrivateMode ? .privateComment : .publicComment
        ) { didSucceed in
            guard didSucceed else { return }
            commentText = ""
            replyTarget = nil
            isPrivateMode = false
            isTextFieldFocused = false
        }
    }

    private func enterReplyMode(for comment: CommentModel) {
        replyTarget = comment
        if comment.visibility == .privateComment {
            isPrivateMode = true
        }
        DispatchQueue.main.async {
            isTextFieldFocused = true
        }
    }

    private func exitReplyMode() {
        replyTarget = nil
        isPrivateMode = false
        isTextFieldFocused = false
    }

    private func resetComposer() {
        commentText = ""
        replyTarget = nil
        isPrivateMode = false
        isTextFieldFocused = false
    }
}

// MARK: 评论行视图
struct CommentRowView: View {
    let comment: CommentModel
    let isSubComment: Bool
    let onReply: (CommentModel) -> Void
    
    @State private var showActionSheet = false
    @State private var navigateToReport = false
    @State private var cancellables = Set<AnyCancellable>()
    
    init(
        comment: CommentModel,
        isSubComment: Bool = false,
        onReply: @escaping (CommentModel) -> Void = { _ in }
    ) {
        self.comment = comment
        self.isSubComment = isSubComment
        self.onReply = onReply
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
                avatarView
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .accessibilityLabel("\(comment.user.displayName) avatar")
                
                VStack(alignment: .leading, spacing: 8) {
                    // 用户名和时间
                    HStack {
                        Text(comment.user.displayName)
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
                    
                    HStack(spacing: 10) {
                        if comment.visibility == .privateComment {
                            Image("secret_active")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                                .accessibilityLabel("Private comment")
                        }

                        Text(formatDate(comment.createdAt))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))

                        Button(action: { onReply(comment) }) {
                            HStack(spacing: 4) {
                                Image("comment")
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                Text(comment.replies.isEmpty ? "Reply" : "\(comment.replies.count)")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.72))
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reply to \(comment.user.displayName)")
                        .accessibilityIdentifier("comment.reply.\(comment.id)")
                    }
                }
            }
            
            if !comment.replies.isEmpty {
                VStack(spacing: 8) {
                    ForEach(comment.replies) { subComment in
                        CommentRowView(comment: subComment, isSubComment: true, onReply: onReply)
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

    @ViewBuilder
    private var avatarView: some View {
        if let avatarURL {
            AsyncImage(url: avatarURL) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    fallbackAvatar
                }
            }
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        Image("avatar")
            .resizable()
            .aspectRatio(contentMode: .fill)
    }

    private var avatarURL: URL? {
        guard let rawValue = comment.user.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }
        return URL(string: APIConfiguration.resourceURLString(rawValue))
    }
    
    // MARK: - 拉黑用户
    private func blockUser() {
        guard AuthManager.shared.currentUser != nil else {
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
        CommentTimestamp.displayText(for: dateString)
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
