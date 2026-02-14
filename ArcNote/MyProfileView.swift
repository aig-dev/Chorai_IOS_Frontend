import SwiftUI
import Combine

struct MyProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPopupMenu = false
    @StateObject private var cardsManager = HomeCardsManager()
    @StateObject private var userProfileManager = UserProfileManager.shared
    
    // 菜单相关状态
    @State private var popupMenuLayout: PopupMenuLayout = .grid2x2
    @State private var currentMenuCardData: UserCard? = nil
    
    // 导航状态
    @State private var navigateToDetail = false
    @State private var navigateToEdit = false
    @State private var selectedCardId: Int? = nil
    @State private var navigateToChat = false
    @State private var conversationId: Int? = nil
    @State private var isCreatingConversation = false
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
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
                
                Text(userProfileManager.userProfile?.username ?? "My Profile")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // 占位符，保持标题居中
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.clear)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            
            // 主要内容
            ScrollView {
                VStack(spacing: 0) {
                    // 顶部间距，为头像留出空间
                    Spacer().frame(height: 30)
                    
                    // 用户资料卡片全屏宽度
                    ZStack(alignment: .topLeading) {
                        // 主卡片内容
                        VStack(spacing: 0) {
                            // 头像占位空间
                            HStack {
                                Spacer().frame(width: 60, height: 15) // 头像占位空间
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 15)
                            
                            // 用户信息区域
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    if userProfileManager.isLoading {
                                        Text("Loading...")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.7))
                                    } else {
                                        Text(userProfileManager.userProfile?.username ?? "User")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        createConversation()
                                    }) {
                                        Image("send_chat")
                                            .resizable()
                                            .frame(width: 42, height: 42)
                                    }
                                }
                                
                                // 第二行：统计数据
                                HStack(spacing: 20) {
                                    HStack(spacing: 4) {
                                        if userProfileManager.isLoading {
                                            Text("--")
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white.opacity(0.7))
                                        } else {
                                            Text("\(userProfileManager.userProfile?.followingCount ?? 0)")
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        Text("following")
                                            .font(.system(size: 17, weight: .regular))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    
                                    Spacer()
                                    HStack(spacing: 4) {
                                        if userProfileManager.isLoading {
                                            Text("--")
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white.opacity(0.7))
                                        } else {
                                            Text("\(userProfileManager.userProfile?.followersCount ?? 0)")
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        Text("followers")
                                            .font(.system(size: 17, weight: .regular))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    
                                    Spacer()
                                    HStack(spacing: 4) {
                                        if userProfileManager.isLoading {
                                            Text("--")
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white.opacity(0.7))
                                        } else {
                                            Text("\(userProfileManager.userProfile?.credit ?? 0)")
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        Text("SYN")
                                            .font(.system(size: 17, weight: .regular))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 15)
                            
                            // 笔记卡片列表 在同一个卡片内
                            VStack(spacing: 20) {
                                if cardsManager.isLoading && cardsManager.cards.isEmpty {
                                    // 加载状态
                                } else if cardsManager.cards.isEmpty {
                                    // 空状态
                                    VStack(spacing: 12) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 32))
                                            .foregroundColor(.white.opacity(0.5))
                                        Text("No notes")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .frame(height: 100)
                                } else {
                                    // 真实数据
                                    ForEach(cardsManager.cards, id: \.id) { card in
                                        UserPostCard(
                                            card: card,
                                            onShowMenu: { cardData in
                                                // 设置当前卡片数据
                                                currentMenuCardData = cardData
                                                popupMenuLayout = .grid2x2
                                                showPopupMenu = true
                                            },
                                            onCardTap: { cardId in
                                                print("cardId=\(cardId)")
                                                selectedCardId = cardId
                                                DispatchQueue.main.async {
                                                    navigateToDetail = true
                                                    print("navigateToDetail: \(navigateToDetail)")
                                                }
                                            },
                                            username: userProfileManager.userProfile?.username ?? "User",
                                            avatarUrl: userProfileManager.userProfile?.avatar,
                                            disableFavorite: true
                                        )
                                        .onAppear {
                                            print("数据: id=\(card.id), commentCount=\(card.commentCount ?? -1), likeCount=\(card.likeCount)")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .background(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                                .cornerRadius(16)
                        )
                        
                        // 头像 骑在边框线上
                        HStack {
                            Group {
                                if let avatarUrl = userProfileManager.userProfile?.avatar, !avatarUrl.isEmpty {
                                    let fullAvatarUrl = avatarUrl.hasPrefix("http://") || avatarUrl.hasPrefix("https://") 
                                        ? avatarUrl 
                                        : "https://api.zhizuo.site/\(avatarUrl.hasPrefix("/") ? String(avatarUrl.dropFirst()) : avatarUrl)"
                                  
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
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                            )
                            .offset(y: -36) // 向上偏移36，使头像中心在卡片上边框
                            
                            Spacer()
                        }
                        .padding(.leading, 20)
                        .padding(.trailing, 20)
                    }
                    .padding(.top, 30)
                }
            }
        }
        .background(
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea(.all)
        )
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .overlay(
            CommentPopupView()
        )
        .onAppear {
            // 加载当前用户资料
            userProfileManager.fetchCurrentUserProfile()
            
            if let userId = AuthManager.shared.currentUser?.id {
                cardsManager.loadUserCards(userId: userId, refresh: true)
            }
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
                print("编辑cardId=\(cardId)")
                selectedCardId = cardId
                DispatchQueue.main.async {
                    navigateToEdit = true
                }
            }
        }
        .navigationDestination(isPresented: $navigateToChat) {
            ChatDetailView(
                conversationId: conversationId ?? 0,
                contactName: userProfileManager.userProfile?.username ?? "User",
                contactStatus: "Online",
                contactAvatar: "avatar"
            )
        }
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
        .popupMenu(isPresented: $showPopupMenu, layout: popupMenuLayout, cardData: currentMenuCardData, searchType: "own")
        .linkPopup()
    }
    
    // MARK: 发起会话
    private func createConversation() {
        guard !isCreatingConversation else { return }
        
        guard let currentUserId = AuthManager.shared.currentUser?.id else {
            print("无法获取当前用户ID")
            return
        }
        
        isCreatingConversation = true
        print("开始发起会话: participantId=\(currentUserId)")
        
        let request = CreateConversationRequest(participantId: currentUserId)
        
        NetworkManager.shared.createConversation(request: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isCreatingConversation = false
                    if case .failure(let error) = completion {
                        print("发起会话失败: \(error.localizedDescription)")
                        
                        // 检查是否是未授权错误
                        if case .unauthorized = error {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("UnauthorizedError"),
                                object: nil
                            )
                        }
                    }
                },
                receiveValue: { response in
                    if response.success {
                        print("发起会话成功: conversationId=\(response.conversation.id)")
                        DispatchQueue.main.async {
                            conversationId = response.conversation.id
                            print("conversationId: \(conversationId ?? -1)")
                            
                            // 延迟一点时间确保状态更新
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                navigateToChat = true
                                print("navigateToChat: \(navigateToChat)")
                            }
                        }
                    } else {
                        print("发起会话失败: 服务器返回失败")
                    }
                }
            )
            .store(in: &cancellables)
    }
}

#Preview {
    MyProfileView()
}


