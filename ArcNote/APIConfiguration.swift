import Foundation

// MARK: API配置管理
struct APIConfiguration {
    
    // MARK: 环境配置
    enum Environment {
        case development
        case staging
        case production
        
        var timeout: TimeInterval {
            switch self {
            case .development:
                return 30
            case .staging:
                return 25
            case .production:
                return 20
            }
        }
    }
    
    // MARK: 当前环境
    static var current: Environment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }
    
    // MARK: API端点定义
    struct Endpoints {
        
        // MARK: 认证
        struct Auth {
            static let login = "/auth/login"
            static let register = "/auth/register"
            static let logout = "/auth/logout"
            static let refresh = "/auth/refresh"
            static let forgotPassword = "/auth/forgot-password"
            static let resetPassword = "/auth/reset-password"
            static let verifyEmail = "/auth/verify-email"
        }
        
        // MARK: 笔记相关
        struct Notes {
            static let base = "/notes"
            static let search = "/notes/search"
            static let favorites = "/notes/favorites"
            static let trash = "/notes/trash"
            static let restore = "/notes/restore"
            static let share = "/notes/share"
            static let export = "/notes/export"
            
            static func detail(id: String) -> String {
                return "/notes/\(id)"
            }
            
            static func update(id: String) -> String {
                return "/notes/\(id)"
            }
            
            static func delete(id: String) -> String {
                return "/notes/\(id)"
            }
            
            static func favorite(id: String) -> String {
                return "/notes/\(id)/favorite"
            }
            
            static func share(id: String) -> String {
                return "/notes/\(id)/share"
            }
        }
        
        // MARK: 标签
        struct Tags {
            static let base = "/tags"
            static let popular = "/tags/popular"
            static let search = "/tags/search"
            
            static func detail(id: String) -> String {
                return "/tags/\(id)"
            }
            
            static func notes(id: String) -> String {
                return "/tags/\(id)/notes"
            }
        }
        
        // MARK: 用户相关
        struct User {
            static let profile = "/user/profile"
            static let settings = "/user/settings"
            static let preferences = "/user/preferences"
            static let avatar = "/user/avatar"
            static let password = "/user/password"
            static let delete = "/user/delete"
            static let export = "/user/export"
        }
        
        // MARK: 文件
        struct Files {
            static let upload = "/files/upload"
            static let download = "/files/download"
            static let delete = "/files/delete"
            
            static func detail(id: String) -> String {
                return "/files/\(id)"
            }
        }
        
        // MARK: 搜索
        struct Search {
            static let global = "/search"
            static let suggestions = "/search/suggestions"
            static let history = "/search/history"
        }
        
        // MARK: 通知相关
        struct Notifications {
            static let base = "/notifications"
            static let unread = "/notifications/unread"
            static let markRead = "/notifications/mark-read"
            static let markAllRead = "/notifications/mark-all-read"
            
            static func detail(id: String) -> String {
                return "/notifications/\(id)"
            }
        }
        
        // MARK: 同步相关
        struct Sync {
            static let status = "/sync/status"
            static let pull = "/sync/pull"
            static let push = "/sync/push"
            static let conflict = "/sync/conflict"
        }
    }
    
    // MARK: HTTP状态码
    struct StatusCodes {
        static let success = 200
        static let created = 201
        static let noContent = 204
        static let badRequest = 400
        static let unauthorized = 401
        static let forbidden = 403
        static let notFound = 404
        static let conflict = 409
        static let unprocessableEntity = 422
        static let tooManyRequests = 429
        static let internalServerError = 500
        static let badGateway = 502
        static let serviceUnavailable = 503
    }
    
    // MARK: 请求头配置
    struct Headers {
        static let contentType = "Content-Type"
        static let authorization = "Authorization"
        static let accept = "Accept"
        static let userAgent = "User-Agent"
        static let apiVersion = "X-API-Version"
        
        static let applicationJSON = "application/json"
        static let multipartFormData = "multipart/form-data"
        
        static func bearer(token: String) -> String {
            return "Bearer \(token)"
        }
        
        static func apiVersion(_ version: String) -> String {
            return version
        }
    }
    
    // MARK: 分页配置
    struct Pagination {
        static let defaultPageSize = 20
        static let maxPageSize = 100
        static let defaultPage = 1
    }
    
    // MARK: 缓存配置
    struct Cache {
        static let defaultTTL: TimeInterval = 300 // 5分钟
        static let longTTL: TimeInterval = 3600 // 1小时
        static let shortTTL: TimeInterval = 60 // 1分钟
    }
    
    // MARK: 重试配置
    struct Retry {
        static let maxRetryCount = 3
        static let retryDelay: TimeInterval = 1.0
        static let exponentialBackoff = true
    }
}

// MARK: - API版本管理
struct APIVersion {
    static let current = "v1"
    static let supportedVersions = ["v1"]
    
    static func isVersionSupported(_ version: String) -> Bool {
        return supportedVersions.contains(version)
    }
}

// MARK: - 请求参数构建器
struct RequestParameters {
    
    // MARK: - 分页参数
    static func pagination(page: Int = 1, pageSize: Int = APIConfiguration.Pagination.defaultPageSize) -> [String: Any] {
        return [
            "page": page,
            "pageSize": min(pageSize, APIConfiguration.Pagination.maxPageSize)
        ]
    }
    
    // MARK: - 搜索参数
    static func search(query: String, tags: [String]? = nil, page: Int = 1, pageSize: Int = APIConfiguration.Pagination.defaultPageSize) -> [String: Any] {
        var parameters: [String: Any] = [
            "query": query,
            "page": page,
            "pageSize": min(pageSize, APIConfiguration.Pagination.maxPageSize)
        ]
        
        if let tags = tags, !tags.isEmpty {
            parameters["tags"] = tags
        }
        
        return parameters
    }
    
    // MARK: 排序参数
    static func sorting(sortBy: String, sortOrder: String = "desc") -> [String: Any] {
        return [
            "sortBy": sortBy,
            "sortOrder": sortOrder
        ]
    }
    
    // MARK: 过滤参数
    static func filtering(filters: [String: Any]) -> [String: Any] {
        return filters
    }
}

// MARK: 响应缓存键生成器
struct CacheKeyGenerator {
    
    static func generate(for endpoint: String, parameters: [String: Any]? = nil) -> String {
        var key = endpoint
        
        if let parameters = parameters {
            let sortedParams = parameters.sorted { $0.key < $1.key }
            let paramString = sortedParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            key += "?\(paramString)"
        }
        
        return key
    }
    
    static func generateUserSpecific(for endpoint: String, userId: String, parameters: [String: Any]? = nil) -> String {
        let baseKey = generate(for: endpoint, parameters: parameters)
        return "\(userId):\(baseKey)"
    }
}


