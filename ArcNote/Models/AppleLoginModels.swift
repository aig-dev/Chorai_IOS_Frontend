import Foundation

// MARK: Apple登录相关数据模型

/// Apple登录请求
struct AppleLoginRequest: Codable {
    let identityToken: String
    let authorizationCode: String
    let userInfo: AppleUserInfo
    
    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case authorizationCode = "authorization_code"
        case userInfo = "user_info"
    }
}

/// Apple用户信息
struct AppleUserInfo: Codable {
    let name: AppleName
}

/// Apple用户姓名
struct AppleName: Codable {
    let firstName: String
    let lastName: String
    
    enum CodingKeys: String, CodingKey {
        case firstName = "firstName"
        case lastName = "lastName"
    }
}
