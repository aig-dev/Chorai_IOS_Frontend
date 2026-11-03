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
    @StateObject private var authManager = AuthManager.shared
    @State private var cancellables = Set<AnyCancellable>()
    @State private var appleSignInDelegate: AppleSignInDelegate?
    @State private var showUnauthorizedAlert = false
    @State private var canOpenReturningSignIn = true
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
            if authManager.isAuthenticated { canOpenReturningSignIn = false }
            authManager.verifyRestoredSession()
        }
        .onChange(of: authManager.isAuthenticated) { authenticated in
            if authenticated { canOpenReturningSignIn = false }
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
            if authManager.needsInterestSelection {
                NavigationStack {
                    ChooseInterestsView(onComplete: authManager.completeInterestSelection)
                }
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

    private var loginView: some View {
        ChoraiWelcomeView(automaticallyOpensReturningSignIn: canOpenReturningSignIn)
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
                receiveValue: { _ in
                    print("后端Google登录成功")
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
                receiveValue: { _ in
                    print("后端Apple登录成功")
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

struct ChoraiWelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("chorai_introduction_seen") private var introductionSeen = false
    @State private var showSplash = true
    @State private var didFinishStartup = false
    @State private var mascotVisible = false
    @State private var page = 0
    @State private var direction: CGFloat = 1
    @State private var showSignIn = false
    @State private var showPrivateBeta = false

    var onLogin: (() -> Void)? = nil
    var onStart: (() -> Void)? = nil
    var remembersIntroduction = true
    var startsWithSignIn = false
    var automaticallyOpensReturningSignIn = true

    private let slides = [
        "Find ideas that\nstay with you.",
        "A place for your thoughts,\nand the things you find.",
        "Let one idea\nlead to another."
    ]
    private let sparkBackground = Color(red: 0.26, green: 0.32, blue: 0.22)
    private var introInk: Color { page == 2 ? Color(red: 1, green: 1, blue: 0.96) : ChoraiTheme.ink }
    private var introAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .timingCurve(0.3, 0.75, 0.25, 1, duration: 0.58)
    }

    var body: some View {
        Group {
            if showSplash && !reduceMotion {
                splash
                    .transition(.opacity)
            } else {
                introduction
                    .transition(.opacity)
            }
        }
        .background((page == 2 ? sparkBackground : ChoraiTheme.background).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSignIn) { SignInView() }
        .navigationDestination(isPresented: $showPrivateBeta) { PrivateBetaEntryView() }
        .task(id: reduceMotion) {
            guard !didFinishStartup else { return }
            if reduceMotion {
                finishStartup()
                return
            }
            withAnimation(.easeOut(duration: 0.55)) { mascotVisible = true }
            do {
                try await Task.sleep(for: .seconds(1))
                finishStartup()
            } catch {}
        }
    }

    private func finishStartup() {
        guard !didFinishStartup else { return }
        didFinishStartup = true
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            showSplash = false
        }
        if startsWithSignIn || (automaticallyOpensReturningSignIn && remembersIntroduction && introductionSeen) {
            openLogin()
        }
    }

    private func markIntroductionSeen() {
        if remembersIntroduction, !introductionSeen {
            introductionSeen = true
        }
    }

    private func openLogin() {
        markIntroductionSeen()
        if let onLogin { onLogin() } else { showSignIn = true }
    }

    private var splash: some View {
        ZStack(alignment: .bottom) {
            Image("cosmos-entry-chora")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .opacity(mascotVisible ? 1 : 0)
                .scaleEffect(mascotVisible ? 1 : 0.84)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            Text("chorai")
                .font(.system(size: 42, weight: .semibold, design: .serif))
                .tracking(-2)
                .foregroundStyle(ChoraiTheme.ink)
                .padding(.bottom, 60)
        }
        .accessibilityIdentifier("welcome.splash")
    }

    private var introduction: some View {
        VStack(spacing: 0) {
            HStack {
                if page > 0 {
                    Button { move(to: page - 1) } label: {
                        Image(systemName: "arrow.left")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Previous introduction")
                    .accessibilityIdentifier("welcome.previous")
                }
                Spacer()
                Button(action: openLogin) {
                    Text("Log In")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 8)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("welcome.login")
            }
            .adaptiveContentGutter()

            Text(slides[page])
                .font(.title3.weight(.medium))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, minHeight: 72)
                .padding(.top, 12)
                .adaptiveContentGutter()
                .layoutPriority(1)

            GeometryReader { geometry in
                let scale = max(0, min(1, geometry.size.width / 340, geometry.size.height / 438))
                ZStack {
                    welcomeArtwork
                        .scaleEffect(scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id("\(page)-\(reduceMotion)")
                        .transition(artTransition(distance: geometry.size.height))
                }
                .clipped()
                .accessibilityHidden(true)
            }
            .animation(introAnimation, value: page)

            VStack(spacing: 16) {
                nextButton
                HStack(spacing: 5) {
                    ForEach(slides.indices, id: \.self) { index in
                        Capsule()
                            .frame(width: index == page ? 20 : 10, height: 2)
                            .opacity(index == page ? 0.85 : 0.25)
                    }
                }
                .animation(introAnimation, value: page)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Introduction \(page + 1) of \(slides.count)")
            }
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .foregroundStyle(introInk)
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcome.introduction")
    }

    private var nextButton: some View {
        Button {
            if page < slides.count - 1 {
                move(to: page + 1)
            } else {
                markIntroductionSeen()
                if let onStart { onStart() } else { showPrivateBeta = true }
            }
        } label: {
            Text(page == slides.count - 1 ? "Get started" : "Next")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 28)
                .frame(minWidth: 118, minHeight: 46)
                .foregroundStyle(page == 2 ? sparkBackground : ChoraiTheme.onAccent)
                .background(introInk, in: Capsule())
                .animation(nil, value: page)
        }
        .buttonStyle(AuthPressButtonStyle())
        .accessibilityIdentifier(page == slides.count - 1 ? "welcome.join-private-beta" : "welcome.next")
    }

    private func move(to nextPage: Int) {
        guard slides.indices.contains(nextPage), nextPage != page else { return }
        direction = nextPage > page ? 1 : -1
        // Animate the artwork and position marks only; palette and words change together.
        page = nextPage
    }

    private func artTransition(distance: CGFloat) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(y: direction * distance),
            removal: .offset(y: -direction * distance)
        )
    }

    @ViewBuilder
    private var welcomeArtwork: some View {
        switch page {
        case 0: discoverArt
        case 1: libraryArt
        default: sparkArt
        }
    }

    private var discoverArt: some View {
        VStack(alignment: .leading, spacing: 24) {
            garden(width: 202, height: 214)
                .overlay(alignment: .bottomTrailing) {
                    Text("A slower\nafternoon.")
                        .font(.system(size: 17, design: .serif))
                        .lineSpacing(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(red: 0.17, green: 0.18, blue: 0.13))
                        .frame(width: 108, height: 88)
                        .background(Color(red: 0.76, green: 0.66, blue: 0.43))
                        .offset(x: 30, y: 24)
                }
                .padding(.trailing, 30)
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 13) {
                Text("Attention is a kind\nof generosity.")
                    .font(.system(size: 25, design: .serif))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(ChoraiTheme.ink)
                Text("Mira Chen · Culture")
                    .font(.system(size: 10))
                    .foregroundStyle(ChoraiTheme.secondaryInk)
            }
            .frame(width: 254, alignment: .leading)
        }
        .frame(width: 254)
        .fixedSize()
    }

    private var libraryArt: some View {
        VStack(spacing: 22) {
            HStack(spacing: 14) {
                libraryTile("A slower afternoon", detail: "Collected moments") {
                    garden(width: 145, height: 160)
                }
                libraryTile("Notes to return to", detail: "My notes") {
                    libraryText("Keep the\nunfinished\nthings.", number: "01")
                }
            }
            HStack(spacing: 14) {
                libraryTile("Questions, still open", detail: "My notes") {
                    libraryText("What if\nwe leave\nthe edges\nopen?")
                }
                libraryTile("Small discoveries", detail: "Collections") {
                    Image("cosmos-entry-chora")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .frame(width: 145, height: 160)
                        .background(Color(red: 0.90, green: 0.90, blue: 0.85))
                }
            }
        }
        .fixedSize()
    }

    private func libraryTile<Art: View>(_ title: String, detail: String, @ViewBuilder art: () -> Art) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            art()
                .padding(.bottom, 4)
            Text(title).font(.system(size: 11, weight: .medium))
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(ChoraiTheme.secondaryInk)
        }
        .frame(width: 145, alignment: .leading)
    }

    private func libraryText(_ title: String, number: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            if let number {
                Text(number).font(.system(size: 10))
            }
            Text(title)
                .font(.system(size: number == nil ? 24 : 21, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(width: 145, height: 160, alignment: .topLeading)
        .foregroundStyle(number == nil ? Color.white : sparkBackground)
        .background(number == nil ? ChoraiTheme.brandAvatarBackground : Color(red: 0.91, green: 0.90, blue: 0.85))
    }

    private var sparkArt: some View {
        VStack(spacing: 20) {
            VStack(spacing: 0) {
                garden(width: 232, height: 202)
                VStack(alignment: .leading, spacing: 12) {
                    Text("FROM YOUR NOTE")
                        .font(.system(size: 8))
                        .tracking(1)
                        .opacity(0.7)
                    Text("The things we notice\nbecome the things\nwe care about.")
                        .font(.system(size: 22, design: .serif))
                        .lineSpacing(2)
                }
                .padding(19)
                .frame(width: 232, alignment: .leading)
                .foregroundStyle(sparkBackground)
                .background(Color(red: 0.96, green: 0.95, blue: 0.90))
            }
            Text("A new perspective.\nA thought worth following.")
                .font(.system(size: 11))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .opacity(0.86)
        }
        .fixedSize()
    }

    private func garden(width: CGFloat, height: CGFloat) -> some View {
        Image("cosmos-entry-garden")
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()
    }
}
