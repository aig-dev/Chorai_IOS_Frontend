import Foundation

// MARK: 关注相关数据模型

/// 关注用户响应
struct FollowResponse: Codable {
    let success: Bool
    let message: String
}

/// 取消关注用户响应
struct UnfollowResponse: Codable {
    let success: Bool
    let message: String
}

/// 检查关注状态响应
struct FollowStatusResponse: Codable {
    let success: Bool
    let message: String
    let data: [String: Bool] // Keys are actor IDs, values are follow states.
}

// MARK: 拉黑用户相关模型

/// 拉黑用户响应
struct BlockUserResponse: Codable {
    let success: Bool
    let message: String
}

/// 取消拉黑用户响应
struct UnblockUserResponse: Codable {
    let success: Bool
    let message: String
}
