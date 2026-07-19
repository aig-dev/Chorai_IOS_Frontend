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
    @State private var navigateToEditProfile = false
    @State private var navigateToChoraProfile = false
    @State private var navigateToInvitationCredits = false
    @ObservedObject private var userProfileManager = UserProfileManager.shared
    @ObservedObject private var authManager = AuthManager.shared
    @State private var cancellables = Set<AnyCancellable>()
    @State private var isLoggingOut = false
    @State private var logoutError: String?
    private let loadsProfileOnAppear: Bool
    private let choraProfileDestination: (() -> AnyView)?
    private let invitationCreditDestination: (() -> AnyView)?

    init(
        loadsProfileOnAppear: Bool = true,
        choraProfileDestination: (() -> AnyView)? = nil,
        invitationCreditDestination: (() -> AnyView)? = nil
    ) {
        self.loadsProfileOnAppear = loadsProfileOnAppear
        self.choraProfileDestination = choraProfileDestination
        self.invitationCreditDestination = invitationCreditDestination
    }
    
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
                    
                    Text("Settings")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.clear)
                        .accessibilityHidden(true)
                }
                .adaptiveContentGutter()
                .padding(.top, 60)
                .padding(.bottom, 30)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // 设置选项列表
                        VStack(spacing: 0) {
                            SettingsRow(imageName: "personal", title: "Personal Data", accessibilityIdentifier: "settings.personal-data") {
                                navigateToEditProfile = true
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.2))

                            SettingsRow(imageName: "bot", title: "Chora Profile", accessibilityIdentifier: "settings.choraProfile") {
                                navigateToChoraProfile = true
                            }

                            Divider()
                                .background(Color.white.opacity(0.2))

                            SettingsRow(
                                imageName: "syn",
                                title: "Invitations & Credits",
                                subtitle: userProfileManager.isCreditLoading
                                    ? "Loading…"
                                    : "\(userProfileManager.regularCreditTotal.formatted()) Credits",
                                accessibilityIdentifier: "settings.invitation-credits"
                            ) {
                                navigateToInvitationCredits = true
                            }

                            Divider()
                                .background(Color.white.opacity(0.2))
                            
                            SettingsRow(imageName: "account", title: "Account & Privacy", accessibilityIdentifier: "settings.account-privacy") {
                                navigateToAccountDetails = true
                            }
                        }
                        
                        .adaptiveContentGutter()
                        
                        // 登出按钮
                        VStack(spacing: 8) {
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
                            .disabled(isLoggingOut)
                            .accessibilityIdentifier("settings.logout")

                            if let logoutError {
                                Text(logoutError)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.65))
                                    .multilineTextAlignment(.center)
                                    .accessibilityIdentifier("settings.logout.error")
                            }
                        }
                        .padding(.horizontal, 100)
                        
                        // 底部隐私声明
                        Text("Your notes stay yours. We never sell your data or run ads.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 20)
                            .accessibilityIdentifier("settings.footer")
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                Text("Settings loaded")
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("screen.settings.loaded")
                #if DEBUG
                Text(loadsProfileOnAppear ? "enabled" : "disabled")
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("settings.profile.autoload")
                #endif
            }
        }
        .alert("Log Out", isPresented: $showLogoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                performLogout()
            }
        } message: {
            Text("Are you sure you want to log out?")
        }
        .navigationDestination(isPresented: $navigateToAccountDetails) {
            AccountPrivacyView()
        }
        .navigationDestination(isPresented: $navigateToEditProfile) {
            EditProfileView()
        }
        .navigationDestination(isPresented: $navigateToChoraProfile) {
            if let choraProfileDestination {
                choraProfileDestination()
            } else {
                ChoraProfileView.production(
                    humanActorID: authManager.currentUser?.id ?? ""
                )
            }
        }
        .navigationDestination(isPresented: $navigateToInvitationCredits) {
            if let invitationCreditDestination {
                invitationCreditDestination()
            } else {
                InvitationCreditView.production(
                    actorID: authManager.currentUser?.id ?? ""
                )
            }
        }
        .onAppear {
            if loadsProfileOnAppear {
                userProfileManager.fetchCurrentUserProfile()
            }
        }
    }
    
    // MARK: - 执行登出
    private func performLogout() {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        logoutError = nil

        authManager.logoutCurrentSession()
            .sink { completion in
                isLoggingOut = false
                if case .failure = completion {
                    logoutError = "Couldn’t log out. Try again."
                }
            } receiveValue: {
                // AuthManager publishes signed-out state; ContentView replaces
                // the root. Pop this destination to reveal that new root.
                DispatchQueue.main.async {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .store(in: &cancellables)
    }
}

struct SettingsRow: View {
    let imageName: String
    let title: String
    let subtitle: String?
    let accessibilityIdentifier: String?
    let action: () -> Void
    
    init(imageName: String, title: String, subtitle: String? = nil, accessibilityIdentifier: String? = nil, action: @escaping () -> Void) {
        self.imageName = imageName
        self.title = title
        self.subtitle = subtitle
        self.accessibilityIdentifier = accessibilityIdentifier
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
        .accessibilityIdentifier(accessibilityIdentifier ?? "settings.row.\(title)")
        .accessibilityValue(subtitle ?? "")
    }
}

struct SettingsDestinationHeader: View {
    let title: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Button(action: dismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
            }
            .accessibilityLabel("Back")
            .accessibilityIdentifier("settings.destination.back")

            Spacer()

            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .accessibilityIdentifier("settings.destination.title")

            Spacer()

            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.clear)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 30)
    }
}

struct SettingsOutlineButton: View {
    let title: String
    var foregroundColor: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(foregroundColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 30)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
} 
