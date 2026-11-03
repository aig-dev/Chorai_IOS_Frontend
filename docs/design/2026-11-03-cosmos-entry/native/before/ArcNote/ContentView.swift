//
//  ContentView.swift
//  ArcNote
//
//  Created by 海了个螺 on 2025/7/23.
//

import SwiftUI
import GoogleSignIn
import Combine
import CoreFlow
import AuthenticationServices

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSignIn = false
    @StateObject private var authManager = AuthManager.shared
    @State private var cancellables = Set<AnyCancellable>()
    @State private var appleSignInDelegate: AppleSignInDelegate?
    @State private var showUnauthorizedAlert = false
    @State private var showChooseInterests = false
    @State private var accessKey = "ios-\(UUID().uuidString.lowercased())"
    @State private var accessKeyCode: String?
    @StateObject private var accessStore = AccessStore(
        service: NetworkAccess.shared,
        codes: KeychainStore.shared,
        hosts: ["chorai.com"]
    )

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                authenticatedView
            } else {
                NavigationStack { loginView }
            }
        }
        .onAppear {
            authManager.verifyRestoredSession()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                authManager.verifyRestoredSession(force: true)
            }
        }
        .onOpenURL { url in
            _ = accessStore.capture(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UnauthorizedError"))) { _ in
            showUnauthorizedAlert = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("InterestsSelectionCompleted"))) { _ in
            print("跳转到主页")
            showChooseInterests = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserLoggedOut"))) { _ in
            // 登出后重置状态，确保显示登录界面
            showChooseInterests = false
        }
        .alert("Authentication Error", isPresented: $showUnauthorizedAlert) {
            Button("OK") {
                // 用户点击OK后清除用户会话并返回登录页面
                authManager.invalidateLocalSession()
            }
        } message: {
            Text("401 Unauthorized - Please sign in again")
        }
        .overlay(alignment: .topLeading) {
            #if DEBUG
            Text(authManager.sessionPhase.rawValue)
                .font(.system(size: 1))
                .foregroundColor(.white.opacity(0.01))
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("auth.session.phase")
            #endif
        }
    }

    @ViewBuilder
    private var authenticatedView: some View {
        if authManager.canEnterProduct {
            if showChooseInterests {
                NavigationStack { ChooseInterestsView() }
            } else {
                TabBarView()
            }
        } else if authManager.accessState?.status == "required" {
            NavigationStack { accessGate(unavailable: false) }
        } else {
            NavigationStack { accessGate(unavailable: true) }
        }
    }

    private func accessGate(unavailable: Bool) -> some View {
        AccessGateView(
            store: accessStore,
            unavailable: unavailable,
            onAllowed: { state in
                authManager.applyAccess(state)
            },
            onSignOut: signOut
        )
    }

    // 登录视图
    private var loginView: some View {
        GeometryReader { geometry in
        ZStack {
            ChoraiBackground()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()


            // 主要内容
                ScrollView {
            VStack(spacing: 0) {
                // 标题和标语 移到中上位置
                VStack(alignment: .leading, spacing: 28) {
                    Text("chorai")
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .foregroundStyle(ChoraiTheme.accent)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Log in to Chorai")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(ChoraiTheme.ink)

                        Text("and see ideas grow.")
                            .font(.title2)
                            .foregroundColor(ChoraiTheme.secondaryInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .adaptiveContentGutter()
                        .padding(.top, max(100, geometry.safeAreaInsets.top + 60))

                        Spacer(minLength: 40)

                // 登录按钮
                VStack(spacing: 16) {
                                            // Login 按钮
                        NavigationLink(destination: SignInView()) {
                        Text("Login")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(ChoraiTheme.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 62)
                            .background(ChoraiTheme.accent, in: Capsule())
                    }
                    .accessibilityIdentifier("welcome.login")

                    // Private beta entry remains independent from registration.
                    NavigationLink(destination: PrivateBetaEntryView()) {
                        Text("Join Private Beta")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(ChoraiTheme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 62)
                            .background(
                                RoundedRectangle(cornerRadius: 32)
                                    .fill(Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 32)
                                            .stroke(ChoraiTheme.separator, lineWidth: 1)
                                    )
                            )
                    }
                    .accessibilityIdentifier("welcome.join-private-beta")
                }
                .adaptiveContentGutter()

                Text(
                    "Use Sign In for an existing email, Google, or Apple account."
                )
                .font(.caption)
                .foregroundColor(ChoraiTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .adaptiveContentGutter()
                .padding(.top, 28)
                .padding(.bottom, max(50, geometry.safeAreaInsets.bottom + 30))
                    }
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Google登录
    private func signInWithGoogle() {
        guard let presentingViewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController else {
            print("无法获取presenting view controller")
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
            if let error = error {
                print("Google登录失败: \(error.localizedDescription)")
                return
            }

            guard let user = result?.user else {
                print("无法获取Google用户信息")
                return
            }

            print("Google登录成功")

            // 调用后端Google登录接口
            guard let idToken = user.idToken?.tokenString else {
                print("无法获取ID Token")
                return
            }

            // 调用后端登录
            DispatchQueue.main.async {
                self.handleGoogleLoginResponse(idToken: idToken)
            }
        }
    }

    // MARK: 处理Google登录响应
    private func handleGoogleLoginResponse(idToken: String) {
        let pair = pendingAccessPair()
        authManager.googleLogin(
            idToken: idToken,
            accessCode: pair.code,
            idempotencyKey: pair.key
        )
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("后端Google登录失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { authResponse in
                    print("后端Google登录成功")
                    // 根据 isNewUser 判断跳转到哪个页面
                    if authResponse.data.isNewUser == true &&
                        authResponse.data.productAccess.status == "allowed" {
                    showChooseInterests = true
                    } else {
                        // 如果不是新用户，直接显示 TabBarView（ContentView 会自动处理）
                        // 因为 authManager.isAuthenticated 会变为 true
                    }
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - 处理Apple登录响应
    private func handleAppleLoginResponse(request: AppleLoginRequest) {
        authManager.appleLogin(request: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("后端Apple登录失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { authResponse in
                    print("后端Apple登录成功")
                    // 根据 isNewUser 判断跳转到哪个页面
                    if authResponse.data.isNewUser == true &&
                        authResponse.data.productAccess.status == "allowed" {
                    showChooseInterests = true
                    } else {
                        // 如果不是新用户，直接显示 TabBarView（ContentView 会自动处理）
                        // 因为 authManager.isAuthenticated 会变为 true
                    }
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - Apple登录
    private func signInWithApple() {

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        // 创建并保持代理引用
        appleSignInDelegate = AppleSignInDelegate { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let authorization):
                    print("Apple授权成功")
                    if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                        guard let identityToken = appleIDCredential.identityToken,
                              let identityTokenString = String(data: identityToken, encoding: .utf8) else {
                            print("无法获取Identity Token")
                            return
                        }

                        guard let authorizationCode = appleIDCredential.authorizationCode,
                              let authorizationCodeString = String(data: authorizationCode, encoding: .utf8) else {
                            print("无法获取Authorization Code")
                            return
                        }

                        // 构建Apple登录请求
                        let appleUserInfo = AppleUserInfo(
                            name: AppleName(
                                firstName: appleIDCredential.fullName?.givenName ?? "",
                                lastName: appleIDCredential.fullName?.familyName ?? ""
                            )
                        )

                        let pair = pendingAccessPair()
                        let appleLoginRequest = AppleLoginRequest(
                            identityToken: identityTokenString,
                            authorizationCode: authorizationCodeString,
                            userInfo: appleUserInfo,
                            accessCode: pair.code,
                            idempotencyKey: pair.key
                        )

                        // 调用后端Apple登录接口
                        self.handleAppleLoginResponse(request: appleLoginRequest)
                    } else {
                        print("无法获取Apple ID凭证")
                    }
                case .failure(let error):
                    print("Apple登录失败: \(error.localizedDescription)")
                }
            }
        }

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = appleSignInDelegate
        authorizationController.performRequests()
    }

    private func pendingAccessPair() -> (code: String?, key: String?) {
        guard let code = KeychainStore.shared.load() else {
            return (nil, nil)
        }
        if accessKeyCode != code {
            accessKeyCode = code
            accessKey = "ios-\(UUID().uuidString.lowercased())"
        }
        return (code, accessKey)
    }

    private func signOut() {
        authManager.logoutCurrentSession()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure = completion {
                        authManager.invalidateLocalSession(clearCode: true)
                    }
                },
                receiveValue: { }
            )
            .store(in: &cancellables)
    }
}


// Apple登录代理
class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let completion: (Result<ASAuthorization, Error>) -> Void

    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
        super.init()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        print("Apple授权成功回调")
        completion(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("Apple授权失败回调: \(error.localizedDescription)")
        completion(.failure(error))
    }
}


// 社交登录按钮行组件
struct SocialLoginRow: View {
    let googleAction: () -> Void
    let appleAction: () -> Void
    var spacing: CGFloat = 24

    var body: some View {
        HStack(spacing: spacing) {
            SocialLoginButton(
                iconName: "btn_google",
                accessibilityLabel: "Continue with Google",
                accessibilityIdentifier: "auth.google",
                action: googleAction
            )
            SocialLoginButton(
                iconName: "btn_apple",
                accessibilityLabel: "Continue with Apple",
                accessibilityIdentifier: "auth.apple",
                action: appleAction
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// 社交登录按钮组件
struct SocialLoginButton: View {
    let iconName: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if iconName == "btn_apple" {
                    Image(systemName: "apple.logo")
                        .font(.title2)
                        .foregroundStyle(ChoraiTheme.ink)
                } else {
                    Image(iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                }
            }
            .frame(width: 56, height: 56)
            .choraiGlassSurface(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
