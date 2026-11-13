import Combine
import CoreFlow
import SwiftUI
import UIKit

// MARK: 评论弹窗管理器
@MainActor
final class CommentPopupManager: ObservableObject {
    @Published var isShowing = false {
        didSet { if !isShowing && oldValue { clearPresentation() } }
    }
    @Published private(set) var isSubmitting = false
    @Published var showErrorAlert = false
    @Published var errorMessage = ""

    var onCommentCreated: ((String) -> Void)?
    static let shared = CommentPopupManager()
    private let reads = CommentReadStore(session: { AuthManager.shared.cardReadSession }, fetch: CommentService.loadPage)
    private var subscriptions = Set<AnyCancellable>()
    private var submissionID: UUID?
    private var pendingWrites: [UUID: String] = [:]

    var cardID: String? { reads.cardID }
    var comments: [CommentModel] { reads.comments }
    var loadedCommentCount: Int { reads.loadedCommentCount }
    var phase: CommentReadPhase { reads.phase }
    var hasFirstPage: Bool { reads.hasFirstPage }
    var canLoadMore: Bool { reads.canLoadMore }

    private init() {
        reads.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        reads.$cardID.sink { [weak self] id in
            if id == nil, let self, isShowing { isShowing = false }
        }.store(in: &subscriptions)
        let center = NotificationCenter.default
        center.publisher(for: .cardReadSessionDidChange).sink { [weak self] _ in
            self?.pendingWrites.removeAll()
        }.store(in: &subscriptions)
        center.publisher(for: .cardReadInvalidated).sink { [weak self] event in
            guard let self, let id = event.object as? String else { return }
            pendingWrites = pendingWrites.filter { $0.value != id }
        }.store(in: &subscriptions)
    }

    private func clearPresentation() {
        submissionID = nil
        isSubmitting = false
        showErrorAlert = false
        errorMessage = ""
    }

    func hide() { isShowing = false }

    func show(for cardId: String) {
        clearPresentation()
        reads.open(cardId)
        isShowing = reads.cardID != nil
    }

    func addComment(
        _ content: String,
        parentCommentId: String? = nil,
        visibility: CommentVisibility = .publicComment,
        completion: ((Bool) -> Void)? = nil
    ) {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = cardID, let session = AuthManager.shared.cardReadSession,
              isShowing, !text.isEmpty, !isSubmitting else {
            completion?(false)
            return
        }
        let request = CreateCommentRequest(content: text, parentCommentId: parentCommentId, visibility: visibility)
        let submission = UUID()
        pendingWrites[submission] = id
        submissionID = submission
        isSubmitting = true
        NetworkManager.shared.createComment(cardId: id, request: request) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.pendingWrites.removeValue(forKey: submission) == id,
                      AuthManager.shared.cardReadSession == session else { return }
                let stillPresented = self.submissionID == submission && self.cardID == id && self.isShowing
                if stillPresented {
                    self.submissionID = nil
                    self.isSubmitting = false
                }

                switch result {
                case .success(let response):
                    let comment = response.data
                    guard response.success, comment.cardId == nil || comment.cardId == id else {
                        if stillPresented {
                            self.showSubmissionError()
                            completion?(false)
                        }
                        return
                    }
                    if let count = self.reads.recordCreated(comment, for: id) {
                        self.publishCount(count, for: id)
                    }
                    if stillPresented { completion?(true) }
                case .failure(let error):
                    guard stillPresented else { return }
                    // A failed reply can refer to a missing/private parent. Recheck the card's read endpoint.
                    if error.invalidatesCardRead { self.reads.refresh() }
                    if case .unauthorized = error {
                        self.hide()
                        NotificationCenter.default.post(name: NSNotification.Name("UnauthorizedError"), object: nil)
                    } else {
                        self.showSubmissionError()
                    }
                    completion?(false)
                }
            }
        }
    }

    func loadMoreComments() { reads.loadMore() }
    func refreshComments() { reads.refresh() }
    func retry() { reads.retry() }
    func comment(withID id: String) -> CommentModel? { reads.comment(withID: id) }

    private func showSubmissionError() {
        errorMessage = "Couldn't post your comment. Please try again."
        showErrorAlert = true
    }

    func removeComment(commentId: String, for cardId: String) {
        if let count = reads.removeThread(commentId, for: cardId) { publishCount(count, for: cardId) }
    }

    private func publishCount(_ count: Int, for id: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("CommentCountChanged"), object: nil,
            userInfo: ["cardId": id, "newCount": count]
        )
    }
}

// MARK: - 评论弹窗视图
struct CommentPopupView: View {
    @ObservedObject private var manager = CommentPopupManager.shared

    var body: some View {
        ChoraiNativeSheetPresenter(
            isPresented: $manager.isShowing,
            detents: [.medium(), .large()],
            initialDetent: .medium
        ) { onFocus in
            CommentSheetContent(onFocus: onFocus)
        }
            .frame(width: 0, height: 0)
    }
}

private struct CommentSheetContent: View {
    @ObservedObject private var manager = CommentPopupManager.shared
    @State private var commentText = ""
    @State private var privateSelected = false
    @State private var replyTargetID: String?
    @FocusState private var isTextFieldFocused: Bool
    let onFocus: () -> Void

    private var replyTarget: CommentModel? {
        replyTargetID.flatMap { manager.comment(withID: $0) }
    }

    var body: some View { commentSheet }

    private var commentSheet: some View {
        NavigationStack {
            commentList
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composer
                }
                .background(ChoraiTheme.background.ignoresSafeArea())
                .foregroundStyle(ChoraiTheme.ink)
                .navigationTitle("Comments")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isTextFieldFocused = false
                            manager.hide()
                        }
                        .accessibilityIdentifier("comment.close")
                    }
                }
                .overlay(alignment: .topLeading) {
                    #if DEBUG
                    Text("Comment popup")
                        .font(.system(size: 1))
                        .foregroundColor(ChoraiTheme.ink.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("comment.popup")
                    #endif
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("adaptive-layout.comment-surface")
                .alert("Error", isPresented: $manager.showErrorAlert) {
                    Button("OK") {
                        manager.showErrorAlert = false
                    }
                } message: {
                    Text(manager.errorMessage)
                }
        }
        .tint(ChoraiTheme.accent)
        .onChange(of: isTextFieldFocused) { isFocused in
            if isFocused {
                onFocus()
            }
        }
        .onChange(of: manager.cardID) { _ in
            commentText = ""
            exitReplyMode()
        }
    }

    private var commentList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 24) {
                if manager.phase == .loading && manager.comments.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading comments…")
                            .font(.subheadline)
                            .foregroundStyle(ChoraiTheme.secondaryInk)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(manager.comments) { comment in
                        CommentRowView(comment: comment) { selectedComment in
                            enterReplyMode(for: selectedComment)
                        }
                        .id(comment.id)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("comment.row.\(comment.id)")
                    }

                    if manager.hasFirstPage && manager.comments.isEmpty {
                        Text("No comments yet")
                            .font(.subheadline)
                            .foregroundStyle(ChoraiTheme.secondaryInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }

                    if manager.canLoadMore {
                        Color.clear
                            .frame(height: 1)
                            .id("comment-load-more-\(manager.loadedCommentCount)")
                            .onAppear {
                                manager.loadMoreComments()
                            }
                            .accessibilityHidden(true)
                    }

                    if manager.phase == .loadingMore {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading more…")
                                .font(.caption)
                                .foregroundStyle(ChoraiTheme.secondaryInk)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                }

                if case .failed(let page) = manager.phase {
                    VStack(spacing: 4) {
                        Text(page > 1 ? "Couldn't load more comments." : "Couldn't update comments.")
                            .font(.subheadline)
                            .foregroundStyle(ChoraiTheme.secondaryInk)
                        Button("Try again") { manager.retry() }
                            .frame(minHeight: 44)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .adaptiveContentGutter()
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            manager.refreshComments()
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(ChoraiTheme.separator)

            VStack(spacing: 4) {
                if let replyTarget {
                    HStack(spacing: 8) {
                        Text("Replying to \(replyTarget.user.displayName)")
                            .font(.caption)
                            .foregroundStyle(ChoraiTheme.secondaryInk)
                            .lineLimit(1)
                        Spacer()
                        Button(action: exitReplyMode) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel reply")
                        .accessibilityIdentifier("comment.reply.cancel")
                    }
                } else if replyTargetID != nil {
                    Text("This comment is no longer available.")
                        .font(.caption)
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                    Button("Cancel reply", action: exitReplyMode)
                        .frame(minHeight: 44)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    Button(action: {
                        guard !isReplyPrivacyLocked else { return }
                        privateSelected.toggle()
                    }) {
                        Image(systemName: isPrivateMode ? "lock.fill" : "globe")
                            .font(.body.weight(.medium))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .choraiGlassButton()
                    .disabled(isReplyPrivacyLocked)
                    .accessibilityLabel(isPrivateMode ? "Private comment" : "Public comment")
                    .accessibilityValue(isPrivateMode ? "Visible only to you and the card author" : "Visible to card readers")
                    .accessibilityHint(isReplyPrivacyLocked ? "Replies to a private thread stay private" : "Double tap to change comment privacy")
                    .accessibilityIdentifier("comment.visibility.toggle")

                    TextField(composerPlaceholder, text: $commentText, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(minHeight: 44)
                        .choraiGlassSurface(cornerRadius: 24)
                        .focused($isTextFieldFocused)
                        .accessibilityIdentifier("comment.input")

                    Button(action: submitComment) {
                        Group {
                            if manager.isSubmitting {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .foregroundStyle(ChoraiTheme.onAccent)
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .choraiGlassButton(prominent: true)
                    .accessibilityLabel("Send comment")
                    .accessibilityIdentifier("comment.send")
                    .disabled(!canSubmit)
                }
            }
            .adaptiveContentGutter()
            .padding(.vertical, 12)
        }
        .background(ChoraiTheme.background)
    }

    private var trimmedCommentText: String {
        commentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedCommentText.isEmpty && !manager.isSubmitting && (replyTargetID == nil || replyTarget != nil)
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

    private var isPrivateMode: Bool { privateSelected || isReplyPrivacyLocked }

    private func submitComment() {
        guard canSubmit else { return }
        manager.addComment(
            trimmedCommentText,
            parentCommentId: replyTargetID,
            visibility: isPrivateMode ? .privateComment : .publicComment
        ) { didSucceed in
            guard didSucceed else { return }
            commentText = ""
            replyTargetID = nil
            privateSelected = false
            isTextFieldFocused = false
        }
    }

    private func enterReplyMode(for comment: CommentModel) {
        replyTargetID = comment.id
        if comment.visibility == .privateComment {
            privateSelected = true
        }
        DispatchQueue.main.async {
            isTextFieldFocused = true
        }
    }

    private func exitReplyMode() {
        replyTargetID = nil
        privateSelected = false
        isTextFieldFocused = false
    }


}

// MARK: 评论行视图
struct CommentRowView: View {
    let comment: CommentModel
    let isSubComment: Bool
    let onReply: (CommentModel) -> Void

    @State private var showActionSheet = false
    @State private var showReport = false
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
        VStack(alignment: .leading, spacing: 12) {
            // 评论内容
            HStack(alignment: .top, spacing: 12) {
                avatarView
                    .frame(width: isSubComment ? 32 : 40, height: isSubComment ? 32 : 40)
                    .clipShape(Circle())
                    .accessibilityLabel("\(comment.user.displayName) avatar")

                VStack(alignment: .leading, spacing: 8) {
                    // 用户名和时间
                    HStack {
                        Text(comment.user.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ChoraiTheme.ink)

                        Spacer()

                        if !isCurrentUserComment {
                            Button(action: {
                                showActionSheet = true
                            }) {
                                Image(systemName: "ellipsis")
                                    .font(.body.weight(.medium))
                                    .foregroundColor(ChoraiTheme.secondaryInk)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Comment actions")
                            .accessibilityIdentifier("comment.actions.\(comment.id)")
                        }
                    }

                    // 评论内容
                    Text(comment.content)
                        .font(.body)
                        .foregroundColor(ChoraiTheme.ink)
                        .multilineTextAlignment(.leading)
                        .accessibilityIdentifier("comment.content.\(comment.id)")

                    HStack(spacing: 10) {
                        if comment.visibility == .privateComment {
                            Image(systemName: "lock.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                                .accessibilityLabel("Private comment")
                        }

                        Text(formatDate(comment.createdAt))
                            .font(.caption.weight(.regular))
                            .foregroundColor(ChoraiTheme.secondaryInk)

                        Button(action: { onReply(comment) }) {
                            Text("Reply")
                                .font(.caption.weight(.medium))
                                .foregroundColor(ChoraiTheme.secondaryInk)
                                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reply to \(comment.user.displayName)")
                        .accessibilityIdentifier("comment.reply.\(comment.id)")
                    }
                }
            }

            if !comment.replies.isEmpty {
                VStack(spacing: 16) {
                    ForEach(comment.replies) { subComment in
                        CommentRowView(comment: subComment, isSubComment: true, onReply: onReply)
                    }
                }
                .padding(.leading, 24)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(ChoraiTheme.separator)
                        .frame(width: 1)
                        .padding(.leading, 8)
                        .accessibilityHidden(true)
                }
            }
        }
        .confirmationDialog("", isPresented: $showActionSheet, titleVisibility: .hidden) {
            Button("Report content", role: .destructive) {
                showReport = true
            }
            Button("Block user", role: .destructive) {
                blockUser()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showReport) {
            ContentReportView(targetType: .comment, targetID: comment.id)
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
        guard let session = AuthManager.shared.cardReadSession,
              let id = comment.cardId ?? CommentPopupManager.shared.cardID else { return }

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
                receiveValue: { response in
                    guard response.success, AuthManager.shared.cardReadSession == session else { return }
                    CommentPopupManager.shared.removeComment(commentId: comment.id, for: id)
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
    let countFont: Font
    @State private var staticCommentCount: Int = 0

    init(cardId: String, cardsManager: RecommendedCardsManager) {
        self.cardId = cardId
        self.cardsManager = cardsManager
        self.useRelatedCardsManager = false
        self.iconSize = 20
        self.countFont = .subheadline.weight(.medium)
        self.staticCommentCount = 0
    }

    init(cardId: String, relatedCardsManager: RelatedCardsManager) {
        self.cardId = cardId
        self.cardsManager = nil
        self.useRelatedCardsManager = true
        self.iconSize = 20
        self.countFont = .subheadline.weight(.medium)
        self.staticCommentCount = 0
    }

    init(cardId: String, commentCount: Int = 0, iconSize: CGFloat = 20, countFont: Font = .subheadline.weight(.medium)) {
        self.cardId = cardId
        self.cardsManager = nil
        self.useRelatedCardsManager = false
        self.iconSize = iconSize
        self.countFont = countFont
        self.staticCommentCount = commentCount
    }

    var body: some View {
        Button(action: {
            manager.show(for: cardId)
        }) {
            HStack(spacing: 4) {
                Image(systemName: "bubble")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                Text("\(displayCommentCount)")
                    .font(countFont)
                    .foregroundColor(ChoraiTheme.ink)
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

#if DEBUG
/// Presentation-only fixture. Its ordinary network session is still intercepted
/// by LocalPreviewURLProtocol; no request can fall through to a live service.
enum CommentPresentationFixture {
    static var isEnabled: Bool {
        LocalDevelopmentPreview.isEnabled
            && ProcessInfo.processInfo.arguments.contains("--ui-test-comment-presentation")
    }

    static func comments(for cardID: String) -> [CommentModel] {
        [
            CommentModel(
                id: "fixture-comment-public", cardId: cardID,
                content: "Leaving room for an unfinished thought makes it easier to join the conversation.",
                createdAt: "2026-10-26T09:00:00Z", updatedAt: nil,
                user: CommentUser(id: "fixture-reader", username: "Mira Chen", avatarUrl: nil),
                replies: []
            ),
            CommentModel(
                id: "fixture-comment-private", cardId: cardID,
                visibility: .privateComment,
                content: "A private question for the author.",
                createdAt: "2026-10-26T10:00:00Z", updatedAt: nil,
                user: CommentUser(id: "fixture-reader-2", username: "Leo Park", avatarUrl: nil),
                replies: []
            )
        ]
    }
}

struct CommentPresentationFixtureScreen: View {
    @State private var showsSpark = false

    var body: some View {
        NavigationStack {
            DetailView(cardId: "preview-field-note")
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Open Spark fixture") { showsSpark = true }
                            .accessibilityIdentifier("comment.fixture.open-spark")
                    }
                }
                .sheet(isPresented: $showsSpark) {
                    NavigationStack {
                        SparkContinuationView.fidelityFixture()
                    }
                }
        }
        .tint(ChoraiTheme.accent)
    }
}
#endif
