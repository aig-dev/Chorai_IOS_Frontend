//
//  SignInView.swift
//  ArcNote
//
//  Created by 海了个螺 on 2025/7/23.
//

import SwiftUI
import Combine
import GoogleSignIn
import AuthenticationServices

struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    
    // 添加状态变量来管理输入内容
    @State private var usernameEmail = ""
    @State private var password = ""
    
    // 登录相关状态
    @State private var isSigningIn = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showTabBar = false
    @State private var showChooseInterests = false
    
    // 认证管理器
    @StateObject private var authManager = AuthManager.shared
    @State private var cancellables = Set<AnyCancellable>()
    @State private var appleSignInDelegate: AppleSignInDelegate?
    
    
    var body: some View {
        VStack(spacing: 0) {
                // 顶部导航栏
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // 标题
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign In")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 40)
                
                // 输入字段
                VStack(spacing: 16) {
                    // Username / Email
                    InputField(icon: "person", placeholder: "Email", text: $usernameEmail, accessibilityIdentifier: "signin.email")
                    
                    // Password
                    InputField(icon: "lock", placeholder: "Password", text: $password, accessibilityIdentifier: "signin.password")
                }
                .padding(.horizontal, 24)
                .padding(.top, 50)
                
                // 忘记密码链接
                HStack {
                    Button("Forget Password?") {
                        // 忘记密码逻辑
                    }
                    .foregroundColor(.white)
                    .font(.subheadline)
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                Spacer()
                // 登录按钮
                Button(action: {
                    signIn()
                }) {
                    HStack {
                        if isSigningIn {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(isSigningIn ? "Logging..." : "SIGN IN")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
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
                                                        endPoint: UnitPoint(x: 1, y: 0.05)
                                                    )
                                                )
                                        )
                                )
                        )
                }
                .disabled(isSigningIn)
                .accessibilityIdentifier("signin.submit")
                .padding(.horizontal, 24)
                .padding(.top, 32)
                
                Spacer()
                
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
                .padding(.horizontal, 24)
                .padding(.top, 32)
                
                // 社交登录图标
                SocialLoginRow(
                    googleAction: {
                        signInWithGoogle()
                    },
                    appleAction: {
                        signInWithApple()
                    }
                )
                .padding(.top, 24)
                .padding(.bottom, 50)
        }
        .background(
            Image("login_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea(.all)
        )
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 100 && abs(value.translation.height) < 50 {
                        dismiss()
                    }
                }
        )
        .navigationDestination(isPresented: $showTabBar) {
            TabBarView()
        }
        .navigationDestination(isPresented: $showChooseInterests) {
            ChooseInterestsView()
        }
        .onTapGesture {
            // 点击空白区域关闭键盘
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .alert("Notice", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("InterestsSelectionCompleted"))) { _ in
            showChooseInterests = false
            showTabBar = true
        }
        .accessibilityIdentifier("screen.signin")
    }
    
    // MARK: - 登录功能
    private func signIn() {
        // 验证输入
//        guard !usernameEmail.isEmpty else {
//            showAlert(message: "请输入用户名或邮箱")
//            return
//        }
        
//        guard !password.isEmpty else {
//            showAlert(message: "请输入密码")
//            return
//        }
        
//        guard password.count >= 6 else {
//            showAlert(message: "密码长度至少6位")
//            return
//        }
        
        // 检测用户名格式是否为邮箱
//        if !isValidEmail(usernameEmail) {
//            showAlert(message: "请输入有效的邮箱地址")
//            return
//        }
        
        // 开始登录
        isSigningIn = true
        
        // 调用登录API
        authManager.login(email: usernameEmail, password: password)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isSigningIn = false
                    if case .failure(let error) = completion {
                        handleLoginError(error)
                    }
                },
                receiveValue: { authResponse in
                    isSigningIn = false
                // 先保存用户会话
                authManager.saveUserSession(authResponse)
                // 根据 isNewUser 判断跳转到哪个页面
                if authResponse.data.isNewUser == true {
                    showChooseInterests = true
                } else {
                        showTabBar = true
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 显示提示信息
    private func showAlert(message: String) {
        alertMessage = message
        showAlert = true
    }
    
    // MARK: 邮箱格式验证
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    // MARK: 处理登录错误
    private func handleLoginError(_ error: NetworkError) {
        switch error {
        case .serverError(let code, let message):
            switch code {
            case 400:
                showAlert(message: "Incorrect username or password")
            case 401:
                showAlert(message: "Incorrect username or password")
            case 404:
                showAlert(message: "User does not exist")
            default:
                showAlert(message: message ?? "Login failed, please try again later")
            }
        case .networkError:
            showAlert(message: "Network connection failed, please check your network settings")
        case .timeout:
            showAlert(message: "Request timeout, please try again later")
        default:
            showAlert(message: error.localizedDescription)
        }
    }
    
    // MARK: - Google登录
    private func signInWithGoogle() {
        guard let presentingViewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
            if let error = error {
                print("Google登录失败: \(error.localizedDescription)")
                return
            }
            
            guard let user = result?.user else {
                return
            }
            
            print("Google登录成功")
            print("用户ID: \(user.userID ?? "无")")
            print("用户邮箱: \(user.profile?.email ?? "无")")
            print("用户姓名: \(user.profile?.name ?? "无")")
            
            guard let idToken = user.idToken?.tokenString else {
                print("无法获取ID Token")
                return
            }
            
            DispatchQueue.main.async {
                self.handleGoogleLoginResponse(idToken: idToken)
            }
        }
    }
    
    // MARK: - 处理Google登录响应
    private func handleGoogleLoginResponse(idToken: String) {
        authManager.googleLogin(idToken: idToken)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("后端Google登录失败: \(error.localizedDescription)")
                        showAlert(message: "Google sign in failed, please try again")
                    }
                },
                receiveValue: { authResponse in
                    print("后端Google登录成功")
                    let user = authResponse.data.user
                    print("用户信息: \(user.username) - \(user.email), isNewUser: \(String(describing: authResponse.data.isNewUser))")
                    // 保存用户会话
                    authManager.saveUserSession(authResponse)
                    // 根据 isNewUser
                    if authResponse.data.isNewUser == true {
                        showChooseInterests = true
                    } else {
                        showTabBar = true
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: Apple登录
    private func signInWithApple() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        
        appleSignInDelegate = AppleSignInDelegate { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let authorization):
                    print("Apple授权成功")
                    if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                        print("Apple登录成功")
                        print("用户ID: \(appleIDCredential.user)")
                        print("邮箱: \(appleIDCredential.email ?? "无")")
                        print("全名: \(appleIDCredential.fullName?.description ?? "无")")
                        
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
                        
                        self.handleAppleLoginResponse(request: appleLoginRequest)
                    } else {
                        print("无法获取Apple ID凭证")
                    }
                case .failure(let error):
                    print("Apple登录失败: \(error.localizedDescription)")
                    showAlert(message: "Apple sign in failed, please try again")
                }
            }
        }
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = appleSignInDelegate
        authorizationController.performRequests()
    }
    
    // MARK: 处理Apple登录响应
    private func handleAppleLoginResponse(request: AppleLoginRequest) {
        authManager.appleLogin(request: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("后端Apple登录失败: \(error.localizedDescription)")
                        showAlert(message: "Apple sign in failed, please try again")
                    }
                },
                receiveValue: { authResponse in
                    print("后端Apple登录成功")
                    let user = authResponse.data.user
                    print("用户信息: \(user.username) - \(user.email), isNewUser: \(String(describing: authResponse.data.isNewUser))")
                    // 存用户会话
                    authManager.saveUserSession(authResponse)
                    // 根据 isNewUser 判断跳转到哪个页面
                    if authResponse.data.isNewUser == true {
                        showChooseInterests = true
                    } else {
                        showTabBar = true
                    }
                }
            )
            .store(in: &cancellables)
    }
}

struct SignInView_Previews: PreviewProvider {
    static var previews: some View {
        SignInView()
    }
} 
