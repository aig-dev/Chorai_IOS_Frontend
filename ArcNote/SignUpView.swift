//
//  SignUpView.swift
//  ArcNote
//
//  Created by 海了个螺 on 2025/7/23.
//

import SwiftUI
import Combine
import GoogleSignIn
import AuthenticationServices

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showSignIn = false
    
    // 添加状态变量来管理输入内容
    @State private var username = ""
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    
    // 验证码相关状态
    @State private var isCodeSent = false
    @State private var countdown = 0
    @State private var isSendingCode = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    // 注册相关状态
    @State private var isRegistering = false
    @State private var showSuccessAlert = false
    @State private var showChooseInterests = false
    @State private var showTabBar = false
    
    // WebView 相关状态
    @State private var showTerms = false
    @State private var showPrivacy = false
    
    // 认证管理器
    @StateObject private var authManager = AuthManager.shared
    @State private var cancellables = Set<AnyCancellable>()
    @State private var appleSignInDelegate: AppleSignInDelegate?
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                // 主要内容
                ScrollView {
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
                                Text("Sign Up")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 40)
                            
                            
                            // 输入字段
                            VStack(spacing: 16) {
                                // Username
                                InputField(icon: "person", placeholder: "Username / Email", text: $username)
                                
                                // Email
                                InputField(icon: "envelope", placeholder: "Email", text: $email)
                                
                                // Code
                                HStack(spacing: 0) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.gray)
                                            .frame(width: 20)
                                        
                                        TextField("Code", text: $code)
                                            .foregroundColor(.white)
                                            .accentColor(.white)
                                            .placeholder(when: code.isEmpty) {
                                                Text("Code")
                                                    .foregroundColor(.white.opacity(0.6))
                                            }
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 50)
                                    
                                    Rectangle()
                                        .frame(width: 1, height: 20)
                                        .foregroundColor(.gray.opacity(0.3))
                                        .padding(.horizontal, 16)
                                    
                                    Button(action: {
                                        sendVerificationCode()
                                    }) {
                                        if isSendingCode {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .progressViewStyle(CircularProgressViewStyle(tint: .teal))
                                        } else if countdown > 0 {
                                            Text("\(countdown)s")
                                                .foregroundColor(.gray)
                                        } else {
                                            Text("Get Code")
                                                .foregroundColor(.teal)
                                        }
                                    }
                                    .disabled(isSendingCode || countdown > 0 || email.isEmpty)
                                    .font(.subheadline)
                                    .padding(.trailing, 16)
                                    .frame(height: 50)
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 28) // 增加圆角使其更椭圆
                                        .fill(Color.clear) // 透明背景
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 28)
                                                .stroke(Color.white.opacity(0.3), lineWidth: 1) // 白色半透明边框
                                        )
                                )
                                
                                // Password
                                InputField(icon: "lock", placeholder: "Password", text: $password)
                                
                                // Confirm Password
                                InputField(icon: "checkmark", placeholder: "Confirm Password", text: $confirmPassword)
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 50)
                            
                            // 创建账户按钮
                            Button(action: {
                                createAccount()
                            }) {
                                HStack {
                                    if isRegistering {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    }
                                    Text(isRegistering ? "Create..." : "CREATE ACCOUNT")
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
                            .disabled(isRegistering)
                            .padding(.horizontal, 24)
                            .padding(.top, 32)
                            
                            // 用户协议提示
                            VStack(spacing: 4) {
                                Text("By continuing, you agree to our")
                                    .foregroundColor(.gray)
                                +
                                Text(" [User Agreement](arcnote://terms) ")
                                    .foregroundColor(.white)
                                    .fontWeight(.medium)
                                    .underline()
                                +
                                Text("and acknowledge that you understand the")
                                    .foregroundColor(.gray)
                                +
                                Text(" [Privacy Policy](arcnote://privacy) ")
                                    .foregroundColor(.white)
                                    .fontWeight(.medium)
                                    .underline()
                            }
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                            .fixedSize(horizontal: false, vertical: true)
                            .tint(.white)
                            .onOpenURL { url in
                                if url.scheme == "arcnote" {
                                    switch url.host {
                                    case "terms":
                                        print("打开 Terms")
                                        showTerms = true
                                    case "privacy":
                                        print("打开 Privacy")
                                        showPrivacy = true
                                    default:
                                        print("\(url.host ?? "nil")")
                                    }
                                }
                            }
                    
                            // 已有账户链接
                            HStack {
                                Text("Already have an account? ")
                                    .foregroundColor(.gray)
                                + Text("Sign In")
                                    .foregroundColor(.white)
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                            .padding(.top, 16)
                            .onTapGesture {
                                showSignIn = true
                            }
                            
                            Spacer(minLength: 20)
                            
                            // 分隔线
                            HStack {
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(.gray.opacity(0.3))
                                
                                Text("Or sign up with")
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
                            HStack(spacing: 20) {
                                SocialLoginButton(iconName: "btn_google", action: {
                                    signInWithGoogle()
                                })
                                
                                SocialLoginButton(iconName: "btn_apple", action: {
                                    signInWithApple()
                                })
                                
                                SocialLoginButton(iconName: "btn_facebook", action: {
                                    // Facebook 登录
                                })
                                
                                SocialLoginButton(iconName: "btn_x", action: {
                                    // Twitter 登录
                                })
                            }
                            .padding(.top, 24)
                            .padding(.bottom, max(50, geometry.safeAreaInsets.bottom + 30))
                        }
                        .frame(minHeight: geometry.size.height)
                    }
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
        .navigationDestination(isPresented: $showSignIn) {
            SignInView()
        }
        .navigationDestination(isPresented: $showChooseInterests) {
            ChooseInterestsView()
        }
        .navigationDestination(isPresented: $showTabBar) {
            TabBarView()
        }
        .navigationDestination(isPresented: $showTerms) {
            WebViewPage(
                url: URL(string: "https://chorai.app/terms")!,
                title: "Terms of Service"
            )
        }
        .navigationDestination(isPresented: $showPrivacy) {
            WebViewPage(
                url: URL(string: "https://chorai.app/privacy")!,
                title: "Privacy Policy"
            )
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
        .alert("Registration Successful", isPresented: $showSuccessAlert) {
            Button("OK") {
                // 这个弹窗现在不会显示，因为直接跳转到兴趣选择页面
            }
        } message: {
            Text("Congratulations! Your account has been successfully created. You can now start using ArcNote.")
        }
        }
    }
    
    // MARK: - 发送验证码
    private func sendVerificationCode() {
        guard !email.isEmpty else {
            showAlert(message: "Please enter email address")
            return
        }
        
        guard isValidEmail(email) else {
            showAlert(message: "Please enter a valid email address")
            return
        }
        
        isSendingCode = true
        
        authManager.sendVerificationCode(email: email)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isSendingCode = false
                    if case .failure(let error) = completion {
                        showAlert(message: error.localizedDescription)
                    }
                },
                receiveValue: { response in
                    if response.success {
                        isCodeSent = true
                        startCountdown()
                        showAlert(message: response.message ?? "Verification code has been sent to your email")
                    } else {
                        showAlert(message: response.message ?? "Failed to send, please try again")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - 创建账户
    private func createAccount() {
        // 验证输入
//        guard !username.isEmpty else {
//            showAlert(message: "请输入用户名或邮箱")
//            return
//        }
        
        // 检测用户名格式是否为邮箱（与 SignInView 一致）
//        if !isValidEmail(username) {
//            showAlert(message: "请输入有效的邮箱地址")
//            return
//        }
        
//        guard !email.isEmpty else {
//            showAlert(message: "请输入邮箱地址")
//            return
//        }
        
//        guard isValidEmail(email) else {
//            showAlert(message: "请输入有效的邮箱地址")
//            return
//        }
        
//        guard !code.isEmpty else {
//            showAlert(message: "请输入验证码")
//            return
//        }
//        
//        guard code.count == 6 else {
//            showAlert(message: "验证码应为6位数字")
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
        
//        guard password.count <= 20 else {
//            showAlert(message: "密码长度不能超过20位")
//            return
//        }
        
//        guard password == confirmPassword else {
//            showAlert(message: "两次输入的密码不一致")
//            return
//        }
        
        // 检查密码强度
//        guard isStrongPassword(password) else {
//            showAlert(message: "密码应包含字母和数字")
//            return
//        }
        
        // 开始注册
        isRegistering = true
        
        // 调用注册API
        authManager.register(
            username: username,
            email: email,
            password: password,
            verificationCode: code
        )
        .sink(
            receiveCompletion: { completion in
                isRegistering = false
                if case .failure(let error) = completion {
                    handleRegistrationError(error)
                }
            },
            receiveValue: { authResponse in
                isRegistering = false
                // 先保存用户会话
                authManager.saveUserSession(authResponse)
                // 根据 isNewUser 判断跳转到哪个页面
                if authResponse.data?.isNewUser == true {
                    showChooseInterests = true
                } else {
                    // 如果不是新用户，跳转到主页
                    showTabBar = true
                }
            }
        )
        .store(in: &cancellables)
    }
    
    // MARK: - 开始倒计时
    private func startCountdown() {
        countdown = 60
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdown > 0 {
                countdown -= 1
            } else {
                timer.invalidate()
            }
        }
    }
    
    // MARK: - 显示提示信息
    private func showAlert(message: String) {
        alertMessage = message
        showAlert = true
    }
    
    // MARK: 验证邮箱格式
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    // MARK: 验证密码强度
    private func isStrongPassword(_ password: String) -> Bool {
        let hasLetter = password.rangeOfCharacter(from: .letters) != nil
        let hasNumber = password.rangeOfCharacter(from: .decimalDigits) != nil
        return hasLetter && hasNumber
    }
    
    // MARK: 处理注册错误
    private func handleRegistrationError(_ error: NetworkError) {
        switch error {
        case .serverError(let code, let message):
            switch code {
            case 400:
                showAlert(message: "Invalid request parameters, please check your input")
            case 409:
                showAlert(message: "Username or email already in use, please try another one")
            case 422:
                showAlert(message: "Verification code is incorrect or expired, please get a new one")
            default:
                showAlert(message: message ?? "Registration failed, please try again later")
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
        guard let presentingViewController = UIApplication.shared.windows.first?.rootViewController else {
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
                    if let userData = authResponse.data {
                        print("用户信息: \(userData.username) - \(userData.email), isNewUser: \(userData.isNewUser)")
                    }
                    // 保存用户会话
                    authManager.saveUserSession(authResponse)
                    // 根据 isNewUser 判断跳转到哪个页面
                    if authResponse.data?.isNewUser == true {
                        showChooseInterests = true
                    } else {
                        // 如果不是新用户，跳转到主页
                        showTabBar = true
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Apple登录
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
    
    // MARK: - 处理Apple登录响应
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
                    if let userData = authResponse.data {
                        print("用户信息: \(userData.username) - \(userData.email), isNewUser: \(userData.isNewUser)")
                    }
                    // 保存用户会话
                    authManager.saveUserSession(authResponse)
                    // 根据 isNewUser 判断跳转到哪个页面
                    if authResponse.data?.isNewUser == true {
                        showChooseInterests = true
                    } else {
                        // 如果不是新用户，跳转到主页
                        showTabBar = true
                    }
                }
            )
            .store(in: &cancellables)
    }
    
}

// 输入字段组件
struct InputField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.gray)
                .frame(width: 20)
            
            TextField(placeholder, text: $text)
                .foregroundColor(.white)
                .accentColor(.white)
                .placeholder(when: text.isEmpty) {
                    Text(placeholder)
                        .foregroundColor(.white.opacity(0.6))
                }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 28) // 增加圆角使其更椭圆
                .fill(Color.clear) // 透明背景
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1) // 白色半透明边框
                )
        )
    }
}

// 扩展 View 来支持自定义 placeholder
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

struct SignUpView_Previews: PreviewProvider {
    static var previews: some View {
        SignUpView()
    }
} 
