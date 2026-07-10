import Foundation
import Combine
import Security

enum AuthSessionPhase: String, Equatable {
    case signedOut = "signed-out"
    case restored
    case verifying
    case verified
    case degraded
}

// MARK: 用户认证管理器
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    private static let foregroundVerificationDebounce: TimeInterval = 2
    
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: User?
    @Published var authToken: String?
    @Published private(set) var sessionPhase: AuthSessionPhase = .signedOut
    
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
        isLoggedIn = userDefaults.bool(forKey: "is_logged_in")
        authToken = SessionTokenStore.load()
        migrateLegacyAuthTokenIfNeeded()
        
        if isLoggedIn,
           let token = authToken,
           !token.isEmpty,
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
            networkManager.setAuthToken(token)
            sessionPhase = .restored
        } else {
            clearUserSession()
        }
    }
    
    func saveUserSession(_ authResponse: AuthResponse) {
        // 保存认证信息
        let userData = authResponse.data
        authToken = userData.token
        isLoggedIn = true
        verifiedToken = userData.token
        sessionPhase = .verified

        print("用户\(userData.user.id),登录成功")
        let user = userData.user
        currentUser = user

        // 保存到UserDefaults
        userDefaults.set(true, forKey: "is_logged_in")
        SessionTokenStore.save(userData.token)
        userDefaults.removeObject(forKey: "auth_token")
        persistUserProjection(user)
        
        // 设置网络管理器的认证令牌
        networkManager.setAuthToken(userData.token)
    }
    
    private func clearUserSession() {
        sessionVerification?.cancel()
        sessionVerification = nil
        verifiedToken = nil
        lastVerificationStartedAt = nil

        // 清除认证信息
        authToken = nil
        currentUser = nil
        isLoggedIn = false
        sessionPhase = .signedOut
        
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
    func register(username: String, email: String, password: String, verificationCode: String) -> AnyPublisher<AuthResponse, NetworkError> {
        return networkManager.register(
            username: username,
            email: email,
            password: password,
            verificationCode: verificationCode
        )
        .receive(on: DispatchQueue.main)
        .handleEvents(receiveOutput: { [weak self] authResponse in
            self?.saveUserSession(authResponse)
        })
        .eraseToAnyPublisher()
    }
    
    func invalidateLocalSession() {
        clearUserSession()
    }

    func verifyRestoredSession(force: Bool = false) {
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
        sessionPhase = .verifying
        sessionVerification = networkManager.verifyToken(presentsError: false)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self else { return }
                self.sessionVerification = nil
                guard case .failure(let error) = completion else { return }
                if case .unauthorized = error {
                    self.invalidateLocalSession()
                } else {
                    self.sessionPhase = .degraded
                }
            } receiveValue: { [weak self] response in
                guard let self,
                      response.success,
                      let data = response.data,
                      data.valid,
                      data.user.id == self.currentUser?.id else {
                    self?.invalidateLocalSession()
                    return
                }
                self.currentUser = data.user
                self.persistUserProjection(data.user)
                self.verifiedToken = token
                self.sessionPhase = .verified
            }
    }

    func logoutCurrentSession() -> AnyPublisher<Void, NetworkError> {
        guard isAuthenticated else {
            invalidateLocalSession()
            return Just(())
                .setFailureType(to: NetworkError.self)
                .eraseToAnyPublisher()
        }

        return networkManager.logoutCurrentSession(presentsError: false)
            .receive(on: DispatchQueue.main)
            .flatMap { response -> AnyPublisher<Void, NetworkError> in
                guard response.success else {
                    return Fail(error: NetworkError.unknown)
                        .eraseToAnyPublisher()
                }
                return Just(())
                    .setFailureType(to: NetworkError.self)
                    .eraseToAnyPublisher()
            }
            .catch { [weak self] error -> AnyPublisher<Void, NetworkError> in
                if case .unauthorized = error {
                    self?.invalidateLocalSession()
                    return Just(())
                        .setFailureType(to: NetworkError.self)
                        .eraseToAnyPublisher()
                }
                return Fail(error: error).eraseToAnyPublisher()
            }
            .handleEvents(receiveOutput: { [weak self] in
                self?.invalidateLocalSession()
            })
            .eraseToAnyPublisher()
    }
    
    // MARK: 发送验证码
    func sendVerificationCode(email: String) -> AnyPublisher<SendVerificationCodeResponse, NetworkError> {
        return networkManager.sendVerificationCode(email: email)
    }
    
    // MARK: Google登录
    func googleLogin(idToken: String) -> AnyPublisher<AuthResponse, NetworkError> {
        return networkManager.googleLogin(idToken: idToken)
            .eraseToAnyPublisher()
    }
    
    func appleLogin(request: AppleLoginRequest) -> AnyPublisher<AuthResponse, NetworkError> {
        return networkManager.appleLogin(loginRequest: request)
            .eraseToAnyPublisher()
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
    var isAuthenticated: Bool {
        return isLoggedIn && authToken != nil && currentUser != nil
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
