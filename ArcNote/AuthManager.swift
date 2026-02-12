import Foundation
import Combine

// MARK: 用户认证管理器
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: User?
    @Published var authToken: String?
    
    private let userDefaults = UserDefaults.standard
    private let networkManager = NetworkManager.shared
    
    private init() {
        loadUserSession()
    }
    
    // MARK: 用户会话管理
    func loadUserSession() {
        isLoggedIn = userDefaults.bool(forKey: "is_logged_in")
        authToken = userDefaults.string(forKey: "auth_token")
        
        if isLoggedIn, let userId = userDefaults.object(forKey: "user_id") as? Int {
            // 从本地存储加载用户信息
            currentUser = User(
                id: userId,
                username: userDefaults.string(forKey: "username") ?? "",
                email: userDefaults.string(forKey: "email") ?? "",
                avatar: userDefaults.string(forKey: "avatar"),
                bio: userDefaults.string(forKey: "bio"),
                credit: userDefaults.object(forKey: "credit") as? Int,
                createdAt: userDefaults.string(forKey: "created_at") ?? "",
                lastLogin: userDefaults.string(forKey: "last_login")
            )
            
            // 设置网络管理器的认证令牌
            if let token = authToken {
                networkManager.setAuthToken(token)
            }
        }
    }
    
    func saveUserSession(_ authResponse: AuthResponse) {
        // 保存认证信息
        authToken = authResponse.token
        isLoggedIn = true
        
        // 从响应数据中提取用户信息
        if let userData = authResponse.data {
            // 直接使用 AuthResponseData 创建 User 对象
            print("用户\(userData.id),登录成功")
            let user = User(
                id: userData.id,
                username: userData.username,
                email: userData.email,
                avatar: nil, // AuthResponseData 中没有 avatar 字段
                bio: nil,    // AuthResponseData 中没有 bio 字段
                credit: nil, // AuthResponseData 中没有 credit 字段
                createdAt: userData.createdAt,
                lastLogin: nil // AuthResponseData 中没有 lastLogin 字段
            )
            currentUser = user
            
            // 保存到UserDefaults
            userDefaults.set(true, forKey: "is_logged_in")
            userDefaults.set(authResponse.token, forKey: "auth_token")
            userDefaults.set(user.id, forKey: "user_id")
            userDefaults.set(user.username, forKey: "username")
            userDefaults.set(user.email, forKey: "email")
            userDefaults.set(user.avatar, forKey: "avatar")
            userDefaults.set(user.bio, forKey: "bio")
            userDefaults.set(user.credit, forKey: "credit")
            userDefaults.set(user.createdAt, forKey: "created_at")
            userDefaults.set(user.lastLogin, forKey: "last_login")
        }
        
        // 设置网络管理器的认证令牌
        networkManager.setAuthToken(authResponse.token)
    }
    
    func clearUserSession() {
        // 清除认证信息
        authToken = nil
        currentUser = nil
        isLoggedIn = false
        
        // 清除UserDefaults
        userDefaults.removeObject(forKey: "is_logged_in")
        userDefaults.removeObject(forKey: "auth_token")
        userDefaults.removeObject(forKey: "user_id")
        userDefaults.removeObject(forKey: "username")
        userDefaults.removeObject(forKey: "email")
        userDefaults.removeObject(forKey: "avatar")
        userDefaults.removeObject(forKey: "bio")
        userDefaults.removeObject(forKey: "credit")
        userDefaults.removeObject(forKey: "created_at")
        userDefaults.removeObject(forKey: "last_login")
        
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
    
    // MARK: 登出方法
    func logout() {
        print("执行本地登出，清除用户信息")
        clearUserSession()
    }
    
    // MARK: 刷新令牌
    func refreshToken() -> AnyPublisher<AuthResponse, NetworkError> {
        return networkManager.refreshToken()
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] authResponse in
                self?.saveUserSession(authResponse)
            })
            .eraseToAnyPublisher()
    }
    
    // MARK: 发送验证码
    func sendVerificationCode(email: String) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
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
