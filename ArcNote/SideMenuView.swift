import CoreFlow
import SwiftUI

struct SideMenuView: View {
    @Binding var isPresented: Bool
    @State private var navigateToNotification = false
    @State private var navigateToTrash = false
    @State private var navigateToSettings = false
    @State private var navigateToMyProfile = false
    @State private var navigateToHelpReport = false
    @ObservedObject private var userProfileManager = UserProfileManager.shared
    @StateObject private var notificationStore = NotificationInboxStore(
        service: NetworkNotificationService()
    )
    
    // 回调函数
    var onMyNotesTapped: (() -> Void)?
    var onFavoritesTapped: (() -> Void)?
    
    var body: some View {
        ZStack {
            // 背景遮罩
            if isPresented {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isPresented = false
                        }
                    }
            }
            
                        // 侧边菜单区域 叠加背景图
            HStack {
                ZStack(alignment: .top) {
                    // 背景图片 叠加在后面，显示在头部位置
                    Image("side_bg")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: UIScreen.main.bounds.width * 0.75)
                        .clipped()
                    
                    // 内容层
                    VStack(alignment: .leading, spacing: 0) {
                        // 整体内容容器
                        VStack(alignment: .leading, spacing: 0) {
                            // 顶部空白区域（无背景色）
                            Spacer()
                                .frame(height: 150)
                            
                            // 内容区域（有背景色）
                            ZStack(alignment: .topLeading) {
                                // 背景
                                VStack(alignment: .leading, spacing: 0) {
                                    Spacer()
                                        .frame(height: 40) // 为头像预留空间
                                    
                                    // 用户资料区域（除头像外）
                                    VStack(alignment: .leading, spacing: 16) {
                                        // 用户名
                                        HStack {
                                            Text(userProfileManager.userProfile?.username ?? "Loading...")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                        
                                        // SYN 积分
                                        HStack(spacing: 8) {
                                            Image("syn").resizable().frame(width: 20, height: 20)
                                            
                                            Text(userProfileManager.isCreditLoading ? "--" : "\(userProfileManager.creditTotal)")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.yellow)
                                            
                                            Text("SYN")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(.white)
                                        }
                                        
                                        // 关注统计
                                        HStack(spacing: 20) {
                                            HStack(spacing: 4) {
                                                if userProfileManager.isLoading {
                                                    Text("--")
                                                        .font(.system(size: 16, weight: .semibold))
                                                        .foregroundColor(.white.opacity(0.7))
                                                } else {
                                                    Text("\(userProfileManager.userProfile?.followingCount ?? 0)")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(.white)
                                                }
                                                Text("following")
                                                    .font(.system(size: 14, weight: .regular))
                                                    .foregroundColor(.white.opacity(0.7))
                                            }
                                            Spacer()
                                            
                                            HStack(spacing: 4) {
                                                if userProfileManager.isLoading {
                                                    Text("--")
                                                        .font(.system(size: 16, weight: .semibold))
                                                        .foregroundColor(.white.opacity(0.7))
                                                } else {
                                                    Text("\(userProfileManager.userProfile?.followersCount ?? 0)")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(.white)
                                                }
                                                Text("followers")
                                                    .font(.system(size: 14, weight: .regular))
                                                    .foregroundColor(.white.opacity(0.7))
                                            }
                                        }
                                    }
                                    .padding(.top, 20)
                                    .padding(.bottom, 20)
                                    Image("line")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                        .clipped()
                                    // 导航菜单项
                                    VStack(spacing: 0) {
                                        SideMenuItem(imageName: "mynotes", title: "My Notes") {
                                            // 收起侧边栏并切换到My Notes
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                isPresented = false
                                            }
                                            // 延迟执行回调，确保动画完成
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                onMyNotesTapped?()
                                            }
                                        }
                                        SideMenuItem(imageName: "favorites", title: "Favorites") {
                                            // 收起侧边栏并切换到Favorites (AIList)
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                isPresented = false
                                            }
                                            // 延迟执行回调，确保动画完成
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                onFavoritesTapped?()
                                            }
                                        }
                                        SideMenuItem(
                                            imageName: "notification",
                                            title: "Notification",
                                            accessibilityIdentifier: "side-menu.notification",
                                            showsUnreadIndicator: notificationStore.unreadCount > 0
                                        ) {
                                            navigateToNotification = true
                                        }
                                        SideMenuItem(imageName: "trash", title: "Trash") {
                                            navigateToTrash = true
                                        }
                                        SideMenuItem(imageName: "settings", title: "Settings", accessibilityIdentifier: "side-menu.settings") {
                                            navigateToSettings = true
                                        }
                                        SideMenuItem(imageName: "help", title: "Help & Report") {
                                            navigateToHelpReport = true
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 0)
//                                        .fill(Color.white.opacity(0.1))
                                        .background(.ultraThinMaterial.opacity(0.9))
                                )
                                .clipShape(
                                    RoundedCorner(radius: 20, corners: [.topRight, .bottomRight])
                                )
                                
                                // 头像
                                Button(action: {
                                    navigateToMyProfile = true
                                }) {
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
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 3)
                                    )
                                }
                                .offset(y: -40) // 向上偏移，让头像中心点与内容区域上边框重叠
                                .padding(.leading, 24) // 靠左对齐，与内容区域左边距一致
                            }
                        }
                    }
                }
                .frame(width: UIScreen.main.bounds.width * 0.75)
                .ignoresSafeArea()
                .offset(x: isPresented ? 0 : -UIScreen.main.bounds.width * 0.75)
                
                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isPresented)
        .navigationDestination(isPresented: $navigateToNotification) {
            NotificationView()
        }
        .navigationDestination(isPresented: $navigateToTrash) {
            TrashView()
        }
        .navigationDestination(isPresented: $navigateToSettings) {
            SettingsView()
        }
        .navigationDestination(isPresented: $navigateToMyProfile) {
            MyProfileView()
        }
        .navigationDestination(isPresented: $navigateToHelpReport) {
            WebViewPage(url: URL(string: "https://www.chorai.app/report")!, title: "Help & Report")
        }
        .onAppear {
            // 当侧边栏出现时加载用户资料
            if isPresented {
                userProfileManager.fetchCurrentUserProfile()
                refreshNotificationIndicator()
            }
        }
        .onChange(of: isPresented) { isShowing in
            // 当侧边栏显示时加载用户资料
            if isShowing {
                userProfileManager.fetchCurrentUserProfile()
                refreshNotificationIndicator()
            }
        }
    }

    private func refreshNotificationIndicator() {
        guard let actorID = AuthManager.shared.currentUser?.id,
              !actorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        notificationStore.load(actorID: actorID)
    }
}

struct SideMenuItem: View {
    let imageName: String
    let title: String
    let accessibilityIdentifier: String?
    let showsUnreadIndicator: Bool
    let action: () -> Void

    init(
        imageName: String,
        title: String,
        accessibilityIdentifier: String? = nil,
        showsUnreadIndicator: Bool = false,
        action: @escaping () -> Void
    ) {
        self.imageName = imageName
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.showsUnreadIndicator = showsUnreadIndicator
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundColor(.white)
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                if showsUnreadIndicator {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 6, height: 6)
                        .accessibilityIdentifier("side-menu.notification.unread-dot")
                }
                
                Spacer()
            }
            .padding(.vertical, 16)
        }
        .accessibilityIdentifier(accessibilityIdentifier ?? "side-menu.item.\(title)")
    }
}

// 自定义圆角形状，支持只设置部分圆角
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}


#Preview {
    SideMenuView(isPresented: .constant(true))
}
