//
//  SignUpView.swift
//  ArcNote
//
//  Created by 海了个螺 on 2025/7/23.
//

import SwiftUI
import Combine
import CoreFlow
import GoogleSignIn
import AuthenticationServices

struct SignUpInitialValues {
    let username: String
    let email: String
    let verificationCode: String
    let password: String
    let confirmPassword: String
    let invitationCode: String

    static let empty = SignUpInitialValues(
        username: "",
        email: "",
        verificationCode: "",
        password: "",
        confirmPassword: "",
        invitationCode: ""
    )
}

@MainActor
struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showSignIn = false
    
    // 添加状态变量来管理输入内容
    @State private var username = ""
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var invitationCode = ""
    
    // 验证码相关状态
    @State private var isCodeSent = false
    @State private var countdown = 0
    @State private var isSendingCode = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    // 注册相关状态
    @State private var showSuccessAlert = false
    @State private var showChooseInterests = false
    @State private var showTabBar = false
    
    // WebView 相关状态
    @State private var showTerms = false
    @State private var showPrivacy = false
    
    // 认证管理器
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var registrationStore: InvitationRegistrationStore
    @State private var cancellables = Set<AnyCancellable>()
    @State private var appleSignInDelegate: AppleSignInDelegate?

    private let navigatesAfterRegistration: Bool
    private let onRegistrationComplete:
        @MainActor (InvitationRegisteredAccount, Bool) -> Void

    init(
        registrar: any InvitationAccountRegistering =
            NetworkInvitationAccountRegistrar(),
        invitationService: any CoreInvitationCreditServing =
            NetworkInvitationCreditService(),
        invitationPersistence: any PendingInvitationCodePersisting =
            UserDefaultsPendingInvitationCodeStore(),
        initialValues: SignUpInitialValues = .empty,
        navigatesAfterRegistration: Bool = true,
        onRegistrationComplete: @escaping @MainActor (
            InvitationRegisteredAccount,
            Bool
        ) -> Void = { _, _ in }
    ) {
        _username = State(initialValue: initialValues.username)
        _email = State(initialValue: initialValues.email)
        _code = State(initialValue: initialValues.verificationCode)
        _password = State(initialValue: initialValues.password)
        _confirmPassword = State(initialValue: initialValues.confirmPassword)
        _invitationCode = State(initialValue: initialValues.invitationCode)
        _registrationStore = StateObject(
            wrappedValue: InvitationRegistrationStore(
                registrar: registrar,
                invitationService: invitationService,
                persistence: invitationPersistence
            )
        )
        self.navigatesAfterRegistration = navigatesAfterRegistration
        self.onRegistrationComplete = onRegistrationComplete
    }
    
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
                            .adaptiveContentGutter()
                            .padding(.top, 20)
                            
                            // 标题
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Sign Up")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .adaptiveContentGutter()
                            .padding(.top, 24)
                            
                            
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

                                InputField(
                                    icon: "person.2",
                                    placeholder: "Invitation Code (Optional)",
                                    text: $invitationCode,
                                    accessibilityIdentifier: "signup.invitation-code"
                                )
                            }
                            .adaptiveContentGutter()
                            .padding(.top, 24)

                            registrationFeedback
                                .adaptiveContentGutter()
                                .padding(.top, 16)
                            
                            // 创建账户按钮
                            Button(action: {
                                createAccount()
                            }) {
                                HStack {
                                    if registrationStore.isBusy {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    }
                                    Text(
                                        registrationStore.isBusy
                                            ? "Create..."
                                            : "CREATE ACCOUNT"
                                    )
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
                            .disabled(
                                registrationStore.isBusy ||
                                    registrationStore.completedAccount != nil
                            )
                            .accessibilityIdentifier("signup.create-account")
                            .adaptiveContentGutter()
                            .padding(.top, 24)
                            
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
                            .adaptiveContentGutter()
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
                            
                            Spacer(minLength: 8)
                            
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
                            .adaptiveContentGutter()
                            .padding(.top, 20)
                            
                            // 社交登录图标
                            SocialLoginRow(
                                googleAction: {
                                    signInWithGoogle()
                                },
                                appleAction: {
                                    signInWithApple()
                                }
                            )
                            .padding(.top, 16)
                            .padding(.bottom, max(32, geometry.safeAreaInsets.bottom + 20))
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
        .overlay(alignment: .topLeading) {
            InvitationCreditScreenAnchor(
                identifier: "screen.signup",
                label: "Sign Up"
            )
        }
        }
    }

    @ViewBuilder
    private var registrationFeedback: some View {
        switch registrationStore.phase {
        case .idle:
            EmptyView()
        case .validating:
            signupProgress(
                "Validating invitation code…",
                identifier: "signup.invitation.validating"
            )
        case .registering:
            signupProgress(
                "Creating account…",
                identifier: "signup.invitation.registering"
            )
        case .redeeming:
            signupProgress(
                "Redeeming invitation code…",
                identifier: "signup.invitation.redeeming"
            )
        case .failedBeforeAccount(let error):
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    InvitationCreditPresentation.message(
                        error,
                        fallback: "The account couldn’t be created."
                    )
                )
                .font(.subheadline)
                .foregroundColor(Color(red: 1, green: 0.62, blue: 0.64))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("signup.invitation.error")

                if InvitationCode.normalized(invitationCode) != nil {
                    HStack(spacing: 12) {
                        SettingsOutlineButton(title: "Retry") {
                            createAccount()
                        }
                        .accessibilityLabel("Retry invitation validation")
                        .accessibilityIdentifier(
                            "signup.invitation.retry-validation"
                        )

                        SettingsOutlineButton(title: "Remove Code") {
                            invitationCode = ""
                            registrationStore.reset()
                        }
                        .accessibilityLabel("Remove invitation code")
                        .accessibilityIdentifier(
                            "signup.invitation.remove-code"
                        )
                    }
                }
            }
        case .accountCreatedPendingRedemption(_, let error):
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "Your account was created. The invitation code still needs to be redeemed."
                )
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("signup.invitation.partial")

                Text(
                    InvitationCreditPresentation.message(
                        error,
                        fallback: "Try again when the connection is ready."
                    )
                )
                .font(.footnote)
                .foregroundColor(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    SettingsOutlineButton(title: "Retry") {
                        retryInvitationRedemption()
                    }
                    .accessibilityLabel("Retry invitation redemption")
                    .accessibilityIdentifier("signup.invitation.retry")

                    SettingsOutlineButton(title: "Continue") {
                        continueAfterPartialRegistration()
                    }
                    .accessibilityLabel("Continue with pending invitation")
                    .accessibilityIdentifier("signup.invitation.continue")
                }
            }
        case .complete:
            if !navigatesAfterRegistration {
                Text("Account created")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .accessibilityIdentifier("signup.invitation.complete")
            }
        }
    }

    private func signupProgress(
        _ text: String,
        identifier: String
    ) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(.white)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
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
        guard !registrationStore.isBusy else { return }
        let request = InvitationAccountRegistrationRequest(
            username: username,
            email: email,
            password: password,
            verificationCode: code
        )
        Task {
            await registrationStore.submit(
                request: request,
                invitationCode: invitationCode
            )
            finishRegistrationIfComplete(completedWithPendingCode: false)
        }
    }

    private func retryInvitationRedemption() {
        guard !registrationStore.isBusy else { return }
        Task {
            await registrationStore.retryRedemption()
            finishRegistrationIfComplete(completedWithPendingCode: false)
        }
    }

    private func continueAfterPartialRegistration() {
        guard !registrationStore.isBusy else { return }
        registrationStore.continueAfterPartialSuccess()
        finishRegistrationIfComplete(completedWithPendingCode: true)
    }

    private func finishRegistrationIfComplete(
        completedWithPendingCode: Bool
    ) {
        guard let account = registrationStore.completedAccount else { return }
        if !completedWithPendingCode {
            invitationCode = registrationStore.invitationCode
        }
        onRegistrationComplete(account, completedWithPendingCode)
        guard navigatesAfterRegistration else { return }
        if account.isNewUser {
            showChooseInterests = true
        } else {
            showTabBar = true
        }
    }
    
    // MARK: - 开始倒计时
    private func startCountdown() {
        countdown = 60
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            Task { @MainActor in
                if countdown > 0 {
                    countdown -= 1
                } else {
                    timer.invalidate()
                }
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
        case .api(let statusCode, _, _):
            switch statusCode {
            case 400:
                showAlert(message: "Invalid request parameters, please check your input")
            case 409:
                showAlert(message: "Username or email already in use, please try another one")
            case 422:
                showAlert(message: "Verification code is incorrect or expired, please get a new one")
            default:
                showAlert(message: "Registration failed, please try again later")
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
                    // 保存用户会话
                    authManager.saveUserSession(authResponse)
                    // 根据 isNewUser 判断跳转到哪个页面
                    if authResponse.data.isNewUser == true {
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
                    // 保存用户会话
                    authManager.saveUserSession(authResponse)
                    // 根据 isNewUser 判断跳转到哪个页面
                    if authResponse.data.isNewUser == true {
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
    let accessibilityIdentifier: String?
    @Binding var text: String

    init(icon: String, placeholder: String, text: Binding<String>, accessibilityIdentifier: String? = nil) {
        self.icon = icon
        self.placeholder = placeholder
        self._text = text
        self.accessibilityIdentifier = accessibilityIdentifier
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.gray)
                .frame(width: 20)
            
            TextField(placeholder, text: $text)
                .foregroundColor(.white)
                .accentColor(.white)
                .modifier(OptionalAccessibilityIdentifier(identifier: accessibilityIdentifier))
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

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
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
