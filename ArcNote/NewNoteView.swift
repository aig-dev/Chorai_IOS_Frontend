import SwiftUI
import MarkupEditor
import Combine

// MARK: 关联笔记数据模型
struct RelatedNote: Identifiable {
    let id = UUID()
    let avatar: String
    let title: String
    let description: String
}

struct NewNoteView: View, MarkupDelegate {
    @Environment(\.dismiss) private var dismiss
    @State private var noteText = ""
    @State private var noteHtml = ""
    @State private var isKeyboardVisible = false
    @State private var defaultTags: [String] = [] // 默认标签（从服务器加载）
    @State private var matchedTags: [String] = [] // 匹配标签（从文本中提取）
    
    // 计算属性：合并显示的标签列表
    private var displayedTags: [String] {
        return (defaultTags + matchedTags).removingDuplicates()
    }
    @State private var isRelatedNotesExpanded = true
    @State private var isPublishing = false
    @State private var showPublishAlert = false
    @State private var publishMessage = ""
    @State private var isPublic = false
    @State private var showPopupMenu = false
    @State private var currentNoteId: Int? = nil
    @State private var isLoadingNote = false
    @State private var relatedNotes: [CardLinkItem] = []
    @State private var isLoadingLinks = false
    @State private var navigateToDetail = false
    @State private var navigateToEdit = false
    @State private var selectedCardId: Int? = nil
    @State private var showDeleteConfirmation = false
    @State private var noteToDelete: CardLinkItem? = nil
    @State private var animateDeleteConfirmation = false
    @State private var updatedAt: String? = nil
    @State private var isPinned: Bool = false
    
    let cardId: Int
    
    init(cardId: Int = 0) {
        self.cardId = cardId
    }
    
    private let networkManager = NetworkManager.shared
    private let authManager = AuthManager.shared
    @State private var cancellables = Set<AnyCancellable>()
    
    private let markupConfiguration: MarkupWKWebViewConfiguration = {
        let config = MarkupWKWebViewConfiguration()
        // 配置MarkupEditor的外观和行为
//        config.markupToolbarStyle = .compact
//        config.markupColorPalette = MarkupColorPalette()
//        config.markupMenuBar = false // 隐藏默认菜单栏
//        config.markupToolbar = false // 隐藏默认工具栏
        
        return config
    }()
    
    var body: some View {
        mainContentView
            .background(backgroundView)
            .navigationBarHidden(true)
            .gesture(swipeGesture)
            .onAppear(perform: onAppearAction)
            .onDisappear(perform: onDisappearAction)
            .linkPopup()
            .popupMenu(isPresented: $showPopupMenu, layout: .grid3x3, cardData: createTempUserCard(), isOwnCard: true)
            .navigationDestination(isPresented: $navigateToDetail) {
                DetailView(cardId: selectedCardId ?? 0)
            }
            .navigationDestination(isPresented: $navigateToEdit) {
                NewNoteView(cardId: selectedCardId ?? 0)
            }
            .alert("Publish Result", isPresented: $showPublishAlert) {
                Button("OK") {
                    if publishMessage.contains("success") || publishMessage.contains("Success") {
                        dismiss()
                    }
                }
            } message: {
                Text(publishMessage)
            }
            .overlay(deleteConfirmationOverlay)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleCardPin"))) { notification in
                handleToggleCardPin(notification: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToEdit"))) { notification in
                if let cardId = notification.userInfo?["cardId"] as? Int {
                    selectedCardId = cardId
                    DispatchQueue.main.async {
                        navigateToEdit = true
                    }
                }
            }
    }
    
    // MARK: 子视图组件
    
    private var mainContentView: some View {
        VStack(spacing: 0) {
            // 顶部导航栏
            topNavigationBar
            
            // 文本输入区域
            textInputArea
            
            // 编辑模式状态信息（仅在编辑模式下显示）
            if cardId > 0 {
                editModeStatusInfo
            }
            
            // 标签显示区域
            tagsSection
            
            // 关联笔记区域
            relatedNotesSection
            
            Spacer()
            
            // 格式化工具栏
            formatToolbar
        }
    }
    
    private var backgroundView: some View {
        Image("home_bg")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .ignoresSafeArea(.all)
    }
    
    private var swipeGesture: some Gesture {
        DragGesture()
            .onEnded { value in
                // 侧滑返回手势
                if value.translation.width > 100 && abs(value.translation.height) < 50 {
                    dismiss()
                }
            }
    }
    
    private func onAppearAction() {
        // MarkupEditor初始化
        print("MarkupEditor initialized")
        
        // 设置LinkPopupManager的回调
        LinkPopupManager.shared.onCardSelected = { [self] selectedItem in
            print("选择卡片: \(selectedItem.title)")
            
            // 将选中的卡片添加到关联笔记中
            let newCardLinkItem = CardLinkItem(
                linkId: selectedItem.id,
                linkedCardId: selectedItem.id,
                title: selectedItem.title,
                content: selectedItem.description,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                author: CardLinkAuthor(
                    id: selectedItem.id,
                    userName: selectedItem.username,
                    avatar: selectedItem.avatar
                )
            )
            
            // 检查是否已存在相同的卡片，避免重复添加
            if !relatedNotes.contains(where: { $0.linkedCardId == selectedItem.id }) {
                relatedNotes.append(newCardLinkItem)
                print("已添加关联笔记: \(selectedItem.title)")
            } else {
                print("关联笔记已存在: \(selectedItem.title)")
            }
        }
        
        // 加载笔记详情和关联笔记
        if cardId > 0 {
            loadNoteDetail()
            loadRelatedNotes()
        }
    }
    
    private func onDisappearAction() {
        MarkupEditor.selectedWebView = nil
        // 退出时自动保存
        autoSaveNote()
    }
    
    private var deleteConfirmationOverlay: some View {
        Group {
            if showDeleteConfirmation {
                ZStack {
                    // 背景遮罩 带渐变动画
                    Color.black
                        .opacity(animateDeleteConfirmation ? 0.5 : 0)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                animateDeleteConfirmation = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    showDeleteConfirmation = false
                                    noteToDelete = nil
                                }
                            }
                        }
                    
                    // 对话框 带渐变动画
                    VStack(spacing: 20) {
                        // 关闭按钮
            HStack {
                            Spacer()
                Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    animateDeleteConfirmation = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        showDeleteConfirmation = false
                                        noteToDelete = nil
                                    }
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // 确认文本
                        Text("Confirm unlink this note?")
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
                                        noteToDelete = nil
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
                                if let note = noteToDelete {
                                    deleteRelatedNote(note)
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    animateDeleteConfirmation = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        showDeleteConfirmation = false
                                        noteToDelete = nil
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
    }
    
    private var topNavigationBar: some View {
            HStack {
                Button(action: {
                    if isKeyboardVisible {
                        // 键盘显示时，关闭键盘
                        // 尝试多种方式关闭键盘
                        if let webView = MarkupEditor.selectedWebView {
                            // 通过 JavaScript 让编辑器失去焦点
                            webView.evaluateJavaScript("""
                                if (document.activeElement) {
                                    document.activeElement.blur();
                                }
                                if (document.body) {
                                    document.body.focus();
                                }
                                """) { _, _ in }
                            webView.resignFirstResponder()
                        }
                        if let webView = MarkupEditor.observedWebView.selectedWebView {
                            // 通过 JavaScript 让编辑器失去焦点
                            webView.evaluateJavaScript("""
                                if (document.activeElement) {
                                    document.activeElement.blur();
                                }
                                if (document.body) {
                                    document.body.focus();
                                }
                                """) { _, _ in }
                            webView.resignFirstResponder()
                        }
                        // 全局关闭键盘
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first {
                            window.endEditing(false)
                        }
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        // 更新状态
                        DispatchQueue.main.async {
                            self.isKeyboardVisible = false
                        }
                    } else {
                        // 键盘隐藏时，返回上一页
                    dismiss()
                    }
                }) {
                    Image(systemName: isKeyboardVisible ? "checkmark" : "chevron.left")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // 隐私按钮
                Button(action: {
                toggleVisibility()
                }) {
                    Image(isPublic ? "public_icon" : "private_icon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
                
                // 菜单按钮
                Button(action: {
                    handleMenuButtonTap()
                }) {
                    if isPublishing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                .disabled(isPublishing)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 20)
    }
            
    private var textInputArea: some View {
            VStack(alignment: .leading, spacing: 16) {
                if isLoadingNote {
                    // 加载状态
                    VStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("Loading note content...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.top, 10)
                        Spacer()
                    }
                } else {
                    MarkupEditorView(markupDelegate: self, configuration: markupConfiguration, html: $noteText, placeholder: "")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 20)
                        .onTapGesture {
                            // 确保键盘显示
                            isKeyboardVisible = true
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                            isKeyboardVisible = true
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                            isKeyboardVisible = false
                    }
                        }
                }
            }
            
    private var editModeStatusInfo: some View {
        HStack(spacing: 8) {
            // 显示更新时间
            if let updatedAt = updatedAt {
                Text(formatDate(updatedAt))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
            }
            // 只有当卡片是公开状态时才显示open图标
            if isPublic {
                Image("open")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
            }
            // 只有当卡片是置顶状态时才显示pin图标
            if isPinned {
                Image("pin")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
    
    private var tagsSection: some View {
        Group {
            if !displayedTags.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                            ForEach(displayedTags, id: \.self) { tag in
                            EditTagView(tag: tag) {
                                removeTag(tag)
                            }
                        }
                        }
                        .padding(.horizontal, 1) // 添加一点内边距，避免标签贴边
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    private var relatedNotesSection: some View {
        Group {
            if !relatedNotes.isEmpty {
                VStack(spacing: 0) {
                    // 展开/收起按钮
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isRelatedNotesExpanded.toggle()
                            }
                        }) {
                            Image(systemName: isRelatedNotesExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 24, height: 24)
                        }
                    }
                    .padding(.horizontal, 16)
                    // .padding(.vertical, 8)
                    
                    // 笔记列表 固定高度，超出滚动
                    if isRelatedNotesExpanded {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(relatedNotes.enumerated()), id: \.element.id) { index, note in
                                    relatedNoteItem(note: note, index: index)
                                }
                            }
                        }
                        .frame(height: 200) // 固定高度 200
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            }
        }
    }
    
    private func relatedNoteItem(note: CardLinkItem, index: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image("avatar")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.author.userName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    HTMLTextRenderer(htmlContent: note.content, maxLines: 2)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
            
            Spacer()
            
                // 删除按钮
                Button(action: {
                    noteToDelete = note
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            .onTapGesture {
                handleRelatedNoteTap(note: note)
            }
            
            // 分割线（除了最后一个）
            if index < relatedNotes.count - 1 {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
        }
    }
    
    private var formatToolbar: some View {
        Group {
            if isKeyboardVisible {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                    FormatButton(imageName: "number", action: {
                        print("Shape button tapped")
                        insertFormattingText("#")
                    })
                    FormatButton(imageName: "bold", action: {
                        print("Bold button tapped")
                        insertBoldFormatting()
                    })
                    FormatButton(imageName: "italic", action: {
                        print("Italic button tapped")
                        insertItalicFormatting()
                    })
                    FormatButton(imageName: "at", action: {
                        print("At button tapped")
                            LinkPopupManager.shared.show(cardId: nil) // 不传递cardId，避免API调用
                    })
                    FormatButton(imageName: "list.bullet", action: {
                        print("Bullet list button tapped")
                        insertBulletList()
                    })
                    FormatButton(imageName: "list.number", action: {
                        print("Numbered list button tapped")
                        insertNumberedList()
                    })
//                    FormatButton(imageName: "photo", action: {
//                        print("Photo button tapped")
//                        insertPhotoFormatting()
//                    })
                    
                    // 隐私按钮
                    Button(action: {
                        isPublic.toggle()
                    }) {
                        Image(isPublic ? "public_icon" : "private_icon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20)
                }
                .padding(.vertical, 10)
                .background(
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .overlay(
                            Rectangle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: isKeyboardVisible)
            }
        }
    }
    
    // MARK: 提取标签方法
    private func extractTags(from text: String) {
        print("extractTags called with text: \(text)")
        
        // 从HTML内容中提取纯文本，然后查找标签
        let plainText = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        print("Plain text after HTML removal: \(plainText)")
        
        let pattern = "#([\\w\\u4e00-\\u9fff]+)"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: plainText.utf16.count)
        
        var tags: [String] = []
        if let matches = regex?.matches(in: plainText, options: [], range: range) {
            for match in matches {
                if let range = Range(match.range(at: 1), in: plainText) {
                    let tag = String(plainText[range])
                    if !tags.contains(tag) {
                        tags.append(tag)
                    }
                }
            }
        }
        
        print("Extracted matched tags: \(tags)")
        matchedTags = tags
    }
    
    // MARK: 移除标签方法
    private func removeTag(_ tag: String) {
        // 同时从默认标签和匹配标签中移除
        if let index = defaultTags.firstIndex(of: tag) {
            defaultTags.remove(at: index)
        }
        if let index = matchedTags.firstIndex(of: tag) {
            matchedTags.remove(at: index)
        }
        
        // 从HTML原文中删除对应的#标签文本
        let pattern = "#\(tag)\\b"
        noteHtml = noteHtml.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        noteText = noteHtml
        
        // 更新MarkupEditor中的内容
        if let webView = MarkupEditor.selectedWebView {
            webView.setHtml(noteHtml)
        }
    }
    
    // MARK: 插入格式化文本
    @MainActor private func insertFormattingText(_ text: String) {
        print("insertFormattingText called with: \(text)")
        // 使用MarkupEditor API插入文本
        MarkupEditor.observedWebView.selectedWebView?.insertShape()
//        MarkupEditor.observedWebView.selectedWebView?.insertText(text)
    }
    
    // MARK: 插入粗体格式化
    @MainActor private func insertBoldFormatting() {
        print("insertBoldFormatting called")
        // 插入HTML粗体标签
        MarkupEditor.observedWebView.selectedWebView?.bold()
    }
    
    // MARK: 插入无序列表
    @MainActor private func insertBulletList() {
        print("insertBulletList called")
        // 插入HTML无序列表
        MarkupEditor.observedWebView.selectedWebView?.toggleListItem(type: .UL)
    }
    
    // MARK: 插入有序列表
    @MainActor private func insertNumberedList() {
        print("insertNumberedList called")
        // 插入HTML有序列表
        MarkupEditor.observedWebView.selectedWebView?.toggleListItem(type: .OL)
    }
    
    // MARK: 插入图片格式化
    @MainActor private func insertPhotoFormatting() {
        print("insertPhotoFormatting called")
        // 使用MarkupEditor API插入图片
//        MarkupEditor.observedWebView.selectedWebView?.insertImage()
    }
    
    // MARK: 插入斜体格式化
    @MainActor private func insertItalicFormatting() {
        print("insertItalicFormatting called")
        // 插入HTML斜体标签
        MarkupEditor.observedWebView.selectedWebView?.italic()
    }
    
    // MARK: 处理菜单按钮点击
    private func handleMenuButtonTap() {
        if currentNoteId == nil {
            // 没有笔记ID
            publishNoteForMenu()
        } else {
            // 如果已有笔记ID，直接打开菜单
            print("已有笔记ID: \(currentNoteId!)")
            showPopupMenu = true
        }
    }
    
    // MARK: 为菜单发布笔记
    private func publishNoteForMenu() {
        guard let userId = authManager.currentUser?.id else {
            publishMessage = "User not logged in, cannot publish"
            showPublishAlert = true
            return
        }
        
        let content = noteHtml.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            publishMessage = "Content cannot be empty"
            showPublishAlert = true
            return
        }
        
        isPublishing = true
        
        // 从HTML内容中提取纯文本作为标题（取前50个字符）
        let plainText = content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let title = String(plainText.prefix(50))
        
        let request = CreateCardRequest(
            userId: userId,
            title: title.isEmpty ? nil : title,
            content: content,
            tags: displayedTags.isEmpty ? nil : displayedTags,
            isPublic: isPublic
        )
        
        networkManager.createCard(request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isPublishing = false
                    if case .failure(let error) = completion {
                        publishMessage = "Publish failed: \(error.localizedDescription)"
                        showPublishAlert = true
                        print("发布失败: \(error)")
                    }
                },
                receiveValue: { response in
                    print("发布成功笔记ID: \(response.data.id)")
                    publishMessage = "Publish success"
                    currentNoteId = response.data.id
                    // 发布成功后打开菜单
                    showPopupMenu = true
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - 创建UserCard
    private func createTempUserCard() -> UserCard {
        return UserCard(
            id: currentNoteId ?? 0,
            title: "New Note",
            content: noteHtml,
            contentHash: "",
            isPublic: isPublic,
            tags: displayedTags,
            createdAt: "",
            updatedAt: updatedAt ?? "",
            likeCount: 0,
            commentCount: 0,
            isLiked: false,
            isPinned: isPinned,
            pinnedAt: nil,
            isFavorited: false,
            favoriteCount: 0, rate: 0
        )
    }
    
    // MARK:  自动保存方法
    private func autoSaveNote() {
        let content = noteHtml.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            print("内容为空，跳过自动保存")
            return
        }
        
        if let noteId = currentNoteId {
            print("笔记已存在ID: \(noteId), 调用更新接口")
            updateNote()
        } else {
            print("开始自动保存笔记")
            publishNote()
        }
    }
    
    // MARK: 发布笔记方法
    private func publishNote() {
        guard let userId = authManager.currentUser?.id else {
            publishMessage = "User not logged in, cannot publish"
            showPublishAlert = true
            return
        }
        
        let content = noteHtml.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            publishMessage = "Content cannot be empty"
            showPublishAlert = true
            return
        }
        
        isPublishing = true
        
        // 从HTML内容中提取纯文本作为标题（取前50个字符）
        let plainText = content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let title = String(plainText.prefix(50))
        
        let request = CreateCardRequest(
            userId: userId,
            title: title.isEmpty ? nil : title,
            content: content,
            tags: displayedTags.isEmpty ? nil : displayedTags,
            isPublic: isPublic
        )
        
        networkManager.createCard(request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isPublishing = false
                    if case .failure(let error) = completion {
                        publishMessage = "fail: \(error.localizedDescription)"
                        showPublishAlert = true
                        print("发布失败: \(error)")
                    }
                },
                receiveValue: { response in
                    print("自动保存成功笔记ID: \(response.data.id)")
                    currentNoteId = response.data.id
                    // 自动保存不需要显示提示，直接退出
                    if !showPopupMenu {
                        dismiss()
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - 更新笔记方法
    private func updateNote() {
        guard let userId = authManager.currentUser?.id,
              let noteId = currentNoteId else {
            publishMessage = "User not logged in or note ID does not exist, cannot update"
            showPublishAlert = true
            return
        }
        
        let content = noteHtml.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            publishMessage = "Content cannot be empty"
            showPublishAlert = true
            return
        }
        
        isPublishing = true
        
        // 从HTML内容中提取纯文本作为标题（取前50个字符）
        let plainText = content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let title = String(plainText.prefix(50))
        
        let request = UpdateCardRequest(
            userId: userId,
            title: title.isEmpty ? nil : title,
            content: content,
            tags: displayedTags.isEmpty ? nil : displayedTags
        )
        
        networkManager.updateCard(cardId: noteId, request: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isPublishing = false
                    if case .failure(let error) = completion {
//                        publishMessage = "更新失败: \(error.localizedDescription)"
//                        showPublishAlert = true
                        print("更新失败: \(error)")
                    }
                },
                receiveValue: { (response: NetworkResponse<CardResponse>) in
                    if let cardResponse = response.data {
                        print("更新成功笔记ID: \(cardResponse.data.id)")
                        // 更新成功后直接退出
                        if !showPopupMenu {
                            dismiss()
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK:  加载笔记详情方法
    private func loadNoteDetail() {
        guard cardId > 0 else {
            return
        }
        
        isLoadingNote = true
        
        guard let userId = authManager.currentUser?.id else {
            publishMessage = "User not logged in, cannot load note details"
            showPublishAlert = true
            isLoadingNote = false
            return
        }
        
        networkManager.getCardDetail(cardId: cardId, userId: userId) { result in
            DispatchQueue.main.async {
                isLoadingNote = false
                
                switch result {
                case .success(let response):
                    let cardDetail = response.data
                    // 设置笔记ID
                    currentNoteId = cardDetail.id
                    
                    noteHtml = cardDetail.content
                    noteText = cardDetail.content
                    
                    isPublic = cardDetail.isPublic
                    
                    updatedAt = cardDetail.updatedAt
                    
                    isPinned = cardDetail.isPinned ?? false
                    
                    defaultTags = cardDetail.tags
                    
                    // 更新MarkupEditor内容
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if let webView = MarkupEditor.selectedWebView {
                            webView.setHtml(cardDetail.content)
                        }
                    }
                case .failure(let error):
                    publishMessage = "Failed to load note details: \(error.localizedDescription)"
                    showPublishAlert = true
                    print("加载笔记详情失败: \(error)")
                }
            }
        }
    }
    
    // MARK: 加载关联笔记
    private func loadRelatedNotes() {
        guard let userId = authManager.currentUser?.id else {
            print("用户未登录")
            return
        }
        
        isLoadingLinks = true
        print("开始加载关联笔记: cardId=\(cardId), userId=\(userId)")
        
        networkManager.getCardLinks(cardId: cardId, userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoadingLinks = false
                    if case .failure(let error) = completion {
                        print("加载关联笔记失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { response in
                    if response.success {
                        print("关联笔记加载成功")
                        let allLinks = response.data.outgoingLinks + response.data.incomingLinks
                        self.relatedNotes = allLinks
                        print("关联笔记数量: \(allLinks.count)")
                    } else {
                        print("加载关联笔记失败: \(response.message)")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 切换可见性方法
    private func toggleVisibility() {
        if let noteId = currentNoteId, noteId > 0 {
            updateCardVisibility()
        } else {
            isPublic.toggle()
        }
    }
    
    // MARK: 更新卡片可见性
    private func updateCardVisibility() {
        guard let userId = authManager.currentUser?.id,
              let noteId = currentNoteId else {
            publishMessage = "Not ID"
            showPublishAlert = true
            return
        }
        
        let newVisibility = !isPublic
        
        networkManager.updateCardVisibility(cardId: noteId, userId: userId, isPublic: newVisibility)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure = completion {
                        DispatchQueue.main.async {
                            self.isPublic = !newVisibility
                        }
                    }
                },
                receiveValue: { response in
                    DispatchQueue.main.async {
                        self.isPublic = newVisibility
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 处理关联笔记点击
    private func handleRelatedNoteTap(note: CardLinkItem) {
        guard let currentUserId = authManager.currentUser?.id else {
            print("用户未登录")
            return
        }
        
        selectedCardId = note.linkedCardId
        print("关联笔记: \(note.title ?? ""), cardId: \(note.linkedCardId)")
  
        
        // 判断卡片是否属于当前用户
        if note.author.id == currentUserId {
            navigateToDetail = false
            DispatchQueue.main.async {
                self.navigateToEdit = true
            }
        } else {
            navigateToEdit = false
            DispatchQueue.main.async {
                self.navigateToDetail = true
            }
        }
    }
    
    // MARK: 删除关联笔记
    private func removeRelatedNote(_ note: CardLinkItem) {
        
        if let index = relatedNotes.firstIndex(where: { $0.id == note.id }) {
            relatedNotes.remove(at: index)
            print("删除关联笔记: \(note.title ?? "")")
        }
    }
    
    // MARK: 日期格式化方法
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        // 尝试多种日期格式
        let dateFormats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        ]
        
        var date: Date?
        for format in dateFormats {
            formatter.dateFormat = format
            if let parsedDate = formatter.date(from: dateString) {
                date = parsedDate
                break
            }
        }
        
        if let date = date {
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
    
    // MARK: - 调用API删除关联笔记
    private func deleteRelatedNote(_ note: CardLinkItem) {
        guard let userId = authManager.currentUser?.id else {
            return
        }
        
        networkManager.deleteCardLink(cardId: cardId, linkId: note.linkedCardId, userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("删除关联笔记失败: \(error.localizedDescription)")
//                        publishMessage = " \(error.localizedDescription)"
//                        showPublishAlert = true
                        
                        removeRelatedNote(note)
                    }
                },
                receiveValue: { response in
                    removeRelatedNote(note)
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - 处理切换卡片Pin状态
    private func handleToggleCardPin(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let cardId = userInfo["cardId"] as? Int else {
            print("通知缺少必要参数")
            return
        }
        
        // 检查是否是当前卡片
        let currentCardId = self.cardId > 0 ? self.cardId : (currentNoteId ?? 0)
        guard cardId == currentCardId else {
            print("cardId(\(cardId))与当前卡片(\(currentCardId))不匹配，忽略")
            return
        }
        
        guard let userId = authManager.currentUser?.id else {
            print("用户未登录")
            return
        }
        
        print("开始切换卡片置顶状态: cardId=\(cardId), 当前状态: \(isPinned)")
        
        let previousIsPinned = isPinned
        
        isPinned.toggle()
        print("isPinned=\(isPinned)")
        
        if showPopupMenu {
            showPopupMenu = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showPopupMenu = true
            }
        }
        
        let publisher: AnyPublisher<PinResponse, NetworkError>
        
        if previousIsPinned {
            print("调用Unpin API")
            publisher = networkManager.unpinCard(cardId: cardId, userId: userId)
        } else {
            print("调用Pin API")
            publisher = networkManager.pinCard(cardId: cardId, userId: userId)
        }
        
        publisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in
                },
                receiveValue: { response in
                    if response.success {
                        print("切换卡片置顶状态成功: isPinned=\(self.isPinned)")
                    } else {
                        print("切换卡片置顶状态失败: \(response.message)")
                        // 无论成功失败都保持新状态，不恢复
                    }
                }
            )
            .store(in: &cancellables)
    }
    
}

// MARK: 格式化按钮组件
struct FormatButton: View {
    let imageName: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: imageName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NewNoteView()
}




// MARK: - 标签视图组件
struct EditTagView: View {
    let tag: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Text(tag)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.white.opacity(0.1))
                .overlay(tagHighlight)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private var tagHighlight: some View {
        RoundedRectangle(cornerRadius: 15)
            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            .mask(
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: 15
                        )
                    )
            )
    }
}

// MARK: - MarkupDelegate 实现
extension NewNoteView {
    
    func markupDidLoad(_ view: MarkupWKWebView, handler: (()->Void)?) {
        MarkupEditor.selectedWebView = view
        handler?()
    }
    
    func markupInput(_ view: MarkupWKWebView) {
        // 获取当前HTML内容并提取标签
        view.getHtml { html in
            DispatchQueue.main.async {
                if let html = html {
                    print("Content changed via markupInput: \(html)")
                    self.noteHtml = html
                    self.extractTags(from: html)
                }
            }
        }
    }
    
}

// MARK: 数组去重扩展
extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
} 
