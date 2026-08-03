import Foundation

// MARK: Apple登录相关数据模型

/// Apple Sign In callback payload kept locally before building the Go auth request.
struct AppleLoginRequest {
    let identityToken: String
    let authorizationCode: String
    let userInfo: AppleUserInfo
    let accessCode: String?
    let idempotencyKey: String?

    init(
        identityToken: String,
        authorizationCode: String,
        userInfo: AppleUserInfo,
        accessCode: String? = nil,
        idempotencyKey: String? = nil
    ) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.userInfo = userInfo
        self.accessCode = accessCode
        self.idempotencyKey = idempotencyKey
    }
}

/// Apple用户信息
struct AppleUserInfo {
    let name: AppleName
}

/// Apple用户姓名
struct AppleName {
    let firstName: String
    let lastName: String
}
