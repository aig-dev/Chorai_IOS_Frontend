import SwiftUI
import CoreFlow

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
    @State private var selectedCardId: String? = nil
    @State private var showFollowList = false
    @State private var followListKind: FollowListKind = .followers
    
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
                                }
                                
                                // 第二行：统计数据
                                HStack(spacing: 20) {
                                    Button {
                                        followListKind = .following
                                        showFollowList = true
                                    } label: {
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
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("my-profile.following-count")
                                    
                                    Spacer()
                                    Button {
                                        followListKind = .followers
                                        showFollowList = true
                                    } label: {
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
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("my-profile.followers-count")
                                    
                                    Spacer()
                                    HStack(spacing: 4) {
                                        if userProfileManager.isCreditLoading {
                                            Text("--")
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white.opacity(0.7))
                                        } else {
                                            Text("\(userProfileManager.creditTotal)")
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
                                    let fullAvatarUrl = APIConfiguration.resourceURLString(avatarUrl)
                                  
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
            
            cardsManager.loadUserCards(refresh: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToDetail"))) { notification in
            if let cardId = notification.userInfo?["cardId"] as? String {
                selectedCardId = cardId
                DispatchQueue.main.async {
                    navigateToDetail = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToEdit"))) { notification in
            if let cardId = notification.userInfo?["cardId"] as? String {
                print("编辑cardId=\(cardId)")
                selectedCardId = cardId
                DispatchQueue.main.async {
                    navigateToEdit = true
                }
            }
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
        .popupMenu(isPresented: $showPopupMenu, layout: popupMenuLayout, cardData: currentMenuCardData, isOwnCard: true)
        .sheet(isPresented: $showFollowList) {
            FollowListView(
                actorID: userProfileManager.userProfile?.id
                    ?? AuthManager.shared.currentUser?.id
                    ?? "",
                actorName: userProfileManager.userProfile?.username ?? "User",
                kind: followListKind,
                viewerActorID: AuthManager.shared.currentUser?.id ?? ""
            )
        }
        .linkPopup()
    }
}

#Preview {
    MyProfileView()
}
