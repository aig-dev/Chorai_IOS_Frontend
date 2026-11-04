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
    let accessCode: String

    static let empty = SignUpInitialValues(
        username: "",
        email: "",
        verificationCode: "",
        password: "",
        confirmPassword: "",
        accessCode: ""
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
    @State private var cancellables = Set<AnyCancellable>()
    @State private var appleSignInDelegate: AppleSignInDelegate?
    @State private var isRegistering = false
    @State private var accessKey = "ios-\(UUID().uuidString.lowercased())"
    @State private var accessKeyCode: String?
    private let initialAccessCode: String

    init(
        initialValues: SignUpInitialValues = .empty
    ) {
        _username = State(initialValue: initialValues.username)
        _email = State(initialValue: initialValues.email)
        _code = State(initialValue: initialValues.verificationCode)
        _password = State(initialValue: initialValues.password)
        _confirmPassword = State(initialValue: initialValues.confirmPassword)
        initialAccessCode = initialValues.accessCode
    }

    var body: some View {
            GeometryReader { geometry in
                // 主要内容
                ScrollView {
                        VStack(spacing: 0) {
                            // 输入字段
                            VStack(spacing: 16) {
                                // Username
                                InputField(
                                    icon: "person",
                                    placeholder: "Username / Email",
                                    text: $username,
                                    accessibilityIdentifier: "signup.username"
                                )

                                // Email
                                InputField(
                                    icon: "envelope",
                                    placeholder: "Email",
                                    text: $email,
                                    accessibilityIdentifier: "signup.email"
                                )

                                // Code
                                HStack(spacing: 0) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(ChoraiTheme.secondaryInk)
                                            .frame(width: 20)

                                        TextField("Code", text: $code)
                                            .textContentType(.oneTimeCode)
                                            .foregroundColor(ChoraiTheme.ink)
                                            .accentColor(ChoraiTheme.ink)
                                            .placeholder(when: code.isEmpty) {
                                                Text("Code")
                                                    .foregroundColor(ChoraiTheme.secondaryInk)
                                            }

                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 50)

                                    Rectangle()
                                        .frame(width: 1, height: 20)
                                        .foregroundColor(ChoraiTheme.secondaryInk)
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
                                                .foregroundColor(ChoraiTheme.secondaryInk)
                                        } else {
                                            Text("Get Code")
                                                .foregroundColor(ChoraiTheme.accent)
                                        }
                                    }
                                    .disabled(isSendingCode || countdown > 0 || email.isEmpty)
                                    .font(.subheadline)
                                    .padding(.trailing, 16)
                                    .frame(minHeight: 50)
                                    .accessibilityIdentifier("signup.get-code")
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 28) // 增加圆角使其更椭圆
                                        .fill(Color.clear) // 透明背景
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 28)
                                                .stroke(ChoraiTheme.separator, lineWidth: 1) // 白色半透明边框
                                        )
                                )

                                // Password
                                InputField(
                                    icon: "lock",
                                    placeholder: "Password",
                                    text: $password,
                                    accessibilityIdentifier: "signup.password"
                                )

                                // Confirm Password
                                InputField(
                                    icon: "checkmark",
                                    placeholder: "Confirm Password",
                                    text: $confirmPassword,
                                    accessibilityIdentifier: "signup.confirm-password"
                                )
                            }
                            .adaptiveContentGutter()
                            .padding(.top, 24)

                            // 创建账户按钮
                            Button(action: {
                                createAccount()
                            }) {
                                HStack {
                                    if isRegistering {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .progressViewStyle(CircularProgressViewStyle(tint: ChoraiTheme.onAccent))
                                    }
                                    Text(
                                        isRegistering
                                            ? "Create..."
                                            : "CREATE ACCOUNT"
                                    )
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(ChoraiTheme.onAccent)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 52)
                                .background(ChoraiTheme.accent, in: Capsule())
                            }
                            .disabled(
                                isRegistering
                            )
                            .accessibilityIdentifier("signup.create-account")
                            .adaptiveContentGutter()
                            .padding(.top, 24)

                            // 用户协议提示
                            VStack(spacing: 4) {
                                Text("By continuing, you agree to our")
                                    .foregroundColor(ChoraiTheme.secondaryInk)
                                +
                                Text(" [User Agreement](arcnote://terms) ")
                                    .foregroundColor(ChoraiTheme.ink)
                                    .fontWeight(.medium)
                                    .underline()
                                +
                                Text("and acknowledge that you understand the")
                                    .foregroundColor(ChoraiTheme.secondaryInk)
                                +
                                Text(" [Privacy Policy](arcnote://privacy) ")
                                    .foregroundColor(ChoraiTheme.ink)
                                    .fontWeight(.medium)
                                    .underline()
                            }
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .adaptiveContentGutter()
                            .padding(.top, 12)
                            .fixedSize(horizontal: false, vertical: true)
                            .tint(ChoraiTheme.ink)
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
                                    .foregroundColor(ChoraiTheme.secondaryInk)
                                + Text("Sign In")
                                    .foregroundColor(ChoraiTheme.ink)
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
                                    .foregroundColor(ChoraiTheme.secondaryInk)

                                Text("Or sign up with")
                                    .font(.caption)
                                    .foregroundColor(ChoraiTheme.secondaryInk)
                                    .padding(.horizontal, 16)

                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(ChoraiTheme.secondaryInk)
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
                    .scrollDismissesKeyboard(.interactively)
            }
            .background(
                ChoraiBackground()
                    .ignoresSafeArea(.all)
            )
        .foregroundStyle(ChoraiTheme.ink)
        .tint(ChoraiTheme.accent)
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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
        .onAppear {
            let code = initialAccessCode.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if (9...64).contains(code.count) {
                KeychainStore.shared.save(code)
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
                        handleVerificationCodeError(error)
                    }
                },
                receiveValue: { response in
                    if response.success {
                        isCodeSent = true
                        startCountdown()
                        showAlert(message: response.message ?? "Verification code has been sent to your email")
                    } else {
                        showAlert(
                            message: AuthenticationErrorPresentation.verificationCodeMessage(
                                statusCode: nil,
                                errorCode: response.errorCode
                            )
                        )
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func handleVerificationCodeError(_ error: NetworkError) {
        switch error {
        case .serverError(let statusCode, _):
            showAlert(
                message: AuthenticationErrorPresentation.verificationCodeMessage(
                    statusCode: statusCode,
                    errorCode: nil
                )
            )
        case .api(let statusCode, let errorCode, _):
            showAlert(
                message: AuthenticationErrorPresentation.verificationCodeMessage(
                    statusCode: statusCode,
                    errorCode: errorCode
                )
            )
        case .networkError:
            showAlert(message: "Network connection failed, please check your network settings")
        case .timeout:
            showAlert(message: "Request timeout, please try again later")
        case .decodingError:
            showAlert(message: "The server returned an unexpected response. Please try again later.")
        default:
            showAlert(message: "Verification code could not be sent. Please try again.")
        }
    }

    // MARK: - 创建账户
    private func createAccount() {
        guard !isRegistering else { return }
        guard username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
              isValidEmail(email),
              code.count == 6,
              password.count >= 8,
              isStrongPassword(password),
              password == confirmPassword else {
            showAlert(message: "Check your account details and try again.")
            return
        }

        let pair = currentAccessPair()
        guard pair.code != nil, pair.key != nil else {
            showAlert(
                message: "Enter a Product Access Code before creating an account."
            )
            return
        }

        isRegistering = true
        authManager.register(
            username: username,
            email: email,
            password: password,
            verificationCode: code,
            accessCode: pair.code,
            idempotencyKey: pair.key
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isRegistering = false
                if case .failure(let error) = completion {
                    handleRegistrationError(error)
                }
            },
            receiveValue: { response in
                isRegistering = false
                routeAfterAuth(response)
            }
        )
        .store(in: &cancellables)
    }

    private func currentAccessPair() -> (code: String?, key: String?) {
        let code = KeychainStore.shared.load()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let code,
              (9...64).contains(code.count) else {
            return (nil, nil)
        }
        if accessKeyCode != code {
            accessKeyCode = code
            accessKey = "ios-\(UUID().uuidString.lowercased())"
        }
        return (code, accessKey)
    }

    private func routeAfterAuth(_ response: AuthResponse) {
        guard response.data.productAccess.status == "allowed" else { return }
        if response.data.isNewUser == true {
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
        case .serverError(let statusCode, _):
            showAlert(
                message: AuthenticationErrorPresentation.registrationMessage(
                    statusCode: statusCode,
                    errorCode: nil
                )
            )
        case .api(let statusCode, let errorCode, _):
            showAlert(
                message: AuthenticationErrorPresentation.registrationMessage(
                    statusCode: statusCode,
                    errorCode: errorCode
                )
            )
        case .networkError:
            showAlert(message: "Network connection failed, please check your network settings")
        case .timeout:
            showAlert(message: "Request timeout, please try again later")
        case .decodingError:
            showAlert(message: "The server returned an unexpected response. Please try again later.")
        default:
            showAlert(message: "Registration failed. Please try again.")
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
        let pair = currentAccessPair()
        guard pair.code != nil, pair.key != nil else {
            showAlert(
                message: "Enter a Product Access Code before creating an account."
            )
            return
        }
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
                        handleRegistrationError(error)
                    }
                },
                receiveValue: { authResponse in
                    print("后端Google登录成功")
                    routeAfterAuth(authResponse)
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

                        let pair = currentAccessPair()
                        guard pair.code != nil, pair.key != nil else {
                            showAlert(
                                message: "Enter a Product Access Code before creating an account."
                            )
                            return
                        }
                        let appleLoginRequest = AppleLoginRequest(
                            identityToken: identityTokenString,
                            authorizationCode: authorizationCodeString,
                            userInfo: appleUserInfo,
                            accessCode: pair.code,
                            idempotencyKey: pair.key
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
                        handleRegistrationError(error)
                    }
                },
                receiveValue: { authResponse in
                    print("后端Apple登录成功")
                    routeAfterAuth(authResponse)
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

    private var isPassword: Bool { placeholder.localizedCaseInsensitiveContains("password") }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(ChoraiTheme.secondaryInk)
                .frame(width: 22)
                .accessibilityHidden(true)
            Group {
                if isPassword {
                    SecureField(placeholder, text: $text)
                        .textContentType(accessibilityIdentifier?.hasPrefix("signup.") == true ? .newPassword : .password)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(placeholder.localizedCaseInsensitiveContains("email") ? .emailAddress : .default)
                        .textContentType(placeholder.localizedCaseInsensitiveContains("email") ? .emailAddress : .username)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body)
            .foregroundStyle(ChoraiTheme.ink)
            .tint(ChoraiTheme.accent)
            .modifier(OptionalAccessibilityIdentifier(identifier: accessibilityIdentifier))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(minHeight: 52)
        .background(ChoraiTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ChoraiTheme.separator, lineWidth: 0.75)
                .allowsHitTesting(false)
        }
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
