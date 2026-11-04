//
//  SignUpView.swift
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
private final class SignUpFormState: ObservableObject {
    struct PendingRequest: Equatable {
        let id = UUID()
        let step: RegistrationDraft.Step
        let loadingTitle: String
    }

    struct StepError {
        let step: RegistrationDraft.Step
        let message: String
        var recoverCode = false
    }

    @Published var draft: RegistrationDraft
    @Published var error: StepError?
    @Published var pending: PendingRequest?

    init(draft: RegistrationDraft) {
        self.draft = draft
    }
}

@MainActor
struct SignUpView: View {
    private typealias Step = RegistrationDraft.Step
    private typealias PendingRequest = SignUpFormState.PendingRequest
    private typealias StepError = SignUpFormState.StepError

    @Environment(\.authEntryOverrides) private var authEntryOverrides
    @StateObject private var model: SignUpFormState
    @State private var showCode = false
    @State private var showUsername = false
    @State private var showPassword = false
    @State private var showConfirmation = false
    @State private var destination: Destination?
    @State private var legalPage: LegalPage?
    @State private var request: AnyCancellable?
    @State private var appleSignInDelegate: AppleSignInDelegate?
    @State private var accessKey = "ios-\(UUID().uuidString.lowercased())"
    @State private var accessKeyCode: String?
    private let initialAccessCode: String

    private enum Destination: Equatable {
        case interests(Step), home(Step)
    }

    private enum LegalPage: String, Identifiable {
        case terms, privacy
        var id: String { rawValue }
        var title: String { self == .terms ? "User Agreement" : "Privacy Policy" }
        var url: URL {
            self == .terms
                ? URL(string: "https://chorai.app/terms")!
                : URL(string: "https://chorai.app/privacy")!
        }
    }

    private var draft: RegistrationDraft {
        get { model.draft }
        nonmutating set { model.draft = newValue }
    }

    private var error: StepError? {
        get { model.error }
        nonmutating set { model.error = newValue }
    }

    private var pending: PendingRequest? {
        get { model.pending }
        nonmutating set { model.pending = newValue }
    }

    init(initialValues: SignUpInitialValues = .empty) {
        _model = StateObject(wrappedValue: SignUpFormState(draft: RegistrationDraft(
            email: initialValues.email,
            code: initialValues.verificationCode,
            username: initialValues.username,
            password: initialValues.password,
            confirmPassword: initialValues.confirmPassword
        )))
        initialAccessCode = initialValues.accessCode
    }

    var body: some View {
        page(.email)
            .navigationDestination(isPresented: $showCode) { codePage }
            .onAppear {
                let code = initialAccessCode.trimmingCharacters(in: .whitespacesAndNewlines)
                if (9...64).contains(code.count) {
                    codeStore.save(code)
                }
            }
    }

    private var codePage: some View {
        page(.code)
            .navigationDestination(isPresented: $showUsername) { usernamePage }
    }

    private var usernamePage: some View {
        page(.username)
            .navigationDestination(isPresented: $showPassword) { passwordPage }
    }

    private var passwordPage: some View {
        page(.password)
            .navigationDestination(isPresented: $showConfirmation) { page(.confirm) }
    }

    private func page(_ step: Step) -> some View {
        SignUpStepPage(
            model: model,
            step: step,
            text: fieldBinding(step),
            subtitle: subtitle(step),
            onSubmit: { advance(from: step) },
            onRecoverCode: returnToCode
        ) {
            switch step {
            case .email:
                AuthProviderButtons(
                    google: signInWithGoogle,
                    apple: signInWithApple,
                    disabled: pending != nil
                )
                .padding(.top, 12)
            case .code:
                codeActions
            default:
                EmptyView()
            }

        } footer: {
            if step == .confirm { legalNotice }
        }
        .navigationDestination(isPresented: destinationBinding(.interests(step))) {
            ChooseInterestsView()
        }
        .navigationDestination(isPresented: destinationBinding(.home(step))) {
            TabBarView()
        }
        .onDisappear {
            if pending?.step == step { cancelRequest() }
            if error?.step == step { error = nil }
        }
    }

    private var codeActions: some View {
        VStack(spacing: 3) {
            ViewThatFits {
                HStack(spacing: 16) { resendButton; changeEmailButton }
                VStack(spacing: 0) { resendButton; changeEmailButton }
            }
            Text("Check your spam folder if it hasn’t arrived.")
                .font(.caption)
                .foregroundStyle(ChoraiTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
    }

    private var resendButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = draft.resendSeconds(at: context.date)
            Button(seconds > 0 ? "Resend code in \(seconds)s" : "Resend code") {
                guard draft.resendSeconds(at: .now) == 0 else { return }
                sendVerificationCode(from: .code)
            }
            .frame(minHeight: 44)
            .disabled(seconds > 0 || pending != nil)
            .accessibilityIdentifier("signup.get-code")
        }
        .font(.footnote.weight(.medium))
    }

    private var changeEmailButton: some View {
        Button("Change email") {
            cancelRequest()
            showCode = false
        }
        .font(.footnote.weight(.medium))
        .frame(minHeight: 44)
        .accessibilityIdentifier("signup.change-email")
    }

    private var legalNotice: some View {
        Text("By continuing, you agree to our [User Agreement](arcnote://terms) and acknowledge our [Privacy Policy](arcnote://privacy).")
            .font(.caption2)
            .foregroundStyle(ChoraiTheme.secondaryInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "arcnote", let host = url.host, let page = LegalPage(rawValue: host) else {
                    return .systemAction
                }
                legalPage = page
                return .handled
            })
            .sheet(item: $legalPage) { page in
                NavigationStack {
                    Group {
                        if authEntryOverrides != nil {
                            Text("Legal page preview is unavailable offline.")
                                .padding(24)
                        } else {
                            WebViewPage(url: page.url, title: page.title)
                        }
                    }
                    .navigationTitle(page.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { legalPage = nil }
                        }
                    }
                }
            }
    }

    private func subtitle(_ step: Step) -> String {
        switch step {
        case .email: return "Use your email to get started."
        case .code: return "Enter the code sent to \(draft.email)"
        case .username: return "Choose a username with at least 2 characters."
        case .password: return "At least 8 characters, with a letter and a number."
        case .confirm: return "Enter it once more."
        }
    }

    private func fieldBinding(_ step: Step) -> Binding<String> {
        let keyPath: WritableKeyPath<RegistrationDraft, String>
        switch step {
        case .email: keyPath = \.email
        case .code: keyPath = \.code
        case .username: keyPath = \.username
        case .password: keyPath = \.password
        case .confirm: keyPath = \.confirmPassword
        }
        return Binding(
            get: { draft[keyPath: keyPath] },
            set: {
                guard draft[keyPath: keyPath] != $0 else { return }
                if error?.step == step { error = nil }
                draft[keyPath: keyPath] = $0
            }
        )
    }

    private func advance(from step: Step) {
        guard pending == nil, draft.canContinue(step) else { return }
        error = nil
        switch step {
        case .email:
            if draft.codeWasSent { showCode = true }
            else { sendVerificationCode(from: .email) }
        case .code: showUsername = true
        case .username: showPassword = true
        case .password: showConfirmation = true
        case .confirm: createAccount()
        }
    }

    private func sendVerificationCode(from step: Step) {
        guard pending == nil, draft.canContinue(.email) else { return }
        let email = draft.email
        let operation = PendingRequest(step: step, loadingTitle: "Sending code…")
        pending = operation
        error = nil

        let publisher = authEntryOverrides?.sendVerificationCode(email)
            ?? AuthManager.shared.sendVerificationCode(email: email)
        request = publisher.receive(on: DispatchQueue.main).sink(
            receiveCompletion: { completion in
                guard pending == operation else { return }
                cancelRequest()
                if case .failure(let failure) = completion {
                    showError(message(for: failure, sendingCode: true), on: step)
                }
            },
            receiveValue: { response in
                guard pending == operation, draft.email == email else { return }
                cancelRequest()
                if response.success {
                    draft.markCodeSent(to: email, at: .now)
                    if step == .email { showCode = true }
                } else {
                    showError(AuthenticationErrorPresentation.verificationCodeMessage(
                        statusCode: nil, errorCode: response.errorCode
                    ), on: step)
                }
            }
        )
    }

    private func createAccount() {
        guard pending == nil else { return }
        guard draft.password == draft.confirmPassword else {
            showError("Your passwords don’t match. Try again.", on: .confirm)
            return
        }
        guard draft.canRegister else {
            showError("Check your account details and try again.", on: .confirm)
            return
        }

        let pair = currentAccessPair()
        guard pair.code != nil, pair.key != nil else {
            showError("Enter a Product Access Code before creating an account.", on: .confirm)
            return
        }

        let operation = PendingRequest(step: .confirm, loadingTitle: "Creating account…")
        pending = operation
        let publisher = authEntryOverrides?.register(
            draft.username, draft.email, draft.password, draft.code, pair.code, pair.key
        ) ?? AuthManager.shared.register(
            username: draft.username,
            email: draft.email,
            password: draft.password,
            verificationCode: draft.code,
            accessCode: pair.code,
            idempotencyKey: pair.key
        )
        request = publisher.receive(on: DispatchQueue.main).sink(
            receiveCompletion: { completion in
                guard pending == operation else { return }
                cancelRequest()
                if case .failure(let failure) = completion {
                    showError(message(for: failure), on: .confirm, recoverCode: isCodeRejection(failure))
                }
            },
            receiveValue: { response in
                guard pending == operation else { return }
                cancelRequest()
                routeAfterAuth(response, from: .confirm)
            }
        )
    }

    private func returnToCode() {
        cancelRequest()
        error = nil
        draft.code = ""
        showConfirmation = false
        showPassword = false
        showUsername = false
    }

    private func cancelRequest() {
        pending = nil
        request?.cancel()
        request = nil
        appleSignInDelegate = nil
    }

    private var codeStore: any CodeStoring {
        authEntryOverrides?.codeStore ?? KeychainStore.shared
    }

    private func currentAccessPair() -> (code: String?, key: String?) {
        let code = codeStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let code, (9...64).contains(code.count) else { return (nil, nil) }
        if accessKeyCode != code {
            accessKeyCode = code
            accessKey = "ios-\(UUID().uuidString.lowercased())"
        }
        return (code, accessKey)
    }

    private func destinationBinding(_ value: Destination) -> Binding<Bool> {
        Binding(
            get: { destination == value },
            set: { if !$0, destination == value { destination = nil } }
        )
    }

    private func routeAfterAuth(_ response: AuthResponse, from step: Step = .email) {
        guard response.data.productAccess.status == "allowed" else { return }
        if let overrides = authEntryOverrides {
            overrides.onAuthenticated(.signUp)
            return
        }
        destination = response.data.isNewUser == true ? .interests(step) : .home(step)
    }

    private func isCodeRejection(_ error: NetworkError) -> Bool {
        switch error {
        case .serverError(let status, _):
            return AuthenticationErrorPresentation.registrationRejectsCode(statusCode: status, errorCode: nil)
        case .api(let status, let code, _):
            return AuthenticationErrorPresentation.registrationRejectsCode(statusCode: status, errorCode: code)
        default: return false
        }
    }

    private func message(for error: NetworkError, sendingCode: Bool = false) -> String {
        let serviceMessage = sendingCode
            ? AuthenticationErrorPresentation.verificationCodeMessage
            : AuthenticationErrorPresentation.registrationMessage
        switch error {
        case .serverError(let status, _): return serviceMessage(status, nil)
        case .api(let status, let code, _): return serviceMessage(status, code)
        case .networkError: return "Connection unavailable. Try again when you’re back online."
        case .timeout: return "Request timed out. Please try again."
        case .decodingError: return "The server returned an unexpected response. Please try again later."
        default:
            return sendingCode
                ? "Verification code could not be sent. Please try again."
                : "Registration failed. Please try again."
        }
    }

    private func showError(_ message: String, on step: Step, recoverCode: Bool = false) {
        error = StepError(step: step, message: message, recoverCode: recoverCode)
    }

    private func signInWithGoogle() {
        guard pending == nil else { return }
        if let overrides = authEntryOverrides {
            overrides.onAuthenticated(.signUp)
            return
        }
        guard let presentingViewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }

        let operation = beginProviderRequest()
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, failure in
            DispatchQueue.main.async {
                guard pending == operation else { return }
                guard let idToken = result?.user.idToken?.tokenString else {
                    cancelRequest()
                    let canceled = (failure as NSError?)?.code == GIDSignInError.canceled.rawValue
                    if !canceled {
                        showError("Google sign in failed. Please try again.", on: .email)
                    }
                    return
                }
                handleGoogleLoginResponse(idToken: idToken, operation: operation)
            }
        }
    }

    private func handleGoogleLoginResponse(idToken: String, operation: PendingRequest) {
        let pair = currentAccessPair()
        guard pair.code != nil, pair.key != nil else {
            showMissingProviderAccessCode()
            return
        }
        finishProviderRequest(
            AuthManager.shared.googleLogin(
                idToken: idToken,
                accessCode: pair.code,
                idempotencyKey: pair.key
            ),
            operation: operation
        )
    }

    private func signInWithApple() {
        guard pending == nil else { return }
        if let overrides = authEntryOverrides {
            overrides.onAuthenticated(.signUp)
            return
        }

        let operation = beginProviderRequest()
        let appleRequest = ASAuthorizationAppleIDProvider().createRequest()
        appleRequest.requestedScopes = [.fullName, .email]

        appleSignInDelegate = AppleSignInDelegate { result in
            DispatchQueue.main.async {
                guard pending == operation else { return }
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let identityToken = credential.identityToken,
                          let identityTokenString = String(data: identityToken, encoding: .utf8),
                          let authorizationCode = credential.authorizationCode,
                          let authorizationCodeString = String(data: authorizationCode, encoding: .utf8) else {
                        cancelRequest()
                        showError("Apple sign in failed. Please try again.", on: .email)
                        return
                    }

                    let appleUserInfo = AppleUserInfo(
                        name: AppleName(
                            firstName: credential.fullName?.givenName ?? "",
                            lastName: credential.fullName?.familyName ?? ""
                        )
                    )
                    let pair = currentAccessPair()
                    guard pair.code != nil, pair.key != nil else {
                        showMissingProviderAccessCode()
                        return
                    }
                    let appleLoginRequest = AppleLoginRequest(
                        identityToken: identityTokenString,
                        authorizationCode: authorizationCodeString,
                        userInfo: appleUserInfo,
                        accessCode: pair.code,
                        idempotencyKey: pair.key
                    )
                    finishProviderRequest(
                        AuthManager.shared.appleLogin(request: appleLoginRequest),
                        operation: operation
                    )
                case .failure(let failure):
                    cancelRequest()
                    if (failure as? ASAuthorizationError)?.code != .canceled {
                        showError("Apple sign in failed. Please try again.", on: .email)
                    }
                }
            }
        }

        let authorizationController = ASAuthorizationController(authorizationRequests: [appleRequest])
        authorizationController.delegate = appleSignInDelegate
        authorizationController.performRequests()
    }

    private func beginProviderRequest() -> PendingRequest {
        let operation = PendingRequest(step: .email, loadingTitle: "Signing in…")
        pending = operation
        error = nil
        return operation
    }

    private func showMissingProviderAccessCode() {
        cancelRequest()
        showError("Enter a Product Access Code before creating an account.", on: .email)
    }

    private func finishProviderRequest(
        _ publisher: AnyPublisher<AuthResponse, NetworkError>,
        operation: PendingRequest
    ) {
        request = publisher.receive(on: DispatchQueue.main).sink(
            receiveCompletion: { completion in
                guard pending == operation else { return }
                cancelRequest()
                if case .failure(let failure) = completion {
                    showError(message(for: failure), on: .email)
                }
            },
            receiveValue: { response in
                guard pending == operation else { return }
                cancelRequest()
                routeAfterAuth(response)
            }
        )
    }

}

@MainActor
private struct SignUpStepPage<Extras: View, Footer: View>: View {
    @ObservedObject var model: SignUpFormState
    let step: RegistrationDraft.Step
    @Binding var text: String
    let subtitle: String
    let onSubmit: () -> Void
    let onRecoverCode: () -> Void
    @ViewBuilder let extras: () -> Extras
    @ViewBuilder let footer: () -> Footer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private enum InputFocus { case plain, secure }
    @FocusState private var focusedInput: InputFocus?
    @ScaledMetric(relativeTo: .title) private var inputSize = 29.0
    @State private var passwordVisible = false

    private var isPassword: Bool { step == .password || step == .confirm }
    private var busy: Bool { model.pending?.step == step }
    private var enabled: Bool { model.pending == nil && model.draft.canContinue(step) }
    private var stepError: SignUpFormState.StepError? {
        model.error?.step == step ? model.error : nil
    }

    private var title: String {
        switch step {
        case .email: return "Enter your email address"
        case .code: return "Check your inbox"
        case .username: return "What should we call you?"
        case .password: return "Create your password"
        case .confirm: return "Confirm your password"
        }
    }

    private var placeholder: String {
        switch step {
        case .email: return "Email address"
        case .code: return "Email code"
        case .username: return "Username"
        case .password: return "Password"
        case .confirm: return "Confirm password"
        }
    }

    private var fieldIdentifier: String {
        switch step {
        case .email: return "signup.email"
        case .code: return "signup.code"
        case .username: return "signup.username"
        case .password: return "signup.password"
        case .confirm: return "signup.confirm-password"
        }
    }

    private var progress: Int {
        switch step {
        case .email: return 2
        case .code: return 3
        case .username: return 4
        case .password: return 5
        case .confirm: return 6
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        AuthEntryHeading(title: title, subtitle: subtitle)
                            .accessibilityIdentifier("signup.step.\(step.rawValue)")
                            .padding(.top, 26)
                        input
                            .padding(.top, inputSpacing(in: geometry.size.height))
                            .padding(.bottom, step == .email ? 12 : 24)
                        if let stepError {
                            VStack(spacing: 4) {
                                Text(stepError.message)
                                    .font(.footnote)
                                    .foregroundStyle(Color.red)
                                    .multilineTextAlignment(.center)
                                    .accessibilityIdentifier("signup.error")

                                if stepError.recoverCode {
                                    Button("Back to email code", action: onRecoverCode)
                                        .font(.footnote.weight(.semibold))
                                        .frame(minHeight: 44)
                                        .accessibilityIdentifier("signup.recover-code")
                                }
                            }
                            .id("signup.error")
                            .padding(.bottom, 20)
                        }
                        extras()
                        if dynamicTypeSize.isAccessibilitySize && step == .confirm {
                            footer()
                                .padding(.top, 24)
                        }
                    }
                    .frame(maxWidth: 460)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: stepError?.message) { message in
                    guard let message else { return }
                    proxy.scrollTo("signup.error", anchor: .center)
                    UIAccessibility.post(notification: .announcement, argument: message)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                AuthPrimaryButton(
                    title: step == .confirm ? "Create account" : "Continue",
                    isLoading: busy,
                    enabled: enabled,
                    loadingTitle: model.pending?.loadingTitle ?? (step == .confirm ? "Creating account…" : "Sending code…"),
                    identifier: step == .confirm ? "signup.create-account" : "signup.continue",
                    action: submit
                )
                if !dynamicTypeSize.isAccessibilitySize {
                    footer()
                }
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(ChoraiTheme.background)
        }
        .authEntryPage()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                AuthProgress(step: progress)
            }
        }
        .onChange(of: busy) { working in
            if working { focusedInput = nil }
        }
        .task {
            // Delay focus until the native push finishes; a canceled push also cancels this task.
            do {
                try await Task.sleep(nanoseconds: reduceMotion ? 50_000_000 : 370_000_000)
                guard !busy else { return }
                focusCurrentInput()
            } catch {}
        }
    }

    private func inputSpacing(in availableHeight: CGFloat) -> CGFloat {
        // The keyboard changes the available viewport. Focus alone never moves the field.
        if dynamicTypeSize.isAccessibilitySize { return 24 }
        return min(112, max(28, availableHeight * 0.19))
    }

    private func focusCurrentInput() {
        focusedInput = isPassword && !passwordVisible ? .secure : .plain
    }

    private var input: some View {
        HStack(spacing: 4) {
            Group {
                if isPassword && !passwordVisible {
                    SecureField(placeholder, text: $text)
                        .focused($focusedInput, equals: .secure)
                        .textContentType(.newPassword)
                } else {
                    TextField(placeholder, text: $text)
                        .focused($focusedInput, equals: .plain)
                        .keyboardType(step == .email ? .emailAddress : .default)
                        .textContentType(contentType)
                }
            }
            .font(dynamicTypeSize.isAccessibilitySize
                ? .body
                : .system(size: step == .email ? inputSize * 27 / 29 : inputSize))
            .tracking(step == .code && !text.isEmpty ? 6 : -0.7)
            .multilineTextAlignment(isPassword ? .leading : .center)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(step == .confirm ? .go : .continue)
            .onSubmit(submit)
            .disabled(busy)
            .accessibilityLabel(placeholder)
            .accessibilityIdentifier(fieldIdentifier)

            if isPassword {
                Button {
                    passwordVisible.toggle()
                    focusCurrentInput()
                } label: {
                    Image(systemName: passwordVisible ? "eye" : "eye.slash")
                        .font(.system(size: 20))
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AuthPressButtonStyle())
                .disabled(busy)
                .accessibilityLabel(passwordVisible ? "Hide password" : "Show password")
            }
        }
        .frame(minHeight: 52)
    }

    private var contentType: UITextContentType? {
        switch step {
        case .email: return .emailAddress
        case .code: return .oneTimeCode
        case .username: return .username
        case .password, .confirm: return .newPassword
        }
    }

    private func submit() {
        guard enabled else { return }
        focusedInput = nil
        onSubmit()
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
        NavigationStack {
            SignUpView()
        }
    }
}
