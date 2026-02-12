import SwiftUI
import Combine

// MARK: - 圆角按钮高光效果
extension View {
    func roundedButtonHighlightEffect(cornerRadius: CGFloat = 20) -> some View {
        self
            .overlay(roundedButtonTopLeftHighlight(cornerRadius: cornerRadius))
            .overlay(roundedButtonBottomRightHighlight(cornerRadius: cornerRadius))
            .overlay(roundedButtonTopEdgeHighlight(cornerRadius: cornerRadius))
            .overlay(roundedButtonBottomEdgeHighlight(cornerRadius: cornerRadius))
    }
    
    private func roundedButtonTopLeftHighlight(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(Color.white.opacity(0.2), lineWidth: 2)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: cornerRadius)
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
    
    private func roundedButtonBottomRightHighlight(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(Color.white.opacity(0.2), lineWidth: 2)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: cornerRadius)
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
    
    private func roundedButtonTopEdgeHighlight(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private func roundedButtonBottomEdgeHighlight(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
            .offset(x: -1, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: cornerRadius)
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

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var showLogoutAlert = false
    @State private var navigateToAccountDetails = false
    @State private var navigateToPreferences = false
    @State private var navigateToAPIAndPlugins = false
    @State private var navigateToEditProfile = false
    @State private var navigateToUpgradePro = false
    @ObservedObject private var userProfileManager = UserProfileManager.shared
    @ObservedObject private var authManager = AuthManager.shared
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ZStack {
            // 背景图片
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶部导航栏
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("Setting")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        // 搜索功能
                    }) {
                        Image("search")
                            .resizable().frame(width: 30, height: 30)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 30)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // 用户信息卡片
//                        VStack(alignment: .leading, spacing: 16) {
//                            HStack {
//                                VStack(alignment: .leading, spacing: 4) {
//                                    HStack(spacing: 8) {
//                                        Text(userProfileManager.userProfile?.username ?? "Loading...")
//                                            .font(.system(size: 24, weight: .bold))
//                                            .foregroundColor(.white)
//                                        
//                                        Text("PRO")
//                                            .font(.system(size: 12, weight: .bold))
//                                            .foregroundColor(.black)
//                                            .padding(.horizontal, 8)
//                                            .padding(.vertical, 4)
//                                            .background(
//                                                RoundedRectangle(cornerRadius: 12)
//                                                    .fill(Color.white)
//                                            )
//                                        
//                                        
//                                        Spacer()
//                                        
////                                        Button(action: {
////                                            navigateToUpgradePro = true
////                                        }) {
////                                            HStack(spacing: 6) {
////                                                Image("pro")
////                                                    .resizable().frame(width: 20, height: 20)
////                                                
////                                                Text("AI+ Privilege")
////                                                    .font(.system(size: 14, weight: .medium))
////                                                    .foregroundColor(.white)
////                                            }
////                                            .padding(.horizontal, 8)
////                                            .padding(.vertical, 8)
////                                            .background(
////                                                RoundedRectangle(cornerRadius: 20)
////                                                    .fill(.ultraThinMaterial.opacity(0.1))
////                                                    .roundedButtonHighlightEffect()
////                                            )
////                                        }
//                                    }
//                                    
//                                    (Text("Expired by ")
//                                        .font(.system(size: 14, weight: .regular))
//                                        .foregroundColor(.gray)
//                                    +
//                                    Text("October 16, 2026")
//                                        .font(.system(size: 14, weight: .regular))
//                                        .foregroundColor(.white))
//                                }
//                            }
//                            
//                            Text("Upgrade membership to enjoy 12+exclusive features")
//                                .font(.system(size: 14, weight: .regular))
//                                .foregroundColor(.white)
//                                .padding(.trailing, 10)
//                        }
//                        .padding(20)
//                        .background(
//                            RoundedRectangle(cornerRadius: 16)
//                                .fill(Color.white.opacity(0.1))
//                                .cardHighlightEffect()
//                        )
//                        .padding(.horizontal, 20)
                        
                        // 设置选项列表
                        VStack(spacing: 0) {
                            SettingsRow(imageName: "personal", title: "Personal Data") {
                                navigateToEditProfile = true
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                            
                            SettingsRow(imageName: "account", title: "Account & Password") {
                                // 跳转到账户密码页面
                                navigateToAccountDetails = true
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                            
//                            SettingsRow(imageName: "preference", title: "Preferences") {
//                                navigateToPreferences = true
//                            }
//                            
//                            Divider()
//                                .background(Color.white.opacity(0.2))
//                            
//                            SettingsRow(imageName: "api", title: "API & Plugins") {
//                                navigateToAPIAndPlugins = true
//                            }
//                            
//                            Divider()
//                                .background(Color.white.opacity(0.2))
//                            
//                            SettingsRow(imageName: "feedback", title: "Feedback") {
//                                // 跳转到反馈页面
//                            }
//                            
//                            Divider()
//                                .background(Color.white.opacity(0.2))
                            
                            SettingsRow(imageName: "about", title: "About Us") {
                                // 跳转到关于我们页面
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                            
                            SettingsRow(imageName: "update", title: "Check for Updates", subtitle: "v4.4.1") {
                                // 检查更新
                            }
                        }
                        
                        .padding(.horizontal, 20)
                        
                        // 登出按钮
                        Button(action: {
                            showLogoutAlert = true
                        }) {
                            Text("Log Out")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    RoundedRectangle(cornerRadius: 30)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, 100)
                        
                        // 底部隐私声明
                        Text("We will never sell your data or run ads, so your subscription is our driving force to keep creating")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 20)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .alert("Log Out", isPresented: $showLogoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                performLogout()
            }
        } message: {
            Text("Are you sure you want to log out?")
        }
        .background(
            NavigationLink(destination: AccountDetailsView(), isActive: $navigateToAccountDetails) {
                EmptyView()
            }
        )
        .background(
            NavigationLink(destination: PreferencesView(), isActive: $navigateToPreferences) {
                EmptyView()
            }
        )
        .background(
            NavigationLink(destination: APIAndPluginsView(), isActive: $navigateToAPIAndPlugins) {
                EmptyView()
            }
        )
        .background(
            NavigationLink(destination: EditProfileView(), isActive: $navigateToEditProfile) {
                EmptyView()
            }
        )
        .background(
            NavigationLink(destination: UpgradeProView(), isActive: $navigateToUpgradePro) {
                EmptyView()
            }
        )
        .onAppear {
            userProfileManager.fetchCurrentUserProfile()
        }
    }
    
    // MARK: - 执行登出
    private func performLogout() {
        print("开始执行登出")
        
        // 直接调用logout方法清除本地信息
        authManager.logout()
        
        print("登出成功发送登出通知")
        // 发送登出通知，让应用重新显示登录界面
        NotificationCenter.default.post(
            name: NSNotification.Name("UserLoggedOut"),
            object: nil
        )
        
        // 关闭设置页面
        DispatchQueue.main.async {
            presentationMode.wrappedValue.dismiss()
        }
    }
}

struct SettingsRow: View {
    let imageName: String
    let title: String
    let subtitle: String?
    let action: () -> Void
    
    init(imageName: String, title: String, subtitle: String? = nil, action: @escaping () -> Void) {
        self.imageName = imageName
        self.title = title
        self.subtitle = subtitle
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
                
                Spacer()
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.gray)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 16)
        }
    }
}

#Preview {
    SettingsView()
} 
