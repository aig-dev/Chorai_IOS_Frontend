import Foundation

// MARK: 关注相关数据模型

/// 关注用户请求
struct FollowRequest: Codable {
    let userId: Int
    let targetUserId: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case targetUserId = "target_user_id"
    }
}

/// 关注用户响应
struct FollowResponse: Codable {
    let success: Bool
    let message: String
    let data: FollowData
}

/// 关注数据
struct FollowData: Codable {
    let targetUser: TargetUser
    
    enum CodingKeys: String, CodingKey {
        case targetUser = "target_user"
    }
}

/// 目标用户信息
struct TargetUser: Codable {
    let id: Int
    let username: String
}

/// 取消关注用户响应
struct UnfollowResponse: Codable {
    let success: Bool
    let message: String
    let data: UnfollowData
}

/// 取消关注数据
struct UnfollowData: Codable {
    let message: String
}

/// 检查关注状态请求
struct FollowStatusRequest: Codable {
    let userId: Int
    let targetUserIds: [Int]
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case targetUserIds = "target_user_ids"
    }
}

/// 检查关注状态响应
struct FollowStatusResponse: Codable {
    let success: Bool
    let message: String
    let data: [String: Bool] // 键是用户ID字符串，值是关注状态
}

// MARK: 拉黑用户相关模型

/// 拉黑用户响应
struct BlockUserResponse: Codable {
    let success: Bool
    let message: String
    let data: BlockUserData
}

/// 拉黑用户数据
struct BlockUserData: Codable {
    let blockId: Int
    let userId: Int
    let blockedId: Int
    
    enum CodingKeys: String, CodingKey {
        case blockId = "block_id"
        case userId = "user_id"
        case blockedId = "blocked_id"
    }
}
