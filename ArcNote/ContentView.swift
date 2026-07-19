//
//  ContentView.swift
//  ArcNote
//
//  Created by 海了个螺 on 2025/7/23.
//

import SwiftUI
import GoogleSignIn
import Combine
import AuthenticationServices

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSignUp = false
    @State private var showSignIn = false
    @StateObject private var authManager = AuthManager.shared
    @State private var cancellables = Set<AnyCancellable>()
    @State private var appleSignInDelegate: AppleSignInDelegate?
    @State private var showUnauthorizedAlert = false
    @State private var showChooseInterests = false
    
    var body: some View {
        NavigationStack {
            // 根据登录状态显示不同视图
            if authManager.isAuthenticated {
                if showChooseInterests {
                    ChooseInterestsView()
                } else {
                    TabBarView()
                }
            } else {
                loginView
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
    
    // 登录视图
    private var loginView: some View {
        GeometryReader { geometry in
        ZStack {
            Image("login_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            
            
            // 主要内容
                ScrollView {
            VStack(spacing: 0) {
                // 标题和标语 移到中上位置
                HStack(alignment: .center, spacing: 16) {
                    Image("logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 60)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Log in to Chorai")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("and see ideas grow.")
                            .font(.title)
                            .foregroundColor(.gray)
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
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 62)
                            .background(
                                RoundedRectangle(cornerRadius: 32)
                                    .fill(.ultraThinMaterial)
                                    // 左上角高光
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 32)
                                            .stroke(Color.white, lineWidth: 2)
                                            .offset(x: 0, y: 0)
                                            .mask(
                                                RoundedRectangle(cornerRadius: 32)
                                                    .fill(
                                                        RadialGradient(
                                                            colors: [Color.white, Color.clear],
                                                            center: .topLeading,
                                                            startRadius: 10,
                                                            endRadius: 35
                                                        )
                                                    )
                                            )
                                    )
                                    // 右下角高光
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 32)
                                            .stroke(Color.white, lineWidth: 2)
                                            .offset(x: 0, y: 0)
                                            .mask(
                                                RoundedRectangle(cornerRadius: 32)
                                                    .fill(
                                                        RadialGradient(
                                                            colors: [Color.white, Color.clear],
                                                            center: .bottomTrailing,
                                                            startRadius: 10,
                                                            endRadius: 35
                                                        )
                                                    )
                                            )
                                    )
                                // 上面边缘高光
                                .overlay(
                                    RoundedRectangle(cornerRadius: 32)
                                        .stroke(Color.white, lineWidth: 1)
                                        .offset(x: 0, y: -1)
                                        .mask(
                                            RoundedRectangle(cornerRadius: 32)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.white, Color.clear],
                                                        startPoint: .top,
                                                        endPoint: UnitPoint(x: 0, y: 0.05)
                                                    )
                                                )
                                        )
                                )
                                // 下面边缘高光
                                .overlay(
                                    RoundedRectangle(cornerRadius: 32)
                                        .stroke(Color.white, lineWidth: 1)
                                        .offset(x: -1, y: 1)
                                        .mask(
                                            RoundedRectangle(cornerRadius: 32)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.white, Color.clear],
                                                        startPoint: .bottom,
                                                        endPoint:UnitPoint(x: 1, y: 0.05)
                                                    )
                                                )
                                        )
                                )
                            )
                    }
                    .accessibilityIdentifier("welcome.login")
                    
                                            // Sign Up 按钮
                        NavigationLink(destination: SignUpView()) {
                        Text("Sign Up")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 62)
                            .background(
                                RoundedRectangle(cornerRadius: 32)
                                    .fill(Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 32)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }
                }
                .adaptiveContentGutter()
                
                // 分隔线
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray.opacity(0.3))
                    
                    Text("Or sign in with")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 16)
                    
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray.opacity(0.3))
        }
                .adaptiveContentGutter()
                .padding(.top, 32)
                
                // 社交登录图标
                SocialLoginRow(
                    googleAction: {
                        self.signInWithGoogle()
                    },
                    appleAction: {
                        signInWithApple()
                    }
                )
                .padding(.top, 24)
                .padding(.bottom, max(50, geometry.safeAreaInsets.bottom + 30))
                    }
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
        .ignoresSafeArea()
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
        authManager.googleLogin(idToken: idToken)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("后端Google登录失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { authResponse in
                    print("后端Google登录成功")
                    // 先保存用户会话
                    authManager.saveUserSession(authResponse)
                    // 根据 isNewUser 判断跳转到哪个页面
                    if authResponse.data.isNewUser == true {
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
                    // 先保存用户会话
                    authManager.saveUserSession(authResponse)
                    // 根据 isNewUser 判断跳转到哪个页面
                    if authResponse.data.isNewUser == true {
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
                        
                        let appleLoginRequest = AppleLoginRequest(
                            identityToken: identityTokenString,
                            authorizationCode: authorizationCodeString,
                            userInfo: appleUserInfo
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
            SocialLoginButton(iconName: "btn_google", action: googleAction)
            SocialLoginButton(iconName: "btn_apple", action: appleAction)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// 社交登录按钮组件
struct SocialLoginButton: View {
    let iconName: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 42, height: 42)
                .foregroundColor(.white)
//                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                )
        }
        .frame(width: 56, height: 56)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
