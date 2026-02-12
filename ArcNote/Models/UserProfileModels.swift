import Foundation

// MARK: 用户资料数据模型
struct UserProfile: Codable, Equatable {
    let id: Int
    let email: String
    let username: String
    let credit: Int
    let avatar: String
    let bio: String?
    let createdAt: String
    let lastLogin: String?
    let followersCount: Int?
    let followingCount: Int?
    let memberLevel: String?
    let location: String?
    let birthday: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case username
        case credit
        case avatar
        case bio
        case createdAt = "created_at"
        case lastLogin = "last_login"
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case memberLevel = "member_level"
        case location
        case birthday
    }
}

// MARK: 用户资料响应模型
struct UserProfileResponse: Codable {
    let success: Bool
    let message: String
    let data: UserProfile
}

// MARK: 用户资料管理器
class UserProfileManager: ObservableObject {
    @Published var userProfile: UserProfile?
    @Published var isLoading: Bool = false
    @Published var error: NetworkError?
    
    static let shared = UserProfileManager()
    
    private init() {}
    
    // 获取用户资料
    func fetchUserProfile(userId: Int) {
        isLoading = true
        error = nil
        
        NetworkManager.shared.getUserProfile(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                switch result {
                case .success(let response):
                    self?.userProfile = response.data
                    print("用户资料获取成功: \(response.data.username)")
                case .failure(let error):
                    self?.error = error
                    print("用户资料获取失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 刷新用户资料
    func refreshUserProfile() {
        guard let userId = userProfile?.id else { return }
        fetchUserProfile(userId: userId)
    }
    
    // 获取当前用户资料
    func fetchCurrentUserProfile() {
        guard let userId = AuthManager.shared.currentUser?.id else {
            return
        }
        fetchUserProfile(userId: userId)
    }
    
    // 更新用户资料
    func updateUserProfile(username: String, avatar: String, bio: String, location: String, birthday: String, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        guard let userId = AuthManager.shared.currentUser?.id else {
            print("未找到当前用户ID")
            completion(.failure(.unauthorized))
            return
        }
        
        NetworkManager.shared.updateUserProfile(
            userId: userId,
            username: username,
            avatar: avatar,
            bio: bio,
            location: location,
            birthday: birthday
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if response.success {
                        // 更新本地用户资料
                        self?.userProfile = response.data
                        completion(.success(true))
                    } else {
                        print("用户资料更新失败: \(response.message)")
                        completion(.failure(.serverError(500, response.message)))
                    }
                case .failure(let error):
                    print("用户资料更新失败: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }
    }
}
