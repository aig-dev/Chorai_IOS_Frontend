import Foundation
import Combine
import CoreFlow
import Security

enum AuthSessionPhase: String, Equatable {
    case signedOut = "signed-out"
    case restored
    case verifying
    case verified
    case degraded
    case needsLogin = "needs-login"
}

// MARK: 用户认证管理器
@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    private static let foregroundVerificationDebounce: TimeInterval = 2
    private static let pendingInterestsActorKey = "pending_interests_actor_id"
    
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: User?
    @Published var authToken: String?
    @Published private(set) var sessionPhase: AuthSessionPhase = .signedOut
    @Published private(set) var accessState: AccessState?
    @Published private(set) var needsInterestSelection = false
    @Published private(set) var offlineNoteAccess = NoteOfflineAccess()
    let backgroundGeneration = NoteBackgroundGeneration()
    private(set) var sessionGeneration: UInt64 = 0 {
        didSet {
            backgroundGeneration.replace(with: sessionGeneration)
            NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let networkManager = NetworkManager.shared
    private var sessionVerification: AnyCancellable?
    private var verifiedToken: String?
    private var lastVerificationStartedAt: Date?
    
    private init() {
        loadUserSession()
    }
    
    // MARK: 用户会话管理
    func loadUserSession() {
        sessionGeneration &+= 1
        sessionVerification?.cancel(); sessionVerification = nil
        verifiedToken = nil; lastVerificationStartedAt = nil
        if let saved = userDefaults.data(forKey: "offline_note_access_v1"),
           let access = try? JSONDecoder().decode(NoteOfflineAccess.self, from: saved) {
            offlineNoteAccess = access
        }
        accessState = nil
        isLoggedIn = userDefaults.bool(forKey: "is_logged_in")
        authToken = SessionTokenStore.load()
        migrateLegacyAuthTokenIfNeeded()
        
        if isLoggedIn,
           let actorId = userDefaults.string(forKey: "actor_id") {
            guard
                let username = userDefaults.string(forKey: "username"),
                let email = userDefaults.string(forKey: "email"),
                let credit = userDefaults.object(forKey: "credit") as? Int,
                let createdAt = userDefaults.string(forKey: "created_at")
            else {
                clearUserSession()
                return
            }

            needsInterestSelection = userDefaults.string(forKey: Self.pendingInterestsActorKey) == actorId

            // 从本地存储加载用户信息
            currentUser = User(
                id: actorId,
                username: username,
                email: email,
                avatar: userDefaults.string(forKey: "avatar"),
                bio: userDefaults.string(forKey: "bio"),
                credit: credit,
                createdAt: createdAt
            )
            
            // 设置网络管理器的认证令牌
            if let token = authToken, !token.isEmpty {
                networkManager.setAuthToken(token)
                sessionPhase = .restored
            } else if canOpenLocalNotes {
                // A missing cloud credential cannot discard an already
                // confirmed account's retained drafts. Cloud writes stay off.
                networkManager.clearAuthToken()
                sessionPhase = .needsLogin
            } else {
                clearUserSession()
            }
        } else {
            clearUserSession()
        }
    }

    #if DEBUG
    func installUITestSession(
        token: String,
        actorID: String,
        email: String,
        username: String,
        createdAt: String
    ) {
        sessionGeneration &+= 1
        sessionVerification?.cancel()
        sessionVerification = nil
        lastVerificationStartedAt = nil
        needsInterestSelection = false
        authToken = token
        isLoggedIn = true
        currentUser = User(
            id: actorID,
            username: username,
            email: email,
            avatar: nil,
            bio: nil,
            credit: 0,
            createdAt: createdAt
        )
        sessionPhase = .restored
        networkManager.setAuthToken(token)
    }
    #endif
    
    func saveUserSession(_ authResponse: AuthResponse) {
        sessionGeneration &+= 1
        sessionVerification?.cancel(); sessionVerification = nil
        lastVerificationStartedAt = nil
        // 保存认证信息
        let userData = authResponse.data
        let actorID = userData.user.id
        let pendingActorID = userDefaults.string(forKey: Self.pendingInterestsActorKey)
        if userData.isNewUser == true || pendingActorID == actorID {
            userDefaults.set(actorID, forKey: Self.pendingInterestsActorKey)
            needsInterestSelection = true
        } else {
            completeInterestSelection()
        }
        networkManager.setAuthToken(userData.token)
        authToken = userData.token
        verifiedToken = userData.token
        sessionPhase = .verified

        print("用户\(userData.user.id),登录成功")
        let user = userData.user
        currentUser = user
        isLoggedIn = true
        applyAccess(userData.productAccess)

        // 保存到UserDefaults
        userDefaults.set(true, forKey: "is_logged_in")
        SessionTokenStore.save(userData.token)
        userDefaults.removeObject(forKey: "auth_token")
        persistUserProjection(user)

    }
    
    func completeInterestSelection() {
        userDefaults.removeObject(forKey: Self.pendingInterestsActorKey)
        needsInterestSelection = false
    }

    private func clearUserSession(clearCode: Bool = false) {
        completeInterestSelection()
        sessionGeneration &+= 1
        sessionVerification?.cancel()
        sessionVerification = nil
        verifiedToken = nil
        lastVerificationStartedAt = nil

        // 清除认证信息
        authToken = nil
        currentUser = nil
        isLoggedIn = false
        sessionPhase = .signedOut
        accessState = nil
        offlineNoteAccess.clear()
        userDefaults.removeObject(forKey: "offline_note_access_v1")
        if clearCode {
            KeychainStore.shared.clear()
        }
        
        // 清除UserDefaults
        userDefaults.removeObject(forKey: "is_logged_in")
        userDefaults.removeObject(forKey: "auth_token")
        SessionTokenStore.delete()
        userDefaults.removeObject(forKey: "actor_id")
        userDefaults.removeObject(forKey: "username")
        userDefaults.removeObject(forKey: "email")
        userDefaults.removeObject(forKey: "avatar")
        userDefaults.removeObject(forKey: "bio")
        userDefaults.removeObject(forKey: "credit")
        userDefaults.removeObject(forKey: "created_at")
        
        // 清除网络管理器的认证令牌
        networkManager.clearAuthToken()
    }
    
    // MARK: 登录方法
    func login(email: String, password: String) -> AnyPublisher<AuthResponse, NetworkError> {
        return networkManager.login(email: email, password: password)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] authResponse in
                self?.saveUserSession(authResponse)
            })
            .eraseToAnyPublisher()
    }
    
    // MARK: 注册方法
    func register(
        username: String,
        email: String,
        password: String,
        verificationCode: String,
        accessCode: String? = nil,
        idempotencyKey: String? = nil
    ) -> AnyPublisher<AuthResponse, NetworkError> {
        return networkManager.register(
            username: username,
            email: email,
            password: password,
            verificationCode: verificationCode,
            accessCode: accessCode,
            idempotencyKey: idempotencyKey
        )
        .receive(on: DispatchQueue.main)
        .handleEvents(receiveOutput: { [weak self] authResponse in
            self?.saveUserSession(authResponse)
        })
        .eraseToAnyPublisher()
    }
    
    func invalidateLocalSession(clearCode: Bool = false) {
        clearUserSession(clearCode: clearCode)
    }

    func verifyRestoredSession(force: Bool = false) {
        guard sessionPhase != .needsLogin else { return }
        guard isAuthenticated, let token = authToken, !token.isEmpty else {
            sessionPhase = .signedOut
            return
        }
        guard sessionVerification == nil else { return }
        if let lastVerificationStartedAt,
           Date().timeIntervalSince(lastVerificationStartedAt)
            < Self.foregroundVerificationDebounce {
            return
        }
        if !force, verifiedToken == token, sessionPhase == .verified {
            return
        }

        lastVerificationStartedAt = Date()
        let generation = sessionGeneration
        let actorID = currentUser?.id
        sessionPhase = .verifying
        sessionVerification = networkManager.verifyToken(presentsError: false)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self, self.sessionGeneration == generation,
                      self.authToken == token, self.currentUser?.id == actorID else { return }
                self.sessionVerification = nil
                guard case .failure(let error) = completion else { return }
                switch error {
                case .unauthorized, .api(statusCode: 401, code: _, message: _, sparkOutcome: _):
                    self.markSessionNeedsLogin()
                case .forbidden, .api(statusCode: 403, code: _, message: _, sparkOutcome: _):
                    self.markAccountRestricted()
                default:
                    self.accessState = nil
                    self.sessionPhase = .degraded
                }
            } receiveValue: { [weak self] response in
                guard let self, self.sessionGeneration == generation,
                      self.authToken == token, self.currentUser?.id == actorID else { return }
                guard response.success,
                      let data = response.data,
                      data.valid,
                      data.user.id == self.currentUser?.id else {
                    self.invalidateLocalSession()
                    return
                }
                self.currentUser = data.user
                self.persistUserProjection(data.user)
                self.verifiedToken = token
                self.applyAccess(data.productAccess)
                self.sessionPhase = .verified
            }
    }

    func logoutCurrentSession() -> AnyPublisher<Void, NetworkError> {
        guard isAuthenticated else {
            invalidateLocalSession(clearCode: true)
            return Just(())
                .setFailureType(to: NetworkError.self)
                .eraseToAnyPublisher()
        }

        // Capture the current credential before hiding the session. Local sign-out
        // does not depend on connectivity, and a delayed response cannot clear a new login.
        let remoteLogout = networkManager.logoutCurrentSession(presentsError: false)
        invalidateLocalSession(clearCode: true)
        return remoteLogout.map { _ in () }
            .catch { _ in Just(()) }
            .setFailureType(to: NetworkError.self)
            .eraseToAnyPublisher()
    }
    
    // MARK: 发送验证码
    func sendVerificationCode(email: String) -> AnyPublisher<SendVerificationCodeResponse, NetworkError> {
        return networkManager.sendVerificationCode(email: email)
    }
    
    // MARK: Google登录
    func googleLogin(
        idToken: String,
        accessCode: String? = nil,
        idempotencyKey: String? = nil
    ) -> AnyPublisher<AuthResponse, NetworkError> {
        return networkManager.googleLogin(
            idToken: idToken,
            accessCode: accessCode,
            idempotencyKey: idempotencyKey
        )
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] response in
                self?.saveUserSession(response)
            })
            .eraseToAnyPublisher()
    }
    
    func appleLogin(request: AppleLoginRequest) -> AnyPublisher<AuthResponse, NetworkError> {
        return networkManager.appleLogin(loginRequest: request)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] response in
                self?.saveUserSession(response)
            })
            .eraseToAnyPublisher()
    }

    func applyAccess(_ state: AccessState) {
        guard state.isValid else {
            accessState = nil
            NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
            return
        }
        // A verified denial retires queued presentation effects before publishing access.
        // The token verification that delivered it still owns the same login generation.
        let retainsOfflineGrant = state.mode == "unavailable" && offlineNoteAccess.allows(currentNoteScope)
        backgroundGeneration.setAccessAllowed(state.status == "allowed" || retainsOfflineGrant)
        accessState = state
        if state.status != "allowed" {
            NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
        }
        if let scope = currentNoteScope {
            offlineNoteAccess.recordConfirmed(state, scope: scope)
            persistOfflineAccess()
        }
        if state.status == "allowed" {
            KeychainStore.shared.clear()
        }
    }

    func markSessionNeedsLogin() {
        guard offlineNoteAccess.allows(currentNoteScope) else { invalidateLocalSession(); return }
        sessionGeneration &+= 1
        sessionVerification?.cancel(); sessionVerification = nil
        verifiedToken = nil; accessState = nil; sessionPhase = .needsLogin
    }

    func markAccountRestricted() {
        sessionGeneration &+= 1
        sessionVerification?.cancel(); sessionVerification = nil
        verifiedToken = nil; offlineNoteAccess.clear(); persistOfflineAccess()
        accessState = AccessState(mode: "private_beta", status: "required", scope: nil, reasonCode: "account_restricted")
        sessionPhase = .degraded
    }

    private func persistOfflineAccess() {
        if let data = try? JSONEncoder().encode(offlineNoteAccess) {
            userDefaults.set(data, forKey: "offline_note_access_v1")
        }
    }

    private func migrateLegacyAuthTokenIfNeeded() {
        guard authToken == nil,
              let legacyToken = userDefaults.string(forKey: "auth_token"),
              !legacyToken.isEmpty
        else {
            userDefaults.removeObject(forKey: "auth_token")
            return
        }

        SessionTokenStore.save(legacyToken)
        authToken = legacyToken
        userDefaults.removeObject(forKey: "auth_token")
    }

    private func persistUserProjection(_ user: User) {
        userDefaults.set(user.id, forKey: "actor_id")
        userDefaults.set(user.username, forKey: "username")
        userDefaults.set(user.email, forKey: "email")
        userDefaults.set(user.avatar, forKey: "avatar")
        userDefaults.set(user.bio, forKey: "bio")
        userDefaults.set(user.credit, forKey: "credit")
        userDefaults.set(user.createdAt, forKey: "created_at")
    }
}

// MARK: - 用户状态扩展
extension AuthManager {
    var cardReadSession: UInt64? {
        #if DEBUG
        if LocalDevelopmentPreview.isEnabled, currentUser?.id == LocalPreviewFixtures.actorID {
            return sessionGeneration
        }
        #endif
        guard isAuthenticated, sessionPhase != .needsLogin,
              accessState?.status != "required" else { return nil }
        return sessionGeneration
    }

    var currentNoteScope: NoteStoreScope? {
        guard isLoggedIn, let actorID = currentUser?.id else { return nil }
        return NoteStoreScope(actorID: actorID, environmentID: APIConfiguration.baseURL)
    }

    var canOpenLocalNotes: Bool {
        offlineNoteAccess.allows(currentNoteScope)
            || (canEnterProduct && networkManager.isConnected)
    }

    var isAuthenticated: Bool {
        return isLoggedIn && authToken != nil && currentUser != nil
    }

    var canEnterProduct: Bool {
        isAuthenticated &&
            sessionPhase == .verified &&
            accessState?.isValid == true &&
            accessState?.status == "allowed"
    }

    var membershipDisplayName: String {
        accessState?.membershipTier.rawValue ?? MembershipTier.free.rawValue
    }
    
    var userDisplayName: String {
        return currentUser?.username ?? "未知用户"
    }
    
    var userEmail: String {
        return currentUser?.email ?? ""
    }
    
    var userAvatar: String? {
        return currentUser?.avatar
    }
}

// MARK: - Keychain-backed auth token storage
enum SessionTokenStore {
    private static let service = Bundle.main.bundleIdentifier ?? "com.michen.arcnote"
    private static let account = "auth_token"

    static func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else {
            return nil
        }

        return token
    }

    static func save(_ token: String) {
        guard let data = token.data(using: .utf8), !token.isEmpty else {
            return
        }

        var query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        query.merge(attributes) { _, new in new }
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
