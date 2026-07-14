import Combine
import Foundation

// MARK: 用户资料数据模型
struct UserProfile: Codable, Equatable {
    let id: String
    let email: String?
    let username: String
    let avatar: String?
    let bio: String?
    let createdAt: String?
    let followersCount: Int?
    let followingCount: Int?
    let isFollowing: Bool?
    let location: String?
    let birthday: String?

    enum CodingKeys: String, CodingKey {
        case actorId = "actor_id"
        case email
        case username
        case avatarUrl = "avatar_url"
        case bio
        case createdAt = "created_at"
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case isFollowing = "is_following"
        case city
        case birthday
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .actorId)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        username = try container.decode(String.self, forKey: .username)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        followersCount = try container.decode(Int.self, forKey: .followerCount)
        followingCount = try container.decode(Int.self, forKey: .followingCount)
        isFollowing = try container.decodeIfPresent(Bool.self, forKey: .isFollowing)
        location = try container.decodeIfPresent(String.self, forKey: .city)
        birthday = try container.decodeIfPresent(String.self, forKey: .birthday)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .actorId)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encode(username, forKey: .username)
        try container.encodeIfPresent(avatar, forKey: .avatarUrl)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(followersCount, forKey: .followerCount)
        try container.encodeIfPresent(followingCount, forKey: .followingCount)
        try container.encodeIfPresent(isFollowing, forKey: .isFollowing)
        try container.encodeIfPresent(location, forKey: .city)
        try container.encodeIfPresent(birthday, forKey: .birthday)
    }
}

// MARK: 用户资料响应模型
struct UserProfileResponse: Codable {
    let success: Bool
    let message: String?
    let data: UserProfile
}

// MARK: 用户资料管理器
class UserProfileManager: ObservableObject {
    @Published var userProfile: UserProfile?
    @Published var creditBalance: [CreditBalanceData] = []
    @Published var isCreditLoading: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: NetworkError?

    static let shared = UserProfileManager()

    private var cancellables = Set<AnyCancellable>()

    private init() {}

    var creditTotal: Int {
        creditBalance.reduce(0) { $0 + $1.balance }
    }

    var regularCreditTotal: Int {
        creditBalance
            .filter { $0.creditTier == "credit" }
            .reduce(0) { $0 + $1.balance }
    }

    // 获取用户资料
    func fetchUserProfile(actorId: String) {
        isLoading = true
        error = nil

        NetworkManager.shared.getUserProfile(actorId: actorId) { [weak self] result in
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
        guard let actorId = userProfile?.id else { return }
        fetchUserProfile(actorId: actorId)
    }

    // 获取当前用户资料
    func fetchCurrentUserProfile() {
        isLoading = true
        error = nil
        fetchCurrentUserCredit()

        NetworkManager.shared.getCurrentUserProfile { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false

                switch result {
                case .success(let response):
                    self?.userProfile = response.data
                    print("当前用户资料获取成功: \(response.data.username)")
                case .failure(let error):
                    self?.error = error
                    print("当前用户资料获取失败: \(error.localizedDescription)")
                }
            }
        }
    }

    func fetchCurrentUserCredit() {
        isCreditLoading = true

        NetworkManager.shared.getUserCredit()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isCreditLoading = false
                    if case .failure(let error) = completion {
                        print("当前用户积分获取失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] response in
                    self?.creditBalance = response.data ?? []
                }
            )
            .store(in: &cancellables)
    }

    // 更新用户资料
    func updateUserProfile(username: String, bio: String, location: String, birthday: String, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        guard AuthManager.shared.currentUser != nil else {
            print("未找到当前用户ID")
            completion(.failure(.unauthorized))
            return
        }

        NetworkManager.shared.updateUserProfile(
            username: username,
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
