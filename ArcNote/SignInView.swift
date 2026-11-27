//
//  SignInView.swift
//  ArcNote
//
//  Created by 海了个螺 on 2025/7/23.
//

import SwiftUI
import UIKit
import Combine
import CoreFlow
import GoogleSignIn
import AuthenticationServices

struct SignInView: View {
    @Environment(\.authEntryOverrides) private var authEntryOverrides
    @FocusState private var focusedField: Field?
    private enum Field { case email, password, visiblePassword }
    @State private var revealsPassword = false
    @State private var isVisible = false

    // 添加状态变量来管理输入内容
    @State private var usernameEmail = ""
    @State private var password = ""

    // 登录相关状态
    @State private var attemptID: UUID?
    @State private var alertMessage = ""
    @State private var showTabBar = false
    @State private var showChooseInterests = false

    // 认证管理器
    private var authManager: AuthManager { AuthManager.shared }
    @State private var request: AnyCancellable?
    @State private var appleSignInDelegate: AppleSignInDelegate?
    @State private var accessKey = "ios-\(UUID().uuidString.lowercased())"
    @State private var accessKeyCode: String?


    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 28) {
                    AuthEntryHeading(title: "Welcome back", subtitle: "Enter your email and password")
                    VStack(spacing: 14) {
                        TextField("Email", text: $usernameEmail)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focusedField, equals: .email)
                            .onSubmit { focusedField = revealsPassword ? .visiblePassword : .password }
                            .accessibilityIdentifier("signin.email")
                            .modifier(SignInFieldSurface(isFocused: focusedField == .email))
                        HStack(spacing: 8) {
                            Group {
                                if revealsPassword { TextField("Password", text: $password).focused($focusedField, equals: .visiblePassword) }
                                else { SecureField("Password", text: $password).focused($focusedField, equals: .password) }
                            }
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit(signIn)
                            .accessibilityIdentifier("signin.password")
                            Button {
                                revealsPassword.toggle()
                                focusedField = revealsPassword ? .visiblePassword : .password
                            } label: {
                                Image(systemName: revealsPassword ? "eye" : "eye.slash")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(AuthPressButtonStyle())
                            .accessibilityLabel(revealsPassword ? "Hide password" : "Show password")
                        }
                        .modifier(SignInFieldSurface(isFocused: focusedField == .password || focusedField == .visiblePassword))
                    }
                    .disabled(isSigningIn)
                    if !alertMessage.isEmpty {
                        Text(alertMessage).font(.footnote).foregroundStyle(Color.red)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("signin.error")
                            .id("signin.error")
                    }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-test-ordinary-phone-signin"),
                       ProcessInfo.processInfo.environment["CHORAI_UI_TEST"] == "1" {
                        ForEach(["A", "B"], id: \.self) { account in
                            Button("Sign in with test account " + account) {
                                signInWithOrdinaryTestAccount(account)
                            }
                            .accessibilityIdentifier("signin.test-account." + account)
                        }
                    }
                    #endif
                    AuthProviderButtons(google: signInWithGoogle, apple: signInWithApple, disabled: isSigningIn)
                }
                .padding(.horizontal, 22)
                .padding(.top, 26)
                .padding(.bottom, 24)
            }
            .onChange(of: alertMessage) { message in
                guard !message.isEmpty else { return }
                proxy.scrollTo("signin.error", anchor: .center)
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AuthPrimaryButton(title: "Sign in", isLoading: isSigningIn,
                              enabled: canSubmit, loadingTitle: "Signing in…",
                              identifier: "signin.submit", action: signIn)
                .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 12)
                .background(ChoraiTheme.background)
        }
        .authEntryPage()
        .navigationTitle("chorai")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink("Sign Up") {
                    if let overrides = authEntryOverrides {
                        PrivateBetaEntryView(
                            preflighter: overrides.preflighter,
                            codeStore: overrides.codeStore,
                            returnsToSignIn: true
                        )
                    } else {
                        PrivateBetaEntryView(returnsToSignIn: true)
                    }
                }
                .font(.subheadline)
                .accessibilityIdentifier("signin.sign-up")
            }
        }
        .navigationDestination(isPresented: $showTabBar) { TabBarView() }
        .navigationDestination(isPresented: $showChooseInterests) { ChooseInterestsView() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("InterestsSelectionCompleted"))) { _ in
            showChooseInterests = false
            showTabBar = true
        }
        .onChange(of: usernameEmail) { _ in alertMessage = "" }
        .onChange(of: password) { _ in alertMessage = "" }
        .task {
            isVisible = true
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, isVisible, focusedField == nil, !isSigningIn else { return }
            focusedField = .email
        }
        .onDisappear {
            isVisible = false
            focusedField = nil
            endAttempt()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.sign-in")
    }

    private var isSigningIn: Bool { attemptID != nil }
    private var canSubmit: Bool { isValidEmail(usernameEmail) && !password.isEmpty }

    private func signIn() {
        guard canSubmit, let id = beginAttempt() else { return }
        let publisher = authEntryOverrides?.login(usernameEmail, password)
            ?? authManager.login(email: usernameEmail, password: password)
        performLogin(publisher, attempt: id)
    }

    #if DEBUG
    private func signInWithOrdinaryTestAccount(_ account: String) {
        let environment = ProcessInfo.processInfo.environment
        let prefix = account == "A" ? "CHORAI_UI_TEST_" : "CHORAI_UI_TEST_TARGET_"
        guard let phone = environment[prefix + "PHONE"], let password = environment[prefix + "PASSWORD"],
              let id = beginAttempt() else { return }
        let publisher = NetworkManager.shared.loginForPhoneUITest(phone: phone, password: password)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { authManager.saveUserSession($0) })
            .eraseToAnyPublisher()
        performLogin(publisher, attempt: id)
    }
    #endif

    private func beginAttempt() -> UUID? {
        guard isVisible, attemptID == nil else { return nil }
        let id = UUID()
        attemptID = id
        focusedField = nil
        alertMessage = ""
        return id
    }

    private func isCurrentAttempt(_ id: UUID) -> Bool {
        isVisible && attemptID == id
    }

    private func endAttempt() {
        attemptID = nil
        request?.cancel()
        request = nil
        appleSignInDelegate = nil
    }

    private func performLogin(
        _ publisher: AnyPublisher<AuthResponse, NetworkError>,
        attempt id: UUID,
        provider: String? = nil
    ) {
        request = publisher.receive(on: DispatchQueue.main).sink(
            receiveCompletion: { completion in
                guard isCurrentAttempt(id) else { return }
                endAttempt()
                if case .failure(let error) = completion {
                    if let provider {
                        handleFederatedLoginError(error, provider: provider)
                    } else {
                        handleLoginError(error)
                    }
                }
            },
            receiveValue: { response in
                guard isCurrentAttempt(id) else { return }
                endAttempt()
                routeAfterAuth(response)
            }
        )
    }

    private func showAlert(message: String) {
        alertMessage = message
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
        case .serverError(let statusCode, _):
            showAlert(
                message: AuthenticationErrorPresentation.signInMessage(
                    statusCode: statusCode,
                    errorCode: nil
                )
            )
        case .api(let statusCode, let errorCode, _, _):
            showAlert(
                message: AuthenticationErrorPresentation.signInMessage(
                    statusCode: statusCode,
                    errorCode: errorCode
                )
            )
        case .unauthorized:
            showAlert(
                message: AuthenticationErrorPresentation.signInMessage(
                    statusCode: 401,
                    errorCode: "UNAUTHORIZED"
                )
            )
        case .forbidden:
            showAlert(
                message: AuthenticationErrorPresentation.signInMessage(
                    statusCode: 403,
                    errorCode: "FORBIDDEN"
                )
            )
        case .notFound:
            showAlert(
                message: AuthenticationErrorPresentation.signInMessage(
                    statusCode: 404,
                    errorCode: nil
                )
            )
        case .networkError:
            showAlert(message: "Network connection failed, please check your network settings")
        case .timeout:
            showAlert(message: "Request timeout, please try again later")
        case .decodingError:
            showAlert(message: "The server returned an unexpected response. Please try again later.")
        default:
            showAlert(message: "Sign-in failed. Please try again.")
        }
    }

    private func handleFederatedLoginError(
        _ error: NetworkError,
        provider: String
    ) {
        let genericMessage = "\(provider) sign-in could not be verified. Please try again."
        switch error {
        case .api(let statusCode, let errorCode, _, _):
            let sharedCodes = [
                "PRODUCT_ACCESS_REQUIRED",
                "FORBIDDEN",
                "ACCOUNT_DISABLED",
                "RATE_LIMIT_EXCEEDED",
                "SERVICE_UNAVAILABLE",
                "DATABASE_ERROR",
                "INTERNAL_ERROR",
            ]
            if sharedCodes.contains(errorCode?.uppercased() ?? "")
                || statusCode == 429
                || (500...599).contains(statusCode) {
                handleLoginError(error)
            } else {
                showAlert(message: genericMessage)
            }
        case .serverError(let statusCode, _)
            where statusCode == 429 || (500...599).contains(statusCode):
            handleLoginError(error)
        case .forbidden, .networkError, .timeout, .decodingError:
            handleLoginError(error)
        default:
            showAlert(message: genericMessage)
        }
    }

    private func signInWithGoogle() {
        if let overrides = authEntryOverrides {
            overrides.onAuthenticated(.signIn)
            return
        }
        guard let id = beginAttempt() else { return }
        guard let presentingViewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController else {
            endAttempt()
            showAlert(message: "Google sign-in could not start. Please try again.")
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
            // Snapshot SDK-owned values before the existing UI delivery hop.
            let idToken = result?.user.idToken?.tokenString
            let succeeded = error == nil
            let canceled = (error as? GIDSignInError)?.code == .canceled
            DispatchQueue.main.async {
                guard isCurrentAttempt(id) else { return }
                guard succeeded, let idToken else {
                    endAttempt()
                    if !canceled {
                        showAlert(message: "Google sign-in could not be verified. Please try again.")
                    }
                    return
                }
                handleGoogleLoginResponse(idToken: idToken, attempt: id)
            }
        }
    }

    private func handleGoogleLoginResponse(idToken: String, attempt id: UUID) {
        guard isCurrentAttempt(id) else { return }
        let pair = pendingAccessPair()
        let publisher = authManager.googleLogin(
            idToken: idToken,
            accessCode: pair.code,
            idempotencyKey: pair.key
        )
        performLogin(publisher, attempt: id, provider: "Google")
    }

    private func signInWithApple() {
        if let overrides = authEntryOverrides {
            overrides.onAuthenticated(.signIn)
            return
        }
        guard let id = beginAttempt() else { return }
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        appleSignInDelegate = AppleSignInDelegate { result in
            DispatchQueue.main.async {
                guard isCurrentAttempt(id) else { return }
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let token = credential.identityToken,
                          let identityToken = String(data: token, encoding: .utf8),
                          let code = credential.authorizationCode,
                          let authorizationCode = String(data: code, encoding: .utf8) else {
                        endAttempt()
                        showAlert(message: "Apple sign-in could not be verified. Please try again.")
                        return
                    }
                    let userInfo = AppleUserInfo(name: AppleName(
                        firstName: credential.fullName?.givenName ?? "",
                        lastName: credential.fullName?.familyName ?? ""
                    ))
                    let pair = pendingAccessPair()
                    let loginRequest = AppleLoginRequest(
                        identityToken: identityToken,
                        authorizationCode: authorizationCode,
                        userInfo: userInfo,
                        accessCode: pair.code,
                        idempotencyKey: pair.key
                    )
                    handleAppleLoginResponse(request: loginRequest, attempt: id)
                case .failure(let error):
                    endAttempt()
                    if (error as? ASAuthorizationError)?.code != .canceled {
                        showAlert(message: "Apple sign-in failed. Please try again.")
                    }
                }
            }
        }

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = appleSignInDelegate
        controller.performRequests()
    }

    private func handleAppleLoginResponse(request: AppleLoginRequest, attempt id: UUID) {
        guard isCurrentAttempt(id) else { return }
        performLogin(authManager.appleLogin(request: request), attempt: id, provider: "Apple")
    }

    private func pendingAccessPair() -> (code: String?, key: String?) {
        guard let code = (authEntryOverrides?.codeStore ?? KeychainStore.shared).load() else {
            return (nil, nil)
        }
        if accessKeyCode != code {
            accessKeyCode = code
            accessKey = "ios-\(UUID().uuidString.lowercased())"
        }
        return (code, accessKey)
    }

    private func routeAfterAuth(_ response: AuthResponse) {
        if let overrides = authEntryOverrides { overrides.onAuthenticated(.signIn); return }
        guard response.data.productAccess.status == "allowed" else { return }
        if response.data.isNewUser == true {
            showChooseInterests = true
        } else {
            showTabBar = true
        }
    }
}

struct SignInView_Previews: PreviewProvider {
    static var previews: some View {
        SignInView()
    }
}

private struct SignInFieldSurface: ViewModifier {
    var isFocused = false

    func body(content: Content) -> some View {
        content.font(.body).foregroundStyle(ChoraiTheme.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(ChoraiTheme.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15)
                .stroke(isFocused ? ChoraiTheme.accent : ChoraiTheme.separator, lineWidth: 1))
    }
}
